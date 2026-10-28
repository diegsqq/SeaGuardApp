import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../utils/responsive.dart';
import 'admin_educational_section_page.dart';

class AdminEducationalPage extends StatelessWidget {
  const AdminEducationalPage({super.key});

  static const Color _pageTop = Color(0xFFE8F4FF);
  static const Color _pageBottom = Color(0xFFF7FCFF);
  static const Color _ink = Color(0xFF102A43);
  static const Color _subtleInk = Color(0xFF486581);
  static const Color _cardBorder = Color(0xFFD8E4F0);
  static const Color _activeStart = Color(0xFF124F8A);
  static const Color _activeEnd = Color(0xFF1D76B8);

  static bool _isActive(dynamic value) {
    if (value == null) return true;
    if (value is bool) return value;
    return value.toString().toLowerCase() == 'true';
  }

  static bool _isArchived(dynamic value) {
    if (value == null) return false;
    if (value is bool) return value;
    return value.toString().toLowerCase() == 'true';
  }

  static IconData _categoryIcon(String category) {
    final key = category.toLowerCase();
    if (key.contains('law') ||
        key.contains('circular') ||
        key.contains('policy')) {
      return Icons.gavel_rounded;
    }
    if (key.contains('sustainable') ||
        key.contains('conservation') ||
        key.contains('environment')) {
      return Icons.eco_rounded;
    }
    if (key.contains('safety') || key.contains('advisory')) {
      return Icons.shield_rounded;
    }
    if (key.contains('report') || key.contains('incident')) {
      return Icons.assignment_rounded;
    }
    return Icons.menu_book_rounded;
  }

  static String _categoryDescription(String category) {
    final key = category.toLowerCase();
    if (key.contains('law') ||
        key.contains('circular') ||
        key.contains('policy')) {
      return 'Official issuances, regulations, and compliance references.';
    }
    if (key.contains('sustainable') ||
        key.contains('conservation') ||
        key.contains('environment')) {
      return 'Practical guidance for protecting habitats and fish stocks.';
    }
    if (key.contains('safety') || key.contains('advisory')) {
      return 'Field-ready safety reminders and response procedures.';
    }
    return 'Reference materials and explainers for fishing communities.';
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final padding = Responsive.pagePadding(context);
    final maxWidth = Responsive.maxContentWidth(context);

    return Scaffold(
      backgroundColor: _pageBottom,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [_pageTop, _pageBottom],
          ),
        ),
        child: SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth),
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(padding, 18, padding, padding),
                child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: FirebaseFirestore.instance
                      .collection('educational_resources')
                      .snapshots(),
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return _StateCard(
                        icon: Icons.error_outline_rounded,
                        title: 'Failed to load categories',
                        message:
                            'Check the Firestore connection and try again.',
                        accent: const Color(0xFFBA1A1A),
                      );
                    }

                    if (!snapshot.hasData) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 64),
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }

                    final docs = snapshot.data!.docs;
                    final categoryCounts = <String, int>{};
                    var videoCount = 0;

                    for (final doc in docs) {
                      final data = doc.data();
                      if (!_isActive(data['active']) ||
                          _isArchived(data['archived'])) {
                        continue;
                      }

                      final name = (data['categoryName'] ?? '')
                          .toString()
                          .trim();
                      if (name.isNotEmpty) {
                        categoryCounts[name] = (categoryCounts[name] ?? 0) + 1;
                      }

                      final youtubeId =
                          (data['youtubeId'] ?? '').toString().trim();
                      final type =
                          (data['type'] ?? '').toString().toLowerCase();
                      if (youtubeId.isNotEmpty || type == 'video') {
                        videoCount++;
                      }
                    }

                    final categories = categoryCounts.keys.toList()..sort();
                    final totalResources = categoryCounts.values.fold<int>(
                      0,
                      (sum, count) => sum + count,
                    );

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _HeroBanner(
                          badge: 'ADMIN LEARNING',
                          title: l.educationalSectionPageTitle,
                          description:
                              'A cleaner library for circulars, practical guides, and visual explainers used across the SeaGuard admin workflow.',
                          stats: [
                            _HeroStat(
                              icon: Icons.grid_view_rounded,
                              label: '${categories.length} categories',
                            ),
                            _HeroStat(
                              icon: Icons.auto_stories_rounded,
                              label: '$totalResources resources',
                            ),
                            if (videoCount > 0)
                              _HeroStat(
                                icon: Icons.play_circle_fill_rounded,
                                label: '$videoCount videos',
                              ),
                          ],
                        ),
                        const SizedBox(height: 24),
                        Text(
                          'Browse by topic',
                          style: TextStyle(
                            color: _ink.withValues(alpha: 0.95),
                            fontFamily: 'serif',
                            fontWeight: FontWeight.w800,
                            fontSize: 20,
                            letterSpacing: 0.2,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Open a category to review the latest documents, PDFs, and BFAR learning materials.',
                          style: TextStyle(
                            color: _subtleInk.withValues(alpha: 0.92),
                            fontSize: 13.5,
                            height: 1.45,
                          ),
                        ),
                        const SizedBox(height: 18),
                        if (categories.isEmpty && videoCount == 0)
                          const _StateCard(
                            icon: Icons.menu_book_outlined,
                            title: 'No educational content yet',
                            message:
                                'Publish a resource in Firestore to populate the learning hub.',
                            accent: Color(0xFF124F8A),
                          )
                        else ...[
                          for (final category in categories)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 14),
                              child: _CategoryCard(
                                icon: _categoryIcon(category),
                                title: category,
                                description: _categoryDescription(category),
                                count: categoryCounts[category] ?? 0,
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          AdminEducationalSectionPage(
                                        initialCategory: category,
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          if (videoCount > 0)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: _VideoFeatureCard(
                                label: l.videoInfographicsSection,
                                count: videoCount,
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          const AdminEducationalSectionPage(
                                        initialCategory:
                                            'Video & Infographics Section',
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                        ],
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HeroStat {
  final IconData icon;
  final String label;

  const _HeroStat({required this.icon, required this.label});
}

class _HeroBanner extends StatelessWidget {
  final String badge;
  final String title;
  final String description;
  final List<_HeroStat> stats;

  const _HeroBanner({
    required this.badge,
    required this.title,
    required this.description,
    required this.stats,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0F365A), Color(0xFF1D76B8)],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F365A).withValues(alpha: 0.28),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: Colors.white24),
            ),
            child: Text(
              badge,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11.2,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white24),
                ),
                child: const Icon(
                  Icons.auto_stories_rounded,
                  color: Colors.white,
                  size: 28,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontFamily: 'serif',
                    fontWeight: FontWeight.w800,
                    fontSize: 28,
                    height: 1.05,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            description,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.9),
              fontSize: 13.4,
              height: 1.5,
              letterSpacing: 0.1,
            ),
          ),
          if (stats.isNotEmpty) ...[
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final stat in stats)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: Colors.white30),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(stat.icon, size: 14, color: Colors.white),
                        const SizedBox(width: 6),
                        Text(
                          stat.label,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11.8,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _CategoryCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final int count;
  final VoidCallback onTap;

  const _CategoryCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.count,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Colors.white, Color(0xFFF6FAFF)],
            ),
            border: Border.all(
              color: AdminEducationalPage._cardBorder.withValues(alpha: 0.95),
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF8DA7C3).withValues(alpha: 0.14),
                blurRadius: 14,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(15),
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      AdminEducationalPage._activeStart,
                      AdminEducationalPage._activeEnd,
                    ],
                  ),
                ),
                child: Icon(icon, color: Colors.white, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: AdminEducationalPage._ink,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      description,
                      style: TextStyle(
                        color: AdminEducationalPage._subtleInk.withValues(
                          alpha: 0.92,
                        ),
                        fontSize: 12.9,
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE7F0FB),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        count == 1
                            ? '1 resource available'
                            : '$count resources available',
                        style: const TextStyle(
                          color: Color(0xFF124F8A),
                          fontWeight: FontWeight.w700,
                          fontSize: 11.8,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: const Color(0xFFEAF1FF),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: const Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 16,
                  color: Color(0xFF124F8A),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VideoFeatureCard extends StatelessWidget {
  final String label;
  final int count;
  final VoidCallback onTap;

  const _VideoFeatureCard({
    required this.label,
    required this.count,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(26),
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(26),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF0D1E30), Color(0xFF134063)],
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF0D1E30).withValues(alpha: 0.3),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.18),
                  border: Border.all(color: Colors.white24),
                ),
                child: const Icon(
                  Icons.play_arrow_rounded,
                  color: Colors.white,
                  size: 32,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      count == 1
                          ? '1 visual resource ready to review'
                          : '$count visual resources ready to review',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.84),
                        fontSize: 12.8,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              const Icon(
                Icons.arrow_forward_rounded,
                color: Colors.white,
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StateCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final Color accent;

  const _StateCard({
    required this.icon,
    required this.title,
    required this.message,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 20, 18, 20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        color: Colors.white.withValues(alpha: 0.92),
        border: Border.all(
          color: AdminEducationalPage._cardBorder.withValues(alpha: 0.9),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, color: accent, size: 28),
          ),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AdminEducationalPage._ink,
              fontWeight: FontWeight.w800,
              fontSize: 17,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AdminEducationalPage._subtleInk.withValues(alpha: 0.9),
              fontSize: 13.2,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}
