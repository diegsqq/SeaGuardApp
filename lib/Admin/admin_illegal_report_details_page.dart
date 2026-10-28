import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../utils/responsive.dart';

class AdminIllegalReportDetailsPage extends StatelessWidget {
  final String reportId;

  const AdminIllegalReportDetailsPage({
    super.key,
    required this.reportId,
  });

  String _formatDate(dynamic value) {
    if (value is Timestamp) {
      final dt = value.toDate().toLocal();
      return DateFormat('MMMM dd, yyyy h:mm a').format(dt);
    }
    if (value is DateTime) {
      return DateFormat('MMMM dd, yyyy h:mm a').format(value.toLocal());
    }
    if (value is String && value.trim().isNotEmpty) {
      DateTime? parsed;
      try {
        parsed = DateFormat('yyyy-MM-dd HH:mm').parseStrict(value);
      } catch (_) {
        parsed = DateTime.tryParse(value);
      }
      if (parsed != null) {
        return DateFormat('MMMM dd, yyyy h:mm a').format(parsed.toLocal());
      }
      return value;
    }
    return '';
  }

  String _formatCompactDate(dynamic value) {
    if (value is Timestamp) {
      final dt = value.toDate().toLocal();
      return DateFormat('MMM dd, yyyy\nh:mm a').format(dt);
    }
    if (value is DateTime) {
      return DateFormat('MMM dd, yyyy\nh:mm a').format(value.toLocal());
    }
    if (value is String && value.trim().isNotEmpty) {
      DateTime? parsed;
      try {
        parsed = DateFormat('yyyy-MM-dd HH:mm').parseStrict(value);
      } catch (_) {
        parsed = DateTime.tryParse(value);
      }
      if (parsed != null) {
        return DateFormat('MMM dd, yyyy\nh:mm a').format(parsed.toLocal());
      }
      return value;
    }
    return '';
  }

  String _titleCase(String value) {
    if (value.isEmpty) return value;
    return value[0].toUpperCase() + value.substring(1);
  }

  List<String> _collectImages(Map<String, dynamic> data) {
    final urls = <String>[];
    void addIf(String? u) {
      final s = (u ?? '').trim();
      if (s.isNotEmpty && !urls.contains(s)) urls.add(s);
    }

    addIf(data['imageUrl']?.toString());
    final raw = data['photoUrls'] ?? data['images'] ?? data['photos'];
    if (raw is List) {
      for (final item in raw) {
        addIf(item?.toString());
      }
    } else if (raw is String) {
      addIf(raw);
    }
    return urls;
  }

  bool _isDataUrl(String url) => url.startsWith('data:image');

  Uint8List? _decodeDataUrl(String url) {
    try {
      final base64Part = url.split(',').last;
      return base64.decode(base64Part);
    } catch (_) {
      return null;
    }
  }

  String _displayOrFallback(String value, String fallback) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? fallback : trimmed;
  }

  dynamic _bestIncidentTimestamp(Map<String, dynamic> data) {
    return data['incidentAt'] ??
        data['incidentDateTime'] ??
        data['incidentDateTimeString'] ??
        data['incidentDate'] ??
        data['occurredAt'] ??
        data['date'];
  }

  dynamic _bestSubmittedTimestamp(Map<String, dynamic> data) {
    return data['submittedAt'] ??
        data['manilaSubmittedAt'] ??
        data['timestamp'] ??
        data['createdAt'];
  }

  Color _priorityBackground(String priority) {
    switch (priority.toLowerCase()) {
      case 'high':
      case 'danger':
        return const Color(0xFFFFE1DB);
      case 'medium':
      case 'moderate':
        return const Color(0xFFFFE8BD);
      case 'low':
      case 'safe':
        return const Color(0xFFD8F1E3);
      default:
        return const Color(0xFFE2E8F0);
    }
  }

  Color _priorityForeground(String priority) {
    switch (priority.toLowerCase()) {
      case 'high':
      case 'danger':
        return const Color(0xFFC2410C);
      case 'medium':
      case 'moderate':
        return const Color(0xFF9A6700);
      case 'low':
      case 'safe':
        return const Color(0xFF0F8A4B);
      default:
        return const Color(0xFF334155);
    }
  }

  Color _statusBackground(String status) {
    switch (status.toLowerCase()) {
      case 'verified':
      case 'resolved':
      case 'done':
        return const Color(0xFFD7F0E0);
      case 'acknowledged':
      case 'reviewed':
        return const Color(0xFFDDEBFF);
      case 'dispatched':
        return const Color(0xFFE8EAF8);
      default:
        return const Color(0xFFF1F5F9);
    }
  }

  Color _statusForeground(String status) {
    switch (status.toLowerCase()) {
      case 'verified':
      case 'resolved':
      case 'done':
        return const Color(0xFF117B4F);
      case 'acknowledged':
      case 'reviewed':
        return const Color(0xFF1D4ED8);
      case 'dispatched':
        return const Color(0xFF4C1D95);
      default:
        return const Color(0xFF475569);
    }
  }

  void _openImage(BuildContext context, {required List<String> urls, required int initialIndex}) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _FullScreenImagePage(
          urls: urls,
          initialIndex: initialIndex,
        ),
      ),
    );
  }

  Widget _buildEvidenceImage(String url) {
    final isData = _isDataUrl(url);
    final dataBytes = isData ? _decodeDataUrl(url) : null;

    if (isData && dataBytes != null) {
      return Image.memory(
        dataBytes,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => const _ImageErrorTile(),
      );
    }

    return Image.network(
      url,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => const _ImageErrorTile(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final padding = Responsive.pagePadding(context);
    final maxWidth = Responsive.maxContentWidth(context);
    final docRef = FirebaseFirestore.instance.collection('reports').doc(reportId);

    return Scaffold(
      backgroundColor: const Color(0xFFF3F6FB),
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF102A43),
        elevation: 0,
        surfaceTintColor: Colors.white,
        title: const Text(
          'Illegal Report',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: docRef.snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Padding(
                    padding: EdgeInsets.all(padding),
                    child: Text(
                      'Failed to load report: ${snapshot.error}',
                      style: const TextStyle(color: Colors.red),
                    ),
                  );
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (!snapshot.data!.exists) {
                  return const Center(child: Text('Report not found.'));
                }

                final data = snapshot.data!.data() ?? {};
                final title = (data['type'] ?? data['title'] ?? 'Illegal Activity').toString();
                final reporter = (data['reporter'] ?? data['reporterName'] ?? '').toString();
                final priority = _titleCase((data['priority'] ?? '').toString());
                final location = (data['location'] ?? '').toString();
                final description = (data['description'] ?? '').toString();
                final status = _titleCase((data['status'] ?? data['actionStatus'] ?? '').toString());
                final incidentDateText = _formatDate(_bestIncidentTimestamp(data));
                final compactIncidentDateText = _formatCompactDate(_bestIncidentTimestamp(data));
                final submittedDateText = _formatDate(_bestSubmittedTimestamp(data));
                final images = _collectImages(data);
                final latitude = (data['latitude'] ?? '').toString().trim();
                final longitude = (data['longitude'] ?? '').toString().trim();
                final reporterLabel = _displayOrFallback(reporter, 'Unknown reporter');
                final incidentDateLabel = _displayOrFallback(incidentDateText, 'Incident time not recorded');
                final compactIncidentDateLabel = _displayOrFallback(compactIncidentDateText, 'Incident time not recorded');
                final submittedDateLabel = _displayOrFallback(submittedDateText, 'Submission time not recorded');
                final summaryText = _displayOrFallback(
                  description,
                  'No narrative was attached to this report. Review the evidence and location details below.',
                );
                final locationLabel = _displayOrFallback(location, 'No location was attached to this report.');
                final coordinates = latitude.isNotEmpty && longitude.isNotEmpty
                    ? '$latitude, $longitude'
                    : 'Coordinates unavailable';
                final priorityLabel = _displayOrFallback(priority, 'Unspecified');
                final statusLabel = _displayOrFallback(status, 'Pending review');
                final imagesList = images.map((e) => e.toString()).toList();

                return SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(padding, padding, padding, padding + 28),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(22),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF0C3B60), Color(0xFF0A6B78)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(28),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF0C3B60).withOpacity(0.18),
                              blurRadius: 26,
                              offset: const Offset(0, 14),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  width: 56,
                                  height: 56,
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.14),
                                    borderRadius: BorderRadius.circular(18),
                                  ),
                                  child: const Icon(
                                    Icons.gpp_maybe_rounded,
                                    color: Colors.white,
                                    size: 28,
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        title,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 24,
                                          fontWeight: FontWeight.w900,
                                          height: 1.1,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        'Submitted by $reporterLabel',
                                        style: TextStyle(
                                          color: Colors.white.withOpacity(0.82),
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 18),
                            Wrap(
                              spacing: 10,
                              runSpacing: 10,
                              children: [
                                _HeroChip(
                                  icon: Icons.schedule_rounded,
                                  label: incidentDateText.isEmpty
                                      ? incidentDateLabel
                                      : 'Incident $incidentDateLabel',
                                ),
                                _HeroChip(
                                  icon: Icons.flag_rounded,
                                  label: 'Priority $priorityLabel',
                                ),
                                _HeroChip(
                                  icon: Icons.verified_user_outlined,
                                  label: 'Status $statusLabel',
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      _SectionPanel(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFFE3DE),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: const Text(
                                    'Illegal Activity',
                                    style: TextStyle(
                                      color: Color(0xFFDC4C2F),
                                      fontWeight: FontWeight.w800,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                                const Spacer(),
                                _Pill(
                                  label: statusLabel,
                                  bg: _statusBackground(statusLabel),
                                  fg: _statusForeground(statusLabel),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              'Incident Summary',
                              style: TextStyle(
                                color: Color(0xFF102A43),
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              summaryText,
                              style: const TextStyle(
                                color: Color(0xFF425466),
                                fontSize: 14,
                                height: 1.55,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 16),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF7FAFC),
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(color: const Color(0xFFDCE3EC)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Row(
                                    children: [
                                      Icon(
                                        Icons.location_on_outlined,
                                        size: 18,
                                        color: Color(0xFF0A6B78),
                                      ),
                                      SizedBox(width: 8),
                                      Text(
                                        'Location Details',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w800,
                                          color: Color(0xFF102A43),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  Text(
                                    locationLabel,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      height: 1.45,
                                      color: Color(0xFF243B53),
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  Text(
                                    'Coordinates: $coordinates',
                                    style: const TextStyle(
                                      fontSize: 13,
                                      color: Color(0xFF52606D),
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final factWidth = (constraints.maxWidth - 12) / 2;
                          const factHeight = 96.0;

                          return Wrap(
                            spacing: 12,
                            runSpacing: 12,
                            children: [
                              SizedBox(
                                width: factWidth,
                                height: factHeight,
                                child: _FactCard(
                                  icon: Icons.person_outline_rounded,
                                  label: 'Reporter',
                                  value: reporterLabel,
                                  accent: const Color(0xFF0A6B78),
                                ),
                              ),
                              SizedBox(
                                width: factWidth,
                                height: factHeight,
                                child: _FactCard(
                                  icon: Icons.schedule_rounded,
                                  label: 'Incident',
                                  value: compactIncidentDateLabel,
                                  accent: const Color(0xFF1565C0),
                                  valueFontSize: 13,
                                ),
                              ),
                              SizedBox(
                                width: factWidth,
                                height: factHeight,
                                child: _FactCard(
                                  icon: Icons.flag_outlined,
                                  label: 'Priority',
                                  value: priorityLabel,
                                  accent: _priorityForeground(priorityLabel),
                                  tone: _priorityBackground(priorityLabel),
                                ),
                              ),
                              SizedBox(
                                width: factWidth,
                                height: factHeight,
                                child: _FactCard(
                                  icon: Icons.task_alt_rounded,
                                  label: 'Status',
                                  value: statusLabel,
                                  accent: _statusForeground(statusLabel),
                                  tone: _statusBackground(statusLabel),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 18),
                      _SectionPanel(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 42,
                              height: 42,
                              decoration: BoxDecoration(
                                color: const Color(0xFFE6F0FA),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: const Icon(
                                Icons.upload_file_outlined,
                                color: Color(0xFF0C3B60),
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Submitted',
                                    style: TextStyle(
                                      color: Color(0xFF7B8794),
                                      fontWeight: FontWeight.w700,
                                      fontSize: 12,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    submittedDateLabel,
                                    style: const TextStyle(
                                      color: Color(0xFF102A43),
                                      fontWeight: FontWeight.w800,
                                      fontSize: 14,
                                      height: 1.35,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      _SectionPanel(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Text(
                                  'Evidence Photos',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w900,
                                    color: Color(0xFF102A43),
                                  ),
                                ),
                                const Spacer(),
                                _Pill(
                                  label: '${images.length} file${images.length == 1 ? '' : 's'}',
                                  bg: const Color(0xFFE6F0FA),
                                  fg: const Color(0xFF0C3B60),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              images.isEmpty
                                  ? 'No supporting photos were attached to this report.'
                                  : 'Tap any photo to inspect it full screen.',
                              style: const TextStyle(
                                fontSize: 13,
                                height: 1.45,
                                color: Color(0xFF52606D),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 16),
                            if (images.isEmpty)
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 26),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF7FAFC),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(color: const Color(0xFFDCE3EC)),
                                ),
                                child: const Column(
                                  children: [
                                    Icon(
                                      Icons.photo_library_outlined,
                                      size: 34,
                                      color: Color(0xFF7B8794),
                                    ),
                                    SizedBox(height: 10),
                                    Text(
                                      'No photos uploaded',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w800,
                                        color: Color(0xFF243B53),
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            else
                              LayoutBuilder(
                                builder: (context, constraints) {
                                  final thumbSize = constraints.maxWidth >= 420 ? 104.0 : 92.0;

                                  return Wrap(
                                    spacing: 10,
                                    runSpacing: 10,
                                    children: List.generate(images.length, (i) {
                                      final url = images[i];

                                      return GestureDetector(
                                        onTap: () => _openImage(
                                          context,
                                          urls: imagesList,
                                          initialIndex: i,
                                        ),
                                        child: Container(
                                          width: thumbSize,
                                          height: thumbSize,
                                          decoration: BoxDecoration(
                                            borderRadius: BorderRadius.circular(18),
                                            boxShadow: [
                                              BoxShadow(
                                                color: Colors.black.withOpacity(0.06),
                                                blurRadius: 14,
                                                offset: const Offset(0, 8),
                                              ),
                                            ],
                                          ),
                                          child: ClipRRect(
                                            borderRadius: BorderRadius.circular(18),
                                            child: Stack(
                                              fit: StackFit.expand,
                                              children: [
                                                _buildEvidenceImage(url),
                                                const DecoratedBox(
                                                  decoration: BoxDecoration(
                                                    gradient: LinearGradient(
                                                      begin: Alignment.topCenter,
                                                      end: Alignment.bottomCenter,
                                                      colors: [
                                                        Color(0x12000000),
                                                        Color(0x70000000),
                                                      ],
                                                    ),
                                                  ),
                                                ),
                                                Positioned(
                                                  left: 8,
                                                  top: 8,
                                                  child: _OverlayChip(
                                                    label: '${i + 1}',
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      );
                                    }),
                                  );
                                },
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _FullScreenImagePage extends StatefulWidget {
  const _FullScreenImagePage({
    required this.urls,
    required this.initialIndex,
  });

  final List<String> urls;
  final int initialIndex;

  @override
  State<_FullScreenImagePage> createState() => _FullScreenImagePageState();
}

class _FullScreenImagePageState extends State<_FullScreenImagePage> {
  late final PageController _controller;
  late int _current;

  @override
  void initState() {
    super.initState();
    _current = widget.initialIndex;
    _controller = PageController(initialPage: _current);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Stack(
        children: [
          PageView.builder(
            controller: _controller,
            onPageChanged: (index) => setState(() => _current = index),
            itemCount: widget.urls.length,
            itemBuilder: (_, index) {
              final url = widget.urls[index];
              final bool isData = url.startsWith('data:image');
              Uint8List? bytes;
              if (isData) {
                try {
                  bytes = base64.decode(url.split(',').last);
                } catch (_) {}
              }

              final image = isData && bytes != null
                  ? Image.memory(bytes, fit: BoxFit.contain)
                  : Image.network(url, fit: BoxFit.contain);

              return Center(
                child: InteractiveViewer(
                  panEnabled: true,
                  minScale: 0.5,
                  maxScale: 4,
                  child: image,
                ),
              );
            },
          ),
          if (widget.urls.length > 1)
            Positioned(
              bottom: 16,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (int i = 0; i < widget.urls.length; i++)
                    Container(
                      width: 8,
                      height: 8,
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: i == _current ? Colors.white : Colors.white54,
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final String label;
  final Color bg;
  final Color fg;

  const _Pill({required this.label, required this.bg, required this.fg});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          color: fg,
        ),
      ),
    );
  }
}

class _HeroChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _HeroChip({
    required this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withOpacity(0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.white),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionPanel extends StatelessWidget {
  final Widget child;

  const _SectionPanel({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFDCE3EC)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _OverlayChip extends StatelessWidget {
  final String label;

  const _OverlayChip({
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xB3141E2E),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0x33FFFFFF)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
          fontSize: 11,
        ),
      ),
    );
  }
}

class _FactCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color accent;
  final Color? tone;
  final double valueFontSize;

  const _FactCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.accent,
    this.tone,
    this.valueFontSize = 14,
  });

  @override
  Widget build(BuildContext context) {
    final toneColor = tone ?? accent.withOpacity(0.10);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFDCE3EC)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 14,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: toneColor,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: accent, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF7B8794),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: valueFontSize,
                    height: 1.35,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF102A43),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ImageErrorTile extends StatelessWidget {
  const _ImageErrorTile();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFE2E8F0),
      child: const Center(
        child: Icon(
          Icons.broken_image_outlined,
          color: Color(0xFF7B8794),
          size: 30,
        ),
      ),
    );
  }
}
