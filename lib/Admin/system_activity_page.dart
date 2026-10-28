import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../utils/responsive.dart';

class SystemActivityPage extends StatefulWidget {
  const SystemActivityPage({super.key});

  @override
  State<SystemActivityPage> createState() => _SystemActivityPageState();
}

class _SystemActivityPageState extends State<SystemActivityPage> {
  int _refreshNonce = 0;

  ImageProvider<Object>? _avatarImageProvider({
    String? avatarBase64,
    String? avatarUrl,
  }) {
    final trimmedBase64 = (avatarBase64 ?? '').trim();
    if (trimmedBase64.isNotEmpty) {
      try {
        return MemoryImage(base64Decode(trimmedBase64));
      } catch (_) {}
    }

    final trimmedUrl = (avatarUrl ?? '').trim();
    if (trimmedUrl.isNotEmpty) {
      return NetworkImage(trimmedUrl);
    }

    return null;
  }

  Future<void> _handleRefresh() async {
    setState(() => _refreshNonce++);
    await Future.delayed(const Duration(milliseconds: 350));
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final padding = Responsive.pagePadding(context);
    final maxWidth = Responsive.maxContentWidth(context, maxWidth: 760);

    return Scaffold(
      backgroundColor: const Color(0xFFEAF4F8),
      appBar: AppBar(
        backgroundColor: const Color(0xFFEAF4F8),
        foregroundColor: const Color(0xFF102A43),
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, size: 26),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          l.adminSystemActivity,
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.2,
          ),
        ),
      ),
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
              top: -88,
              right: -70,
              size: 220,
              colors: const [
                Color(0x2913A4B4),
                Color(0x12103B66),
              ],
            ),
            _buildBackgroundOrb(
              top: 220,
              left: -92,
              size: 170,
              colors: const [
                Color(0x175BC0EB),
                Color(0x0A0A3558),
              ],
            ),
            SafeArea(
              top: false,
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxWidth),
                  child: RefreshIndicator(
                    onRefresh: _handleRefresh,
                    edgeOffset: 12,
                    color: const Color(0xFF0F6A86),
                    child: ListView(
                      key: ValueKey('system-activity-$_refreshNonce'),
                      physics: const BouncingScrollPhysics(
                        parent: AlwaysScrollableScrollPhysics(),
                      ),
                      padding: EdgeInsets.fromLTRB(
                        padding,
                        10,
                        padding,
                        padding + 16,
                      ),
                      children: [
                        _buildActivityContent(context),
                      ],
                    ),
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

  Widget _buildActivityContent(BuildContext context) {
    const pcgRoles = [
      'pcg',
      'pcg_mobile',
      'pcg_subadmin',
      'web-admin-pcg',
      'sub-admin',
      'admin',
    ];
    final currentUid = FirebaseAuth.instance.currentUser?.uid;

    return StreamBuilder<QuerySnapshot>(
      key: ValueKey('pcg-users-$_refreshNonce'),
      stream: FirebaseFirestore.instance
          .collection('users')
          .where('role', whereIn: pcgRoles)
          .limit(50)
          .snapshots(),
      builder: (context, userSnap) {
        final l = AppLocalizations.of(context)!;

        if (userSnap.connectionState == ConnectionState.waiting) {
          return _buildStateCard(
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 48),
              child: Center(child: CircularProgressIndicator()),
            ),
          );
        }

        if (userSnap.hasError) {
          return _buildEmptyState(
            message: 'Could not load PCG accounts.',
            icon: Icons.cloud_off_rounded,
          );
        }

        final userDocs = userSnap.data?.docs ?? [];
        final Map<String, Map<String, dynamic>> pcgUsers = {};
        for (final doc in userDocs) {
          pcgUsers[doc.id] = doc.data() as Map<String, dynamic>;
        }

        if (pcgUsers.isEmpty) {
          return _buildEmptyState(
            message: 'No PCG accounts found.',
            icon: Icons.shield_outlined,
          );
        }

        return StreamBuilder<QuerySnapshot>(
          key: ValueKey('activity-$_refreshNonce'),
          stream: FirebaseFirestore.instance
              .collection('activity_logs')
              .orderBy('timestamp', descending: true)
              .limit(200)
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return _buildStateCard(
                child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 48),
                  child: Center(child: CircularProgressIndicator()),
                ),
              );
            }

            if (snapshot.hasError) {
              return _buildEmptyState(
                message: 'Could not load activity logs.',
                icon: Icons.history_toggle_off_rounded,
              );
            }

            final docs = snapshot.data?.docs ?? [];
            final Map<String, Map<String, dynamic>> lastByUser = {};

            for (final doc in docs) {
              final data = doc.data() as Map<String, dynamic>;
              final uid = (data['userId'] ?? data['uid'] ?? '').toString();
              if (!pcgUsers.containsKey(uid)) continue;
              if (lastByUser.containsKey(uid)) continue;

              final timestamp = data['timestamp'];
              if (timestamp is! Timestamp) continue;

              lastByUser[uid] = {
                'timestamp': timestamp,
                'action': data['action'] ?? '',
              };
            }

            final members = pcgUsers.entries.map((entry) {
              final userData = entry.value;
              final last = lastByUser[entry.key];
              final name = (userData['fullName'] ??
                      userData['name'] ??
                      "${userData['firstName'] ?? ''} ${userData['lastName'] ?? ''}")
                  .toString()
                  .trim();
              final station = (userData['station'] ?? '').toString().trim();
              final username = (userData['username'] ?? '').toString().trim();
              final contact = (userData['contact_number'] ?? '').toString().trim();
              final email = (userData['email'] ?? '').toString().trim();
              final displayName = name.isNotEmpty
                  ? name
                  : station.isNotEmpty
                      ? station
                      : username.isNotEmpty
                          ? username
                          : contact.isNotEmpty
                              ? contact
                              : (email.isNotEmpty ? email : 'Unknown User');
              final role = (userData['role'] ?? '').toString().trim();
              final roleLabel = (userData['roleLabel'] ??
                      userData['role_label'] ??
                      '')
                  .toString()
                  .trim();
              final action = (last?['action'] ?? '').toString().trim();
              final logTimestamp = last?['timestamp'] as Timestamp?;
              final logDate = logTimestamp?.toDate();
              final userLastActive = _asDate(
                userData['lastActive'] ??
                    userData['last_active'] ??
                    userData['lastSeen'] ??
                    userData['last_seen'],
              );
              final bestDate = logDate ?? userLastActive;
              final isFresh = bestDate != null &&
                  DateTime.now().difference(bestDate) <=
                      const Duration(minutes: 5);
              final isSelf = currentUid != null && currentUid == entry.key;
              final avatarUrl = (userData['profileImageUrl'] ??
                      userData['photo_url'] ??
                      userData['authPhotoUrl'] ??
                      userData['avatarUrl'])
                  ?.toString()
                  .trim();
              final avatarBase64 =
                  userData['profileImageBase64']?.toString().trim();

              return _ActivityMember(
                displayName: displayName,
                station: station,
                showStation: station.isNotEmpty &&
                    station.toLowerCase() != displayName.toLowerCase(),
                roleLabel: roleLabel.isNotEmpty
                    ? roleLabel
                    : _prettyRole(role),
                action: action,
                bestDate: bestDate,
                isActive: isSelf || isFresh,
                avatarBase64: avatarBase64,
                avatarUrl: avatarUrl,
              );
            }).toList()
              ..sort((a, b) {
                final ta = a.bestDate ?? DateTime.fromMillisecondsSinceEpoch(0);
                final tb = b.bestDate ?? DateTime.fromMillisecondsSinceEpoch(0);
                return tb.compareTo(ta);
              });

            if (members.isEmpty) {
              return _buildEmptyState(
                message: 'No PCG accounts found.',
                icon: Icons.shield_outlined,
              );
            }

            final onlineCount =
                members.where((member) => member.isActive).length;
            final activeTodayCount = members
                .where(
                  (member) =>
                      member.isActive ||
                      (member.bestDate != null &&
                          DateTime.now().difference(member.bestDate!) <=
                              const Duration(days: 1)),
                )
                .length;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildOverviewCard(
                  title: l.adminSystemActivity,
                  totalCount: members.length,
                  onlineCount: onlineCount,
                  activeTodayCount: activeTodayCount,
                ),
                const SizedBox(height: 18),
                const Padding(
                  padding: EdgeInsets.only(left: 4),
                  child: Text(
                    'Activity roster',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF34506A),
                      letterSpacing: 0.25,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                ...members.map(_buildActivityTile),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildOverviewCard({
    required String title,
    required int totalCount,
    required int onlineCount,
    required int activeTodayCount,
  }) {
    return Container(
      width: double.infinity,
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
            color: const Color(0xFF083A64).withValues(alpha: 0.22),
            blurRadius: 24,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            top: -28,
            right: -18,
            child: Container(
              width: 110,
              height: 110,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.08),
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(
                      Icons.shield_rounded,
                      color: Colors.white,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Text(
                      'PCG admin presence and recent field activity at a glance.',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w500,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  height: 1.05,
                ),
              ),
              const SizedBox(height: 18),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _buildStatChip(
                    label: 'PCG accounts',
                    value: totalCount.toString(),
                  ),
                  _buildStatChip(
                    label: 'Online now',
                    value: onlineCount.toString(),
                  ),
                  _buildStatChip(
                    label: 'Active today',
                    value: activeTodayCount.toString(),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatChip({
    required String label,
    required String value,
  }) {
    return Container(
      constraints: const BoxConstraints(minWidth: 104),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.14),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w900,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.white.withValues(alpha: 0.82),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActivityTile(_ActivityMember member) {
    final statusColor = member.isActive
        ? const Color(0xFF1D9B5E)
        : const Color(0xFF7B8794);
    final statusBackground = member.isActive
        ? const Color(0xFFE7F8EE)
        : const Color(0xFFF1F5F9);
    final statusLabel = member.isActive ? 'Online' : 'Offline';
    final lastSeenLabel = member.isActive
        ? 'Live now'
        : member.bestDate != null
        ? 'Last active ${_relativeTime(member.bestDate!)}'
        : 'No recent log';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: member.isActive
              ? const Color(0xFFCBEAD7)
              : const Color(0xFFD7E4EF),
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0A3558).withValues(alpha: 0.06),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildAvatar(member, statusColor),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      member.displayName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF102A43),
                        height: 1.15,
                      ),
                    ),
                    if (member.showStation) ...[
                      const SizedBox(height: 4),
                      Text(
                        member.station.toUpperCase(),
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF486581),
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                    const SizedBox(height: 6),
                    Text(
                      member.roleLabel,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF627D98),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: statusBackground,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: statusColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      statusLabel,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: statusColor,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (member.action.isNotEmpty) ...[
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
              decoration: BoxDecoration(
                color: const Color(0xFFF7FBFE),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFDCEAF4)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.bolt_rounded,
                    size: 18,
                    color: Color(0xFF0F6A86),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      member.action,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF243B53),
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildMetaChip(
                icon: Icons.schedule_rounded,
                label: lastSeenLabel,
                color: const Color(0xFF154A79),
              ),
              if (member.station.isNotEmpty)
                _buildMetaChip(
                  icon: Icons.location_on_outlined,
                  label: member.station,
                  color: const Color(0xFF0F6A86),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAvatar(_ActivityMember member, Color statusColor) {
    final displayName = member.displayName.isNotEmpty
        ? member.displayName
        : 'PCG';
    final parts = displayName.trim().split(RegExp(r'\s+'));
    final initials = parts.length >= 2
        ? '${parts[0].isNotEmpty ? parts[0][0] : ''}${parts[1].isNotEmpty ? parts[1][0] : ''}'
        : (displayName.isNotEmpty ? displayName[0] : '?');
    final avatarImage = _avatarImageProvider(
      avatarBase64: member.avatarBase64,
      avatarUrl: member.avatarUrl,
    );

    return Stack(
      clipBehavior: Clip.none,
      children: [
        CircleAvatar(
          radius: 28,
          backgroundColor: const Color(0xFFE6F1F7),
          foregroundColor: const Color(0xFF0A4D68),
          backgroundImage: avatarImage,
          child: avatarImage == null
              ? Text(
                  initials.toUpperCase(),
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                  ),
                )
              : null,
        ),
        Positioned(
          right: -1,
          bottom: -1,
          child: Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF0A3558).withValues(alpha: 0.1),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Center(
              child: Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  color: statusColor,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMetaChip({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  DateTime? _asDate(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  String _relativeTime(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) return '${diff.inHours} h ago';
    if (diff.inDays < 7) {
      return '${diff.inDays} day${diff.inDays == 1 ? '' : 's'} ago';
    }
    final weeks = (diff.inDays / 7).floor();
    if (weeks < 5) return '$weeks week${weeks == 1 ? '' : 's'} ago';
    final months = (diff.inDays / 30).floor();
    if (months < 12) return '$months month${months == 1 ? '' : 's'} ago';
    final years = (diff.inDays / 365).floor();
    return '$years year${years == 1 ? '' : 's'} ago';
  }

  String _prettyRole(String role) {
    final cleaned = role.replaceAll(RegExp(r'[_-]+'), ' ').trim();
    if (cleaned.isEmpty) return 'PCG team';

    return cleaned
        .split(' ')
        .where((part) => part.isNotEmpty)
        .map((part) {
          final lower = part.toLowerCase();
          if (lower == 'pcg') return 'PCG';
          if (lower == 'web') return 'Web';
          return '${part[0].toUpperCase()}${part.substring(1).toLowerCase()}';
        })
        .join(' ');
  }

  Widget _buildStateCard({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0xFFD7E6F5)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0A3558).withValues(alpha: 0.07),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _buildEmptyState({
    required String message,
    required IconData icon,
  }) {
    return _buildStateCard(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 22),
        child: Column(
          children: [
            Container(
              width: 58,
              height: 58,
              decoration: const BoxDecoration(
                color: Color(0xFFEAF3FF),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: const Color(0xFF154A79)),
            ),
            const SizedBox(height: 14),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                color: Color(0xFF243B53),
                fontWeight: FontWeight.w700,
                height: 1.35,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActivityMember {
  const _ActivityMember({
    required this.displayName,
    required this.station,
    required this.showStation,
    required this.roleLabel,
    required this.action,
    required this.bestDate,
    required this.isActive,
    required this.avatarBase64,
    required this.avatarUrl,
  });

  final String displayName;
  final String station;
  final bool showStation;
  final String roleLabel;
  final String action;
  final DateTime? bestDate;
  final bool isActive;
  final String? avatarBase64;
  final String? avatarUrl;
}
