import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';

class TermsConditionsPage extends StatefulWidget {
  final String? continueRouteName;
  final bool signOutOnContinue;

  const TermsConditionsPage({
    super.key,
    this.continueRouteName,
    this.signOutOnContinue = false,
  });

  @override
  State<TermsConditionsPage> createState() => _TermsConditionsPageState();
}

class _TermsConditionsPageState extends State<TermsConditionsPage> {
  static const Color _ink = Color(0xFF102A43);
  static const Color _mutedInk = Color(0xFF486581);
  static const Color _bgTop = Color(0xFFF8FCFF);
  static const Color _bgBottom = Color(0xFFEAF4F8);
  static const Color _cardBorder = Color(0xFFD6E7EF);
  static const Color _panelBorder = Color(0xFFD1E3EA);
  static const Color _brand = Color(0xFF0F6A86);
  static const Color _brandDeep = Color(0xFF083A64);
  static const Color _brandSoft = Color(0xFFE7F7FB);

  bool isChecked = false;

  Future<void> _acceptAndContinue() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set(
        {
          'acceptedTerms': true,
          'termsAcceptedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    }

    if (!mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    final acceptedMessage = _cleanAcceptedMessage(
      AppLocalizations.of(context)!.acceptedTerms,
    );
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        padding: EdgeInsets.zero,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 18),
        duration: const Duration(seconds: 3),
        content: Container(
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
                color: _brandDeep.withValues(alpha: 0.24),
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
                  Icons.check_rounded,
                  color: Color(0xFFB8F3D5),
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  acceptedMessage,
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
        ),
      ),
    );

    if (widget.signOutOnContinue) {
      await FirebaseAuth.instance.signOut();
    }

    if (!mounted) return;

    final route = widget.continueRouteName;
    if (route != null && route.isNotEmpty) {
      Navigator.pushNamedAndRemoveUntil(context, route, (_) => false);
    } else {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final bottomInset = MediaQuery.of(context).padding.bottom;
    final sections = <_TermsSection>[
      _TermsSection(
        title: l.introduction,
        icon: Icons.info_outline_rounded,
        accent: const Color(0xFF0F6A86),
        paragraphs: [l.introductionText],
      ),
      _TermsSection(
        title: l.userResponsibilities,
        icon: Icons.verified_user_outlined,
        accent: const Color(0xFF1A73A8),
        bullets: [l.accurateInformation, l.accountConfidentiality],
      ),
      _TermsSection(
        title: l.restrictions,
        icon: Icons.gpp_bad_outlined,
        accent: const Color(0xFFC05621),
        bullets: [l.noIllegalActivities, l.noHacking],
      ),
      _TermsSection(
        title: l.dataPrivacy,
        icon: Icons.lock_outline_rounded,
        accent: const Color(0xFF2D8C72),
        paragraphs: [l.privacyText],
      ),
      _TermsSection(
        title: l.limitationOfLiability,
        icon: Icons.balance_outlined,
        accent: const Color(0xFF6B46C1),
        paragraphs: [l.liabilityText],
      ),
      _TermsSection(
        title: l.changesToTerms,
        icon: Icons.update_rounded,
        accent: const Color(0xFF0F6A86),
        paragraphs: [l.changesText],
      ),
    ];

    return Scaffold(
      backgroundColor: _bgBottom,
      appBar: AppBar(
        leading: widget.continueRouteName == null
            ? IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: () => Navigator.pop(context),
              )
            : null,
        title: Text(
          l.adminTermsConditions,
          style: const TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: 22,
            letterSpacing: 0.2,
            color: _ink,
          ),
        ),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        foregroundColor: _ink,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [_bgTop, _bgBottom],
          ),
        ),
        child: Stack(
          children: [
            _buildBackgroundOrb(
              top: -94,
              right: -72,
              size: 230,
              colors: const [Color(0x3313A4B4), Color(0x12103B66)],
            ),
            _buildBackgroundOrb(
              top: 210,
              left: -92,
              size: 180,
              colors: const [Color(0x1A5BC0EB), Color(0x0D0A3558)],
            ),
            SafeArea(
              top: false,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final horizontalPadding = constraints.maxWidth >= 720
                      ? 24.0
                      : 16.0;

                  return Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 760),
                      child: Column(
                        children: [
                          Expanded(
                            child: ListView(
                              physics: const BouncingScrollPhysics(),
                              padding: EdgeInsets.fromLTRB(
                                horizontalPadding,
                                14,
                                horizontalPadding,
                                14,
                              ),
                              children: [
                                _buildHeroCard(l),
                                const SizedBox(height: 16),
                                ...sections.map(_buildSectionCard),
                              ],
                            ),
                          ),
                          _buildConsentPanel(
                            l,
                            horizontalPadding: horizontalPadding,
                            bottomInset: bottomInset,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeroCard(AppLocalizations l) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF083A64), Color(0xFF0F6A86)],
        ),
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            color: _brandDeep.withValues(alpha: 0.22),
            blurRadius: 28,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            top: -30,
            right: -18,
            child: Container(
              width: 116,
              height: 116,
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
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.shield_outlined,
                      size: 16,
                      color: Colors.white,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      l.adminTermsConditions,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.4,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l.termsAndConditions,
                          style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w900,
                            height: 1.05,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          l.adminTermsConditionsSubtitle,
                          style: TextStyle(
                            fontSize: 14,
                            height: 1.5,
                            fontWeight: FontWeight.w500,
                            color: Colors.white.withValues(alpha: 0.86),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 14),
                  Container(
                    width: 62,
                    height: 62,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.16),
                      ),
                    ),
                    child: const Icon(
                      Icons.gavel_rounded,
                      size: 30,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSectionCard(_TermsSection section) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _cardBorder),
        boxShadow: [
          BoxShadow(
            color: _brandDeep.withValues(alpha: 0.06),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            top: -22,
            right: -10,
            child: Container(
              width: 82,
              height: 82,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: section.accent.withValues(alpha: 0.07),
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          section.accent.withValues(alpha: 0.18),
                          section.accent.withValues(alpha: 0.08),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(section.icon, color: section.accent, size: 22),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        section.title,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: _ink,
                          height: 1.2,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              if (section.paragraphs.isNotEmpty || section.bullets.isNotEmpty)
                const SizedBox(height: 14),
              ...section.paragraphs.map(
                (paragraph) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(
                    paragraph,
                    style: const TextStyle(
                      fontSize: 15.2,
                      height: 1.55,
                      color: _mutedInk,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
              ...section.bullets.map(
                (bullet) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Icon(
                          Icons.check_circle_rounded,
                          size: 18,
                          color: section.accent,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          bullet,
                          style: const TextStyle(
                            fontSize: 15.2,
                            height: 1.55,
                            color: _mutedInk,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildConsentPanel(
    AppLocalizations l, {
    required double horizontalPadding,
    required double bottomInset,
  }) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        horizontalPadding,
        0,
        horizontalPadding,
        bottomInset > 0 ? bottomInset : 16,
      ),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.96),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(
            color: isChecked
                ? _brand.withValues(alpha: 0.24)
                : _panelBorder,
          ),
          boxShadow: [
            BoxShadow(
              color: _brandDeep.withValues(alpha: 0.08),
              blurRadius: 22,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: () => setState(() => isChecked = !isChecked),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                decoration: BoxDecoration(
                  color: isChecked ? _brandSoft : const Color(0xFFF5F9FC),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: isChecked
                        ? _brand.withValues(alpha: 0.18)
                        : _panelBorder,
                  ),
                ),
                child: Row(
                  children: [
                    Checkbox(
                      value: isChecked,
                      activeColor: _brand,
                      side: const BorderSide(
                        color: Color(0xFF5E7488),
                        width: 1.6,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                      onChanged: (value) {
                        setState(() => isChecked = value ?? false);
                      },
                    ),
                    Expanded(
                      child: Text(
                        l.agreeToTerms,
                        style: const TextStyle(
                          fontSize: 14.4,
                          color: _ink,
                          fontWeight: FontWeight.w700,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: isChecked ? _acceptAndContinue : null,
                style: FilledButton.styleFrom(
                  backgroundColor: _brandDeep,
                  disabledBackgroundColor: const Color(0xFFB0BDC9),
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(56),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),
                child: Text(
                  l.continueButton,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.2,
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

  String _cleanAcceptedMessage(String message) {
    return message
        .replaceFirst('✅ ', '')
        .replaceFirst('✅', '')
        .replaceFirst('âœ… ', '')
        .replaceFirst('âœ…', '')
        .trim();
  }
}

class _TermsSection {
  final String title;
  final IconData icon;
  final Color accent;
  final List<String> paragraphs;
  final List<String> bullets;

  const _TermsSection({
    required this.title,
    required this.icon,
    required this.accent,
    this.paragraphs = const [],
    this.bullets = const [],
  });
}
