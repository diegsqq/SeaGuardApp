import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../l10n/app_localizations.dart';

class TermsAndConditionPage extends StatefulWidget {
  final String? continueRouteName;
  final bool signOutOnContinue;

  const TermsAndConditionPage({
    super.key,
    this.continueRouteName,
    this.signOutOnContinue = false,
  });

  @override
  State<TermsAndConditionPage> createState() => _TermsAndConditionPageState();
}

class _TermsAndConditionPageState extends State<TermsAndConditionPage> {
  static const Color _ink = Color(0xFF102A43);
  static const Color _mutedInk = Color(0xFF486581);
  static const Color _bgTop = Color(0xFFEAF3FF);
  static const Color _bgBottom = Color(0xFFF7FBFF);
  static const Color _cardBorder = Color(0xFFD4E4F4);
  static const Color _brand = Color(0xFF0F3D69);

  bool isChecked = false;

  Future<void> _acceptAndContinue() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'acceptedTerms': true,
        'termsAcceptedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
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
            color: _brand,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: _brand.withValues(alpha: 0.22),
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
                  Icons.check_rounded,
                  color: Color(0xFFD7FFE7),
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

    final sections = <_TermsSection>[
      _TermsSection(title: l.introduction, paragraphs: [l.introductionText]),
      _TermsSection(
        title: l.userResponsibilities,
        bullets: [l.accurateInformation, l.accountConfidentiality],
      ),
      _TermsSection(
        title: l.restrictions,
        bullets: [l.noIllegalActivities, l.noHacking],
      ),
      _TermsSection(title: l.dataPrivacy, paragraphs: [l.privacyText]),
      _TermsSection(
        title: l.limitationOfLiability,
        paragraphs: [l.liabilityText],
      ),
      _TermsSection(title: l.changesToTerms, paragraphs: [l.changesText]),
    ];

    return Scaffold(
      backgroundColor: _bgBottom,
      appBar: AppBar(
        leading: widget.continueRouteName == null
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => Navigator.pop(context),
              )
            : null,
        title: Text(
          l.termsAndConditions,
          style: const TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: 29,
            letterSpacing: 0.2,
            color: _ink,
          ),
        ),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        foregroundColor: _ink,
        scrolledUnderElevation: 0,
        elevation: 0,
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
                  color: const Color(0xFFB9D9F6).withValues(alpha: 0.34),
                ),
              ),
            ),
            Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: double.infinity,
                          margin: const EdgeInsets.only(bottom: 14),
                          padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.8),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: _cardBorder),
                            boxShadow: [
                              BoxShadow(
                                color: _ink.withValues(alpha: 0.04),
                                blurRadius: 10,
                                offset: const Offset(0, 5),
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
                                  color: const Color(0xFFEAF3FF),
                                  borderRadius: BorderRadius.circular(11),
                                ),
                                child: const Icon(
                                  Icons.policy_outlined,
                                  size: 20,
                                  color: _brand,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'Please review these terms carefully before continuing.',
                                  style: const TextStyle(
                                    color: _mutedInk,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                    height: 1.45,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        ...sections.map(
                          (section) => _buildSectionCard(section),
                        ),
                        const SizedBox(height: 10),
                      ],
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.92),
                    border: const Border(
                      top: BorderSide(color: Color(0xFFD9E6F3)),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: _ink.withValues(alpha: 0.06),
                        blurRadius: 12,
                        offset: const Offset(0, -3),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => setState(() => isChecked = !isChecked),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 2,
                            vertical: 4,
                          ),
                          child: Row(
                            children: [
                              Checkbox(
                                value: isChecked,
                                activeColor: _brand,
                                onChanged: (value) {
                                  setState(() {
                                    isChecked = value ?? false;
                                  });
                                },
                              ),
                              Expanded(
                                child: Text(
                                  l.agreeToTerms,
                                  style: const TextStyle(
                                    fontSize: 14.5,
                                    color: _ink,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: isChecked ? _acceptAndContinue : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _brand,
                            disabledBackgroundColor: const Color(0xFFB0B8C5),
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            elevation: isChecked ? 4 : 0,
                          ),
                          child: Text(
                            l.continueButton,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionCard(_TermsSection section) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: Colors.white,
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            section.title,
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 19.5,
              color: _ink,
              height: 1.15,
            ),
          ),
          if (section.paragraphs.isNotEmpty || section.bullets.isNotEmpty)
            const SizedBox(height: 10),
          ...section.paragraphs.map(
            (p) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                p,
                style: const TextStyle(
                  fontSize: 16,
                  height: 1.45,
                  color: _mutedInk,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
          ...section.bullets.map(
            (b) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 7),
                    child: Icon(Icons.circle, size: 6, color: _brand),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      b,
                      style: const TextStyle(
                        fontSize: 16,
                        height: 1.45,
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
  final List<String> paragraphs;
  final List<String> bullets;

  const _TermsSection({
    required this.title,
    this.paragraphs = const [],
    this.bullets = const [],
  });
}
