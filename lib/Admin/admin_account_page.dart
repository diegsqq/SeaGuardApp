import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../screens/login/login_screen.dart';
import '../utils/loading_delay.dart';
import '../utils/responsive.dart';
import 'admin_pcg_management_page.dart';
import 'language_settings_page.dart';
import 'system_activity_page.dart';
import 'terms_conditions_page.dart';

class AdminAccountPage extends StatefulWidget {
  const AdminAccountPage({super.key});

  @override
  State<AdminAccountPage> createState() => _AdminAccountPageState();
}

class _AdminAccountPageState extends State<AdminAccountPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  bool _loading = false;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final padding = Responsive.pagePadding(context);
    final maxWidth = Responsive.maxContentWidth(context, maxWidth: 720);
    final vertical = Responsive.verticalSpace(context);
    final currentUser = _auth.currentUser;
    final adminTitle = _resolveAdminTitle(currentUser, l);
    final adminEmail = currentUser?.email?.trim() ?? '';

    return Stack(
      children: [
        Scaffold(
          backgroundColor: const Color(0xFFEAF4F8),
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
                  alignment: Alignment.topRight,
                  top: -96,
                  right: -72,
                  size: 230,
                  colors: const [
                    Color(0x3313A4B4),
                    Color(0x12103B66),
                  ],
                ),
                _buildBackgroundOrb(
                  alignment: Alignment.centerLeft,
                  top: 170,
                  left: -92,
                  size: 180,
                  colors: const [
                    Color(0x1A5BC0EB),
                    Color(0x0D0A3558),
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
                          vertical + 6,
                          padding,
                          vertical * 1.8,
                        ),
                        children: [
                          _buildHeroCard(
                            context,
                            title: adminTitle,
                            subtitle: adminEmail.isNotEmpty
                                ? adminEmail
                                : l.adminRoleTitle,
                          ),
                          SizedBox(height: vertical + 8),
                          Padding(
                            padding: const EdgeInsets.only(left: 4),
                            child: Text(
                              l.adminQuickActions,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF34506A),
                                letterSpacing: 0.3,
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          _buildActionCard(
                            context,
                            title: l.adminSystemActivity,
                            subtitle: l.adminSystemActivitySubtitle,
                            icon: Icons.insights_rounded,
                            accent: const Color(0xFF0F6A86),
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const SystemActivityPage(),
                                ),
                              );
                            },
                          ),
                          const SizedBox(height: 12),
                          _buildActionCard(
                            context,
                            title: 'Account Management & Registration',
                            subtitle:
                                'Review PCG registrations, approve access, and manage account details.',
                            icon: Icons.manage_accounts_rounded,
                            accent: const Color(0xFF1A73A8),
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const AdminPcgManagementPage(),
                                ),
                              );
                            },
                          ),
                          const SizedBox(height: 12),
                          _buildActionCard(
                            context,
                            title: l.adminLanguage,
                            subtitle: l.adminLanguageSubtitle,
                            icon: Icons.translate_rounded,
                            accent: const Color(0xFF2D8C72),
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                      const AdminLanguageSettingsPage(),
                                ),
                              );
                            },
                          ),
                          const SizedBox(height: 12),
                          _buildActionCard(
                            context,
                            title: l.adminTermsConditions,
                            subtitle: l.adminTermsConditionsSubtitle,
                            icon: Icons.gavel_rounded,
                            accent: const Color(0xFF6F5CC2),
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                      const TermsConditionsPage(),
                                ),
                              );
                            },
                          ),
                          SizedBox(height: vertical + 8),
                          _buildLogoutCard(context),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_loading)
          Positioned.fill(
            child: ColoredBox(
              color: const Color(0xFF0A3558).withValues(alpha: 0.18),
              child: const Center(
                child: SizedBox(
                  width: 54,
                  height: 54,
                  child: CircularProgressIndicator(strokeWidth: 4),
                ),
              ),
            ),
          ),
      ],
    );
  }

  String _resolveAdminTitle(User? user, AppLocalizations l) {
    final displayName = user?.displayName?.trim();
    if (displayName != null && displayName.isNotEmpty) {
      return displayName;
    }

    final email = user?.email?.trim();
    if (email != null && email.isNotEmpty) {
      final localPart = email.split('@').first;
      final words = localPart
          .split(RegExp(r'[._-]+'))
          .where((word) => word.trim().isNotEmpty)
          .map((word) {
            final clean = word.trim();
            return '${clean[0].toUpperCase()}${clean.substring(1).toLowerCase()}';
          })
          .toList();
      if (words.isNotEmpty) {
        return words.join(' ');
      }
    }

    return l.adminRoleTitle;
  }

  Widget _buildBackgroundOrb({
    required double size,
    required List<Color> colors,
    double? top,
    double? left,
    double? right,
    AlignmentGeometry alignment = Alignment.center,
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
              begin: alignment,
              end: Alignment.bottomRight,
              colors: colors,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeroCard(
    BuildContext context, {
    required String title,
    required String subtitle,
  }) {
    final l = AppLocalizations.of(context)!;

    return Container(
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
            color: const Color(0xFF083A64).withValues(alpha: 0.24),
            blurRadius: 28,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            top: -26,
            right: -18,
            child: Container(
              width: 112,
              height: 112,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.08),
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l.adminAccountTitle,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.1,
                  color: Colors.white.withValues(alpha: 0.78),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Container(
                    width: 68,
                    height: 68,
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.18),
                      ),
                    ),
                    child: ClipOval(
                      child: Image.asset(
                        'assets/pcg.jpg',
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                            height: 1.05,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          subtitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                            color: Colors.white.withValues(alpha: 0.82),
                            height: 1.25,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Text(
                l.adminAccountSubtitle,
                style: TextStyle(
                  fontSize: 13.5,
                  height: 1.45,
                  fontWeight: FontWeight.w500,
                  color: Colors.white.withValues(alpha: 0.86),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActionCard(
    BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
    required Color accent,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Ink(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: accent.withValues(alpha: 0.14),
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF0A3558).withValues(alpha: 0.07),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Stack(
            children: [
              Positioned(
                top: -18,
                right: -10,
                child: Container(
                  width: 84,
                  height: 84,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: accent.withValues(alpha: 0.08),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 15,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            accent.withValues(alpha: 0.18),
                            accent.withValues(alpha: 0.08),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: Icon(
                        icon,
                        color: accent,
                        size: 22,
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
                              fontSize: 15.5,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF102A43),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            subtitle,
                            style: const TextStyle(
                              fontSize: 12.8,
                              fontWeight: FontWeight.w500,
                              color: Color(0xFF627D98),
                              height: 1.35,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      Icons.arrow_forward_ios_rounded,
                      size: 16,
                      color: accent.withValues(alpha: 0.82),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLogoutCard(BuildContext context) {
    final l = AppLocalizations.of(context)!;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7F5),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFF5D2CD)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF9F2D20).withValues(alpha: 0.06),
            blurRadius: 18,
            offset: const Offset(0, 8),
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
                  color: const Color(0xFFFDE8E6),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.logout_rounded,
                  color: Color(0xFFB42318),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  l.adminLogOut,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF7A271A),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            l.adminSignOutSubtitle,
            style: const TextStyle(
              fontSize: 13.2,
              fontWeight: FontWeight.w500,
              color: Color(0xFF9E4C40),
              height: 1.45,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _loading ? null : _logoutAdmin,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFB42318),
                foregroundColor: Colors.white,
                disabledBackgroundColor: const Color(0xFFB42318),
                disabledForegroundColor: Colors.white,
                minimumSize: const Size.fromHeight(50),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              icon: _loading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          Colors.white,
                        ),
                      ),
                    )
                  : const Icon(Icons.logout_rounded),
              label: Text(
                _loading ? l.adminLoggingOut : l.adminLogOut,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _logoutAdmin() async {
    final l = AppLocalizations.of(context)!;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
        surfaceTintColor: Colors.white,
        title: Text(
          l.adminConfirmLogout,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        content: Text(
          l.adminConfirmLogoutMessage,
          style: const TextStyle(
            color: Color(0xFF486581),
            height: 1.45,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l.adminCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF0F2548),
              foregroundColor: Colors.white,
            ),
            child: Text(l.confirm),
          ),
        ],
      ),
    );

    if (confirm != true) return;
    setState(() => _loading = true);
    final loadingDelay = Future<void>.delayed(appLoadingDelay);

    try {
      final email = _auth.currentUser?.email ?? 'Unknown Admin';

      await _firestore.collection('system_logs').add({
        'user': email,
        'action': 'Admin logged out',
        'timestamp': Timestamp.now(),
      });

      await _auth.signOut();

      if (mounted) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const LoginScreen()),
          (route) => false,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Logout failed: $e')),
        );
      }
    } finally {
      await loadingDelay;
      if (mounted) setState(() => _loading = false);
    }
  }
}
