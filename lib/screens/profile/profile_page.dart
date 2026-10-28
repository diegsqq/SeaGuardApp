import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../dashboard/navbar_screen.dart';
import 'recent_reports_page.dart';
import '../dashboard/dashboard_screen.dart';
import '../detection/detection_screen.dart';
import '../community/community_screen.dart';
import '../notification_page.dart';
import 'offline_learning_materials_page.dart';
import 'edit_profile_page.dart';
import 'account_management_page.dart';
import 'language_selection_page.dart';
import 'terms_and_condition_page.dart';
import '../../l10n/app_localizations.dart';
import '../../utils/loading_delay.dart';
import '../../utils/responsive.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  static const Color _ink = Color(0xFF102A43);
  static const Color _mutedInk = Color(0xFF486581);
  static const Color _line = Color(0xFFD7E6F5);
  static const Color _tileBlue = Color(0xFFEAF3FF);
  static const Color _brand = Color(0xFF0F2548);

  Map<String, dynamic>? userData;
  bool isLoading = true;
  bool _isLoggingOut = false;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      await withMinimumLoadingTime(Future<void>.value());
      if (mounted) {
        setState(() => isLoading = false);
      }
      return;
    }

    final doc = await withMinimumLoadingTime(FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .get());
    if (!mounted) return;
    setState(() {
      userData = doc.data();
      isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final padding = Responsive.pagePadding(context);
    final maxWidth = Responsive.maxContentWidth(context, maxWidth: 600);
    final vertical = Responsive.verticalSpace(context);
    final bottomInset = MediaQuery.of(context).padding.bottom;
    final firstName = (userData?['firstName'] ?? '').toString().trim();
    final lastName = (userData?['lastName'] ?? '').toString().trim();
    final fullName = '$firstName $lastName'.trim().isEmpty
        ? 'SeaGuard User'
        : '$firstName $lastName'.trim();
    final roleName = (userData?['role'] ?? 'Resident').toString();

    return Stack(
      children: [
        Scaffold(
          backgroundColor: const Color(0xFFF4F8FD),
          appBar: AppBar(
            title: Text(
              AppLocalizations.of(context)!.editProfile,
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w900,
                color: _ink,
              ),
            ),
            centerTitle: false,
            backgroundColor: const Color(0xFFF4F8FD),
            elevation: 0,
            scrolledUnderElevation: 0,
            foregroundColor: _ink,
          ),
          body: isLoading
              ? const Center(child: CircularProgressIndicator())
              : userData == null
              ? Center(
                  child: Text(
                    AppLocalizations.of(context)!.failedToLoadUserData,
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadUserData,
                  child: Center(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: maxWidth),
                      child: ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: EdgeInsets.only(bottom: bottomInset + 118),
                        children: [
                          SizedBox(height: vertical * 0.45),
                          Padding(
                            padding: EdgeInsets.symmetric(horizontal: padding),
                            child: Container(
                              padding: const EdgeInsets.fromLTRB(
                                16,
                                14,
                                14,
                                14,
                              ),
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [Colors.white, Color(0xFFF5FAFF)],
                                ),
                                borderRadius: BorderRadius.circular(22),
                                border: Border.all(color: _line),
                                boxShadow: [
                                  BoxShadow(
                                    color: _brand.withValues(alpha: 0.06),
                                    blurRadius: 18,
                                    offset: const Offset(0, 10),
                                  ),
                                ],
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  CircleAvatar(
                                    radius: 32,
                                    backgroundColor: const Color(0xFFE7EEF7),
                                    backgroundImage:
                                        userData!['profileImageBase64'] != null
                                        ? MemoryImage(
                                            base64Decode(
                                              userData!['profileImageBase64'],
                                            ),
                                          )
                                        : (userData!['profileImageUrl'] != null
                                              ? NetworkImage(
                                                  userData!['profileImageUrl'],
                                                )
                                              : null),
                                    child:
                                        (userData!['profileImageBase64'] ==
                                                null &&
                                            userData!['profileImageUrl'] ==
                                                null)
                                        ? const Icon(
                                            Icons.person,
                                            size: 34,
                                            color: Color(0xFF5D7389),
                                          )
                                        : null,
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          fullName,
                                          style: const TextStyle(
                                            fontSize: 19,
                                            fontWeight: FontWeight.w800,
                                            color: _ink,
                                            height: 1.1,
                                          ),
                                        ),
                                        const SizedBox(height: 3),
                                        Text(
                                          roleName,
                                          style: const TextStyle(
                                            fontSize: 13.5,
                                            color: _mutedInk,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Material(
                                    color: Colors.transparent,
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(12),
                                      onTap: () async {
                                        final updated = await Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) => EditProfilePage(
                                              userData: userData!,
                                            ),
                                          ),
                                        );
                                        if (updated == true) {
                                          await _loadUserData();
                                        }
                                      },
                                      child: Ink(
                                        width: 40,
                                        height: 40,
                                        decoration: BoxDecoration(
                                          color: _tileBlue,
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                          border: Border.all(color: _line),
                                        ),
                                        child: const Icon(
                                          Icons.edit_outlined,
                                          size: 18,
                                          color: Color(0xFF154A79),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          SizedBox(height: vertical + 2),
                          Padding(
                            padding: EdgeInsets.symmetric(horizontal: padding),
                            child: const Text(
                              'Account & Preferences',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF243B53),
                                letterSpacing: 0.2,
                              ),
                            ),
                          ),
                          Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: padding,
                              vertical: 10,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _buildMenuButton(
                                  context,
                                  AppLocalizations.of(
                                    context,
                                  )!.accountManagement,
                                  subtitle:
                                      'Security, credentials, and account controls',
                                  icon: Icons.shield_outlined,
                                  onPressed: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) =>
                                            const AccountManagementPage(),
                                      ),
                                    );
                                  },
                                ),
                                _buildMenuButton(
                                  context,
                                  AppLocalizations.of(context)!.recentReports,
                                  subtitle: AppLocalizations.of(
                                    context,
                                  )!.yourRecentIllegalFishingReports,
                                  icon: Icons.receipt_long_outlined,
                                  onPressed: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) =>
                                            const RecentReportsPage(),
                                      ),
                                    );
                                  },
                                ),
                                _buildMenuButton(
                                  context,
                                  "Tips and Guide",
                                  subtitle: 'Saved tips and guides',
                                  icon: Icons.menu_book_outlined,
                                  onPressed: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) =>
                                            const OfflineLearningMaterialsPage(),
                                      ),
                                    );
                                  },
                                ),
                                _buildMenuButton(
                                  context,
                                  AppLocalizations.of(
                                    context,
                                  )!.termsAndConditions,
                                  subtitle: 'Policies and legal agreements',
                                  icon: Icons.description_outlined,
                                  onPressed: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) =>
                                            const TermsAndConditionPage(),
                                      ),
                                    );
                                  },
                                ),
                                _buildMenuButton(
                                  context,
                                  AppLocalizations.of(context)!.language,
                                  subtitle:
                                      'Choose your preferred app language',
                                  icon: Icons.language_outlined,
                                  onPressed: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) =>
                                            const LanguageSelectionPage(),
                                      ),
                                    );
                                  },
                                ),
                              ],
                            ),
                          ),
                          Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: padding,
                              vertical: 10,
                            ),
                            child: _buildLogoutCard(context),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
          bottomNavigationBar: CustomBottomNavBar(
            currentIndex: 4,
            onTap: (index) {
              if (index == 4) return; // Already on profile

              switch (index) {
                case 0:
                  Navigator.pushAndRemoveUntil(
                    context,
                    MaterialPageRoute(builder: (_) => const DashboardScreen()),
                    (route) => false,
                  );
                  break;
                case 1:
                  Navigator.pushAndRemoveUntil(
                    context,
                    MaterialPageRoute(builder: (_) => const CommunityScreen()),
                    (route) => false,
                  );
                  break;
                case 2:
                  Navigator.pushAndRemoveUntil(
                    context,
                    MaterialPageRoute(builder: (_) => const DetectionScreen()),
                    (route) => false,
                  );
                  break;
                case 3:
                  Navigator.pushAndRemoveUntil(
                    context,
                    MaterialPageRoute(builder: (_) => const NotificationPage()),
                    (route) => false,
                  );
                  break;
                default:
                  break;
              }
            },
          ),
        ),
        if (_isLoggingOut)
          Positioned.fill(
            child: ColoredBox(
              color: Colors.black.withValues(alpha: 0.08),
              child: const Center(
                child: SizedBox(
                  height: 46,
                  width: 46,
                  child: CircularProgressIndicator(strokeWidth: 3.5),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildLogoutCard(BuildContext context) {
    final l = AppLocalizations.of(context)!;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7F5),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFF5D2CD)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFB42318).withValues(alpha: 0.04),
            blurRadius: 14,
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
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                l.logOut,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF7A271A),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'Sign out of this device and end the current session securely.',
            style: TextStyle(
              fontSize: 13.2,
              fontWeight: FontWeight.w600,
              color: Color(0xFF9E4C40),
              height: 1.35,
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _isLoggingOut ? null : _confirmAndLogout,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFC81E16),
                foregroundColor: Colors.white,
                disabledBackgroundColor: const Color(0xFFC81E16),
                disabledForegroundColor: Colors.white,
                minimumSize: const Size.fromHeight(48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              icon: _isLoggingOut
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
                  : const Icon(Icons.logout_rounded, size: 18),
              label: Text(
                _isLoggingOut ? 'Logging out...' : l.logOut,
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

  Future<void> _confirmAndLogout() async {
    final l = AppLocalizations.of(context)!;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.adminConfirmLogout),
        content: Text(l.adminConfirmLogoutMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l.cancel),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0F2548),
              foregroundColor: Colors.white,
            ),
            child: Text(l.confirm),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      setState(() => _isLoggingOut = true);
      await FirebaseAuth.instance.signOut();
      if (mounted) {
        Navigator.pushReplacementNamed(context, '/login');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Logout failed: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoggingOut = false);
      }
    }
  }

  Widget _buildMenuButton(
    BuildContext context,
    String title, {
    required IconData icon,
    String? subtitle,
    VoidCallback? onPressed,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap:
              onPressed ??
              () {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('$title page is under construction.')),
                );
              },
          borderRadius: BorderRadius.circular(16),
          child: Ink(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _line),
              boxShadow: [
                BoxShadow(
                  color: _brand.withValues(alpha: 0.045),
                  blurRadius: 12,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: _tileBlue,
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Icon(icon, color: const Color(0xFF154A79), size: 18),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                          color: _ink,
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12.5,
                            color: _mutedInk,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: Color(0xFF829AB1),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
