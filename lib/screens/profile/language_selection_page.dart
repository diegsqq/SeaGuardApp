import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/language_provider.dart';
import '../../l10n/app_localizations.dart';

const Color _brandColor = Color(0xFF0F2548);
const Color _inkColor = Color(0xFF102A43);
const Color _mutedInkColor = Color(0xFF486581);
const Color _bgTop = Color(0xFFEAF3FF);
const Color _bgBottom = Color(0xFFF7FBFF);

class LanguageSelectionPage extends StatefulWidget {
  const LanguageSelectionPage({super.key});

  @override
  State<LanguageSelectionPage> createState() => _LanguageSelectionPageState();
}

class _LanguageSelectionPageState extends State<LanguageSelectionPage> {
  String _selectedLanguage = 'en';
  final List<String> _languages = ['en', 'fil'];
  bool _isChangingLanguage = false;
  String _initialLanguage = 'en';

  @override
  void initState() {
    super.initState();
    // Initialize from provider
    final provider = Provider.of<LanguageProvider>(context, listen: false);
    _selectedLanguage = provider.locale.languageCode;
    _initialLanguage = _selectedLanguage;
  }

  String _getDisplayName(String code, BuildContext context) {
    return code == 'en' ? 'English' : 'Filipino';
  }

  String _getLanguageNote(String code) {
    return code == 'en'
        ? 'Use the app interface in English.'
        : 'Gamitin ang app sa wikang Filipino.';
  }

  @override
  Widget build(BuildContext context) {
    final hasPendingChange = _selectedLanguage != _initialLanguage;

    return Scaffold(
      backgroundColor: _bgBottom,
      appBar: AppBar(
        title: Text(
          AppLocalizations.of(context)!.selectLanguage,
          style: const TextStyle(
            fontSize: 29,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.2,
            color: _inkColor,
          ),
        ),
        centerTitle: false,
        backgroundColor: Colors.transparent,
        foregroundColor: _inkColor,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: SafeArea(
        child: Stack(
          children: [
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [_bgTop, _bgBottom],
                ),
              ),
            ),
            Positioned(
              top: -70,
              right: -90,
              child: Container(
                width: 220,
                height: 220,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFFB9D9F6).withValues(alpha: 0.32),
                ),
              ),
            ),
            LayoutBuilder(
              builder: (context, constraints) {
                return Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 500),
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight: constraints.maxHeight - 32,
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.start,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Container(
                              margin: const EdgeInsets.only(bottom: 14),
                              padding: const EdgeInsets.fromLTRB(
                                14,
                                14,
                                14,
                                14,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.82),
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(
                                  color: const Color(0xFFD4E4F4),
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: _inkColor.withValues(alpha: 0.04),
                                    blurRadius: 10,
                                    offset: const Offset(0, 5),
                                  ),
                                ],
                              ),
                              child: const Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(
                                    Icons.translate_rounded,
                                    color: Color(0xFF0F3D69),
                                    size: 22,
                                  ),
                                  SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      'Choose your preferred language for labels, messages, and navigation.',
                                      style: TextStyle(
                                        color: _mutedInkColor,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 14,
                                        height: 1.45,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            ..._languages.map((lang) {
                              final isSelected = _selectedLanguage == lang;
                              return Card(
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                  side: BorderSide(
                                    color: isSelected
                                        ? const Color(0xFF91BEE8)
                                        : const Color(0xFFD4E4F4),
                                    width: isSelected ? 1.4 : 1.0,
                                  ),
                                ),
                                color: isSelected
                                    ? const Color(0xFFEAF3FF)
                                    : Colors.white,
                                margin: const EdgeInsets.only(bottom: 10),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(16),
                                  onTap: () {
                                    setState(() {
                                      _selectedLanguage = lang;
                                    });
                                  },
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 10,
                                    ),
                                    child: Row(
                                      children: [
                                        Radio<String>(
                                          value: lang,
                                          groupValue: _selectedLanguage,
                                          activeColor: _brandColor,
                                          onChanged: (value) {
                                            setState(() {
                                              _selectedLanguage = value!;
                                            });
                                          },
                                        ),
                                        const SizedBox(width: 4),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                _getDisplayName(lang, context),
                                                style: TextStyle(
                                                  fontSize: 17,
                                                  fontWeight: FontWeight.w700,
                                                  color: isSelected
                                                      ? _brandColor
                                                      : _inkColor,
                                                ),
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                _getLanguageNote(lang),
                                                style: const TextStyle(
                                                  fontSize: 13.2,
                                                  color: _mutedInkColor,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        if (isSelected)
                                          const Icon(
                                            Icons.check_circle_rounded,
                                            color: _brandColor,
                                            size: 19,
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            }),
                            const SizedBox(height: 16),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed:
                                    _isChangingLanguage || !hasPendingChange
                                    ? null
                                    : () async {
                                        final messenger =
                                            ScaffoldMessenger.maybeOf(context);
                                        final navigator = Navigator.of(context);
                                        setState(
                                          () => _isChangingLanguage = true,
                                        );
                                        try {
                                          final provider =
                                              Provider.of<LanguageProvider>(
                                                context,
                                                listen: false,
                                              );
                                          await provider.setLanguage(
                                            _selectedLanguage,
                                          );
                                          if (mounted) {
                                            final l = AppLocalizations.of(
                                              context,
                                            )!;
                                            navigator.pop();
                                            messenger?.hideCurrentSnackBar();
                                            messenger?.showSnackBar(
                                              SnackBar(
                                                backgroundColor:
                                                    Colors.transparent,
                                                elevation: 0,
                                                padding: EdgeInsets.zero,
                                                behavior:
                                                    SnackBarBehavior.floating,
                                                margin:
                                                    const EdgeInsets.fromLTRB(
                                                      16,
                                                      0,
                                                      16,
                                                      18,
                                                    ),
                                                duration: const Duration(
                                                  seconds: 3,
                                                ),
                                                content: _buildSuccessToast(
                                                  l.languageSet(
                                                    _getDisplayName(
                                                      _selectedLanguage,
                                                      context,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            );
                                          }
                                        } finally {
                                          if (mounted) {
                                            setState(
                                              () => _isChangingLanguage = false,
                                            );
                                          }
                                        }
                                      },
                                style: ElevatedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 14,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  backgroundColor: _brandColor,
                                  disabledBackgroundColor: const Color(
                                    0xFFB0B8C5,
                                  ),
                                  foregroundColor: Colors.white,
                                  textStyle: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                  ),
                                  elevation: hasPendingChange ? 4 : 0,
                                ),
                                child: _isChangingLanguage
                                    ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          valueColor:
                                              AlwaysStoppedAnimation<Color>(
                                                Colors.white,
                                              ),
                                        ),
                                      )
                                    : Text(
                                        hasPendingChange
                                            ? AppLocalizations.of(context)!.save
                                            : 'Saved',
                                      ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSuccessToast(String message) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: _brandColor,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: _brandColor.withValues(alpha: 0.22),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.translate_rounded,
              color: Color(0xFFD7FFE7),
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14.2,
                fontWeight: FontWeight.w700,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
