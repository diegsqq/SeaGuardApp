import 'package:flutter/material.dart';
import '../../l10n/app_localizations.dart';

class OfflineLearningMaterialsPage extends StatelessWidget {
  const OfflineLearningMaterialsPage({super.key});

  static const Color _ink = Color(0xFF102A43);
  static const Color _mutedInk = Color(0xFF486581);
  static const Color _bgTop = Color(0xFFEAF3FF);
  static const Color _bgBottom = Color(0xFFF7FBFF);
  static const Color _cardBorder = Color(0xFFD6E5F4);

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final sections = <_Section>[
      _Section(
        title: l.offlineLearningSustainableTitle,
        content: l.offlineLearningSustainableContent,
        icon: Icons.sailing_rounded,
        accent: const Color(0xFF1C7ED6),
      ),
      _Section(
        title: l.offlineLearningBiodiversityTitle,
        content: l.offlineLearningBiodiversityContent,
        icon: Icons.eco_rounded,
        accent: const Color(0xFF2B8A5A),
      ),
      _Section(
        title: l.offlineLearningIllegalTitle,
        content: l.offlineLearningIllegalContent,
        icon: Icons.gavel_rounded,
        accent: const Color(0xFFD9480F),
      ),
      _Section(
        title: l.offlineLearningConservationTitle,
        content: l.offlineLearningConservationContent,
        icon: Icons.waves_rounded,
        accent: const Color(0xFF3B5BDB),
      ),
    ];

    return Scaffold(
      backgroundColor: _bgBottom,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        foregroundColor: _ink,
        centerTitle: false,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, size: 24),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          l.offlineLearningMaterialsTitle,
          style: const TextStyle(
            fontSize: 29,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.2,
          ),
        ),
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
              right: -80,
              child: Container(
                width: 220,
                height: 220,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFFAED4F7).withValues(alpha: 0.36),
                ),
              ),
            ),
            Positioned(
              top: 160,
              left: -70,
              child: Container(
                width: 170,
                height: 170,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFFCDE5FA).withValues(alpha: 0.4),
                ),
              ),
            ),
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 18,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: double.infinity,
                        margin: const EdgeInsets.only(bottom: 16),
                        padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.78),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: _cardBorder),
                          boxShadow: [
                            BoxShadow(
                              color: _ink.withValues(alpha: 0.05),
                              blurRadius: 12,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: const Color(0xFFE7F2FF),
                                borderRadius: BorderRadius.circular(11),
                              ),
                              child: const Icon(
                                Icons.offline_bolt_rounded,
                                color: Color(0xFF1C7ED6),
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                l.offlineLearningMaterialsIntro,
                                textAlign: TextAlign.left,
                                style: const TextStyle(
                                  fontSize: 14.5,
                                  color: _mutedInk,
                                  height: 1.45,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      for (final section in sections)
                        _buildCard(
                          title: section.title,
                          content: section.content,
                          icon: section.icon,
                          accent: section.accent,
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

  Widget _buildCard({
    required String title,
    required String content,
    required IconData icon,
    required Color accent,
  }) {
    final paragraphs = content
        .trim()
        .split('\n\n')
        .where((p) => p.trim().isNotEmpty)
        .toList();
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _cardBorder),
        boxShadow: [
          BoxShadow(
            color: _ink.withValues(alpha: 0.06),
            blurRadius: 14,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(icon, size: 19, color: accent),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: _ink,
                    height: 1.1,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (int i = 0; i < paragraphs.length; i++) ...[
            Text(
              paragraphs[i].trim(),
              style: TextStyle(
                fontSize: 16.2,
                height: 1.45,
                color: _ink.withValues(alpha: 0.9),
                fontWeight: FontWeight.w500,
              ),
            ),
            if (i != paragraphs.length - 1) const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}

class _Section {
  final String title;
  final String content;
  final IconData icon;
  final Color accent;

  const _Section({
    required this.title,
    required this.content,
    required this.icon,
    required this.accent,
  });
}
