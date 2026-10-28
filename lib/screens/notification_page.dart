import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:intl/intl.dart';
import 'community/community_screen.dart' as community;
import 'dashboard/navbar_screen.dart';
import 'dashboard/weather_ocean_alerts_screen.dart';
import 'profile/recent_reports_page.dart';
import '../utils/responsive.dart';

const Color _notificationPrimaryColor = Color(0xFF0F2548);

Future<void> sendNotificationToUser({
  required String targetUserId,
  required String title,
  required String message,
  Map<String, dynamic>? extra,
}) async {
  if (targetUserId.isEmpty) return;
  try {
    await FirebaseFirestore.instance.collection('notifications').add({
      'targetUserId': targetUserId,
      'title': title,
      'message': message,
      'timestamp': FieldValue.serverTimestamp(),
      'isRead': false,
      if (extra != null) ...extra,
    });
  } catch (_) {}
}

class NotificationPage extends StatefulWidget {
  const NotificationPage({super.key});

  @override
  State<NotificationPage> createState() => _NotificationPageState();
}

class _NotificationPageState extends State<NotificationPage> {
  static const Color _pageTop = Color(0xFFEAF4FF);
  static const Color _pageBottom = Color(0xFFF8FCFF);
  static const Color _ink = Color(0xFF102A43);
  static const Color _subtleInk = Color(0xFF486581);

  Stream<QuerySnapshot>? _notificationsStream;
  Stream<QuerySnapshot>? _reportsStream;
  Stream<QuerySnapshot>? _sightingsStream;
  Stream<QuerySnapshot>? _roleNotificationsStream;
  String? _userRole;
  List<bool> _readStatuses = [];
  String _selectedFilter = 'All';

  @override
  void initState() {
    super.initState();
    _initNotifications();

    _readStatuses = List.generate(notificationsData.length, (index) => false);
  }

  Future<void> _initNotifications() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        final snap = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();
        _userRole = (snap.data()?['role'] ?? '').toString().toLowerCase();
        if (_userRole != null && _userRole!.isNotEmpty) {
          final roleKey = _userRole!.contains('pcg') ? 'pcg' : _userRole!;
          _roleNotificationsStream = FirebaseFirestore.instance
              .collection('notifications')
              .where('targetRole', isEqualTo: roleKey)
              .snapshots();
        }
      } catch (_) {}

      setState(() {
        _notificationsStream = FirebaseFirestore.instance
            .collection('notifications')
            .where('targetUserId', isEqualTo: user.uid)
            .snapshots();
        // Keep Firestore query simple (no composite index required); sort client-side.
        _reportsStream = FirebaseFirestore.instance
            .collection('reports')
            .where('uid', isEqualTo: user.uid)
            .snapshots();
        _sightingsStream = FirebaseFirestore.instance
            .collection('sightings')
            .where('userId', isEqualTo: user.uid)
            .snapshots();
      });
    }
  }

  final List<Map<String, dynamic>> notificationsData = [
    {
      'title': 'Weather Update',
      'message':
          'Heavy rain expected in the next 2 hours. Please secure your boats.',
      'time': '2 hours ago',
      'type': 'weather_alert',
      'icon': Icons.warning,
      'color': Colors.orange,
    },
    {
      'title': 'Community Reminder',
      'message':
          'Remember to report any illegal fishing activities you witness.',
      'time': '5 hours ago',
      'type': 'community',
      'icon': Icons.info,
      'color': Colors.blue,
    },
    {
      'title': 'Coast Guard Patrol',
      'message': 'Coast Guard patrol spotted near Sual waters for monitoring.',
      'time': '1 day ago',
      'type': 'pcg_alert',
      'icon': Icons.security,
      'color': Colors.green,
    },
    {
      'title': 'Rare Fish Sighting',
      'message': 'Rare fish sighted in Bolinao waters.',
      'time': '2 days ago',
      'type': 'alert',
      'icon': Icons.waves,
      'color': Colors.teal,
    },
    {
      'title': 'Marine Alert',
      'message': 'Strong currents detected in Lingayen Gulf. Exercise caution.',
      'time': '3 days ago',
      'type': 'weather_alert',
      'icon': Icons.warning_amber,
      'color': Colors.red,
    },
  ];

  @override
  Widget build(BuildContext context) {
    final padding = Responsive.pagePadding(context);
    final maxWidth = Responsive.maxContentWidth(context);

    return Scaffold(
      backgroundColor: _pageBottom,
      appBar: AppBar(
        toolbarHeight: 52,
        title: const Text(
          'Notifications',
          style: TextStyle(
            fontFamily: 'serif',
            fontSize: 28,
            fontWeight: FontWeight.w800,
            color: _ink,
          ),
        ),
        centerTitle: false,
        backgroundColor: Colors.transparent,
        foregroundColor: _ink,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        elevation: 0,
      ),
      bottomNavigationBar: CustomBottomNavBar(
        currentIndex: 3,
        onTap: (int index) {},
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [_pageTop, _pageBottom],
          ),
        ),
        child: SafeArea(
          top: false,
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth),
              child: StreamBuilder<QuerySnapshot>(
                stream: _roleNotificationsStream,
                builder: (context, roleSnapshot) {
                  final roleDocs =
                      roleSnapshot.data?.docs ?? <QueryDocumentSnapshot>[];
                  return StreamBuilder<QuerySnapshot>(
                    stream: _notificationsStream,
                    builder: (context, notifSnapshot) {
                      return StreamBuilder<QuerySnapshot>(
                        stream: _reportsStream,
                        builder: (context, reportsSnapshot) {
                          return StreamBuilder<QuerySnapshot>(
                            stream: _sightingsStream,
                            builder: (context, sightingsSnapshot) {
                              if (_notificationsStream == null &&
                                  _reportsStream == null &&
                                  _sightingsStream == null &&
                                  _roleNotificationsStream == null) {
                                return _buildNotificationBody(
                                  useStaticData: true,
                                  firestoreNotifications: const [],
                                  firestoreReports: const [],
                                  firestoreSightings: const [],
                                  notifications: notificationsData,
                                  padding: padding,
                                );
                              }

                              if (notifSnapshot.hasError ||
                                  reportsSnapshot.hasError ||
                                  sightingsSnapshot.hasError ||
                                  roleSnapshot.hasError) {
                                return Center(
                                  child: Text(
                                    'Error: ${notifSnapshot.error ?? reportsSnapshot.error ?? sightingsSnapshot.error ?? roleSnapshot.error}',
                                  ),
                                );
                              }

                              if ((notifSnapshot.connectionState ==
                                          ConnectionState.waiting ||
                                      _notificationsStream == null) &&
                                  (reportsSnapshot.connectionState ==
                                          ConnectionState.waiting ||
                                      _reportsStream == null) &&
                                  (sightingsSnapshot.connectionState ==
                                          ConnectionState.waiting ||
                                      _sightingsStream == null) &&
                                  (roleSnapshot.connectionState ==
                                          ConnectionState.waiting ||
                                      _roleNotificationsStream == null)) {
                                return const Center(
                                  child: CircularProgressIndicator(),
                                );
                              }

                              final notifDocs = _dedupeDocs([
                                ...roleDocs,
                                ...(notifSnapshot.data?.docs ??
                                    <QueryDocumentSnapshot>[]),
                              ]);
                              notifDocs.sort((a, b) {
                                final ta =
                                    (a.data()
                                        as Map<String, dynamic>)['timestamp'];
                                final tb =
                                    (b.data()
                                        as Map<String, dynamic>)['timestamp'];
                                final da = ta is Timestamp
                                    ? ta.toDate()
                                    : DateTime.fromMillisecondsSinceEpoch(0);
                                final db = tb is Timestamp
                                    ? tb.toDate()
                                    : DateTime.fromMillisecondsSinceEpoch(0);
                                return db.compareTo(da);
                              });

                              final reportDocs =
                                  reportsSnapshot.data?.docs ??
                                  <QueryDocumentSnapshot>[];
                              reportDocs.sort((a, b) {
                                final ta = _asDate(
                                  (a.data()
                                      as Map<String, dynamic>?)?['submittedAt'],
                                );
                                final tb = _asDate(
                                  (b.data()
                                      as Map<String, dynamic>?)?['submittedAt'],
                                );
                                return tb.compareTo(ta);
                              });

                              final sightingDocs =
                                  sightingsSnapshot.data?.docs ??
                                  <QueryDocumentSnapshot>[];

                              final combined = _dedupeDocs([
                                ...notifDocs,
                                ...reportDocs,
                                ...sightingDocs,
                              ]);
                              combined.sort((a, b) {
                                final aData = _isReportDoc(a)
                                    ? _reportAsNotificationMap(a)
                                    : _isSightingDoc(a)
                                    ? _sightingAsNotificationMap(a)
                                    : (a.data() as Map<String, dynamic>);
                                final bData = _isReportDoc(b)
                                    ? _reportAsNotificationMap(b)
                                    : _isSightingDoc(b)
                                    ? _sightingAsNotificationMap(b)
                                    : (b.data() as Map<String, dynamic>);
                                return _asDate(
                                  bData['timestamp'],
                                ).compareTo(_asDate(aData['timestamp']));
                              });

                              final dedupedCombined = _dedupeByContent(
                                combined,
                              );
                              final useStaticData = dedupedCombined.isEmpty;
                              final notifications = useStaticData
                                  ? notificationsData
                                  : dedupedCombined;

                              return _buildNotificationBody(
                                useStaticData: useStaticData,
                                firestoreNotifications: notifDocs,
                                firestoreReports: reportDocs,
                                firestoreSightings: sightingDocs,
                                notifications: notifications,
                                padding: padding,
                              );
                            },
                          );
                        },
                      );
                    },
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  bool _isReportDoc(QueryDocumentSnapshot doc) =>
      doc.reference.parent.id == 'reports';

  List<QueryDocumentSnapshot> _dedupeDocs(List<QueryDocumentSnapshot> docs) {
    final seen = <String>{};
    final unique = <QueryDocumentSnapshot>[];
    for (final doc in docs) {
      final key = doc.reference.path;
      if (seen.add(key)) {
        unique.add(doc);
      }
    }
    return unique;
  }

  List<QueryDocumentSnapshot> _dedupeByContent(
    List<QueryDocumentSnapshot> docs,
  ) {
    final seenKeys = <String>{};
    final unique = <QueryDocumentSnapshot>[];
    for (final doc in docs) {
      final data = _isReportDoc(doc)
          ? _reportAsNotificationMap(doc)
          : _isSightingDoc(doc)
          ? _sightingAsNotificationMap(doc)
          : (doc.data() as Map<String, dynamic>);
      final title = (data['title'] ?? '').toString().trim().toLowerCase();
      final category = (data['category'] ?? data['type'] ?? '')
          .toString()
          .trim()
          .toLowerCase();
      final message = (data['message'] ?? '').toString().trim().toLowerCase();
      final ts = _asDate(data['timestamp']).millisecondsSinceEpoch;
      final key = '$title|$category|$ts|${message.hashCode}';
      if (seenKeys.add(key)) {
        unique.add(doc);
      }
    }
    return unique;
  }

  DateTime _asDate(dynamic value) {
    if (value == null) return DateTime.fromMillisecondsSinceEpoch(0);
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) {
      final parsed = DateTime.tryParse(value);
      if (parsed != null) return parsed;
    }
    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  String _formatFullDate(dynamic ts) {
    final date = _asDate(ts);
    return DateFormat('yyyy-MM-dd HH:mm').format(date);
  }

  dynamic _bestReportTimestamp(Map<String, dynamic> report) {
    return report['submittedAt'] ?? report['timestamp'] ?? report['date'];
  }

  Map<String, dynamic> _reportAsNotificationMap(QueryDocumentSnapshot doc) {
    final report = (doc.data() as Map<String, dynamic>?) ?? <String, dynamic>{};
    final status = (report['status'] ?? report['actionStatus'] ?? 'Pending')
        .toString();
    final location =
        (report['location'] ??
                report['address'] ??
                report['formattedAddress'] ??
                report['streetAddress'] ??
                '')
            .toString();
    final description = (report['description'] ?? report['details'] ?? '')
        .toString();
    final illegalType = (report['type'] ?? report['title'] ?? 'Illegal Report')
        .toString();
    final image =
        report['localImagePath'] ??
        report['imageUrl'] ??
        report['photoUrls'] ??
        report['photo_urls'];
    final double? lat = _asDouble(report['latitude'] ?? report['lat']);
    final double? lng = _asDouble(
      report['longitude'] ?? report['lng'] ?? report['long'],
    );
    final String timeStr = _formatFullDate(_bestReportTimestamp(report));
    final witness =
        (report['witness'] ??
                report['witnessDescription'] ??
                report['witnessStatement'] ??
                report['witness_notes'] ??
                '')
            .toString();
    final priority =
        (report['priority'] ??
                report['priorityLevel'] ??
                report['emergencyLevel'] ??
                '')
            .toString();
    final weather =
        (report['weather'] ??
                report['weatherSummary'] ??
                report['weatherCondition'] ??
                report['seaCondition'] ??
                '')
            .toString();
    final reporter =
        (report['reporter'] ??
                report['reporterName'] ??
                report['reportedBy'] ??
                '')
            .toString();

    final lines = <String>[
      'Status: ${status.isEmpty ? 'Pending' : status}',
      if (reporter.isNotEmpty) 'Reported by: $reporter',
      if (location.isNotEmpty && location.toLowerCase() != 'location fetch')
        'Location: $location',
      if (lat != null && lng != null)
        'Coordinates: ${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}',
      if (description.isNotEmpty) 'Details: $description',
      if (witness.isNotEmpty) 'Witness: $witness',
      if (priority.isNotEmpty) 'Priority: $priority',
      if (weather.isNotEmpty) 'Weather: $weather',
      if (timeStr.isNotEmpty) 'Time: $timeStr',
    ];

    return <String, dynamic>{
      'type': 'illegal_report',
      'category': 'illegal',
      'title': illegalType,
      'message': lines.join('\n'),
      'timestamp': _bestReportTimestamp(report),
      'isRead': report['userIsRead'] == true,
      'reportId': doc.id,
      'status': status,
      'location': location,
      'image': image,
      if (reporter.isNotEmpty) 'reporter': reporter,
      if (lat != null) 'latitude': lat,
      if (lng != null) 'longitude': lng,
    };
  }

  bool _isSightingDoc(QueryDocumentSnapshot doc) =>
      doc.reference.parent.id == 'sightings';

  dynamic _bestSightingTimestamp(Map<String, dynamic> sighting) {
    return sighting['decisionAt'] ??
        sighting['reviewedAt'] ??
        sighting['updatedAt'] ??
        _bestSightingReportTimestamp(sighting);
  }

  dynamic _bestSightingReportTimestamp(Map<String, dynamic> sighting) {
    return sighting['sightingAt'] ??
        sighting['sightingDateTime'] ??
        sighting['sightingDateTimeString'] ??
        sighting['manilaDateTime'] ??
        sighting['reportedAt'] ??
        sighting['createdAt'] ??
        sighting['manilaTimeString'] ??
        sighting['reportedTimeString'];
  }

  Map<String, dynamic> _sightingAsNotificationMap(QueryDocumentSnapshot doc) {
    final sighting =
        (doc.data() as Map<String, dynamic>?) ?? <String, dynamic>{};
    final species = (sighting['species'] ?? 'Sighting Logged')
        .toString()
        .trim();
    final status =
        (sighting['decision'] ?? sighting['status'] ?? 'Pending review')
            .toString()
            .trim();
    final notes = (sighting['bfarNotes'] ?? sighting['notes'] ?? '')
        .toString()
        .trim();
    final location = (sighting['location'] ?? '').toString().trim();
    final decisionBy = (sighting['decisionBy'] ?? '').toString().trim();
    final dynamic rawImages = sighting['imageUrls'];
    final List<String> imageUrls = rawImages is List
        ? rawImages
              .where((e) => e != null && e.toString().trim().isNotEmpty)
              .map((e) => e.toString())
              .toList()
        : <String>[];
    final image = imageUrls.isNotEmpty
        ? imageUrls
        : (sighting['imageUrl'] ?? sighting['imageUrls']);
    final double? lat = _asDouble(sighting['latitude'] ?? sighting['lat']);
    final double? lng = _asDouble(
      sighting['longitude'] ?? sighting['lng'] ?? sighting['long'],
    );
    final String reportedTimeStr = _formatFullDate(
      _bestSightingReportTimestamp(sighting),
    );
    final String updatedTimeStr = _formatFullDate(_bestSightingTimestamp(sighting));
    final bool hasStatusUpdate =
        sighting['decisionAt'] != null ||
        sighting['reviewedAt'] != null ||
        sighting['updatedAt'] != null;
    final weather =
        (sighting['weather'] ??
                sighting['weatherSummary'] ??
                sighting['weatherCondition'] ??
                sighting['seaCondition'] ??
                '')
            .toString();

    final lines = <String>[
      'Status: ${status.isEmpty ? 'Pending review' : status}',
      if (location.isNotEmpty) 'Location: $location',
      if (lat != null && lng != null)
        'Coordinates: ${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}',
      if (notes.isNotEmpty) 'Notes: $notes',
      if (decisionBy.isNotEmpty) 'By: $decisionBy',
      if (weather.isNotEmpty) 'Weather: $weather',
      if (reportedTimeStr.isNotEmpty) 'Sighting time: $reportedTimeStr',
      if (hasStatusUpdate && updatedTimeStr.isNotEmpty)
        'Updated: $updatedTimeStr',
    ];

    return <String, dynamic>{
      'type': 'sighting_decision',
      'category': 'sighting',
      'title': species.isEmpty ? 'Sighting Logged' : species,
      'message':
          lines.where((l) => l.trim().isNotEmpty).join('\n').trim().isEmpty
          ? 'Awaiting review'
          : lines.where((l) => l.trim().isNotEmpty).join('\n'),
      'timestamp': _bestSightingTimestamp(sighting),
      'isRead': sighting['userIsRead'] == true,
      'sightingId': doc.id,
      'status': status,
      'image': image,
      'imageUrls': imageUrls,
      if (lat != null) 'latitude': lat,
      if (lng != null) 'longitude': lng,
    };
  }

  double? _asDouble(dynamic value) {
    if (value is num) return value.toDouble();
    if (value is String && value.trim().isNotEmpty) {
      return double.tryParse(value.trim());
    }
    return null;
  }

  bool _containsAny(Map<String, dynamic> data, List<String> keys) {
    final type = (data['type'] ?? data['category'] ?? '')
        .toString()
        .toLowerCase();
    final title = (data['title'] ?? '').toString().toLowerCase();
    final message = (data['message'] ?? '').toString().toLowerCase();
    return keys.any(
      (k) => type.contains(k) || title.contains(k) || message.contains(k),
    );
  }

  bool _isEmergencyNotification(Map<String, dynamic> data) {
    if (data['notifyAll'] == true) return true;
    return _containsAny(data, const ['emergency', 'sos', 'urgent', 'evacuate']);
  }

  bool _isWeatherNotification(Map<String, dynamic> data) {
    if (_isSightingNotification(data))
      return false; // Sightings should not be labeled as weather
    // Do not treat explicit illegal items as weather, even if text contains ocean keywords.
    if (_isIllegalNotification(data)) return false;
    final category = (data['category'] ?? data['type'] ?? '')
        .toString()
        .toLowerCase();
    if (category.contains('weather')) return true;
    if (category.contains('ocean')) return true;
    if (category.contains('fishing')) return true;
    return _containsAny(data, const [
      'weather',
      'ocean',
      'storm',
      'rain',
      'gale',
      'alert',
      'warning',
      'current',
      'tide',
      'wind',
      'wave',
      'swell',
      'fish',
      'fishing',
      'safe to fish',
      'no fish',
    ]);
  }

  bool _isIllegalNotification(Map<String, dynamic> data) {
    if (_isEmergencyNotification(data)) return false;
    return _containsAny(data, const [
      'illegal',
      'violation',
      'poaching',
      'blast',
    ]);
  }

  bool _isSightingNotification(Map<String, dynamic> data) {
    return _containsAny(data, const [
      'sighting',
      'marine sighting',
      'log sighting',
      'bfar decision',
    ]);
  }

  bool _isCommunityNotification(Map<String, dynamic> data) {
    return _containsAny(data, const [
      'community',
      'pcg',
      'bfar',
      'coast guard',
      'patrol',
      'post',
      'comment',
      'like',
      'admin',
    ]);
  }

  bool _isCommunityModeration(Map<String, dynamic> data) {
    final type = (data['type'] ?? '').toString().toLowerCase();
    final category = (data['category'] ?? '').toString().toLowerCase();
    final title = (data['title'] ?? '').toString().toLowerCase();
    return type.contains('community_post_pending') ||
        category.contains('community_post_pending') ||
        title.contains('community post pending') ||
        type.contains('post_report') ||
        category.contains('post_report') ||
        title.contains('post reported') ||
        type.contains('comment_report') ||
        category.contains('comment_report');
  }

  bool _roleMatchesTarget(Map<String, dynamic> data) {
    final role = (_userRole ?? '').toLowerCase();
    if (role.isEmpty) return true;
    final targetRole = (data['targetRole'] ?? '').toString().toLowerCase();
    if (targetRole.isEmpty) return true;
    if (role.contains(targetRole) || targetRole.contains(role)) return true;
    if (role.contains('bfar') && targetRole.contains('bfar')) return true;
    return false;
  }

  bool _shouldDisplayForRole(Map<String, dynamic> data) {
    final role = (_userRole ?? '').toLowerCase();
    if (role.isEmpty) return true;
    final bool isPcg = role.contains('pcg');
    final bool isBfar = role.contains('bfar');

    // PCG sub-admin/mobile should not see BFAR-only community moderation notices.
    if (isPcg && !isBfar && _isCommunityModeration(data)) {
      return false;
    }

    return _roleMatchesTarget(data);
  }

  Map<String, dynamic>? _tagFor(Map<String, dynamic> data) {
    if (_isEmergencyNotification(data)) {
      return {
        'label': 'Emergency Alert',
        'bg': Colors.red.withOpacity(0.10),
        'fg': Colors.red.shade700,
      };
    }
    if (_isIllegalNotification(data)) {
      return {
        'label': 'Report Update',
        'bg': Colors.red.withOpacity(0.10),
        'fg': Colors.red.shade700,
      };
    }
    if (_isSightingNotification(data)) {
      return {
        'label': 'Sighting Update',
        'bg': Colors.teal.withOpacity(0.12),
        'fg': Colors.teal.shade700,
      };
    }
    if (_isWeatherNotification(data)) {
      return {
        'label': 'Weather',
        'bg': Colors.orange.withOpacity(0.12),
        'fg': Colors.orange.shade800,
      };
    }
    if (_isCommunityNotification(data)) {
      final bool isPcg = _containsAny(data, const [
        'pcg',
        'coast guard',
        'patrol',
      ]);
      final bool isBfar = _containsAny(data, const ['bfar']);
      if (isPcg) {
        return {
          'label': 'PCG Update',
          'bg': Colors.blueAccent.withOpacity(0.1),
          'fg': Colors.blueAccent,
        };
      }
      if (isBfar) {
        return {
          'label': 'BFAR Update',
          'bg': Colors.teal.withOpacity(0.12),
          'fg': Colors.teal.shade700,
        };
      }
      return {
        'label': 'Community Update',
        'bg': Colors.blueAccent.withOpacity(0.1),
        'fg': Colors.blueAccent,
      };
    }
    return null;
  }

  IconData _iconForNotification(Map<String, dynamic> data) {
    if (_isEmergencyNotification(data)) {
      return Icons.warning_amber_rounded;
    }
    if (_isIllegalNotification(data)) {
      return Icons.report_problem_outlined;
    }
    if (_isSightingNotification(data)) {
      return Icons.visibility_outlined;
    }
    if (_isWeatherNotification(data)) {
      return Icons.cloud_outlined;
    }
    if (_isCommunityNotification(data)) {
      return Icons.forum_outlined;
    }
    return Icons.notifications_active_rounded;
  }

  bool _matchesSelectedFilter(Map<String, dynamic> data) {
    switch (_selectedFilter) {
      case 'Alerts':
        // Alerts should surface PCG/sub-admin items and emergencies, not weather updates.
        return _isEmergencyNotification(data) || _isCommunityNotification(data);
      case 'Reports':
        return _isIllegalNotification(data);
      case 'Weather':
        return _isWeatherNotification(data);
      case 'Sightings':
        return _isSightingNotification(data);
      case 'Community':
        // Show only community-style updates, not reports/sightings/weather/emergencies.
        return _isCommunityNotification(data) &&
            !_isIllegalNotification(data) &&
            !_isSightingNotification(data) &&
            !_isEmergencyNotification(data) &&
            !_isWeatherNotification(data);
      default:
        return true;
    }
  }

  Widget _filterDropdown({List<String>? filters}) {
    final items =
        filters ??
        const ['All', 'Alerts', 'Reports', 'Sightings', 'Community', 'Weather'];

    return Container(
      height: 36,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF12365B), Color(0xFF1F6EA8)],
        ),
        borderRadius: BorderRadius.circular(999),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF12365B).withValues(alpha: 0.28),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _selectedFilter,
          isExpanded: true,
          isDense: true,
          itemHeight: null,
          iconSize: 18,
          alignment: Alignment.centerLeft,
          icon: const Icon(
            Icons.keyboard_arrow_down_rounded,
            color: Colors.white,
          ),
          dropdownColor: const Color(0xFF12365B),
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: 12.5,
          ),
          items: items
              .map(
                (label) => DropdownMenuItem<String>(
                  value: label,
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 12.5,
                    ),
                  ),
                ),
              )
              .toList(),
          onChanged: (value) {
            if (value == null) return;
            setState(() => _selectedFilter = value);
          },
        ),
      ),
    );
  }

  Widget _buildNotificationBody({
    required bool useStaticData,
    required List<QueryDocumentSnapshot> firestoreNotifications,
    required List<QueryDocumentSnapshot> firestoreReports,
    required List<QueryDocumentSnapshot> firestoreSightings,
    required List<dynamic> notifications,
    required double padding,
  }) {
    if (useStaticData && _readStatuses.length != notifications.length) {
      _readStatuses = List<bool>.filled(notifications.length, false);
    }

    final bool hasUnread = useStaticData
        ? _readStatuses.any((read) => !read)
        : [
            ...firestoreNotifications,
            ...firestoreReports,
            ...firestoreSightings,
          ].any((doc) {
            final data = _isReportDoc(doc)
                ? _reportAsNotificationMap(doc)
                : _isSightingDoc(doc)
                ? _sightingAsNotificationMap(doc)
                : (doc.data() as Map<String, dynamic>);
            return (data['isRead'] ?? false) == false;
          });

    final List<dynamic> filteredForUi = useStaticData
        ? (notifications as List<Map<String, dynamic>>)
              .asMap()
              .entries
              .where(
                (entry) =>
                    _matchesSelectedFilter(entry.value) &&
                    _shouldDisplayForRole(entry.value),
              )
              .toList()
        : (notifications as List<QueryDocumentSnapshot>).where((doc) {
            final data = _isReportDoc(doc)
                ? _reportAsNotificationMap(doc)
                : _isSightingDoc(doc)
                ? _sightingAsNotificationMap(doc)
                : (doc.data() as Map<String, dynamic>);
            return _matchesSelectedFilter(data) && _shouldDisplayForRole(data);
          }).toList();

    final int unreadCount = useStaticData
        ? _readStatuses.where((read) => !read).length
        : [
            ...firestoreNotifications,
            ...firestoreReports,
            ...firestoreSightings,
          ].where((doc) {
            final data = _isReportDoc(doc)
                ? _reportAsNotificationMap(doc)
                : _isSightingDoc(doc)
                ? _sightingAsNotificationMap(doc)
                : (doc.data() as Map<String, dynamic>);
            return (data['isRead'] ?? false) == false;
          }).length;

    Future<void> markAllAsRead() async {
      if (useStaticData) {
        setState(() {
          _readStatuses = List<bool>.filled(_readStatuses.length, true);
        });
        return;
      }

      final allDocs = [
        ...firestoreNotifications,
        ...firestoreReports,
        ...firestoreSightings,
      ];
      for (final doc in allDocs) {
        final data = _isReportDoc(doc)
            ? _reportAsNotificationMap(doc)
            : _isSightingDoc(doc)
            ? _sightingAsNotificationMap(doc)
            : (doc.data() as Map<String, dynamic>);
        if ((data['isRead'] ?? false) == true) continue;
        if (_isReportDoc(doc) || _isSightingDoc(doc)) {
          await doc.reference.update({'userIsRead': true});
        } else {
          await doc.reference.update({'isRead': true});
        }
      }
    }

    Future<void> clearAllNotifications() async {
      if (useStaticData) {
        setState(() {
          notificationsData.clear();
          _readStatuses.clear();
        });
        return;
      }

      for (final doc in firestoreNotifications) {
        await doc.reference.delete();
      }
      // Do not delete reports and sightings. They belong to user history.
    }

    return Padding(
      padding: EdgeInsets.fromLTRB(padding, 8, padding, padding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF12365B), Color(0xFF1F6EA8)],
              ),
              border: Border.all(color: Colors.white.withValues(alpha: 0.24)),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF12365B).withValues(alpha: 0.28),
                  blurRadius: 12,
                  offset: const Offset(0, 7),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(11),
                      ),
                      child: const Icon(
                        Icons.notifications_active_rounded,
                        color: Colors.white,
                        size: 19,
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Live Notification Feed',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 14.2,
                          letterSpacing: 0.1,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        '$unreadCount unread',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11.2,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.insights_rounded,
                        size: 16,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${filteredForUi.length} shown of ${notifications.length} total updates',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.95),
                          fontSize: 11.6,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 9),
          LayoutBuilder(
            builder: (context, constraints) {
              final bool compact = constraints.maxWidth < 410;
              final buttonPadding = EdgeInsets.symmetric(
                horizontal: compact ? 8 : 13,
                vertical: 9,
              );
              final buttonTextStyle = TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: compact ? 11.2 : 12,
              );

              final dropdown = _filterDropdown();

              final markAllButton = FilledButton(
                onPressed: hasUnread ? markAllAsRead : null,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF124F8A),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(999),
                  ),
                  padding: buttonPadding,
                  textStyle: buttonTextStyle,
                  minimumSize: const Size(0, 38),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.done_all_rounded, size: 16),
                    SizedBox(width: compact ? 4 : 6),
                    Flexible(
                      child: Text(
                        compact ? 'Mark read' : 'Mark all read',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              );

              final clearAllButton = OutlinedButton(
                onPressed: clearAllNotifications,
                style: OutlinedButton.styleFrom(
                  foregroundColor: _ink,
                  side: const BorderSide(color: Color(0xFFC5D5E6)),
                  backgroundColor: const Color(0xFFF6FAFE),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(999),
                  ),
                  padding: buttonPadding,
                  textStyle: buttonTextStyle,
                  minimumSize: const Size(0, 38),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.delete_outline_rounded, size: 16),
                    SizedBox(width: compact ? 4 : 6),
                    Flexible(
                      child: Text(
                        compact ? 'Clear' : 'Clear all',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              );

              if (compact) {
                return Column(
                  children: [
                    dropdown,
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(child: markAllButton),
                        const SizedBox(width: 8),
                        Expanded(child: clearAllButton),
                      ],
                    ),
                  ],
                );
              }

              return Row(
                children: [
                  Expanded(flex: 34, child: dropdown),
                  const SizedBox(width: 8),
                  Expanded(flex: 40, child: markAllButton),
                  const SizedBox(width: 8),
                  Expanded(flex: 26, child: clearAllButton),
                ],
              );
            },
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Recent Updates',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: _ink,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 9,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.86),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: const Color(0xFFD7E3F1)),
                ),
                child: Text(
                  '${filteredForUi.length}',
                  style: const TextStyle(
                    color: _ink,
                    fontWeight: FontWeight.w800,
                    fontSize: 12.2,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: filteredForUi.isEmpty
                ? Center(
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(18, 22, 18, 22),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.94),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: const Color(0xFFD8E4F0)),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(
                              0xFF8DA7C3,
                            ).withValues(alpha: 0.10),
                            blurRadius: 12,
                            offset: const Offset(0, 7),
                          ),
                        ],
                      ),
                      child: const Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.notifications_none_rounded,
                            size: 34,
                            color: _subtleInk,
                          ),
                          SizedBox(height: 8),
                          Text(
                            'No notifications yet',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: _ink,
                              fontWeight: FontWeight.w800,
                              fontSize: 15.4,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'You are all caught up. New alerts will appear here.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: _subtleInk,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.only(bottom: 88),
                    itemCount: filteredForUi.length,
                    itemBuilder: (context, index) {
                      late final Map<String, dynamic> data;
                      late final dynamic timestamp;
                      int? staticIndex;
                      QueryDocumentSnapshot? doc;

                      if (useStaticData) {
                        final entry =
                            filteredForUi[index]
                                as MapEntry<int, Map<String, dynamic>>;
                        staticIndex = entry.key;
                        data = entry.value;
                        timestamp = data['time'];
                      } else {
                        doc = filteredForUi[index] as QueryDocumentSnapshot;
                        data = _isReportDoc(doc)
                            ? _reportAsNotificationMap(doc)
                            : _isSightingDoc(doc)
                            ? _sightingAsNotificationMap(doc)
                            : (doc.data() as Map<String, dynamic>);
                        timestamp = data['timestamp'];
                      }

                      final isRead = useStaticData
                          ? _readStatuses[staticIndex!]
                          : (data['isRead'] == true);
                      final tag = _tagFor(data);
                      final Color chipFg = (tag?['fg'] as Color?) ?? _ink;
                      final Color chipBg =
                          (tag?['bg'] as Color?) ?? const Color(0xFFE7EEF8);
                      final String chipLabel =
                          (tag?['label'] as String?) ?? 'Update';
                      final Color accentColor = chipFg;
                      final IconData leadingIcon = _iconForNotification(data);

                      final timeText = useStaticData
                          ? timestamp.toString()
                          : _formatTimestamp(timestamp);

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(18),
                            onTap: () async {
                              if (useStaticData &&
                                  !_readStatuses[staticIndex!]) {
                                setState(() {
                                  _readStatuses[staticIndex!] = true;
                                });
                              } else if (!useStaticData &&
                                  !isRead &&
                                  doc != null) {
                                if (_isReportDoc(doc) || _isSightingDoc(doc)) {
                                  await doc.reference.update({
                                    'userIsRead': true,
                                  });
                                } else {
                                  await doc.reference.update({'isRead': true});
                                }
                              }

                              if (!mounted) return;
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => NotificationDetailsPage(
                                    data: data,
                                    timeText: timeText,
                                    notificationId: doc?.id,
                                  ),
                                ),
                              );
                            },
                            child: Ink(
                              padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(18),
                                gradient: const LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [Colors.white, Color(0xFFF4F9FF)],
                                ),
                                border: Border.all(
                                  color: !isRead
                                      ? const Color(0xFFBBD3EE)
                                      : const Color(0xFFD8E4F0),
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(
                                      0xFF8DA7C3,
                                    ).withValues(alpha: isRead ? 0.07 : 0.13),
                                    blurRadius: 9,
                                    offset: const Offset(0, 5),
                                  ),
                                ],
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Container(
                                        width: 42,
                                        height: 42,
                                        decoration: BoxDecoration(
                                          color: accentColor.withValues(
                                            alpha: isRead ? 0.10 : 0.16,
                                          ),
                                          borderRadius: BorderRadius.circular(14),
                                        ),
                                        child: Icon(
                                          leadingIcon,
                                          color: accentColor,
                                          size: 21,
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                Container(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 8,
                                                        vertical: 3,
                                                      ),
                                                  decoration: BoxDecoration(
                                                    color: chipBg,
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          999,
                                                        ),
                                                  ),
                                                  child: Text(
                                                    chipLabel,
                                                    style: TextStyle(
                                                      color: chipFg,
                                                      fontSize: 10.6,
                                                      fontWeight:
                                                          FontWeight.w800,
                                                    ),
                                                  ),
                                                ),
                                                const Spacer(),
                                                Text(
                                                  timeText,
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: const TextStyle(
                                                    color: _subtleInk,
                                                    fontSize: 11.2,
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 6),
                                            Row(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                if (!isRead) ...[
                                                  Container(
                                                    width: 10,
                                                    height: 10,
                                                    margin:
                                                        const EdgeInsets.only(
                                                          top: 4,
                                                        ),
                                                    decoration: BoxDecoration(
                                                      color: accentColor
                                                          .withValues(
                                                            alpha: 0.95,
                                                          ),
                                                      shape: BoxShape.circle,
                                                    ),
                                                  ),
                                                  const SizedBox(width: 8),
                                                ],
                                                Expanded(
                                                  child: Text(
                                                    data['title'] ?? 'No Title',
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: TextStyle(
                                                      color: _ink.withValues(
                                                        alpha: isRead
                                                            ? 0.94
                                                            : 1,
                                                      ),
                                                      fontWeight:
                                                          FontWeight.w800,
                                                      fontSize: 15.8,
                                                      height: 1.2,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Container(
                                        width: 28,
                                        height: 28,
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFE7EFFA),
                                          borderRadius:
                                              BorderRadius.circular(10),
                                        ),
                                        child: const Icon(
                                          Icons.chevron_right_rounded,
                                          color: _subtleInk,
                                          size: 17,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.all(9),
                                    decoration: BoxDecoration(
                                      color: accentColor.withValues(
                                        alpha: 0.06,
                                      ),
                                      borderRadius: BorderRadius.circular(13),
                                      border: Border.all(
                                        color: accentColor.withValues(
                                          alpha: 0.12,
                                        ),
                                      ),
                                    ),
                                    child: Text(
                                      data['message'] ?? 'No Message',
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: _subtleInk,
                                        fontSize: 12.8,
                                        height: 1.28,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  String _formatTimestamp(dynamic timestamp) {
    if (timestamp == null) return 'Unknown time';
    if (timestamp is Timestamp) {
      final now = DateTime.now();
      final date = timestamp.toDate();
      final difference = now.difference(date);

      if (difference.inDays > 0) {
        return '${difference.inDays} day${difference.inDays > 1 ? 's' : ''} ago';
      } else if (difference.inHours > 0) {
        return '${difference.inHours} hour${difference.inHours > 1 ? 's' : ''} ago';
      } else if (difference.inMinutes > 0) {
        return '${difference.inMinutes} minute${difference.inMinutes > 1 ? 's' : ''} ago';
      } else {
        return 'Just now';
      }
    }
    if (timestamp is DateTime) {
      final now = DateTime.now();
      final difference = now.difference(timestamp);
      if (difference.inDays > 0) {
        return '${difference.inDays} day${difference.inDays > 1 ? 's' : ''} ago';
      } else if (difference.inHours > 0) {
        return '${difference.inHours} hour${difference.inHours > 1 ? 's' : ''} ago';
      } else if (difference.inMinutes > 0) {
        return '${difference.inMinutes} minute${difference.inMinutes > 1 ? 's' : ''} ago';
      } else {
        return 'Just now';
      }
    }
    if (timestamp is String) {
      final parsed = DateTime.tryParse(timestamp);
      if (parsed != null) {
        return _formatTimestamp(parsed);
      }
    }
    return timestamp.toString().isEmpty ? 'Unknown time' : timestamp.toString();
  }
}

class _NotificationAction {
  final String label;
  final Widget Function() builder;
  final String? postId;

  const _NotificationAction({
    required this.label,
    required this.builder,
    this.postId,
  });
}

String? _extractCommunityPostIdFrom(Map<String, dynamic> data) {
  String? normalize(dynamic v) {
    if (v == null) return null;
    final s = v.toString().trim();
    return s.isEmpty ? null : s;
  }

  void collectFromMap(Map<dynamic, dynamic> map, List<String> out) {
    for (final entry in map.entries) {
      final key = entry.key.toString().toLowerCase();
      if (key.contains('post')) {
        final normalized = normalize(entry.value);
        if (normalized != null) out.add(normalized);
      }
    }
  }

  final ids = <String>[];

  final direct = <dynamic>[
    data['communityPostId'],
    data['community_post_id'],
    data['adminPostId'],
    data['postId'],
    data['post_id'],
    data['pcgPostId'],
    data['pcg_post_id'],
    data['bfarPostId'],
    data['bfar_post_id'],
    data['targetPostId'],
    data['target_post_id'],
    data['likedPostId'],
    data['liked_post_id'],
  ];

  ids.addAll(direct.map(normalize).whereType<String>());

  for (final key in ['post', 'communityPost', 'payload', 'data']) {
    final value = data[key];
    if (value is Map) {
      collectFromMap(value, ids);
      for (final nestedKey in ['id', 'postId', 'post_id']) {
        final normalized = normalize(value[nestedKey]);
        if (normalized != null) ids.add(normalized);
      }
    }
  }

  return ids.isNotEmpty ? ids.first : null;
}

class NotificationDetailsPage extends StatelessWidget {
  final Map<String, dynamic> data;
  final String timeText;
  final String? notificationId;
  static const _communityActionLabel = 'Open Community';

  const NotificationDetailsPage({
    super.key,
    required this.data,
    required this.timeText,
    this.notificationId,
  });

  DateTime _asDate(dynamic value) {
    if (value == null) return DateTime.fromMillisecondsSinceEpoch(0);
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) {
      final parsed = DateTime.tryParse(value);
      if (parsed != null) return parsed;
    }
    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  String _formatAbsolute(dynamic value) {
    final date = _asDate(value);
    if (date.millisecondsSinceEpoch == 0) return 'Unknown date';
    return DateFormat('MMM d, yyyy • h:mm a').format(date);
  }

  Map<String, dynamic>? _tagFor(Map<String, dynamic> data) {
    bool containsAny(List<String> keys) {
      final type = (data['type'] ?? data['category'] ?? '')
          .toString()
          .toLowerCase();
      final title = (data['title'] ?? '').toString().toLowerCase();
      final message = (data['message'] ?? '').toString().toLowerCase();
      return keys.any(
        (k) => type.contains(k) || title.contains(k) || message.contains(k),
      );
    }

    if (data['notifyAll'] == true ||
        containsAny(['emergency', 'urgent', 'sos'])) {
      final level = (data['emergencyLevel'] ?? '').toString().toLowerCase();
      final Color fg = level == 'danger'
          ? Colors.red.shade700
          : level == 'moderate'
          ? Colors.orange.shade800
          : level == 'safe'
          ? Colors.green.shade700
          : Colors.red.shade700;
      return {'label': 'Emergency Alert', 'bg': fg.withOpacity(0.10), 'fg': fg};
    }
    if (containsAny(['illegal', 'report', 'violation'])) {
      return {
        'label': 'Report Update',
        'bg': Colors.red.withOpacity(0.10),
        'fg': Colors.red.shade700,
      };
    }
    if (containsAny(['sighting'])) {
      return {
        'label': 'Sighting Update',
        'bg': Colors.teal.withOpacity(0.12),
        'fg': Colors.teal.shade700,
      };
    }
    if (containsAny([
      'weather',
      'ocean',
      'storm',
      'rain',
      'gale',
      'alert',
      'warning',
    ])) {
      return {
        'label': 'Weather & Ocean',
        'bg': Colors.orange.withOpacity(0.12),
        'fg': Colors.orange.shade800,
      };
    }
    if (containsAny(['pcg', 'coast guard', 'patrol'])) {
      return {
        'label': 'PCG Update',
        'bg': Colors.blueAccent.withOpacity(0.1),
        'fg': Colors.blueAccent,
      };
    }
    if (containsAny(['bfar'])) {
      return {
        'label': 'BFAR Update',
        'bg': Colors.teal.withOpacity(0.12),
        'fg': Colors.teal.shade700,
      };
    }
    if (containsAny(['community', 'post', 'comment', 'like', 'admin'])) {
      return {
        'label': 'Community Update',
        'bg': Colors.blueAccent.withOpacity(0.1),
        'fg': Colors.blueAccent,
      };
    }
    return null;
  }

  _NotificationAction? _actionFor(String title, String message) {
    final type = (data['type'] ?? data['category'] ?? '')
        .toString()
        .toLowerCase();
    final t = title.toLowerCase();
    final m = message.toLowerCase();
    bool matchAny(List<String> keys) =>
        keys.any((k) => type.contains(k) || t.contains(k) || m.contains(k));

    final String? communityPostId = _extractCommunityPostIdFrom(data);
    final bool hasCommunityPostId =
        communityPostId != null && communityPostId.isNotEmpty;

    if (matchAny(['illegal'])) {
      return _NotificationAction(
        label: 'View My Reports',
        builder: () => RecentReportsPage(initialTab: 'Reports'),
      );
    }

    if (matchAny(['weather', 'ocean', 'storm', 'gale', 'warning', 'alert'])) {
      return _NotificationAction(
        label: 'View Weather & Ocean Alerts',
        builder: () => WeatherOceanAlertsScreen(),
      );
    }

    if (hasCommunityPostId ||
        data['pcgPostId'] != null ||
        matchAny([
          'pcg',
          'bfar',
          'community',
          'post',
          'comment',
          'like',
          'admin',
        ])) {
      return _NotificationAction(
        label: 'Open Community',
        builder: () => hasCommunityPostId
            ? community.CommunityScreen(initialPostId: communityPostId)
            : const community.CommunityScreen(),
        postId: communityPostId,
      );
    }

    if (matchAny(['sighting'])) {
      return _NotificationAction(
        label: 'View My Sightings',
        builder: () => RecentReportsPage(initialTab: 'Sightings'),
      );
    }

    return null;
  }

  @override
  Widget build(BuildContext context) {
    final title = (data['title'] ?? 'Notification').toString();
    final message = (data['message'] ?? '').toString();
    final action = _actionFor(title, message);
    final tag = _tagFor(data);
    final Color accent = (tag?['fg'] as Color?) ?? _notificationPrimaryColor;
    final padding = Responsive.pagePadding(context);
    final maxWidth = Responsive.maxContentWidth(context);
    final rawTimestamp = data['timestamp'] ?? data['time'];
    final absoluteTime = _formatAbsolute(rawTimestamp);
    final String reportedBy =
        (data['reporter'] ?? data['reporterName'] ?? data['reportedBy'] ?? '')
            .toString()
            .trim();
    final dynamic imagesRaw = data['imageUrls'] ?? data['image'];
    final String? reportId = data['reportId']?.toString();
    final String? sightingId = data['sightingId']?.toString();
    final List<String> images = imagesRaw is List
        ? imagesRaw
              .where((e) => e != null && e.toString().isNotEmpty)
              .map((e) => e.toString())
              .toList()
        : (imagesRaw != null ? [imagesRaw.toString()] : <String>[]);
    final bool isSighting =
        (data['category'] ?? '').toString().toLowerCase().contains(
          'sighting',
        ) ||
        (data['type'] ?? '').toString().toLowerCase().contains('sighting');
    final bool hasTag =
        tag != null && ((tag['label'] ?? '').toString().isNotEmpty);

    Widget infoChip({
      required IconData icon,
      required String label,
      Color? background,
      Color? foreground,
      FontWeight weight = FontWeight.w700,
    }) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: background ?? Colors.white.withValues(alpha: 0.78),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.white.withValues(alpha: 0.38)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: foreground ?? accent),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12.3,
                color: foreground ?? const Color(0xFF203B54),
                fontWeight: weight,
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF5FAFF),
      appBar: AppBar(
        title: const Text(
          'Notification',
          style: TextStyle(
            fontFamily: 'serif',
            fontSize: 31,
            fontWeight: FontWeight.w800,
            color: Color(0xFF102A43),
            letterSpacing: 0.2,
          ),
        ),
        centerTitle: false,
        backgroundColor: Colors.transparent,
        foregroundColor: const Color(0xFF102A43),
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        elevation: 0,
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFE9F3FF), Color(0xFFF8FCFF)],
          ),
        ),
        child: SafeArea(
          top: false,
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth),
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  padding,
                  padding - 2,
                  padding,
                  padding + 4,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(22),
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            accent.withValues(alpha: 0.20),
                            Colors.white.withValues(alpha: 0.98),
                          ],
                        ),
                        border: Border.all(
                          color: accent.withValues(alpha: 0.22),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: accent.withValues(alpha: 0.14),
                            blurRadius: 18,
                            offset: const Offset(0, 11),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 54,
                                height: 54,
                                decoration: BoxDecoration(
                                  color: accent.withValues(alpha: 0.14),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  isSighting
                                      ? Icons.pest_control_rodent_rounded
                                      : Icons.notifications_active_rounded,
                                  color: accent,
                                  size: 25,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      title,
                                      style: const TextStyle(
                                        fontSize: 25,
                                        fontWeight: FontWeight.w800,
                                        color: Color(0xFF102A43),
                                        height: 1.08,
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      crossAxisAlignment:
                                          WrapCrossAlignment.center,
                                      children: [
                                        if (hasTag)
                                          infoChip(
                                            icon: Icons.label_rounded,
                                            label:
                                                (tag['label'] as String?) ?? '',
                                            background:
                                                (tag['bg'] as Color?) ??
                                                accent.withValues(alpha: 0.12),
                                            foreground:
                                                (tag['fg'] as Color?) ?? accent,
                                          ),
                                        infoChip(
                                          icon: Icons.schedule_rounded,
                                          label: timeText,
                                          background: Colors.white.withValues(
                                            alpha: 0.80,
                                          ),
                                          foreground: const Color(0xFF2C4B68),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          infoChip(
                            icon: Icons.calendar_today_rounded,
                            label: absoluteTime,
                            background: Colors.white.withValues(alpha: 0.78),
                            foreground: const Color(0xFF2C4B68),
                          ),
                          if (reportedBy.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            infoChip(
                              icon: Icons.person_pin_circle_outlined,
                              label: 'Reported by $reportedBy',
                              background: accent.withValues(alpha: 0.10),
                              foreground: accent,
                            ),
                          ],
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Container(
                                width: 28,
                                height: 28,
                                decoration: BoxDecoration(
                                  color: accent.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(9),
                                ),
                                child: Icon(
                                  Icons.notes_rounded,
                                  size: 17,
                                  color: accent,
                                ),
                              ),
                              const SizedBox(width: 8),
                              const Text(
                                'Details',
                                style: TextStyle(
                                  fontSize: 16.5,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF102A43),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.88),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: const Color(0xFFD3E1F0),
                              ),
                            ),
                            child: Text(
                              message.isEmpty
                                  ? 'No details available.'
                                  : message,
                              style: const TextStyle(
                                fontSize: 15.2,
                                color: Color(0xFF2A3E52),
                                height: 1.44,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    if (images.isNotEmpty) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.94),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: const Color(0xFFD3E1F0)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Photos',
                              style: TextStyle(
                                fontSize: 14.8,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF102A43),
                              ),
                            ),
                            const SizedBox(height: 10),
                            SizedBox(
                              height: math.min(
                                140,
                                MediaQuery.of(context).size.height * 0.20,
                              ),
                              child: ListView.separated(
                                scrollDirection: Axis.horizontal,
                                itemCount: images.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(width: 12),
                                itemBuilder: (context, index) {
                                  final raw = images[index];
                                  return _NotificationImageThumb(
                                    imageRaw: raw,
                                    resolver: resolveNotificationImageUrl,
                                    borderRadius: 14,
                                    height: math.min(
                                      140,
                                      MediaQuery.of(context).size.height * 0.20,
                                    ),
                                    heroTagOverride: _heroTagFor(
                                      raw,
                                      id: sightingId ?? reportId,
                                    ),
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                    ] else
                      FutureBuilder<String?>(
                        future: _fetchImageFromLinkedDoc(
                          reportId: reportId,
                          sightingId: sightingId,
                        ),
                        builder: (context, snapshot) {
                          if (snapshot.connectionState ==
                              ConnectionState.waiting) {
                            return Container(
                              width: double.infinity,
                              height: 110,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.92),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: const Color(0xFFD3E1F0),
                                ),
                              ),
                              child: const Center(
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            );
                          }
                          final resolvedRaw = snapshot.data;
                          if (resolvedRaw == null || resolvedRaw.isEmpty)
                            return const SizedBox.shrink();
                          return Container(
                            width: double.infinity,
                            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.94),
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(
                                color: const Color(0xFFD3E1F0),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Photos',
                                  style: TextStyle(
                                    fontSize: 14.8,
                                    fontWeight: FontWeight.w800,
                                    color: Color(0xFF102A43),
                                  ),
                                ),
                                const SizedBox(height: 10),
                                _NotificationImageThumb(
                                  imageRaw: resolvedRaw,
                                  resolver: resolveNotificationImageUrl,
                                  borderRadius: 14,
                                  height: math.min(
                                    140,
                                    MediaQuery.of(context).size.height * 0.20,
                                  ),
                                  heroTagOverride: _heroTagFor(
                                    resolvedRaw,
                                    id: sightingId ?? reportId,
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    if (action != null) ...[
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton(
                          onPressed: () async {
                            if (action.label == _communityActionLabel) {
                              final postId = await _resolveCommunityPostId(
                                action.postId,
                              );
                              final dest = (postId != null && postId.isNotEmpty)
                                  ? community.CommunityScreen(
                                      initialPostId: postId,
                                    )
                                  : const community.CommunityScreen();
                              if (!context.mounted) return;
                              Navigator.push(
                                context,
                                MaterialPageRoute(builder: (_) => dest),
                              );
                              return;
                            }

                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => action.builder(),
                              ),
                            );
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF0F2D4A),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            elevation: 10,
                            shadowColor: const Color(0x330F2D4A),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.open_in_new_rounded, size: 18),
                              const SizedBox(width: 8),
                              Text(
                                action.label,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 14.6,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<String?> _resolveCommunityPostId(String? initial) async {
    if (initial != null && initial.isNotEmpty) return initial;

    final fromLocal = _extractCommunityPostIdFrom(data);
    if (fromLocal != null && fromLocal.isNotEmpty) return fromLocal;

    if (notificationId == null || notificationId!.isEmpty) return null;
    try {
      final snap = await FirebaseFirestore.instance
          .collection('notifications')
          .doc(notificationId!)
          .get();
      if (!snap.exists) return null;
      final docData = snap.data() ?? <String, dynamic>{};
      final fromDoc = _extractCommunityPostIdFrom(docData);
      return fromDoc;
    } catch (_) {
      return null;
    }
  }
}

class _NotificationImageThumb extends StatelessWidget {
  final dynamic imageRaw;
  final Future<String?> Function(dynamic) resolver;
  final double borderRadius;
  final double height;
  final String? heroTagOverride;

  const _NotificationImageThumb({
    required this.imageRaw,
    required this.resolver,
    this.borderRadius = 10,
    this.height = 110,
    this.heroTagOverride,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: resolver(imageRaw),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Container(
            height: height,
            decoration: BoxDecoration(
              color: Colors.grey.shade200,
              borderRadius: BorderRadius.circular(borderRadius),
            ),
            alignment: Alignment.center,
            child: const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        }
        final resolved = snapshot.data;
        if (resolved == null || resolved.isEmpty) {
          return const SizedBox.shrink();
        }

        ImageProvider provider;
        if (resolved.startsWith('data:image')) {
          try {
            final parts = resolved.split(',');
            final b64 = parts.length > 1
                ? parts[1]
                : parts.first.replaceFirst('data:image/jpeg;base64,', '');
            provider = MemoryImage(base64Decode(b64));
          } catch (_) {
            provider = NetworkImage(resolved);
          }
        } else if (resolved.startsWith('file://')) {
          provider = FileImage(File(resolved.replaceFirst('file://', '')));
        } else {
          provider = NetworkImage(resolved);
        }

        final heroTag = heroTagOverride ?? _heroTagFor(imageRaw);

        return GestureDetector(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    _FullScreenImagePage(provider: provider, heroTag: heroTag),
              ),
            );
          },
          child: Hero(
            tag: heroTag,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(borderRadius),
              child: Image(
                image: provider,
                height: height,
                width: double.infinity,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => Container(
                  height: height,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(borderRadius),
                  ),
                  alignment: Alignment.center,
                  child: const Icon(Icons.broken_image, color: Colors.grey),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

Future<String?> resolveNotificationImageUrl(dynamic raw) async {
  if (raw == null) return null;
  if (raw is List && raw.isNotEmpty) {
    raw = raw.firstWhere(
      (e) => e != null && e.toString().isNotEmpty,
      orElse: () => null,
    );
    if (raw == null) return null;
  }
  final url = raw.toString().trim();
  if (url.isEmpty) return null;
  final isWindowsPath = RegExp(r'^[A-Za-z]:[\\\\/]').hasMatch(url);
  if (url.startsWith('file://')) return url;
  if (url.startsWith('/') || isWindowsPath) return "file://$url";
  if (url.startsWith('data:image')) return url;
  if (url.startsWith('gs://')) {
    try {
      return await FirebaseStorage.instance.refFromURL(url).getDownloadURL();
    } catch (_) {
      return null;
    }
  }
  if (url.startsWith('http')) return url;
  try {
    return await FirebaseStorage.instance.ref(url).getDownloadURL();
  } catch (_) {
    return null;
  }
}

String _heroTagFor(dynamic raw, {String? id}) {
  final base = raw == null ? '' : raw.toString();
  final hash = base.hashCode.toUnsigned(20).toRadixString(16);
  return 'notif-img-${id ?? ''}-$hash';
}

Future<String?> _fetchImageFromLinkedDoc({
  String? reportId,
  String? sightingId,
}) async {
  try {
    if (reportId != null && reportId.isNotEmpty) {
      final doc = await FirebaseFirestore.instance
          .collection('reports')
          .doc(reportId)
          .get();
      if (doc.exists) {
        final data = doc.data() ?? {};
        final raw =
            data['photoUrls'] ??
            data['photo_urls'] ??
            data['imageUrl'] ??
            data['localImagePath'];
        if (raw != null && raw.toString().isNotEmpty) return raw.toString();
      }
    }
    if (sightingId != null && sightingId.isNotEmpty) {
      final doc = await FirebaseFirestore.instance
          .collection('sightings')
          .doc(sightingId)
          .get();
      if (doc.exists) {
        final data = doc.data() ?? {};
        final raw = data['imageUrls'] ?? data['imageUrl'];
        if (raw != null && raw.toString().isNotEmpty) return raw.toString();
      }
    }
  } catch (_) {}
  return null;
}

class _FullScreenImagePage extends StatelessWidget {
  final ImageProvider provider;
  final String heroTag;

  const _FullScreenImagePage({required this.provider, required this.heroTag});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            Center(
              child: Hero(
                tag: heroTag,
                child: InteractiveViewer(
                  minScale: 0.8,
                  maxScale: 4.0,
                  child: Image(image: provider, fit: BoxFit.contain),
                ),
              ),
            ),
            Positioned(
              top: 12,
              left: 12,
              child: CircleAvatar(
                backgroundColor: Colors.black54,
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
