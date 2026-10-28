import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../l10n/app_localizations.dart';
import '../utils/responsive.dart';
import 'admin_emergency_report_details_page.dart';
import 'admin_illegal_report_details_page.dart';
import 'admin_weather_ocean_alert.dart';
import 'illegal_reports.dart';

class AdminNotificationPage extends StatefulWidget {
  const AdminNotificationPage({super.key});

  @override
  State<AdminNotificationPage> createState() => _AdminNotificationPageState();
}

class _AdminNotificationPageState extends State<AdminNotificationPage> {
  static const Color _pillColor = Color(0xFF0F2548);
  static const Color _pageTop = Color(0xFFEAF4FF);
  static const Color _pageBottom = Color(0xFFF8FCFF);
  static const Color _ink = Color(0xFF102A43);
  static const Color _subtleInk = Color(0xFF486581);
  Stream<QuerySnapshot>? _notificationsStream;
  Stream<QuerySnapshot>? _reportsStream;
  String _selectedFilter = 'All';
  String? _currentAdminId;

  final List<Map<String, dynamic>> _staticNotifications = [
    {
      'title': 'PCG Alert: Weather',
      'message': 'Gale warning in Lingayen Gulf. Secure vessels and postpone departures.',
      'time': 'Just now',
      'type': 'weather_alert',
    },
    {
      'title': 'Illegal Report Submitted',
      'message': 'User reported suspected dynamite fishing near Bonuan waters.',
      'time': '15 min ago',
      'type': 'illegal_report',
    },
    {
      'title': 'PCG Review Needed',
      'message': 'PCG web portal marked a report as approved. Review and respond.',
      'time': '1 hour ago',
      'type': 'report_approved',
    },
  ];

  List<bool> _readStatuses = [];

  @override
  void initState() {
    super.initState();
    _currentAdminId = FirebaseAuth.instance.currentUser?.uid;

    _notificationsStream = FirebaseFirestore.instance
        .collection('notifications')
        .orderBy('timestamp', descending: true)
        .snapshots();

    // Fallback source for "Illegal Reports by users" when notifications aren't being written
    // (e.g., due to Firestore rules). Admins can always read from `reports`.
    _reportsStream = FirebaseFirestore.instance
        .collection('reports')
        .orderBy('submittedAt', descending: true)
        .limit(50)
        .snapshots();

    _readStatuses = List<bool>.filled(_staticNotifications.length, false);
  }

  bool _isRelevant(Map<String, dynamic> data) {
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

    // Comment reports are intended for web admins only.
    if (type.contains('comment_report') || category.contains('comment_report')) {
      return false;
    }

    // Exclude community feed items from the admin notification list.
    if (_isCommunityNotification(data)) {
      return false;
    }

    // Ignore user-targeted notifications to keep the admin feed clean.
    final targetUserId = (data['targetUserId'] ?? '').toString().trim();
    if (targetUserId.isNotEmpty) {
      return false;
    }

    // Ignore emergency notifications originated by this sub-admin.
    final senderId = (data['reporterId'] ?? data['senderId'] ?? '').toString().trim();
    if (_currentAdminId != null &&
        senderId.isNotEmpty &&
        senderId == _currentAdminId &&
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

  bool _isReportDoc(QueryDocumentSnapshot doc) => doc.reference.parent.id == 'reports';

  dynamic _bestReportTimestamp(Map<String, dynamic> report) {
    return report['submittedAt'] ?? report['manilaSubmittedAt'] ?? report['timestamp'] ?? report['date'];
  }

  Map<String, dynamic> _reportAsNotificationMap(QueryDocumentSnapshot doc) {
    final report = (doc.data() as Map<String, dynamic>?) ?? <String, dynamic>{};
    final illegalType = (report['type'] ?? report['title'] ?? 'Illegal Activity').toString();
    final priority = (report['priority'] ?? '').toString();
    final location = (report['location'] ?? '').toString();
    final reporter = (report['reporter'] ?? report['reporterName'] ?? '').toString();
    final status = (report['status'] ?? report['actionStatus'] ?? '').toString();

    final lines = <String>[
      'Type: $illegalType',
      if (priority.isNotEmpty) 'Priority: $priority',
      if (location.isNotEmpty) 'Location: $location',
      if (reporter.isNotEmpty) 'Reporter: $reporter',
    ];

      return <String, dynamic>{
        'type': 'illegal_report',
        'category': 'illegal',
        'title': 'Illegal Report Submitted',
        'message': lines.join('\n'),
        'timestamp': _bestReportTimestamp(report),
        // Mirror notification field names so existing UI/filters work.
        'isRead': report['adminIsRead'] == true || report['adminCleared'] == true,
        'reportId': doc.id,
        'illegalType': illegalType,
        if (status.isNotEmpty) 'status': status,
        if (priority.isNotEmpty) 'priority': priority,
        if (location.isNotEmpty) 'location': location,
    };
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

  String _formatTimestamp(dynamic timestamp) {
    if (timestamp == null) return '';
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
      final trimmed = timestamp.trim();
      if (trimmed.isEmpty) return '';
      final parsed = DateTime.tryParse(trimmed);
      if (parsed != null) {
        return _formatTimestamp(parsed);
      }
      return trimmed;
    }
    final fallback = timestamp.toString().trim();
    return fallback;
  }

  /// Returns a tuple-like map with label/bg/fg for the notification chip, or null if none.
  Map<String, dynamic>? _tagFor(Map<String, dynamic> data) {
    final type = (data['type'] ?? data['category'] ?? '').toString().toLowerCase();
    final title = (data['title'] ?? '').toString().toLowerCase();
    final message = (data['message'] ?? '').toString().toLowerCase();

    bool containsAny(List<String> keys, String value) => keys.any((k) => value.contains(k));

    final bool isEmergency = _isEmergencyReport(data) ||
        containsAny(['emergency'], type) ||
        containsAny(['emergency'], title);
    final bool isPcg = containsAny(['pcg'], type) || containsAny(['pcg'], title);
    final bool isWeather = containsAny(['weather', 'ocean', 'storm', 'alert'], type) ||
        containsAny(['weather', 'ocean', 'storm', 'alert'], title) ||
        containsAny(['weather', 'ocean', 'storm', 'alert'], message);
    final bool isIllegal = containsAny(['illegal'], type) ||
        containsAny(['illegal'], title) ||
        containsAny(['illegal'], message);

    if (isEmergency) {
      final level = (data['emergencyLevel'] ?? '').toString().toLowerCase();
      final Color fg = level == 'danger'
          ? Colors.red.shade700
          : level == 'moderate'
              ? Colors.orange.shade800
              : level == 'safe'
                  ? Colors.green.shade700
                  : Colors.red.shade700;
      return {
        'label': 'Emergency Report',
        'bg': fg.withOpacity(0.10),
        'fg': fg,
      };
    }
    if (isWeather) {
      return {
        'label': 'Weather Ocean Alert',
        'bg': Colors.orange.withOpacity(0.12),
        'fg': Colors.orange.shade800,
      };
    }
    if (isIllegal) {
      return {
        'label': 'Illegal Activity Report',
        'bg': Colors.red.withOpacity(0.10),
        'fg': Colors.red.shade700,
      };
    }
    if (isPcg) {
      return {
        'label': 'PCG Alert',
        'bg': Colors.blueAccent.withOpacity(0.1),
        'fg': Colors.blueAccent,
      };
    }
    return null;
  }

  IconData _iconForNotification(Map<String, dynamic> data) {
    if (_isEmergencyReport(data)) {
      return Icons.warning_amber_rounded;
    }
    if (_isIllegalReport(data)) {
      return Icons.report_problem_outlined;
    }
    if (_isWeatherAlert(data)) {
      return Icons.cloud_outlined;
    }
    if ((data['type'] ?? data['category'] ?? '')
        .toString()
        .toLowerCase()
        .contains('pcg')) {
      return Icons.shield_outlined;
    }
    return Icons.notifications_active_rounded;
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

  bool _isIllegalReport(Map<String, dynamic> data) {
    final type = (data['type'] ?? data['category'] ?? '').toString().toLowerCase();
    final title = (data['title'] ?? '').toString().toLowerCase();
    final message = (data['message'] ?? '').toString().toLowerCase();
    return type.contains('illegal') || title.contains('illegal') || message.contains('illegal');
  }

  bool _isWeatherAlert(Map<String, dynamic> data) {
    final type = (data['type'] ?? data['category'] ?? '').toString().toLowerCase();
    final title = (data['title'] ?? '').toString().toLowerCase();
    final message = (data['message'] ?? '').toString().toLowerCase();
    const keys = ['weather', 'ocean', 'storm', 'alert', 'warning'];
    bool containsAny(String v) => keys.any((k) => v.contains(k));
    return containsAny(type) || containsAny(title) || containsAny(message);
  }

  Future<void> _showNotificationDetail(BuildContext context, Map<String, dynamic> data) async {
    final String title = (data['title'] ?? 'Notification').toString();
    final String message = (data['message'] ?? 'No details provided.').toString();
    final String timeText = _formatTimestamp(data['timestamp'] ?? data['time']);
    final String location = (data['location'] ?? '').toString();
    final String priority = (data['priority'] ?? '').toString();
    final String status = (data['status'] ?? '').toString();
    final String reporter = (data['reporterName'] ?? data['reporterLabel'] ?? data['reporter'] ?? '').toString().trim();
    final bool isWeather = _isWeatherAlert(data);
    final tag = _tagFor(data);
    final Color accent = (tag?['fg'] as Color?) ?? _pillColor;
    final Color chipBg = (tag?['bg'] as Color?) ?? accent.withValues(alpha: 0.12);
    final String chipLabel = (tag?['label'] as String?) ?? 'Update';
    final IconData leadingIcon = _iconForNotification(data);
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              12,
              0,
              12,
              MediaQuery.of(ctx).viewInsets.bottom + 12,
            ),
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFFF7FBFF),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.16),
                    blurRadius: 28,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Center(
                      child: Container(
                        width: 42,
                        height: 5,
                        decoration: BoxDecoration(
                          color: const Color(0xFFB7C8DA),
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            _pillColor,
                            accent,
                          ],
                        ),
                        borderRadius: BorderRadius.circular(22),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 46,
                                height: 46,
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.16),
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: Icon(
                                  leadingIcon,
                                  color: Colors.white,
                                  size: 24,
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
                                        fontSize: 21,
                                        fontWeight: FontWeight.w900,
                                        color: Colors.white,
                                        height: 1.1,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      'Review the alert summary and linked metadata below.',
                                      style: TextStyle(
                                        fontSize: 13.3,
                                        color: Colors.white.withValues(alpha: 0.82),
                                        fontWeight: FontWeight.w600,
                                        height: 1.4,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(999),
                                  onTap: () => Navigator.pop(ctx),
                                  child: Container(
                                    width: 36,
                                    height: 36,
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(alpha: 0.14),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.close_rounded,
                                      color: Colors.white,
                                      size: 20,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: chipBg,
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  chipLabel,
                                  style: TextStyle(
                                    color: accent,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                              if (timeText.isNotEmpty)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.14),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Text(
                                    timeText,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              if (reporter.isNotEmpty)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.14),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Text(
                                    reporter,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: const Color(0xFFD8E4F0)),
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
                                  color: accent.withValues(alpha: 0.10),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(
                                  Icons.notes_rounded,
                                  size: 18,
                                  color: accent,
                                ),
                              ),
                              const SizedBox(width: 10),
                              const Text(
                                'Summary',
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 16,
                                  color: _ink,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: accent.withValues(alpha: 0.06),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: accent.withValues(alpha: 0.12),
                              ),
                            ),
                            child: Text(
                              message,
                              style: const TextStyle(
                                fontSize: 15,
                                height: 1.45,
                                color: _ink,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (location.isNotEmpty || priority.isNotEmpty || status.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: const Color(0xFFD8E4F0)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Details',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 16,
                                color: _ink,
                              ),
                            ),
                            const SizedBox(height: 12),
                            if (location.isNotEmpty)
                              _detailRow(
                                icon: Icons.location_on_outlined,
                                label: 'Location',
                                value: location,
                                accent: accent,
                              ),
                            if (priority.isNotEmpty)
                              _detailRow(
                                icon: Icons.flag_outlined,
                                label: 'Priority',
                                value: priority,
                                accent: accent,
                              ),
                            if (status.isNotEmpty)
                              _detailRow(
                                icon: Icons.check_circle_outline,
                                label: 'Status',
                                value: status,
                                accent: accent,
                              ),
                          ],
                        ),
                      ),
                    ],
                    if (isWeather) ...[
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: _pillColor,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          onPressed: () {
                            Navigator.of(ctx).pop();
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const AdminWeatherOceanAlerts(),
                              ),
                            );
                          },
                          child: const Text(
                            'View Weather & Ocean Alerts',
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _detailRow({
    required IconData icon,
    required String label,
    required String value,
    Color? accent,
  }) {
    final tone = accent ?? _pillColor;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: tone.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: tone.withValues(alpha: 0.12)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: tone.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, size: 18, color: tone),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 12.4,
                      color: tone,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    value,
                    style: const TextStyle(
                      fontSize: 13.8,
                      color: _ink,
                      height: 1.35,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool _matchesSelectedFilter(Map<String, dynamic> data) {
    switch (_selectedFilter) {
      case 'Illegal Reports':
        return _isIllegalReport(data);
      case 'Emergency Reports':
        return _isEmergencyReport(data);
      case 'Weather Alerts':
        return _isWeatherAlert(data);
      default:
        return true;
    }
  }

  Widget _filterDropdown({double? maxWidth}) {
    const filters = ['All', 'Illegal Reports', 'Emergency Reports', 'Weather Alerts'];

    final dropdown = SizedBox(
      height: 36,
      child: Container(
        decoration: BoxDecoration(
          color: _pillColor,
          borderRadius: BorderRadius.circular(999),
          boxShadow: const [
            BoxShadow(color: Colors.black26, blurRadius: 6, offset: Offset(0, 2)),
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
            icon: const Icon(Icons.keyboard_arrow_down, color: Colors.white),
            dropdownColor: _pillColor,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 12.4,
            ),
            items: filters
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
                        fontSize: 12.4,
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
      ),
    );

    if (maxWidth != null) {
      return ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: dropdown,
      );
    }
    return dropdown;
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final padding = Responsive.pagePadding(context);
    final maxWidth = Responsive.maxContentWidth(context);
    return Scaffold(
      backgroundColor: _pageBottom,
      appBar: AppBar(
        title: Text(
          l.adminNotificationsTitle,
          style: const TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: 22,
            color: _ink,
            letterSpacing: -0.3,
          ),
        ),
        centerTitle: false,
        backgroundColor: Colors.transparent,
        foregroundColor: _ink,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        elevation: 0,
        leading: Navigator.canPop(context)
            ? IconButton(
                icon: Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFD7E3F1)),
                  ),
                  child: const Icon(Icons.arrow_back_rounded),
                ),
                onPressed: () => Navigator.pop(context),
              )
            : null,
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
                stream: _notificationsStream,
                builder: (context, snapshot) {
                  return StreamBuilder<QuerySnapshot>(
                    stream: _reportsStream,
                    builder: (context, reportsSnapshot) {
              final firestoreNotifications = snapshot.data?.docs ?? [];
              final filteredNotifications = firestoreNotifications.where((doc) {
                final data = doc.data() as Map<String, dynamic>;
                return _isRelevant(data);
              }).toList();

               final reportDocs = reportsSnapshot.data?.docs ?? [];
               final notifiedReportIds = filteredNotifications
                   .map((doc) {
                     final data = doc.data() as Map<String, dynamic>;
                     return (data['reportId'] ?? '').toString().trim();
                   })
                   .where((id) => id.isNotEmpty)
                   .toSet();
              final filteredReports = reportDocs.where((doc) {
                if (notifiedReportIds.contains(doc.id)) return false;
                final data = (doc.data() as Map<String, dynamic>?) ?? <String, dynamic>{};
                if (data['adminCleared'] == true) return false;
                return true;
              }).toList();

              final combinedFirestore = [...filteredNotifications, ...filteredReports];
              combinedFirestore.sort((a, b) {
                final aData = _isReportDoc(a)
                    ? _reportAsNotificationMap(a)
                    : (a.data() as Map<String, dynamic>);
                final bData = _isReportDoc(b)
                    ? _reportAsNotificationMap(b)
                    : (b.data() as Map<String, dynamic>);
                return _asDate(bData['timestamp']).compareTo(_asDate(aData['timestamp']));
              });

              final useStaticData = combinedFirestore.isEmpty &&
                  (snapshot.connectionState == ConnectionState.waiting ||
                      reportsSnapshot.connectionState == ConnectionState.waiting);
              bool hasUnread;
              int unreadCount;

              final notifications = useStaticData
                  ? [
                      {
                        'title': l.adminStaticWeatherAlertTitle,
                        'message': l.adminStaticWeatherAlertMessage,
                        'time': 'Just now',
                        'type': 'weather_alert',
                      },
                      {
                        'title': l.adminStaticIllegalSubmittedTitle,
                        'message': l.adminStaticIllegalSubmittedMessage,
                        'time': '15 min ago',
                        'type': 'illegal_report',
                      },
                      {
                        'title': l.adminStaticReviewNeededTitle,
                        'message': l.adminStaticReviewNeededMessage,
                        'time': '1 hour ago',
                        'type': 'report_approved',
                      },
                    ]
                  : combinedFirestore;

          final List<dynamic> filteredForUi = useStaticData
              ? (notifications as List<Map<String, dynamic>>)
                  .asMap()
                  .entries
                  .where((entry) => _matchesSelectedFilter(entry.value))
                  .toList()
              : (notifications as List<QueryDocumentSnapshot>)
                  .where((doc) {
                    final data = _isReportDoc(doc)
                        ? _reportAsNotificationMap(doc)
                        : (doc.data() as Map<String, dynamic>);
                    return _matchesSelectedFilter(data);
                  })
                  .toList();

          if (useStaticData && _readStatuses.length != notifications.length) {
            _readStatuses = List<bool>.filled(notifications.length, false);
          }

          if (useStaticData) {
            hasUnread = _readStatuses.any((read) => !read);
            unreadCount = _readStatuses.where((read) => !read).length;
          } else {
            final liveNotifications = notifications.whereType<QueryDocumentSnapshot>();
            hasUnread = liveNotifications.any((doc) {
              final data = _isReportDoc(doc)
                  ? _reportAsNotificationMap(doc)
                  : (doc.data() as Map<String, dynamic>);
              return (data['isRead'] ?? false) == false;
            });
            unreadCount = liveNotifications.where((doc) {
              final data = _isReportDoc(doc)
                  ? _reportAsNotificationMap(doc)
                  : (doc.data() as Map<String, dynamic>);
              return (data['isRead'] ?? false) == false;
            }).length;
           }
           final bool markAllEnabled = hasUnread;
           final actionStyle = FilledButton.styleFrom(
             backgroundColor: const Color(0xFF124F8A),
             foregroundColor: Colors.white,
             shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
             padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
             textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.2),
             minimumSize: const Size(0, 38),
           );

           return Padding(
             padding: EdgeInsets.fromLTRB(padding, 8, padding, padding),
             child: Column(
               crossAxisAlignment: CrossAxisAlignment.start,
               children: [
                 Container(
                   width: double.infinity,
                   padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                   decoration: BoxDecoration(
                     borderRadius: BorderRadius.circular(16),
                     gradient: const LinearGradient(
                       begin: Alignment.topLeft,
                       end: Alignment.bottomRight,
                       colors: [Color(0xFF12365B), Color(0xFF1F6EA8)],
                     ),
                     border: Border.all(color: Colors.white.withValues(alpha: 0.24)),
                     boxShadow: [
                       BoxShadow(
                         color: const Color(0xFF12365B).withValues(alpha: 0.28),
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
                             width: 32,
                             height: 32,
                             decoration: BoxDecoration(
                               color: Colors.white.withValues(alpha: 0.18),
                               borderRadius: BorderRadius.circular(10),
                             ),
                             child: const Icon(
                               Icons.dashboard_customize_rounded,
                               color: Colors.white,
                               size: 18,
                             ),
                           ),
                           const SizedBox(width: 9),
                           const Expanded(
                             child: Text(
                               'Admin Notification Desk',
                               style: TextStyle(
                                 color: Colors.white,
                                 fontWeight: FontWeight.w800,
                                 fontSize: 14,
                                 letterSpacing: 0.1,
                               ),
                             ),
                           ),
                           Container(
                             padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                             decoration: BoxDecoration(
                               color: Colors.white.withValues(alpha: 0.16),
                               borderRadius: BorderRadius.circular(999),
                             ),
                             child: Text(
                               '$unreadCount unread',
                               style: const TextStyle(
                                 color: Colors.white,
                                 fontSize: 11,
                                 fontWeight: FontWeight.w800,
                               ),
                             ),
                           ),
                         ],
                       ),
                       const SizedBox(height: 7),
                       Text(
                         '${filteredForUi.length} updates across weather, emergency, and report alerts.',
                         style: TextStyle(
                           color: Colors.white.withValues(alpha: 0.84),
                           fontSize: 12,
                           fontWeight: FontWeight.w600,
                           height: 1.25,
                         ),
                       ),
                     ],
                   ),
                 ),
                 const SizedBox(height: 9),
                 LayoutBuilder(
                   builder: (context, constraints) {
                     final bool compact = constraints.maxWidth < 410;
                     final dropdownWidth = math.min(
                       constraints.maxWidth,
                       math.max(120.0, math.min(constraints.maxWidth * 0.35, 150.0)),
                     );
                     final buttonPadding = EdgeInsets.symmetric(
                       horizontal: compact ? 8 : 13,
                       vertical: 9,
                     );
                     final buttonTextStyle = TextStyle(
                       fontWeight: FontWeight.w800,
                       fontSize: compact ? 11.4 : 12,
                     );

                     final dropdown = SizedBox(
                       width: compact ? double.infinity : dropdownWidth,
                       child: _filterDropdown(),
                     );

                          final markAllButton = FilledButton(
                            onPressed: markAllEnabled
                                ? () async {
                                    if (useStaticData) {
                                      setState(() {
                                        _readStatuses = List<bool>.filled(_readStatuses.length, true);
                                      });
                                    } else {
                                      for (final doc in (notifications as List<QueryDocumentSnapshot>)) {
                                        final data = _isReportDoc(doc)
                                            ? _reportAsNotificationMap(doc)
                                            : (doc.data() as Map<String, dynamic>);
                                        if ((data['isRead'] ?? false) == true) continue;
                                        if (_isReportDoc(doc)) {
                                          await doc.reference.update({
                                            'adminIsRead': true,
                                            'adminReadAt': FieldValue.serverTimestamp(),
                                          });
                                        } else {
                                          await doc.reference.update({'isRead': true});
                                          final reportId = (data['reportId'] ?? '').toString().trim();
                                          if (reportId.isNotEmpty) {
                                            try {
                                              await FirebaseFirestore.instance.collection('reports').doc(reportId).update({
                                                'adminIsRead': true,
                                                'adminReadAt': FieldValue.serverTimestamp(),
                                              });
                                            } catch (_) {
                                              // Ignore: report might not exist or rules may block update
                                            }
                                          }
                                        }
                                      }
                                    }
                                  }
                                : null,
                            style: actionStyle,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.done_all_rounded, size: 16),
                                SizedBox(width: compact ? 4 : 6),
                                Flexible(
                                  child: Text(
                                    compact ? 'Mark read' : l.adminMarkAllRead,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          );

                          final clearAllButton = OutlinedButton(
                            onPressed: () async {
                              if (useStaticData) {
                                setState(() {
                                  _staticNotifications.clear();
                                  _readStatuses.clear();
                                });
                              } else {
                                final reportIdsToClear = <String>{};
                                for (final doc in filteredNotifications) {
                                  final data = (doc.data() as Map<String, dynamic>?) ?? <String, dynamic>{};
                                  final reportId = (data['reportId'] ?? '').toString().trim();
                                  if (reportId.isNotEmpty) {
                                    reportIdsToClear.add(reportId);
                                  }
                                  await doc.reference.delete();
                                }

                                for (final doc in reportDocs) {
                                  reportIdsToClear.remove(doc.id);
                                  try {
                                    await doc.reference.update({
                                      'adminIsRead': true,
                                      'adminReadAt': FieldValue.serverTimestamp(),
                                      'adminCleared': true,
                                      'adminClearedAt': FieldValue.serverTimestamp(),
                                    });
                                  } catch (_) {
                                    // Ignore: rules may block update
                                  }
                                }

                                for (final reportId in reportIdsToClear) {
                                  try {
                                    await FirebaseFirestore.instance.collection('reports').doc(reportId).update({
                                      'adminIsRead': true,
                                      'adminReadAt': FieldValue.serverTimestamp(),
                                      'adminCleared': true,
                                      'adminClearedAt': FieldValue.serverTimestamp(),
                                    });
                                  } catch (_) {
                                    // Ignore: report might not exist or rules may block update
                                  }
                                }
                              }
                            },
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
                                    compact ? 'Clear' : l.adminClearAll,
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
                    Expanded(
                      child: Text(
                        l.adminRecentUpdates,
                        style: const TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w800,
                          color: _ink,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
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
                          fontSize: 12,
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
                                   color: const Color(0xFF8DA7C3).withValues(alpha: 0.10),
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
                                   'New admin-facing alerts will appear here.',
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
                           itemCount: filteredForUi.length,
                           itemBuilder: (context, index) {
                       late final Map<String, dynamic> data;
                       late final dynamic timestamp;
                       int? staticIndex;

                       if (useStaticData) {
                        final entry = filteredForUi[index] as MapEntry<int, Map<String, dynamic>>;
                        staticIndex = entry.key;
                        data = entry.value;
                        timestamp = data['time'];
                      } else {
                        final doc = filteredForUi[index] as QueryDocumentSnapshot;
                        data = _isReportDoc(doc)
                            ? _reportAsNotificationMap(doc)
                            : (doc.data() as Map<String, dynamic>);
                        timestamp = data['timestamp'];
                      }

                      final isRead = useStaticData
                          ? _readStatuses[staticIndex!]
                          : (data['isRead'] == true);
                      final tag = _tagFor(data);
                      final reporterLabel = (data['reporterName'] ?? data['reporterLabel'] ?? '').toString();
                      Color chipFg = Colors.black;
                      Color chipBg = Colors.grey.shade200;
                      String chipLabel = '';
                      if (tag != null) {
                        chipFg = (tag['fg'] as Color?) ?? Colors.black;
                        chipBg = (tag['bg'] as Color?) ?? Colors.grey.shade200;
                        chipLabel = (tag['label'] as String?) ?? '';
                      }
                      final IconData leadingIcon = _iconForNotification(data);

                       return GestureDetector(
                        onTap: () async {
                          final navigator = Navigator.of(context);
                          if (useStaticData && !_readStatuses[staticIndex!]) {
                            setState(() {
                              _readStatuses[staticIndex!] = true;
                            });
                          } else if (!useStaticData && !isRead) {
                            final doc = filteredForUi[index] as QueryDocumentSnapshot;
                             if (_isReportDoc(doc)) {
                               await doc.reference.update({
                                 'adminIsRead': true,
                                 'adminReadAt': FieldValue.serverTimestamp(),
                               });
                             } else {
                               await doc.reference.update({'isRead': true});
                               final reportId = (data['reportId'] ?? '').toString().trim();
                               if (reportId.isNotEmpty) {
                                 try {
                                   await FirebaseFirestore.instance.collection('reports').doc(reportId).update({
                                     'adminIsRead': true,
                                     'adminReadAt': FieldValue.serverTimestamp(),
                                   });
                                 } catch (_) {
                                   // Ignore: report might not exist or rules may block update
                                 }
                               }
                             }
                           }

                          if (!useStaticData && _isEmergencyReport(data)) {
                            navigator.push(
                              MaterialPageRoute(
                                builder: (_) => AdminEmergencyReportDetailsPage(notification: data),
                              ),
                            );
                            return;
                          }

                          if (!useStaticData && _isIllegalReport(data)) {
                            final reportId = (data['reportId'] ?? data['illegalReportId'] ?? '').toString().trim();
                            if (reportId.isNotEmpty) {
                              navigator.push(
                                MaterialPageRoute(
                                  builder: (_) => AdminIllegalReportDetailsPage(reportId: reportId),
                                ),
                              );
                            } else {
                              navigator.push(
                                MaterialPageRoute(builder: (_) => const IllegalReportsPage()),
                              );
                            }
                            return;
                          }

                          if (!useStaticData && _isWeatherAlert(data)) {
                            await _showNotificationDetail(context, data);
                            return;
                          }

                          await _showNotificationDetail(context, data);
                        },
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
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
                                color: const Color(0xFF8DA7C3).withValues(
                                  alpha: isRead ? 0.07 : 0.13,
                                ),
                                blurRadius: 8,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
                            child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    width: 38,
                                    height: 38,
                                    decoration: BoxDecoration(
                                      color: chipFg.withValues(
                                        alpha: isRead ? 0.10 : 0.16,
                                      ),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Icon(
                                      leadingIcon,
                                      color: chipFg,
                                      size: 20,
                                    ),
                                  ),
                                  const SizedBox(width: 9),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            if (chipLabel.isNotEmpty)
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                                decoration: BoxDecoration(
                                                  color: chipBg,
                                                  borderRadius: BorderRadius.circular(999),
                                                ),
                                                child: Text(
                                                  chipLabel,
                                                  style: TextStyle(
                                                    color: chipFg,
                                                    fontWeight: FontWeight.w800,
                                                    fontSize: 10.8,
                                                  ),
                                                ),
                                              ),
                                            const Spacer(),
                                            Text(
                                              useStaticData ? timestamp : _formatTimestamp(timestamp),
                                              style: const TextStyle(
                                                color: _subtleInk,
                                                fontSize: 10.8,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 6),
                                        Row(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            if (!isRead) ...[
                                              Container(
                                                width: 10,
                                                height: 10,
                                                margin: const EdgeInsets.only(top: 4),
                                                decoration: BoxDecoration(
                                                  color: chipFg.withValues(alpha: 0.95),
                                                  shape: BoxShape.circle,
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                            ],
                                            Expanded(
                                              child: Text(
                                                data['title'] ?? l.adminNoTitle,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  color: _ink.withValues(alpha: isRead ? 0.94 : 1),
                                                  fontWeight: FontWeight.w800,
                                                  fontSize: 15.2,
                                                  height: 1.1,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        if (_isEmergencyReport(data) && reporterLabel.isNotEmpty) ...[
                                          const SizedBox(height: 5),
                                          Text(
                                            'Reported by: $reporterLabel',
                                            style: const TextStyle(
                                              color: _subtleInk,
                                              fontSize: 11.8,
                                              fontWeight: FontWeight.w700,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 7),
                                  Container(
                                    width: 28,
                                    height: 28,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFE7EFFA),
                                      borderRadius: BorderRadius.circular(11),
                                    ),
                                    child: const Icon(
                                      Icons.chevron_right_rounded,
                                      color: _subtleInk,
                                      size: 16,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(9),
                                decoration: BoxDecoration(
                                  color: chipFg.withValues(alpha: 0.06),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: chipFg.withValues(alpha: 0.12),
                                  ),
                                ),
                                child: Text(
                                  data['message'] ?? l.adminNoMessage,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 12.6,
                                    color: _subtleInk,
                                    height: 1.25,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
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
}
