import 'package:flutter/material.dart';

import '../utils/responsive.dart';

class EmergencyLevelOption {
  const EmergencyLevelOption({
    required this.label,
    required this.description,
    required this.badge,
    required this.color,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final String description;
  final String badge;
  final Color color;
  final IconData icon;
  final VoidCallback onTap;
}

class EmergencyLevelSelectorScaffold extends StatelessWidget {
  const EmergencyLevelSelectorScaffold({
    super.key,
    required this.title,
    required this.headline,
    required this.description,
    required this.options,
  });

  final String title;
  final String headline;
  final String description;
  final List<EmergencyLevelOption> options;

  static const Color _ink = Color(0xFF0A2239);
  static const Color _ocean = Color(0xFF0D4D69);
  static const Color _mist = Color(0xFFF4FBFD);

  @override
  Widget build(BuildContext context) {
    final padding = Responsive.pagePadding(context);
    final maxWidth = Responsive.maxContentWidth(context);

    return Scaffold(
      backgroundColor: _mist,
      appBar: AppBar(
        backgroundColor: _mist,
        surfaceTintColor: Colors.transparent,
        foregroundColor: _ink,
        scrolledUnderElevation: 0,
        elevation: 0,
        title: Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: 22,
            color: _ink,
            letterSpacing: -0.3,
          ),
        ),
        leading: IconButton(
          icon: Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFD7EAF1)),
            ),
            child: const Icon(Icons.arrow_back_rounded),
          ),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFFE7F6FA),
              Color(0xFFF8FCFE),
            ],
          ),
        ),
        child: SafeArea(
          top: false,
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth),
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(padding, 12, padding, padding),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Color(0xFF08263F),
                            Color(0xFF0D4D69),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(28),
                        boxShadow: [
                          BoxShadow(
                            color: _ocean.withValues(alpha: 0.18),
                            blurRadius: 24,
                            offset: const Offset(0, 12),
                          ),
                        ],
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 54,
                            height: 54,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(18),
                            ),
                            child: const Icon(
                              Icons.sos_rounded,
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
                                  headline,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 22,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: -0.2,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  description,
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.8),
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    height: 1.4,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    for (final option in options)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: _EmergencyLevelCard(option: option),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EmergencyLevelCard extends StatelessWidget {
  const _EmergencyLevelCard({required this.option});

  final EmergencyLevelOption option;

  static const Color _ink = Color(0xFF0A2239);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(28),
          onTap: option.onTap,
          child: Ink(
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.96),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: option.color.withValues(alpha: 0.22)),
              boxShadow: [
                BoxShadow(
                  color: option.color.withValues(alpha: 0.12),
                  blurRadius: 24,
                  offset: const Offset(0, 14),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(18),
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
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              option.color.withValues(alpha: 0.82),
                              option.color,
                            ],
                          ),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Icon(
                          option.icon,
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
                              option.label,
                              style: const TextStyle(
                                color: _ink,
                                fontSize: 24,
                                fontWeight: FontWeight.w900,
                                letterSpacing: -0.3,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              option.description,
                              style: TextStyle(
                                color: _ink.withValues(alpha: 0.68),
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                height: 1.45,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: option.color.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          option.badge,
                          style: TextStyle(
                            color: option.color,
                            fontWeight: FontWeight.w800,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Container(
                    height: 12,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                        colors: [
                          option.color,
                          option.color.withValues(alpha: 0.72),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Text(
                        'Continue',
                        style: TextStyle(
                          color: option.color,
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                        ),
                      ),
                      const Spacer(),
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: option.color.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.arrow_forward_rounded,
                          color: option.color,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
