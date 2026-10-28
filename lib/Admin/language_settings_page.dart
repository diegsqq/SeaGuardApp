import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../providers/language_provider.dart';
import '../utils/responsive.dart';

class AdminLanguageSettingsPage extends StatefulWidget {
  const AdminLanguageSettingsPage({super.key});

  @override
  State<AdminLanguageSettingsPage> createState() =>
      _AdminLanguageSettingsPageState();
}

class _AdminLanguageSettingsPageState extends State<AdminLanguageSettingsPage> {
  static const Color _brandColor = Color(0xFF0A4D68);
  static const Color _inkColor = Color(0xFF102A43);
  static const Color _mutedInkColor = Color(0xFF486581);

  late String _selectedLanguage;
  late String _initialLanguage;
  final List<String> _languages = ['en', 'fil'];
  bool _isChangingLanguage = false;

  @override
  void initState() {
    super.initState();
    final provider = Provider.of<LanguageProvider>(context, listen: false);
    _selectedLanguage = provider.locale.languageCode;
    _initialLanguage = _selectedLanguage;
  }

  String _getDisplayName(String code) {
    return code == 'en' ? 'English' : 'Filipino';
  }

  String _getLanguageNote(String code) {
    return code == 'en'
        ? 'Use the admin dashboard in English.'
        : 'Gamitin ang admin dashboard sa wikang Filipino.';
  }

  Future<void> _saveLanguage() async {
    if (_isChangingLanguage || _selectedLanguage == _initialLanguage) return;

    setState(() => _isChangingLanguage = true);
    try {
      final provider = Provider.of<LanguageProvider>(context, listen: false);
      final messenger = ScaffoldMessenger.maybeOf(context);
      final navigator = Navigator.of(context);
      await provider.setLanguage(_selectedLanguage);

      if (!mounted) return;
      final l = AppLocalizations.of(context)!;
      navigator.pop();
      messenger?.hideCurrentSnackBar();
      messenger?.showSnackBar(
        SnackBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          padding: EdgeInsets.zero,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 18),
          duration: const Duration(seconds: 3),
          content: _buildSuccessToast(
            l.languageSet(_getDisplayName(_selectedLanguage)),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isChangingLanguage = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final padding = Responsive.pagePadding(context);
    final maxWidth = Responsive.maxContentWidth(context, maxWidth: 560);
    final hasPendingChange = _selectedLanguage != _initialLanguage;

    return Scaffold(
      backgroundColor: const Color(0xFFEAF4F8),
      appBar: AppBar(
        title: Text(
          l.selectLanguage,
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.2,
            color: _inkColor,
          ),
        ),
        centerTitle: false,
        backgroundColor: const Color(0xFFEAF4F8),
        foregroundColor: _inkColor,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFFF8FCFF),
              Color(0xFFEAF4F8),
            ],
          ),
        ),
        child: Stack(
          children: [
            _buildBackgroundOrb(
              top: -86,
              right: -76,
              size: 220,
              colors: const [
                Color(0x2913A4B4),
                Color(0x12103B66),
              ],
            ),
            _buildBackgroundOrb(
              top: 230,
              left: -100,
              size: 180,
              colors: const [
                Color(0x175BC0EB),
                Color(0x0A0A3558),
              ],
            ),
            SafeArea(
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxWidth),
                  child: ListView(
                    physics: const BouncingScrollPhysics(),
                    padding: EdgeInsets.fromLTRB(
                      padding,
                      12,
                      padding,
                      padding + 12,
                    ),
                    children: [
                      _buildHeroCard(l),
                      const SizedBox(height: 18),
                      Padding(
                        padding: const EdgeInsets.only(left: 4),
                        child: Text(
                          'Available languages',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF34506A),
                            letterSpacing: 0.25,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      ..._languages.map(
                        (language) => _buildLanguageCard(
                          language: language,
                          selected: _selectedLanguage == language,
                        ),
                      ),
                      const SizedBox(height: 18),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: const Color(0xFFD7E6F5)),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF0A3558).withValues(alpha: 0.05),
                              blurRadius: 16,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              hasPendingChange
                                  ? 'Your language selection will update immediately after saving.'
                                  : 'This language is already active for the admin dashboard.',
                              style: const TextStyle(
                                fontSize: 13.2,
                                fontWeight: FontWeight.w600,
                                color: _mutedInkColor,
                                height: 1.4,
                              ),
                            ),
                            const SizedBox(height: 14),
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton.icon(
                                onPressed:
                                    _isChangingLanguage || !hasPendingChange
                                    ? null
                                    : _saveLanguage,
                                style: FilledButton.styleFrom(
                                  backgroundColor: _brandColor,
                                  foregroundColor: Colors.white,
                                  disabledBackgroundColor: const Color(
                                    0xFFB9C6D3,
                                  ),
                                  minimumSize: const Size.fromHeight(54),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(18),
                                  ),
                                ),
                                icon: _isChangingLanguage
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2.2,
                                          valueColor:
                                              AlwaysStoppedAnimation<Color>(
                                                Colors.white,
                                              ),
                                        ),
                                      )
                                    : Icon(
                                        hasPendingChange
                                            ? Icons.save_rounded
                                            : Icons.check_circle_rounded,
                                      ),
                                label: Text(
                                  _isChangingLanguage
                                      ? 'Saving...'
                                      : hasPendingChange
                                      ? l.save
                                      : 'Saved',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 15.5,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBackgroundOrb({
    required double size,
    required List<Color> colors,
    double? top,
    double? left,
    double? right,
  }) {
    return Positioned(
      top: top,
      left: left,
      right: right,
      child: IgnorePointer(
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: colors,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeroCard(AppLocalizations l) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF083A64),
            Color(0xFF0F6A86),
          ],
        ),
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF083A64).withValues(alpha: 0.22),
            blurRadius: 24,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            top: -28,
            right: -18,
            child: Container(
              width: 110,
              height: 110,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.08),
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(
                  Icons.translate_rounded,
                  color: Colors.white,
                  size: 28,
                ),
              ),
              const SizedBox(height: 18),
              Text(
                l.selectLanguage,
                style: const TextStyle(
                  fontSize: 27,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  height: 1.05,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                l.adminLanguageSubtitle,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w500,
                  height: 1.45,
                  color: Colors.white.withValues(alpha: 0.86),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLanguageCard({
    required String language,
    required bool selected,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: selected ? const Color(0xFFEAF3FF) : Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: selected
              ? const Color(0xFF91BEE8)
              : const Color(0xFFD7E6F5),
          width: selected ? 1.4 : 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0A3558).withValues(alpha: 0.05),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: () => setState(() => _selectedLanguage = language),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Radio<String>(
                  value: language,
                  groupValue: _selectedLanguage,
                  activeColor: _brandColor,
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() => _selectedLanguage = value);
                  },
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _getDisplayName(language),
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: selected ? _brandColor : _inkColor,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        _getLanguageNote(language),
                        style: const TextStyle(
                          fontSize: 13.2,
                          color: _mutedInkColor,
                          fontWeight: FontWeight.w500,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
                if (selected)
                  const Icon(
                    Icons.check_circle_rounded,
                    color: _brandColor,
                    size: 20,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSuccessToast(String message) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF083A64), Color(0xFF0F6A86)],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF083A64).withValues(alpha: 0.22),
            blurRadius: 22,
            offset: const Offset(0, 12),
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
              color: Color(0xFFB8F3D5),
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
