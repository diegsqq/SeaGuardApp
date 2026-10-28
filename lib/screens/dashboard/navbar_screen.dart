import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dashboard_screen.dart';
import '../community/community_screen.dart';
import '../detection/detection_screen.dart';
import '../notification_page.dart';
import '../profile/profile_page.dart';

class CustomBottomNavBar extends StatelessWidget {
  final int currentIndex;
  final Function(int) onTap;

  const CustomBottomNavBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  Future<void> _showScanMenu(BuildContext context) async {
    final screenSize = MediaQuery.of(context).size;
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    const menuWidth = 85.0;
    const menuHeight = 160.0;

    final itemWidth = screenSize.width / 5;
    final centerX = itemWidth * 2 + itemWidth / 2;
    final left =
        (centerX - (menuWidth / 2)).clamp(8.0, screenSize.width - menuWidth - 8);
    final right = screenSize.width - left - menuWidth;
    final top = screenSize.height -
        kBottomNavigationBarHeight -
        bottomPadding -
        menuHeight +
        48;

    final selection = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(left, top, right, 0),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      items: const [
        PopupMenuItem(
          value: 'camera',
          child: SizedBox(
            width: menuWidth,
            child: Row(
              children: [
                Icon(Icons.camera_alt_outlined),
                SizedBox(width: 2),
                Text('Camera'),
              ],
            ),
          ),
        ),
        PopupMenuDivider(height: 1),
        PopupMenuItem(
          value: 'upload',
          child: SizedBox(
            width: menuWidth,
            child: Row(
              children: [
                Icon(Icons.upload_file_outlined),
                SizedBox(width: 2),
                Text('Upload'),
              ],
            ),
          ),
        ),
      ],
    );

    if (selection == 'camera') {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(
          builder: (_) =>
              const DetectionScreen(launchMode: DetectionLaunchMode.camera),
        ),
        (route) => false,
      );
    } else if (selection == 'upload') {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(
          builder: (_) =>
              const DetectionScreen(launchMode: DetectionLaunchMode.gallery),
        ),
        (route) => false,
      );
    }
  }

  void _pushRoot(BuildContext context, Widget page) {
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => page),
      (route) => false,
    );
  }

  void _navigate(BuildContext context, int index) {
    if (index == currentIndex && index != 2) return;

    switch (index) {
      case 0:
        _pushRoot(context, const DashboardScreen());
        break;
      case 1:
        _pushRoot(context, const CommunityScreen());
        break;
      case 2:
        _showScanMenu(context);
        break;
      case 3:
        _pushRoot(context, const NotificationPage());
        break;
      case 4:
        _pushRoot(context, const ProfilePage());
        break;
      default:
        return;
    }
  }

  Widget _buildNavItem({
    required BuildContext context,
    required IconData icon,
    required String label,
    required bool selected,
    required VoidCallback onTap,
    int badgeCount = 0,
  }) {
    final color = selected ? const Color(0xFF0F2548) : Colors.black54;
    return Semantics(
      label: label,
      selected: selected,
      button: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(icon, color: color, size: 24),
                  if (badgeCount > 0)
                    Positioned(
                      top: -6,
                      right: -10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.red,
                          borderRadius: BorderRadius.circular(12),
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
              if (selected)
                Container(
                  height: 4,
                  width: 14,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildScanButton(BuildContext context) {
    return InkWell(
      onTap: () => _navigate(context, 2),
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF0F2548),
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.12),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: const Icon(Icons.qr_code_scanner, color: Colors.white, size: 22),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return _buildBar(context, unreadCount: 0);
    }
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('notifications')
          .where('targetUserId', isEqualTo: user.uid)
          .where('isRead', isEqualTo: false)
          .snapshots(),
      builder: (context, snapshot) {
        final unreadCount = snapshot.data?.docs.length ?? 0;
        return _buildBar(context, unreadCount: unreadCount);
      },
    );
  }

  Widget _buildBar(BuildContext context, {required int unreadCount}) {
    return SafeArea(
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFE9EDF5),
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: _buildNavItem(
                context: context,
                icon: Icons.home,
                label: 'Home',
                selected: currentIndex == 0,
                onTap: () => _navigate(context, 0),
              ),
            ),
            Expanded(
              child: _buildNavItem(
                context: context,
                icon: Icons.chat,
                label: 'Community',
                selected: currentIndex == 1,
                onTap: () => _navigate(context, 1),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: _buildScanButton(context),
            ),
            Expanded(
              child: _buildNavItem(
                context: context,
                icon: Icons.notifications,
                label: 'Alerts',
                selected: currentIndex == 3,
                onTap: () => _navigate(context, 3),
                badgeCount: unreadCount,
              ),
            ),
            Expanded(
              child: _buildNavItem(
                context: context,
                icon: Icons.person,
                label: 'Profile',
                selected: currentIndex == 4,
                onTap: () => _navigate(context, 4),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
