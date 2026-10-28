import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../utils/functions_config.dart';
import '../../utils/responsive.dart';

class AiAssistantPage extends StatefulWidget {
  const AiAssistantPage({super.key});

  @override
  State<AiAssistantPage> createState() => _AiAssistantPageState();
}

class _AiAssistantPageState extends State<AiAssistantPage> {
  final TextEditingController _controller = TextEditingController();
  final List<_AiMessage> _messages = <_AiMessage>[];
  bool _sending = false;
  bool _offlineNoticeShown = false;
  bool _aiOnline = true;
  String? _statusNote = 'Online: connected to cloud assistant.';

  final List<String> _quickPrompts = const [
    'What fish is safe to eat today?',
    'Where is it safe to fish now?',
    'Explain this species like I\'m 12.',
    'Give me a 1-sentence summary.',
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;

    String reply = '';
    bool isError = false;

    setState(() {
      _messages.add(_AiMessage(text: text, isUser: true));
      _sending = true;
      _controller.clear();
    });

    try {
      reply = await _askAssistant(text, _messages);
      if (mounted) {
        setState(() {
          _aiOnline = true;
          _statusNote = 'Online: responses are coming from the cloud assistant.';
        });
      }
    } catch (e) {
      reply = _offlineFallback(text, _messages);
      isError = false;
      if (mounted) {
        setState(() {
          _aiOnline = false;
          _statusNote = 'Offline: using built-in tips until the AI reconnects.';
        });
        if (!_offlineNoticeShown) {
          _offlineNoticeShown = true;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Using offline assistant while the AI service reconnects.'),
            ),
          );
        }
        debugPrint('AI assistant fell back to offline mode: $e');
      }
    } finally {
      if (mounted) {
        setState(() {
          _messages.add(_AiMessage(text: reply, isUser: false, isError: isError));
          _sending = false;
        });
      }
    }
  }

  Future<String> _askAssistant(String question, List<_AiMessage> history) async {
    Future<String> callEndpoint(String path, Map<String, dynamic> payload) async {
      final uris = functionUriCandidates(path);
      Object? lastError;

      for (final uri in uris) {
        try {
          final resp = await http
              .post(
                uri,
                headers: {'Content-Type': 'application/json'},
                body: jsonEncode(payload),
              )
              .timeout(const Duration(seconds: 12));

          if (resp.statusCode == 200) {
            final body = jsonDecode(resp.body);
            if (body is Map && body['answer'] is String) {
              final ans = (body['answer'] as String).trim();
              if (ans.isNotEmpty) return ans;
            }
          }
          lastError = 'HTTP ${resp.statusCode}';
        } catch (e) {
          lastError = e;
        }
      }
      throw Exception(lastError ?? 'No reachable function URL');
    }

    final payload = {
      'question': question,
      'history': history
          .where((m) => m.text.trim().isNotEmpty)
          .map((m) => {
                'role': m.isUser ? 'user' : 'assistant',
                'content': m.text,
              })
          .toList(),
    };

    // Support nested and flat function IDs; keep legacy names for compatibility.
    final endpoints = [
      'ai/assistant',
      'ai-assistant',
      'aiAssistant',
      'ai/ask/fish',
      'ai-ask-fish',
      'aiAskFish',
    ];
    final errors = <String>[];
    for (final path in endpoints) {
      try {
        return await callEndpoint(path, payload);
      } catch (e) {
        errors.add('$path: $e');
      }
    }
    throw Exception('Assistant unavailable (${errors.join('; ')})');
  }

  String _offlineFallback(String question, List<_AiMessage> history) {
    final normalizedQuestion = question.trim().isNotEmpty ? question.trim() : _lastUserQuestion(history);
    final q = normalizedQuestion.isNotEmpty ? normalizedQuestion : 'your question';
    final lower = q.toLowerCase();

    final tips = <String>[];
    final general = <String>[
      'Check today\'s local advisories before catching or eating fish.',
      'Favor smaller, fast-growing fish to reduce mercury risk.',
      'Skip trips during lightning, high winds, or poor visibility.',
    ];

    if (lower.contains('eat')) {
      tips.addAll([
        'For eating: look for clear eyes, firm flesh, and a clean smell; chill catch quickly.',
        'Avoid reef fish after algal blooms or sewage alerts, and trim dark meat to lower contaminants.',
      ]);
    }

    if (lower.contains('safe') && lower.contains('fish')) {
      tips.addAll([
        'Safety on the water: winds under ~20 km/h and waves under ~1.5 m are more comfortable.',
        'Wear a PFD, carry lights, and fish with a partner when conditions are uncertain.',
      ]);
    }

    if (tips.isEmpty) {
      tips.add('Here\'s a quick offline answer—share the fish name, location, and any concern for a sharper tip.');
    }

    final bullets = [
      'Here\'s what I can share for "$q":',
      ...tips.map((t) => '• $t'),
      '',
      'General checks:',
      ...general.map((t) => '• $t'),
    ];

    return bullets.join('\n');
  }

  String _lastUserQuestion(List<_AiMessage> history) {
    for (var i = history.length - 1; i >= 0; i--) {
      final msg = history[i];
      if (msg.isUser && msg.text.trim().isNotEmpty) {
        return msg.text.trim();
      }
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final padding = Responsive.pagePadding(context);
    final maxWidth = Responsive.maxContentWidth(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('AI Assistant'),
        foregroundColor: Colors.black,
        backgroundColor: Colors.white,
        elevation: 0,
      ),
      body: SafeArea(
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFFF6F8FB), Color(0xFFEFF2F7)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth),
              child: Column(
                children: [
                  Padding(
                    padding: EdgeInsets.fromLTRB(padding, padding, padding, 6),
                    child: _heroCard(),
                  ),
                  Padding(
                    padding: EdgeInsets.fromLTRB(padding, 0, padding, 8),
                    child: _statusBanner(),
                  ),
                  if (_quickPrompts.isNotEmpty)
                    SizedBox(
                      height: 46,
                      child: ListView.separated(
                        padding: EdgeInsets.symmetric(horizontal: padding),
                        scrollDirection: Axis.horizontal,
                        itemBuilder: (_, i) => ActionChip(
                          label: Text(
                            _quickPrompts[i],
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          onPressed: _sending
                              ? null
                              : () {
                                  _controller.text = _quickPrompts[i];
                                  _controller.selection = TextSelection.fromPosition(
                                    TextPosition(offset: _controller.text.length),
                                  );
                                  _send();
                                },
                          backgroundColor: Colors.white,
                          shape: StadiumBorder(
                            side: BorderSide(color: Colors.grey.shade300),
                          ),
                        ),
                        separatorBuilder: (_, __) => const SizedBox(width: 8),
                        itemCount: _quickPrompts.length,
                      ),
                    ),
                  Expanded(
                    child: ListView.builder(
                      padding: EdgeInsets.fromLTRB(padding, 8, padding, padding),
                      itemCount: _messages.length,
                      itemBuilder: (context, index) {
                        final msg = _messages[index];
                        return Align(
                          alignment:
                              msg.isUser ? Alignment.centerRight : Alignment.centerLeft,
                          child: _messageBubble(msg),
                        );
                      },
                    ),
                  ),
                  const Divider(height: 1),
                  Padding(
                    padding: EdgeInsets.fromLTRB(padding, 12, padding, padding + 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _controller,
                            maxLines: 4,
                            minLines: 1,
                            textInputAction: TextInputAction.send,
                            onSubmitted: (_) => _send(),
                            decoration: InputDecoration(
                              hintText: 'Ask anything...',
                              filled: true,
                              fillColor: Colors.white,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: BorderSide(color: Colors.grey.shade300),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: BorderSide(color: Colors.grey.shade300),
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 14,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        ElevatedButton(
                          onPressed: _sending ? null : _send,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF0F2548),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            padding: const EdgeInsets.all(14),
                            elevation: 4,
                          ),
                          child: _sending
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.send_rounded, size: 18),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _heroCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 12,
            offset: Offset(0, 6),
          ),
        ],
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: const [
          CircleAvatar(
            radius: 22,
            backgroundColor: Color(0xFF0F2548),
            child: Icon(Icons.smart_toy_rounded, color: Colors.white),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Ask anything',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: Colors.black87,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Get quick answers about fish, safety, or the sea.',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.black54,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _messageBubble(_AiMessage msg) {
    final isUser = msg.isUser;
    final bg = isUser
        ? const Color(0xFF0F2548)
        : (msg.isError ? Colors.red.shade50 : Colors.white);
    final fg = isUser
        ? Colors.white
        : (msg.isError ? Colors.red.shade800 : Colors.black87);
    final borderColor = msg.isError ? Colors.red.shade200 : Colors.grey.shade300;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width * 0.8,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(16),
          topRight: const Radius.circular(16),
          bottomLeft: Radius.circular(isUser ? 16 : 4),
          bottomRight: Radius.circular(isUser ? 4 : 16),
        ),
        border: isUser ? null : Border.all(color: borderColor),
        boxShadow: const [
          BoxShadow(
            color: Color(0x12000000),
            blurRadius: 8,
            offset: Offset(0, 4),
          ),
        ],
        ),
      child: Text(
        msg.text,
        style: TextStyle(
          color: fg,
          fontSize: 14.5,
          height: 1.45,
          fontWeight: msg.isError ? FontWeight.w600 : FontWeight.w500,
        ),
      ),
    );
  }

  Widget _statusBanner() {
    if (_statusNote == null || _statusNote!.isEmpty) {
      return const SizedBox.shrink();
    }
    final online = _aiOnline;
    final bg = online ? Colors.green.shade50 : Colors.amber.shade50;
    final fg = online ? Colors.green.shade800 : Colors.orange.shade800;
    final icon = online ? Icons.cloud_done_rounded : Icons.cloud_off_rounded;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: fg.withOpacity(0.25)),
      ),
      child: Row(
        children: [
          Icon(icon, color: fg, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _statusNote!,
              style: TextStyle(color: fg, fontSize: 13.5, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _AiMessage {
  final String text;
  final bool isUser;
  final bool isError;

  _AiMessage({
    required this.text,
    required this.isUser,
    this.isError = false,
  });
}
