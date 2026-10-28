import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dashboard_screen.dart';
import 'educational_screen.dart';
import '../../l10n/app_localizations.dart';

class EducationalSectionPage extends StatefulWidget {
  final String selectedCategory;
  const EducationalSectionPage({super.key, required this.selectedCategory});

  @override
  State<EducationalSectionPage> createState() => _EducationalSectionPageState();
}

class _EducationalSectionPageState extends State<EducationalSectionPage> {
  static const Color _pageTop = Color(0xFFE8F4FF);
  static const Color _pageBottom = Color(0xFFF7FCFF);
  static const Color _ink = Color(0xFF102A43);
  static const Color _subtleInk = Color(0xFF486581);
  static const Color _cardBorder = Color(0xFFD8E4F0);
  static const Color _activeStart = Color(0xFF124F8A);
  static const Color _activeEnd = Color(0xFF1D76B8);

  late String _selectedCategory;

  bool _isActive(dynamic value) {
    if (value == null) return true;
    if (value is bool) return value;
    return value.toString().toLowerCase() == 'true';
  }

  bool _isArchived(dynamic value) {
    if (value == null) return false;
    if (value is bool) return value;
    return value.toString().toLowerCase() == 'true';
  }

  @override
  void initState() {
    super.initState();
    _selectedCategory = widget.selectedCategory;
  }

  void _handleBack() {
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const DashboardScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;

    return Scaffold(
      backgroundColor: _pageBottom,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        elevation: 0,
        leadingWidth: 68,
        leading: Padding(
          padding: const EdgeInsets.only(left: 12),
          child: IconButton(
            style: IconButton.styleFrom(
              backgroundColor: Colors.white.withValues(alpha: 0.94),
              foregroundColor: _ink,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
            onPressed: _handleBack,
          ),
        ),
        centerTitle: true,
        title: Text(
          l.educationalSectionPageTitle,
          style: const TextStyle(
            fontFamily: 'serif',
            fontWeight: FontWeight.w800,
            fontSize: 24,
            color: _ink,
            letterSpacing: 0.2,
          ),
        ),
      ),
      body: SafeArea(
        top: false,
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [_pageTop, _pageBottom],
            ),
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('educational_resources')
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const Padding(
                    padding: EdgeInsets.all(12),
                    child: Text(
                      'Failed to load categories.',
                      style: TextStyle(color: Colors.red),
                    ),
                  );
                }
                if (!snapshot.hasData) {
                  return const Padding(
                    padding: EdgeInsets.all(22),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }

                final docs = snapshot.data!.docs;
                final categoryCounts = <String, int>{};
                bool hasVideo = false;
                for (final d in docs) {
                  final data = d.data();
                  if (_isActive(data['active']) && !_isArchived(data['archived'])) {
                    final name = (data['categoryName'] ?? '').toString().trim();
                    if (name.isNotEmpty) {
                      categoryCounts[name] = (categoryCounts[name] ?? 0) + 1;
                    }
                    final yt = (data['youtubeId'] ?? '').toString().trim();
                    final type = (data['type'] ?? '').toString().toLowerCase();
                    if (yt.isNotEmpty || type == 'video') hasVideo = true;
                  }
                }

                final sorted = categoryCounts.keys.toList()..sort();
                if (sorted.isEmpty && !hasVideo) {
                  return const Padding(
                    padding: EdgeInsets.all(12),
                    child: Text('No categories available.'),
                  );
                }
                if (sorted.isNotEmpty && !sorted.contains(_selectedCategory)) {
                  _selectedCategory = sorted.first;
                }

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildIntroCard(l),
                    const SizedBox(height: 18),
                    if (sorted.isNotEmpty) ...[
                      ...sorted.map(
                        (category) => Padding(
                          padding: const EdgeInsets.only(bottom: 14),
                          child: _buildCategoryButton(
                            context,
                            title: category,
                            count: categoryCounts[category] ?? 0,
                          ),
                        ),
                      ),
                    ],
                    if (hasVideo) ...[
                      const SizedBox(height: 4),
                      _buildVideoRow(context, l.videoInfographicsSection),
                    ],
                    const SizedBox(height: 8),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildIntroCard(AppLocalizations l) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF12365B), Color(0xFF1F6EA8)],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF12365B).withValues(alpha: 0.35),
            blurRadius: 16,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(13),
                  border: Border.all(color: Colors.white24),
                ),
                child: const Icon(
                  Icons.menu_book_rounded,
                  color: Colors.white,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  l.educationalResources,
                  style: const TextStyle(
                    fontFamily: 'serif',
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 22,
                    height: 1.05,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Choose a topic to open regulations, practical guides, and media resources for safer and sustainable fishing.',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.92),
              fontSize: 13.2,
              height: 1.45,
              letterSpacing: 0.1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryButton(
    BuildContext context, {
    required String title,
    required int count,
  }) {
    final isSelected = title == _selectedCategory;
    final icon = _categoryIcon(title);
    final labelColor = isSelected ? Colors.white : _ink;
    final hintColor = isSelected
        ? Colors.white.withValues(alpha: 0.82)
        : _subtleInk.withValues(alpha: 0.92);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: () {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => EducationalScreen(initialCategory: title),
            ),
          );
        },
        child: Ink(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            gradient: isSelected
                ? const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [_activeStart, _activeEnd],
                  )
                : const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Colors.white, Color(0xFFF6FAFF)],
                  ),
            border: Border.all(
              color: isSelected
                  ? Colors.transparent
                  : _cardBorder.withValues(alpha: 0.95),
            ),
            boxShadow: [
              BoxShadow(
                color: isSelected
                    ? _activeStart.withValues(alpha: 0.3)
                    : const Color(0xFF8DA7C3).withValues(alpha: 0.16),
                blurRadius: isSelected ? 16 : 10,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(13),
                  color: isSelected
                      ? Colors.white.withValues(alpha: 0.2)
                      : const Color(0xFFE7F0FB),
                ),
                child: Icon(icon, color: labelColor, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15.3,
                        fontWeight: FontWeight.w800,
                        color: labelColor,
                        height: 1.22,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      count == 1
                          ? '1 resource available'
                          : '$count resources available',
                      style: TextStyle(
                        fontSize: 12.3,
                        color: hintColor,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.arrow_forward_ios_rounded,
                size: 16,
                color: labelColor.withValues(alpha: isSelected ? 0.92 : 0.7),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildVideoRow(BuildContext context, String label) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: () {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => const EducationalScreen(
                initialCategory: 'Video & Infographics Section',
              ),
            ),
          );
        },
        child: Ink(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF0F1F2F), Color(0xFF113454)],
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF0F1F2F).withValues(alpha: 0.34),
                blurRadius: 16,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.2),
                  border: Border.all(color: Colors.white24),
                ),
                child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 30),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 15.6,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Watch guides and visual explainers',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.82),
                        fontSize: 12.2,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              const Icon(
                Icons.arrow_forward_rounded,
                color: Colors.white,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _categoryIcon(String category) {
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
    return Icons.article_rounded;
  }
}
