import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'admin_account_page.dart';
import 'admin_dashboard_page.dart';
import 'admin_educational_page.dart';
import 'admin_notification_page.dart';

class AdminNavigationBar extends StatelessWidget {
  const AdminNavigationBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  final int currentIndex;
  final ValueChanged<int> onTap;

  void _handleTap(int index) {
    if (index == currentIndex) return;
    onTap(index);
  }

  bool _isCommunityNotification(Map<String, dynamic> data) {
    final type = (data['type'] ?? data['category'] ?? '').toString().toLowerCase();
    final title = (data['title'] ?? '').toString().toLowerCase();
    final message = (data['message'] ?? '').toString().toLowerCase();
    const communityKeys = [
      'community',
      'post',
      'comment',
      'like',
      'pcg post',
      'bfar post',
      'post_report',
      'post reported',
      'community_post_pending',
    ];
    bool containsAny(String value) => communityKeys.any((k) => value.contains(k));
    return containsAny(type) || containsAny(title) || containsAny(message);
  }

  bool _isEmergencyReport(Map<String, dynamic> data) {
    if (data['notifyAll'] == true) return true;
    final title = (data['title'] ?? '').toString().toLowerCase();
    final type = (data['type'] ?? data['category'] ?? '').toString().toLowerCase();
    final message = (data['message'] ?? '').toString().toLowerCase();
    if (title.contains('emergency')) return true;
    if (type.contains('emergency')) return true;
    if (message.contains('level:') && (data['lat'] != null || data['mapUrl'] != null)) return true;
    return false;
  }

  bool _isRelevant(Map<String, dynamic> data, String? currentAdminId) {
    final type = (data['type'] ?? data['category'] ?? '').toString().toLowerCase();
    final category = (data['category'] ?? '').toString().toLowerCase();
    final status = (data['status'] ?? data['approvalStatus'] ?? '')
        .toString()
        .trim()
        .toLowerCase();

    if ((type.contains('pcg_registration_request') ||
            category.contains('pcg_registration')) &&
        status == 'approved') {
      return false;
    }

    if (type.contains('comment_report') || category.contains('comment_report')) {
      return false;
    }
    if (_isCommunityNotification(data)) {
      return false;
    }

    final targetUserId = (data['targetUserId'] ?? '').toString().trim();
    if (targetUserId.isNotEmpty) {
      return false;
    }

    final senderId = (data['reporterId'] ?? data['senderId'] ?? '').toString().trim();
    if (currentAdminId != null &&
        senderId.isNotEmpty &&
        senderId == currentAdminId &&
        _isEmergencyReport(data)) {
      return false;
    }

    final title = (data['title'] ?? '').toString().toLowerCase();
    final message = (data['message'] ?? '').toString().toLowerCase();
    const keywords = [
      'pcg',
      'illegal',
      'report',
      'approved',
      'bfar',
      'education',
      'resource',
      'weather',
      'ocean',
      'alert',
      'storm',
      'warning',
    ];
    bool containsKeyword(String value) => keywords.any((k) => value.contains(k));

    return containsKeyword(type) || containsKeyword(title) || containsKeyword(message);
  }

  Widget _buildNavItem({
    required String label,
    required bool selected,
    required VoidCallback onTap,
    required Widget icon,
    int badgeCount = 0,
  }) {
    const accent = Color(0xFF0A3558);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          decoration: BoxDecoration(
            gradient: selected
                ? const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color(0xFF083A64),
                      Color(0xFF0F6A86),
                    ],
                  )
                : null,
            borderRadius: BorderRadius.circular(20),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: accent.withValues(alpha: 0.18),
                      blurRadius: 16,
                      offset: const Offset(0, 8),
                    ),
                  ]
                : const [],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  icon,
                  if (badgeCount > 0)
                    Positioned(
                      top: -6,
                      right: -10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE34D4D),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: Colors.white, width: 1.2),
                        ),
                        child: Text(
                          badgeCount > 99 ? '99+' : '$badgeCount',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              FittedBox(
                child: Text(
                  label,
                  style: TextStyle(
                    color: selected
                        ? Colors.white
                        : accent.withValues(alpha: 0.72),
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.1,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildIcon(IconData icon, {required bool selected}) {
    return Icon(
      icon,
      size: 22,
      color: selected ? Colors.white : const Color(0xFF0A3558),
    );
  }

  Widget _buildProfileIcon({required bool selected}) {
    return Container(
      width: 24,
      height: 24,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: selected ? Colors.white.withValues(alpha: 0.12) : Colors.white,
        shape: BoxShape.circle,
        border: Border.all(
          color: selected
              ? Colors.white.withValues(alpha: 0.24)
              : const Color(0xFF0A3558).withValues(alpha: 0.18),
        ),
      ),
      child: ClipOval(
        child: Image.asset(
          'assets/pcg.jpg',
          fit: BoxFit.cover,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentAdminId = FirebaseAuth.instance.currentUser?.uid;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
        child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('notifications')
              .where('isRead', isEqualTo: false)
              .snapshots(),
          builder: (context, snapshot) {
            int unreadNotifications = 0;
            final Set<String> notifiedReportIds = <String>{};
            if (!snapshot.hasError) {
              final docs = snapshot.data?.docs ?? [];
              for (final d in docs) {
                final data = d.data();
                if (!_isRelevant(data, currentAdminId)) continue;
                unreadNotifications++;
                final reportId = (data['reportId'] ?? '').toString().trim();
                if (reportId.isNotEmpty) {
                  notifiedReportIds.add(reportId);
                }
              }
            }

            return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('reports')
                  .orderBy('submittedAt', descending: true)
                  .limit(25)
                  .snapshots(),
              builder: (context, reportsSnapshot) {
                int unreadReports = 0;
                if (!reportsSnapshot.hasError) {
                  final reportDocs = reportsSnapshot.data?.docs ?? [];
                  for (final doc in reportDocs) {
                    if (notifiedReportIds.contains(doc.id)) continue;
                    final data = doc.data();
                    if (data['adminCleared'] == true) continue;
                    if (data['adminIsRead'] == true) continue;
                    unreadReports++;
                  }
                }

                final unread = unreadNotifications + unreadReports;

                return Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF7FBFE).withValues(alpha: 0.96),
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(color: const Color(0xFFD8EAF3)),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF0A3558).withValues(alpha: 0.1),
                        blurRadius: 24,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: _buildNavItem(
                          label: 'Home',
                          selected: currentIndex == 0,
                          onTap: () => _handleTap(0),
                          icon: _buildIcon(
                            Icons.home_rounded,
                            selected: currentIndex == 0,
                          ),
                        ),
                      ),
                      Expanded(
                        child: _buildNavItem(
                          label: 'Learning',
                          selected: currentIndex == 1,
                          onTap: () => _handleTap(1),
                          icon: _buildIcon(
                            Icons.video_library_rounded,
                            selected: currentIndex == 1,
                          ),
                        ),
                      ),
                      Expanded(
                        child: _buildNavItem(
                          label: 'Alerts',
                          selected: currentIndex == 2,
                          onTap: () => _handleTap(2),
                          badgeCount: unread,
                          icon: _buildIcon(
                            Icons.notifications_rounded,
                            selected: currentIndex == 2,
                          ),
                        ),
                      ),
                      Expanded(
                        child: _buildNavItem(
                          label: 'Account',
                          selected: currentIndex == 3,
                          onTap: () => _handleTap(3),
                          icon: _buildProfileIcon(
                            selected: currentIndex == 3,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

/// Wrapper that hosts admin tabs and uses [AdminNavigationBar] to switch.
class AdminNavigationScaffold extends StatefulWidget {
  const AdminNavigationScaffold({super.key, this.initialIndex = 0});

  final int initialIndex;

  @override
  State<AdminNavigationScaffold> createState() => _AdminNavigationScaffoldState();
}

class _AdminNavigationScaffoldState extends State<AdminNavigationScaffold> {
  late int _selectedIndex;

  late final List<Widget> _pages = const [
    AdminDashboard(),
    AdminEducationalPage(),
    AdminNotificationPage(),
    AdminAccountPage(),
  ];

  void _handleTap(int index) {
    if (index == _selectedIndex) return;
    setState(() => _selectedIndex = index);
  }

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.initialIndex.clamp(0, _pages.length - 1);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFEAF4F8),
      body: IndexedStack(
        index: _selectedIndex,
        children: _pages,
      ),
      bottomNavigationBar: AdminNavigationBar(
        currentIndex: _selectedIndex,
        onTap: _handleTap,
      ),
    );
  }
}
