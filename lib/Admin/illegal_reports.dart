import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../screens/notification_page.dart';
import '../utils/responsive.dart';

class IllegalReportsPage extends StatefulWidget {
  const IllegalReportsPage({super.key});

  @override
  State<IllegalReportsPage> createState() => _IllegalReportsPageState();
}

class _IllegalReportsPageState extends State<IllegalReportsPage> {
  static const Color _ink = Color(0xFF0A2239);
  static const Color _ocean = Color(0xFF0D4D69);
  static const Color _mist = Color(0xFFF4FBFD);

  Stream<QuerySnapshot<Map<String, dynamic>>>? _reportsStream;
  String _selectedTab = 'All';
  final Map<String, String> _userContacts = {};
  final Map<String, String> _userNames = {};
  final Set<String> _fetchingContacts = {};
  bool _isActionInProgress = false;
  int _pageIndex = 0;
  static const int _pageSize = 10;
  final ScrollController _listController = ScrollController();

  final List<Map<String, dynamic>> allReports = List.generate(50, (index) {
    final types = [
      'Illegal Fishing',
      'Unauthorized Marine Construction',
      'Oil Spillage',
      'Illegal Dumping',
      'Dynamite Fishing',
      'Coral Destruction',
      'Marine Wildlife Poaching'
    ];
    return {
      'createdAt': DateTime.now().subtract(Duration(hours: index * 3)),
      'location': 'Bonuan Beach, Dagupan',
      'type': types[index % types.length],
      'description': 'Suspicious activity spotted near shoreline.',
      'priority': index % 3 == 0 ? 'High' : 'Medium',
      'status': 'pending',
      'pcgAlerted': index % 3 == 0,
      'pcgAlertedAt': DateTime.now(),
      'actionStatus': 'Pending',
      'editing': false,
      'reporter': 'User ${index + 1}',
    };
  });
  @override
  void initState() {
    super.initState();
    _reportsStream = FirebaseFirestore.instance
        .collection('reports')
        .orderBy('submittedAt', descending: true)
        .snapshots();
  }

  @override
  void dispose() {
    _listController.dispose();
    super.dispose();
  }

  String _readFirstText(Map<String, dynamic> data, List<String> keys) {
    for (final key in keys) {
      final value = (data[key] ?? '').toString().trim();
      if (value.isNotEmpty && value.toLowerCase() != 'null') {
        return value;
      }
    }
    return '';
  }

  String _bestContactFromData(Map<String, dynamic> data) {
    final direct = _readFirstText(data, [
      'contact',
      'contact_number',
      'contactNumber',
      'phoneNumber',
      'phone',
      'mobile',
      'email',
    ]);
    if (direct.isNotEmpty) {
      return direct;
    }

    final username = _readFirstText(data, ['username']);
    if (username.isNotEmpty) {
      return username;
    }

    return '';
  }

  String _bestNameFromData(Map<String, dynamic> data) {
    final direct = _readFirstText(data, [
      'reporter',
      'reporterName',
      'submittedBy',
      'fullName',
      'name',
      'displayName',
      'username',
    ]);
    if (direct.isNotEmpty) {
      return direct;
    }

    final first = _readFirstText(data, ['firstName', 'first_name']);
    final last = _readFirstText(data, ['lastName', 'last_name']);
    final combined = '$first $last'.trim();
    if (combined.isNotEmpty) {
      return combined;
    }

    final email = _readFirstText(data, ['email']);
    if (email.isNotEmpty && email.contains('@')) {
      return email.split('@').first;
    }

    return '';
  }

  Future<void> _ensureContactLoaded(String uid) async {
    if (uid.isEmpty || (_userContacts.containsKey(uid) && _userNames.containsKey(uid)) || _fetchingContacts.contains(uid)) {
      return;
    }
    _fetchingContacts.add(uid);
    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      if (!doc.exists) return;
      final data = doc.data() ?? {};
      final best = _bestContactFromData(data);
      final name = _bestNameFromData(data);
      setState(() {
        if (best.isNotEmpty) {
          _userContacts[uid] = best;
        }
        if (name.isNotEmpty) {
          _userNames[uid] = name;
        }
      });
    } catch (_) {
    } finally {
      _fetchingContacts.remove(uid);
    }
  }

  void _setDecisionLocal(int globalIndex, String decision) {
    if (globalIndex < 0 || globalIndex >= allReports.length) {
      return;
    }
    setState(() {
      allReports[globalIndex]['actionStatus'] = decision;
      allReports[globalIndex]['status'] = decision == 'Approved' ? 'resolved' : decision.toLowerCase();
      allReports[globalIndex]['editing'] = false;
    });
  }

  String? _nextStatusValue(String statusLabel) {
    switch (statusLabel.toLowerCase()) {
      case 'acknowledge':
      case 'acknowledged':
      case 'new':
        return 'dispatched';
      case 'dispatched':
        return 'verified';
      case 'verified':
        return 'resolved';
      default:
        return null;
    }
  }

  Future<void> _runWithActionLock(Future<void> Function() task) async {
    if (_isActionInProgress) return;
    setState(() => _isActionInProgress = true);
    try {
      await task();
    } finally {
      if (mounted) setState(() => _isActionInProgress = false);
    }
  }

  Future<void> _advanceReportStatus({
    required Map<String, dynamic> report,
    required bool useFallback,
    String? docId,
    int? localIndex,
  }) async {
    final currentLabel = _statusLabel(report);
    final String? nextStatus = _nextStatusValue(currentLabel);
    if (nextStatus == null) return;

    final String reportId = docId ?? '';
    final String uid = (report['uid'] ?? '').toString();
    final String title = (report['type'] ?? report['title'] ?? 'Illegal Activity').toString();
    final String location = (report['location'] ?? 'Unknown location').toString();

    if (!useFallback && reportId.isNotEmpty) {
      await FirebaseFirestore.instance.collection('reports').doc(reportId).update({
        'actionStatus': nextStatus,
        'status': nextStatus,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } else if (useFallback && localIndex != null) {
      _setDecisionLocal(localIndex, nextStatus);
    }

    final String nextLabel = nextStatus[0].toUpperCase() + nextStatus.substring(1);
    if (uid.isNotEmpty) {
      await sendNotificationToUser(
        targetUserId: uid,
        title: 'Report $nextLabel',
        message: 'Your report "$title" at $location was marked $nextLabel by PCG.',
        extra: {
          'type': 'illegal_report',
          'category': 'illegal',
          'status': nextStatus,
          if (reportId.isNotEmpty) 'reportId': reportId,
        },
      );
    }
    await FirebaseFirestore.instance.collection('notifications').add({
      'targetRole': 'pcg',
      'type': 'illegal_report',
      'category': 'pcg_illegal',
      'title': 'Report $nextLabel',
      'message': '$title marked as $nextLabel. Location: $location',
      'timestamp': FieldValue.serverTimestamp(),
      'isRead': false,
      if (reportId.isNotEmpty) 'reportId': reportId,
    });

    await FirebaseFirestore.instance.collection('notifications').add({
      'targetRole': 'bfar',
      'type': 'illegal_report',
      'category': 'bfar_illegal',
      'title': 'Report $nextLabel',
      'message': '$title marked as $nextLabel. Location: $location',
      'timestamp': FieldValue.serverTimestamp(),
      'isRead': false,
      if (reportId.isNotEmpty) 'reportId': reportId,
    });
  }

  Future<void> _markInvalid({
    required Map<String, dynamic> report,
    required bool useFallback,
    String? docId,
    int? localIndex,
  }) async {
    const targetStatus = 'invalid';
    final String reportId = docId ?? '';
    final String uid = (report['uid'] ?? '').toString();
    final String title = (report['type'] ?? report['title'] ?? 'Illegal Activity').toString();
    final String location = (report['location'] ?? 'Unknown location').toString();
    final String reporterName = _reporterName(report).isNotEmpty
        ? _reporterName(report)
        : (report['reporter'] ?? report['reporterName'] ?? 'Unknown reporter').toString();

    if (!useFallback && reportId.isNotEmpty) {
      await FirebaseFirestore.instance.collection('reports').doc(reportId).update({
        'actionStatus': targetStatus,
        'status': targetStatus,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      if (uid.isNotEmpty) {
        await _recordFakeReportViolation(
          uid: uid,
          reporterName: reporterName,
          reportId: reportId,
          reportTitle: title,
          location: location,
        );
      }
    } else if (useFallback && localIndex != null) {
      _setDecisionLocal(localIndex, targetStatus);
    }

    if (uid.isNotEmpty) {
      await sendNotificationToUser(
        targetUserId: uid,
        title: 'Fake report violation issued',
        message: 'Your report "$title" at $location was marked invalid by PCG. A fake report violation was added to your account.',
        extra: {
          'type': 'illegal_report',
          'category': 'illegal',
          'status': targetStatus,
          'violationType': 'fake_report',
          if (reportId.isNotEmpty) 'reportId': reportId,
        },
      );
    }

    await FirebaseFirestore.instance.collection('notifications').add({
      'targetRole': 'pcg',
      'type': 'illegal_report',
      'category': 'pcg_illegal',
      'title': 'Report marked Invalid',
      'message': '$title marked invalid. Location: $location',
      'timestamp': FieldValue.serverTimestamp(),
      'isRead': false,
      if (reportId.isNotEmpty) 'reportId': reportId,
    });

    await FirebaseFirestore.instance.collection('notifications').add({
      'targetRole': 'bfar',
      'type': 'illegal_report',
      'category': 'bfar_illegal',
      'title': 'Report marked Invalid',
      'message': '$title marked invalid. Location: $location',
      'timestamp': FieldValue.serverTimestamp(),
      'isRead': false,
      if (reportId.isNotEmpty) 'reportId': reportId,
    });
  }

  Future<void> _recordFakeReportViolation({
    required String uid,
    required String reporterName,
    required String reportId,
    required String reportTitle,
    required String location,
  }) async {
    final db = FirebaseFirestore.instance;
    final violationRef = db.collection('violations').doc('${uid}_${reportId}_fake_report');
    final userRef = db.collection('users').doc(uid);
    final reportRef = db.collection('reports').doc(reportId);

    await db.runTransaction((transaction) async {
      final existing = await transaction.get(violationRef);
      if (existing.exists) {
        transaction.update(reportRef, {
          'violationIssued': true,
          'violationId': violationRef.id,
          'violationType': 'fake_report',
          'violationUpdatedAt': FieldValue.serverTimestamp(),
        });
        return;
      }

      transaction.set(violationRef, {
        'uid': uid,
        'userId': uid,
        'reporterName': reporterName,
        'reportId': reportId,
        'reportTitle': reportTitle,
        'location': location,
        'type': 'fake_report',
        'category': 'illegal_report',
        'title': 'Fake Report',
        'description': 'Illegal activity report was marked invalid/fake by PCG review.',
        'status': 'active',
        'severity': 'warning',
        'createdAt': FieldValue.serverTimestamp(),
      });

      transaction.set(userRef, {
        'violationCount': FieldValue.increment(1),
        'fakeReportViolationCount': FieldValue.increment(1),
        'lastViolationAt': FieldValue.serverTimestamp(),
        'accountStanding': 'warning',
      }, SetOptions(merge: true));

      transaction.update(reportRef, {
        'violationIssued': true,
        'violationId': violationRef.id,
        'violationType': 'fake_report',
        'violationIssuedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  DateTime? _parseDateValue(dynamic value) {
    DateTime? dt;
    if (value is Timestamp) {
      dt = value.toDate();
    } else if (value is DateTime) {
      dt = value;
    } else if (value is String && value.isNotEmpty) {
      try {
        dt = DateFormat('yyyy-MM-dd HH:mm').parseStrict(value);
      } catch (_) {
        try {
          dt = DateTime.tryParse(value);
        } catch (_) {
          dt = null;
        }
      }
    }
    return dt;
  }

  String _formatDate(dynamic value) {
    final dt = _parseDateValue(value);
    if (dt == null) return '';
    return DateFormat('yyyy-MM-dd hh:mma').format(dt).toLowerCase();
  }

  String _bestSubmittedDateText(Map<String, dynamic> report) {
    final value = report['submittedAt'] ??
        report['manilaSubmittedAt'] ??
        report['timestamp'] ??
        report['createdAt'];
    return _formatDate(value);
  }

  String _bestIncidentDateText(Map<String, dynamic> report) {
    final value = report['incidentAt'] ??
        report['incidentDateTime'] ??
        report['incidentDateTimeString'] ??
        report['incidentDate'] ??
        report['occurredAt'] ??
        report['date'];
    return _formatDate(value);
  }

  String _reporterName(Map<String, dynamic> report) {
    final uid = (report['uid'] ?? '').toString();
    final direct = _bestNameFromData(report);
    if (direct.isNotEmpty) return direct;
    final lookup = _userNames[uid] ?? '';
    if (lookup.isNotEmpty) return lookup;
    return '';
  }

  String _reportContact(Map<String, dynamic> report) {
    final uid = (report['uid'] ?? '').toString();
    final direct = _bestContactFromData(report);
    if (direct.isNotEmpty) return direct;
    final lookup = _userContacts[uid] ?? '';
    if (lookup.isNotEmpty) return lookup;
    return 'N/A';
  }

  Color _statusAccent(String status) {
    switch (status.toLowerCase()) {
      case 'acknowledge':
      case 'acknowledged':
      case 'new':
        return const Color(0xFF2876F7);
      case 'dispatched':
        return const Color(0xFF6B7280);
      case 'verified':
        return const Color(0xFF22A06B);
      case 'resolved':
        return const Color(0xFF0E7490);
      case 'invalid':
        return const Color(0xFFE56A54);
      default:
        return _ocean;
    }
  }

  Color _priorityBackground(String priority) {
    switch (priority.toLowerCase()) {
      case 'high':
        return const Color(0xFFFFE0DC);
      case 'medium':
        return const Color(0xFFD8E8FF);
      case 'low':
        return const Color(0xFFE1F6E7);
      default:
        return const Color(0xFFE9EEF3);
    }
  }

  Color _priorityForeground(String priority) {
    switch (priority.toLowerCase()) {
      case 'high':
        return const Color(0xFFB42318);
      case 'medium':
        return const Color(0xFF185ABC);
      case 'low':
        return const Color(0xFF1E7F47);
      default:
        return const Color(0xFF475467);
    }
  }

  String _coordinatesText(Map<String, dynamic> report) {
    final lat = report['lat'] ?? report['latitude'];
    final lng = report['lng'] ?? report['lon'] ?? report['longitude'];
    if (lat == null || lng == null) return '';
    return 'Lat $lat, Lon $lng';
  }

  @override
  Widget build(BuildContext context) {
    final padding = Responsive.pagePadding(context);
    final maxWidth = Responsive.maxContentWidth(context);
    return Scaffold(
      backgroundColor: _mist,
      appBar: AppBar(
        title: const Text(
          'Illegal Activities Reports',
          style: TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: 22,
            color: _ink,
            letterSpacing: -0.3,
          ),
        ),
        centerTitle: false,
        backgroundColor: _mist,
        surfaceTintColor: Colors.transparent,
        foregroundColor: _ink,
        scrolledUnderElevation: 0,
        elevation: 0,
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
              child: _buildReportsList(padding),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildReportsList(double padding) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: padding, vertical: padding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF08263F),
                  Color(0xFF0D4D69),
                ],
              ),
              borderRadius: BorderRadius.circular(26),
              boxShadow: [
                BoxShadow(
                  color: _ocean.withValues(alpha: 0.18),
                  blurRadius: 22,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: const Icon(
                    Icons.gavel_rounded,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'PCG Report Board',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 19,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Track case status, review evidence, and move reports through response stages.',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.78),
                          fontSize: 13.5,
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
          const SizedBox(height: 16),
          _TabBar(
            selected: _selectedTab,
            onSelect: (tab) => setState(() {
              _selectedTab = tab;
              _pageIndex = 0;
              if (_listController.hasClients) {
                _listController.jumpTo(0);
              }
            }),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _reportsStream,
              builder: (context, snapshot) {
                final docs = snapshot.data?.docs ?? [];
                final bool useFallback = docs.isEmpty;
                final List<Map<String, dynamic>> all = useFallback
                    ? allReports
                    : docs
                        .map((d) => {
                              'id': d.id,
                              ...d.data(),
                            })
                        .toList();

                final reports = all.where((report) {
                  if (_selectedTab == 'All') return true;
                  final status = _statusLabel(report).toLowerCase();
                  return status == _selectedTab.toLowerCase();
                }).toList();

                if (reports.isEmpty) {
                  return Center(
                    child: Container(
                      padding: const EdgeInsets.all(22),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.94),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: const Color(0xFFD7EAF1)),
                      ),
                      child: const Text(
                        'No reports found',
                        style: TextStyle(
                          color: _ink,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  );
                }

                final totalPages = (reports.length / _pageSize).ceil().clamp(1, reports.length);
                if (_pageIndex > totalPages - 1) {
                  _pageIndex = totalPages - 1;
                }
                final start = _pageIndex * _pageSize;
                final pageItems = reports.skip(start).take(_pageSize).toList();

                return Column(
                  children: [
                    Expanded(
                      child: ListView.builder(
                        controller: _listController,
                        itemCount: pageItems.length,
                        itemBuilder: (context, index) {
                    final report = pageItems[index];
                    final uid = (report['uid'] ?? '').toString();
                    final int localIndex = all.indexOf(report);
                    if (uid.isNotEmpty) {
                      _ensureContactLoaded(uid);
                    }
                    final String? docId = report['id'] as String?;
                    final bool pcgApproved = report['pcgAlerted'] == true ||
                      report['pcgApproved'] == true ||
                      report['bfarApproved'] == true;
                    final String statusRaw = (report['status'] ?? '').toString();
                    String actionStatus = (report['actionStatus'] ?? '').toString();
                    if (actionStatus.isEmpty || actionStatus == 'null') {
                      if (statusRaw == 'resolved') {
                        actionStatus = 'Approved';
                      } else if (statusRaw == 'under_review') {
                        actionStatus = 'Declined';
                      } else {
                        actionStatus = 'Pending';
                      }
                    }
                    report['actionStatus'] = actionStatus;
                    report['status'] = statusRaw;
                    final String incidentDateText = _bestIncidentDateText(report);
                    final String submittedDateText = _bestSubmittedDateText(report);
                    final String priority = (report['priority'] ?? '').toString();
                    final String reporterName = _reporterName(report);
                    final String contactValue = _reportContact(report);
                    final String statusLabel = _statusLabel(report);
                    final String? nextStatus = _nextStatusValue(statusLabel);
                    final bool isInvalid = statusLabel.toLowerCase() == 'invalid';
                    final bool isResolved = statusLabel.toLowerCase() == 'resolved';
                    final bool canAdvance = nextStatus != null && !isInvalid && !isResolved;
                    final bool showInvalidCta = isResolved && !isInvalid;
                    final String ctaText = showInvalidCta ? 'Invalid' : _ctaLabel(statusLabel);

                    return _buildReportCard(
                      context: context,
                      report: report,
                      useFallback: useFallback,
                      localIndex: localIndex,
                      docId: docId,
                      pcgApproved: pcgApproved,
                      incidentDateText: incidentDateText,
                      submittedDateText: submittedDateText,
                      priority: priority,
                      reporterName: reporterName,
                      contactValue: contactValue,
                      statusLabel: statusLabel,
                      ctaText: ctaText,
                      showInvalidCta: showInvalidCta,
                      canAdvance: canAdvance,
                    );
                        },
                      ),
                    ),
                    if (reports.length > _pageSize)
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.94),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: const Color(0xFFD7EAF1),
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: _ocean.withValues(alpha: 0.08),
                                blurRadius: 16,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                icon: const Icon(Icons.chevron_left_rounded),
                                onPressed: _pageIndex > 0
                                    ? () => setState(() {
                                          _pageIndex -= 1;
                                          if (_listController.hasClients) {
                                            _listController.jumpTo(0);
                                          }
                                        })
                                    : null,
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: _mist,
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  'Page ${_pageIndex + 1} / $totalPages',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    color: _ink,
                                  ),
                                ),
                              ),
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                icon: const Icon(Icons.chevron_right_rounded),
                                onPressed: _pageIndex < totalPages - 1
                                    ? () => setState(() {
                                          _pageIndex += 1;
                                          if (_listController.hasClients) {
                                            _listController.jumpTo(0);
                                          }
                                        })
                                    : null,
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReportCard({
    required BuildContext context,
    required Map<String, dynamic> report,
    required bool useFallback,
    required int localIndex,
    required String? docId,
    required bool pcgApproved,
    required String incidentDateText,
    required String submittedDateText,
    required String priority,
    required String reporterName,
    required String contactValue,
    required String statusLabel,
    required String ctaText,
    required bool showInvalidCta,
    required bool canAdvance,
  }) {
    final accent = _statusAccent(statusLabel);
    final priorityLabel = priority.isEmpty ? 'Unknown' : priority;
    final location = (report['location'] ?? '').toString();
    final coordinates = _coordinatesText(report);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: accent.withValues(alpha: 0.2)),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.08),
            blurRadius: 22,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _StatusBadge(status: statusLabel),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: _priorityBackground(priorityLabel),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    priorityLabel,
                    style: TextStyle(
                      color: _priorityForeground(priorityLabel),
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                if (pcgApproved)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE1F6E7),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: const Text(
                      'PCG Alerted',
                      style: TextStyle(
                        color: Color(0xFF1E7F47),
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        (report['type'] ?? report['title'] ?? 'Illegal Activity').toString(),
                        style: const TextStyle(
                          color: _ink,
                          fontWeight: FontWeight.w900,
                          fontSize: 21,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        incidentDateText.isEmpty
                            ? 'Incident time not recorded'
                            : 'Incident: $incidentDateText',
                        style: TextStyle(
                          color: _ink.withValues(alpha: 0.58),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(
                    Icons.assignment_rounded,
                    color: accent,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.location_on_rounded,
                        size: 18,
                        color: accent,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          location.isEmpty ? 'Unknown location' : location,
                          style: const TextStyle(
                            color: _ink,
                            fontWeight: FontWeight.w700,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (coordinates.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.only(left: 28),
                      child: Text(
                        coordinates,
                        style: TextStyle(
                          color: _ink.withValues(alpha: 0.58),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 14),
            _IconRow(
              icon: Icons.person_outline_rounded,
              label: 'Reporter',
              value: reporterName.isNotEmpty ? reporterName : 'Unknown',
              iconSize: 18,
              labelStyle: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 14,
                color: _ink,
              ),
              valueStyle: TextStyle(
                fontSize: 14,
                color: _ink.withValues(alpha: 0.72),
                fontWeight: FontWeight.w600,
              ),
            ),
            _IconRow(
              icon: Icons.call_outlined,
              label: 'Contact',
              value: contactValue,
              iconSize: 18,
              labelStyle: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 14,
                color: _ink,
              ),
              valueStyle: TextStyle(
                fontSize: 14,
                color: _ink.withValues(alpha: 0.72),
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: _ink,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                    ),
                    onPressed: () => _showDetails(
                      context: context,
                      report: report,
                      useFallback: useFallback,
                      docId: docId,
                      index: localIndex,
                      pcgApproved: pcgApproved,
                      incidentDateText: incidentDateText,
                      submittedDateText: submittedDateText,
                      priority: priority,
                    ),
                    child: const Text(
                      'Open Details',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: accent),
                      foregroundColor: accent,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                    ),
                    onPressed: showInvalidCta
                        ? (_isActionInProgress
                            ? null
                            : () => _runWithActionLock(
                                  () => _markInvalid(
                                    report: report,
                                    docId: docId,
                                    localIndex: localIndex,
                                    useFallback: useFallback,
                                  ),
                                ))
                        : canAdvance && !_isActionInProgress
                            ? () => _runWithActionLock(
                                  () => _advanceReportStatus(
                                    report: report,
                                    docId: docId,
                                    localIndex: localIndex,
                                    useFallback: useFallback,
                                  ),
                                )
                            : null,
                    child: Text(
                      ctaText,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _statusLabel(Map<String, dynamic> report) {
    final actionStatus = (report['actionStatus'] ?? '').toString().toLowerCase();
    final statusRaw = (report['status'] ?? '').toString().toLowerCase();
    if (statusRaw.contains('invalid') || actionStatus.contains('invalid')) return 'Invalid';
    if (statusRaw.contains('acknowledge') || actionStatus.contains('acknowledge')) return 'Acknowledged';
    if (statusRaw.contains('resolved') || actionStatus == 'approved') return 'Resolved';
    if (statusRaw.contains('verified') || actionStatus == 'verified') return 'Verified';
    if (statusRaw.contains('dispatched')) return 'Dispatched';
    if (actionStatus.contains('pending') || statusRaw.contains('pending')) return 'Acknowledged';
    return 'New';
  }

  String _ctaLabel(String status) {
    switch (status.toLowerCase()) {
      case 'new':
      case 'acknowledge':
      case 'acknowledged':
        return 'Acknowledged';
      case 'dispatched':
        return 'Dispatched';
      case 'verified':
        return 'Verified';
      case 'resolved':
        return 'Invalid';
      case 'invalid':
        return 'Invalid';
      default:
        return status.isEmpty ? 'Update' : status[0].toUpperCase() + status.substring(1);
    }
  }

  void _showDetails({
    required BuildContext context,
    required Map<String, dynamic> report,
    required bool useFallback,
    required String? docId,
    required int index,
    required bool pcgApproved,
    required String incidentDateText,
    required String submittedDateText,
    required String priority,
  }) {
    final List<String> displayImages = _extractImages(
      report['images'] ?? report['photos'] ?? report['photoUrls'] ?? report['photourls'],
    );
    final String reporterName = _reporterName(report);
    final String contact = _reportContact(report);
    final String priorityLabel = priority.isEmpty ? 'Unknown' : priority;
    final String statusLabel = _statusLabel(report);
    final String? nextStatus = _nextStatusValue(statusLabel);
    final bool isInvalid = statusLabel.toLowerCase() == 'invalid';
    final bool isResolved = statusLabel.toLowerCase() == 'resolved';
    final bool canAdvance = nextStatus != null && !isInvalid && !isResolved;
    final bool showInvalidCta = isResolved && !isInvalid;
    final String ctaText = showInvalidCta ? 'Invalid' : _ctaLabel(statusLabel);
    final Color accent = _statusAccent(statusLabel);
    final String locationValue = (report['location'] ?? '').toString().trim();
    final String coordinatesValue = _coordinatesText(report);
    showDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 280, maxWidth: 460),
            child: Container(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.white,
                    Color(0xFFF7FBFD),
                  ],
                ),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: accent.withValues(alpha: 0.16)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.16),
                    blurRadius: 28,
                    offset: const Offset(0, 18),
                  ),
                ],
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            _ink,
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
                                  color: Colors.white.withValues(alpha: 0.14),
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: const Icon(
                                  Icons.assignment_rounded,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      (report['type'] ?? report['title'] ?? 'Illegal Activity').toString(),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w900,
                                        fontSize: 22,
                                        color: Colors.white,
                                        letterSpacing: -0.2,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      'Case details, reporter info, and attached evidence.',
                                      style: TextStyle(
                                        color: Colors.white.withValues(alpha: 0.78),
                                        fontWeight: FontWeight.w600,
                                        height: 1.35,
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
                                  onTap: () => Navigator.pop(context),
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
                              _StatusBadge(status: statusLabel),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: _priorityBackground(priorityLabel),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  priorityLabel,
                                  style: TextStyle(
                                    color: _priorityForeground(priorityLabel),
                                    fontWeight: FontWeight.w800,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                              if (pcgApproved)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.14),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: const Text(
                                    'PCG Alerted',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w800,
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
                    _DetailFactCard(
                      icon: Icons.event_available_rounded,
                      label: 'Incident Date & Time',
                      value: incidentDateText.isEmpty ? 'Incident time not recorded' : incidentDateText,
                      accent: accent,
                    ),
                    const SizedBox(height: 12),
                    _DetailFactCard(
                      icon: Icons.schedule_rounded,
                      label: 'Submitted',
                      value: submittedDateText.isEmpty ? 'No submission time' : submittedDateText,
                      accent: accent,
                    ),
                    const SizedBox(height: 12),
                    _DetailFactCard(
                      icon: Icons.location_on_rounded,
                      label: 'Location',
                      value: locationValue.isEmpty ? 'Unknown location' : locationValue,
                      supportingText: coordinatesValue.isEmpty ? null : coordinatesValue,
                      accent: accent,
                    ),
                    const SizedBox(height: 12),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final compact = constraints.maxWidth < 360;
                        final reporterCard = _DetailFactCard(
                          icon: Icons.person_outline_rounded,
                          label: 'Reporter',
                          value: reporterName.isNotEmpty ? reporterName : 'Unknown',
                          accent: accent,
                        );
                        final contactCard = _DetailFactCard(
                          icon: Icons.call_outlined,
                          label: 'Contact',
                          value: contact,
                          accent: accent,
                        );

                        if (compact) {
                          return Column(
                            children: [
                              reporterCard,
                              const SizedBox(height: 12),
                              contactCard,
                            ],
                          );
                        }

                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: reporterCard),
                            const SizedBox(width: 12),
                            Expanded(child: contactCard),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 16),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: accent.withValues(alpha: 0.12)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 38,
                                height: 38,
                                decoration: BoxDecoration(
                                  color: accent.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Icon(
                                  Icons.photo_library_outlined,
                                  color: accent,
                                ),
                              ),
                              const SizedBox(width: 12),
                              const Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Evidence',
                                      style: TextStyle(
                                        color: _ink,
                                        fontWeight: FontWeight.w800,
                                        fontSize: 16,
                                      ),
                                    ),
                                    SizedBox(height: 2),
                                    Text(
                                      'Tap an image to open it full screen.',
                                      style: TextStyle(
                                        color: Color(0xFF667085),
                                        fontWeight: FontWeight.w600,
                                        fontSize: 12.5,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          _ImageStrip(
                            urls: displayImages,
                            height: 128,
                            thumbWidth: 152,
                            onTap: (index) => _openFullScreenGallery(context, displayImages, index),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 15),
                              backgroundColor: Colors.white,
                              side: BorderSide(color: _ink.withValues(alpha: 0.24)),
                              foregroundColor: _ink,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(18),
                              ),
                              textStyle: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Done'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton(
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 15),
                              backgroundColor: accent,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(18),
                              ),
                              textStyle: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            onPressed: showInvalidCta
                                ? (_isActionInProgress
                                    ? null
                                    : () async {
                                        final navigator = Navigator.of(context);
                                        await _runWithActionLock(
                                          () => _markInvalid(
                                            report: report,
                                            docId: docId,
                                            localIndex: index,
                                            useFallback: useFallback,
                                          ),
                                        );
                                        navigator.pop();
                                      })
                                : canAdvance && !_isActionInProgress
                                    ? () async {
                                        final navigator = Navigator.of(context);
                                        await _runWithActionLock(
                                          () => _advanceReportStatus(
                                            report: report,
                                            docId: docId,
                                            localIndex: index,
                                            useFallback: useFallback,
                                          ),
                                        );
                                        navigator.pop();
                                      }
                                    : null,
                            child: Text(ctaText),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  List<String> _extractImages(dynamic raw) {
    List<String> urls = [];
    String coerce(dynamic item) {
      if (item == null) return '';
      if (item is String) return item;
      if (item is Map) {
        final candidates = [
          item['url'],
          item['downloadUrl'],
          item['imageUrl'],
          item['path'],
          item['image'],
        ];
        for (final c in candidates) {
          final s = c?.toString() ?? '';
          if (s.isNotEmpty) return s;
        }
      }
      return item.toString();
    }

    if (raw is List) {
      urls = raw.map(coerce).where((e) => e.isNotEmpty).toList();
    } else if (raw is Map) {
      final single = coerce(raw);
      if (single.isNotEmpty) urls.add(single);
    } else if (raw is String && raw.isNotEmpty) {
      urls = [raw];
    }
    return urls;
  }

  void _openFullScreenGallery(BuildContext context, List<String> urls, int initialIndex) {
    if (urls.isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _FullScreenImagePage(
          urls: urls,
          initialIndex: initialIndex,
        ),
      ),
    );
  }
}

class _DetailFactCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String? supportingText;
  final Color accent;

  const _DetailFactCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.accent,
    this.supportingText,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: accent.withValues(alpha: 0.12)),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.04),
            blurRadius: 14,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(15),
            ),
            child: Icon(icon, color: accent, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label.toUpperCase(),
                  style: const TextStyle(
                    color: Color(0xFF667085),
                    fontWeight: FontWeight.w800,
                    fontSize: 11.5,
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  value,
                  style: const TextStyle(
                    color: Color(0xFF0A2239),
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    height: 1.35,
                  ),
                ),
                if (supportingText != null && supportingText!.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    supportingText!,
                    style: TextStyle(
                      color: const Color(0xFF0A2239).withValues(alpha: 0.62),
                      fontWeight: FontWeight.w600,
                      height: 1.35,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ImageStrip extends StatelessWidget {
  final List<String> urls;
  final double height;
  final double thumbWidth;
  final ValueChanged<int>? onTap;

  const _ImageStrip({
    required this.urls,
    this.height = 110,
    this.thumbWidth = 130,
    this.onTap,
  });

  bool _isDataUrl(String url) => url.startsWith('data:image');

  Uint8List? _decodeDataUrl(String url) {
    try {
      final base64Part = url.split(',').last;
      return base64.decode(base64Part);
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final list = urls.isEmpty ? ['placeholder_1', 'placeholder_2'] : urls;
    return SizedBox(
      height: height,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: list.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (_, i) {
          final url = list[i];
          final isPlaceholder = url.startsWith('placeholder_');
          if (isPlaceholder) {
            return Container(
              width: thumbWidth,
              height: height,
              decoration: BoxDecoration(
                color: Colors.grey.shade200,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.image_not_supported, color: Colors.black54),
            );
          }
          final isData = _isDataUrl(url);
          final dataBytes = isData ? _decodeDataUrl(url) : null;
          final child = ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: isData && dataBytes != null
                ? Image.memory(
                    dataBytes,
                    width: thumbWidth,
                    height: height,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      width: thumbWidth,
                      height: height,
                      color: Colors.grey.shade200,
                      child: const Icon(Icons.broken_image),
                    ),
                  )
                : Image.network(
                    url,
                    width: thumbWidth,
                    height: height,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      width: thumbWidth,
                      height: height,
                      color: Colors.grey.shade200,
                      child: const Icon(Icons.broken_image),
                    ),
                  ),
          );
          return GestureDetector(
            onTap: onTap != null ? () => onTap!(i) : null,
            child: child,
          );
        },
      ),
    );
  }
}

class _FullScreenImagePage extends StatefulWidget {
  const _FullScreenImagePage({
    required this.urls,
    required this.initialIndex,
  });

  final List<String> urls;
  final int initialIndex;

  @override
  State<_FullScreenImagePage> createState() => _FullScreenImagePageState();
}

class _FullScreenImagePageState extends State<_FullScreenImagePage> {
  late final PageController _controller;
  late int _current;

  @override
  void initState() {
    super.initState();
    _current = widget.initialIndex;
    _controller = PageController(initialPage: _current);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Stack(
        children: [
          PageView.builder(
            controller: _controller,
            onPageChanged: (index) => setState(() => _current = index),
            itemCount: widget.urls.length,
            itemBuilder: (_, index) {
              final url = widget.urls[index];
              final bool isData = url.startsWith('data:image');
              Uint8List? bytes;
              if (isData) {
                try {
                  bytes = base64.decode(url.split(',').last);
                } catch (_) {}
              }

              final image = isData && bytes != null
                  ? Image.memory(bytes, fit: BoxFit.contain)
                  : Image.network(url, fit: BoxFit.contain);

              return Center(
                child: InteractiveViewer(
                  panEnabled: true,
                  minScale: 0.5,
                  maxScale: 4,
                  child: image,
                ),
              );
            },
          ),
          if (widget.urls.length > 1)
            Positioned(
              bottom: 16,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (int i = 0; i < widget.urls.length; i++)
                    Container(
                      width: 8,
                      height: 8,
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: i == _current ? Colors.white : Colors.white54,
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _IconRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final double iconSize;
  final TextStyle? labelStyle;
  final TextStyle? valueStyle;

  const _IconRow({
    required this.icon,
    required this.label,
    required this.value,
    this.iconSize = 16,
    this.labelStyle,
    this.valueStyle,
  });

  @override
  Widget build(BuildContext context) {
    final String trimmedLabel = label.trim();
    final String labelText = trimmedLabel.endsWith(':') ? trimmedLabel : '$trimmedLabel:';

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(icon, size: iconSize, color: Colors.black87),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: valueStyle ?? const TextStyle(fontSize: 14, color: Colors.black87),
                children: [
                  TextSpan(
                    text: '$labelText ',
                    style: labelStyle ?? const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: Colors.black),
                  ),
                  TextSpan(text: value),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String status;

  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final lower = status.toLowerCase();
    Color bg = const Color(0xFFE9EEF3);
    Color fg = const Color(0xFF475467);
    if (lower == 'new') {
      bg = const Color(0xFFD8E8FF);
      fg = const Color(0xFF185ABC);
    } else if (lower == 'acknowledge' || lower == 'acknowledged') {
      bg = const Color(0xFFD8E8FF);
      fg = const Color(0xFF185ABC);
    } else if (lower == 'verified') {
      bg = const Color(0xFFE1F6E7);
      fg = const Color(0xFF1E7F47);
    } else if (lower == 'dispatched') {
      bg = const Color(0xFFECEFF3);
      fg = const Color(0xFF475467);
    } else if (lower == 'resolved') {
      bg = const Color(0xFFDDF4F8);
      fg = const Color(0xFF0E7490);
    } else if (lower == 'invalid') {
      bg = const Color(0xFFFFE0DC);
      fg = const Color(0xFFB42318);
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        status,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          color: fg,
        ),
      ),
    );
  }
}

class _TabBar extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onSelect;

  const _TabBar({required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final tabs = ['All', 'Acknowledged', 'Dispatched', 'Verified', 'Resolved', 'Invalid'];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: tabs.map((tab) {
          final bool isActive = tab == selected;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => onSelect(tab),
                borderRadius: BorderRadius.circular(999),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOutCubic,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    gradient: isActive
                        ? const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              Color(0xFF083A64),
                              Color(0xFF0F6A86),
                            ],
                          )
                        : null,
                    color: isActive ? null : Colors.white.withValues(alpha: 0.92),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: isActive
                          ? Colors.transparent
                          : const Color(0xFFD7EAF1),
                    ),
                    boxShadow: isActive
                        ? [
                            BoxShadow(
                              color: const Color(0xFF0A3558).withValues(alpha: 0.16),
                              blurRadius: 16,
                              offset: const Offset(0, 8),
                            ),
                          ]
                        : const [],
                  ),
                  child: Text(
                    tab,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: isActive ? Colors.white : const Color(0xFF0A2239),
                    ),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
