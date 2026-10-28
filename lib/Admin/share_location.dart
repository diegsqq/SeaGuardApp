import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/responsive.dart';

class ShareLocationPage extends StatefulWidget {
  final String emergencyLevel;
  final bool notifyAll;
  final String reporterName;

  const ShareLocationPage({
    super.key,
    required this.emergencyLevel,
    this.notifyAll = false,
    this.reporterName = 'Admin PCG',
  });

  @override
  State<ShareLocationPage> createState() => _ShareLocationPageState();
}

class _ShareLocationPageState extends State<ShareLocationPage> {
  static const Color _ink = Color(0xFF0A2239);
  static const Color _mist = Color(0xFFF4FBFD);
  static const Color _surface = Colors.white;

  Position? _currentPosition;
  String _status = '';
  bool _sending = false;
  final TextEditingController _addressController = TextEditingController();
  String? _reporterLabel;
  bool _isOnline = true;
  bool _isSyncing = false;
  StreamSubscription<dynamic>? _connectivitySub;
  List<Map<String, dynamic>> _pendingQueue = [];
  static const String _pendingKey = 'pending_shared_locations';

  Color _emergencyAccent() {
    switch (widget.emergencyLevel.toLowerCase()) {
      case 'danger':
        return const Color(0xFFE55454);
      case 'moderate':
        return const Color(0xFFD7B646);
      default:
        return const Color(0xFF4BA4E6);
    }
  }

  IconData _emergencyIcon() {
    switch (widget.emergencyLevel.toLowerCase()) {
      case 'danger':
        return Icons.priority_high_rounded;
      case 'moderate':
        return Icons.warning_amber_rounded;
      default:
        return Icons.shield_outlined;
    }
  }

  String _stateTitle() {
    if (_sending) return 'Sending live location';
    if (_currentPosition != null || _addressController.text.trim().isNotEmpty) {
      return 'Location ready';
    }
    return 'Waiting for location';
  }

  String _stateDescription() {
    if (_sending) {
      return 'We are fetching your current position, resolving the address, and pushing the alert.';
    }
    if (_addressController.text.trim().isNotEmpty) {
      return _addressController.text.trim();
    }
    if (_currentPosition != null) {
      return _composeLabel(pos: _currentPosition, address: null);
    }
    return 'No live coordinates attached yet. Tap the button below to retry location capture.';
  }

  Color _statusColor() {
    final lower = _status.toLowerCase();
    if (lower.contains('failed') ||
        lower.contains('denied') ||
        lower.contains('unable')) {
      return const Color(0xFFE55454);
    }
    if (lower.contains('offline') || lower.contains('retry')) {
      return const Color(0xFFD7B646);
    }
    if (lower.contains('success') || lower.contains('sent')) {
      return const Color(0xFF22A06B);
    }
    return _ink;
  }

  @override
  void initState() {
    super.initState();
    _loadReporterLabel();
    _initConnectivityQueue();
    _determinePosition();
  }

  @override
  void dispose() {
    _connectivitySub?.cancel();
    _addressController.dispose();
    super.dispose();
  }

  Future<void> _loadReporterLabel() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final snapshot = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final data = snapshot.data();
      if (data == null) return;
      final role = (data['role'] ?? '').toString().trim();
      final province = (data['province'] ?? '').toString().trim();
      final region = (data['region'] ?? '').toString().trim();
      final municipality = (data['municipality'] ?? '').toString().trim();
      final unit = [province, region, municipality].firstWhere(
        (v) => v.isNotEmpty,
        orElse: () => '',
      );
      final labelParts = <String>[
        if (role.isNotEmpty) role,
        if (unit.isNotEmpty) unit,
      ];
      final label = labelParts.join(' ').trim();
      if (label.isNotEmpty && mounted) {
        setState(() => _reporterLabel = label);
      }
    } catch (_) {
    }
  }

  Future<void> _initConnectivityQueue() async {
    await _loadPendingQueue();
    await _refreshConnectivity();
    if (_isOnline) {
      _syncPendingQueue();
    }
    _connectivitySub = Connectivity().onConnectivityChanged.listen((result) {
      final online = _isConnected(result);
      if (mounted) {
        setState(() => _isOnline = online);
      } else {
        _isOnline = online;
      }
      if (online) {
        _syncPendingQueue();
      }
    });
  }

  Future<void> _refreshConnectivity() async {
    try {
      final status = await Connectivity().checkConnectivity();
      final online = _isConnected(status);
      if (mounted) {
        setState(() => _isOnline = online);
      } else {
        _isOnline = online;
      }
    } catch (_) {}
  }

  bool _isConnected(dynamic status) {
    if (status is ConnectivityResult) return status != ConnectivityResult.none;
    if (status is List<ConnectivityResult>) {
      return status.any((r) => r != ConnectivityResult.none);
    }
    return false;
  }

  Future<void> _loadPendingQueue() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getStringList(_pendingKey) ?? [];
    final pending = <Map<String, dynamic>>[];
    for (final item in stored) {
      try {
        final decoded = jsonDecode(item);
        if (decoded is Map<String, dynamic>) pending.add(decoded);
      } catch (_) {}
    }
    if (mounted) {
      setState(() => _pendingQueue = pending);
    } else {
      _pendingQueue = pending;
    }
  }

  Future<void> _persistPendingQueue() async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = _pendingQueue.map((e) => jsonEncode(e)).toList();
    await prefs.setStringList(_pendingKey, encoded);
  }

  Future<void> _queueLocation(Map<String, dynamic> payload) async {
    _pendingQueue.insert(0, payload);
    await _persistPendingQueue();
    if (mounted) setState(() {});
  }

  Future<void> _syncPendingQueue() async {
    if (_isSyncing || !_isOnline || _pendingQueue.isEmpty) return;
    _isSyncing = true;
    try {
      for (int i = _pendingQueue.length - 1; i >= 0; i--) {
        final item = _pendingQueue[i];
        final ok = await _sendLocationOnline(item, silent: true);
        if (ok) {
          _pendingQueue.removeAt(i);
          await _persistPendingQueue();
          if (mounted) setState(() {});
        }
      }
    } finally {
      _isSyncing = false;
    }
  }

  Future<void> _notifyAllUsers({
    double? lat,
    double? lng,
    required String locationLabel,
    required bool notifyAll,
    required String emergencyLevel,
    String? reporterName,
  }) async {
    final reporterId = FirebaseAuth.instance.currentUser?.uid;
    final bool isEmergency = notifyAll;
    final color = emergencyLevel.toLowerCase() == 'danger'
        ? 'red'
        : emergencyLevel.toLowerCase() == 'moderate'
            ? 'amber'
            : 'green';
    final mapUrl = (lat != null && lng != null)
        ? 'https://www.google.com/maps?q=$lat,$lng'
        : null;

    final notifications = FirebaseFirestore.instance.collection('notifications');
    final batch = FirebaseFirestore.instance.batch();

    Map<String, dynamic> basePayload(String? targetUserId, {String? targetRole}) => {
          'targetUserId': targetUserId,
          'targetRole': targetRole,
          'title': isEmergency ? 'Emergency Reported' : 'Location Shared',
          'message': isEmergency
              ? 'Level: $emergencyLevel. Location: $locationLabel'
              : 'Location: $locationLabel',
          'reporterName': reporterName ?? widget.reporterName,
          'timestamp': FieldValue.serverTimestamp(),
          'isRead': false,
          'icon': 'warning',
      'color': color,
      'notifyAll': isEmergency,
          'emergencyLevel': emergencyLevel,
          'type': isEmergency ? 'emergency_report' : 'location_shared',
          'category': isEmergency ? 'emergency_report' : 'location_shared',
          if (reporterId != null) 'reporterId': reporterId,
      'lat': lat,
      'lng': lng,
      'locationLabel': locationLabel,
      if (mapUrl != null) 'mapUrl': mapUrl,
    };

    if (isEmergency) {
      final usersSnap = await FirebaseFirestore.instance.collection('users').get();
      for (final doc in usersSnap.docs) {
        final userId = doc.id;
        batch.set(notifications.doc(), basePayload(userId));
      }
      batch.set(notifications.doc(), basePayload(null, targetRole: 'web-admin-pcg'));
      batch.set(notifications.doc(), basePayload(null, targetRole: 'web-admin-bfar'));
    } else {
      batch.set(notifications.doc(), basePayload(null, targetRole: 'web-admin-pcg'));
    }

    await batch.commit();
  }

  Future<void> _persistSharedLocation({
    double? lat,
    double? lng,
    required String locationLabel,
    required bool notifyAll,
    required String emergencyLevel,
    String? reporterName,
  }) async {
    final reporterId = FirebaseAuth.instance.currentUser?.uid;
    final mapUrl = (lat != null && lng != null) ? 'https://www.google.com/maps?q=$lat,$lng' : null;
    await FirebaseFirestore.instance.collection('shared_locations').add({
      'lat': lat,
      'lng': lng,
      'locationLabel': locationLabel,
      'emergencyLevel': emergencyLevel,
      'notifyAll': notifyAll,
      'scope': notifyAll ? 'all' : 'pcg-only',
      'reporterName': reporterName ?? widget.reporterName,
      if (reporterId != null) 'reporterId': reporterId,
      'sharedAt': FieldValue.serverTimestamp(),
      'source': 'admin',
      if (mapUrl != null) 'mapUrl': mapUrl,
    });
  }

  String _composeLabel({Position? pos, String? address}) {
    final coords = pos != null ? '${pos.latitude.toStringAsFixed(5)}, ${pos.longitude.toStringAsFixed(5)}' : '';
    final hasAddress = address != null && address.trim().isNotEmpty;
    if (hasAddress && coords.isNotEmpty) return '$address ($coords)';
    if (hasAddress) return address;
    if (coords.isNotEmpty) return coords;
    return 'Unknown location';
  }

  Future<bool> _ensureServiceAndPermission() async {
    setState(() => _status = 'Checking location permission...');
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      setState(() => _status = 'Location services are OFF. Opening settings...');
      await Geolocator.openLocationSettings();
      return false;
    }
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        setState(() => _status = 'Location permissions are denied.');
        return false;
      }
    }
    if (permission == LocationPermission.deniedForever ||
        permission == LocationPermission.unableToDetermine) {
      setState(() => _status = 'Location permissions are permanently denied. Opening settings...');
      await Geolocator.openAppSettings();
      return false;
    }
    return true;
  }

  Future<String> _resolveAddress(Position pos) async {
    try {
      final placemarks = await placemarkFromCoordinates(pos.latitude, pos.longitude);
      if (placemarks.isNotEmpty) {
        final place = placemarks.first;
        final city = place.locality?.isNotEmpty == true ? place.locality : place.subAdministrativeArea;
        final admin = place.administrativeArea;
        final country = place.country;
        final parts = [
          if (city != null && city.isNotEmpty) city,
          if (admin != null && admin.isNotEmpty) admin,
          if (country != null && country.isNotEmpty) country,
        ];
        if (parts.isNotEmpty) {
          return parts.join(', ');
        }
      }
    } catch (_) {
      // ignore and fall back
    }
    return '${pos.latitude.toStringAsFixed(5)}, ${pos.longitude.toStringAsFixed(5)}';
  }

  Future<bool> _sendLocationOnline(Map<String, dynamic> payload, {bool silent = false}) async {
    try {
      await Future.wait([
        _notifyAllUsers(
          lat: (payload['lat'] as num?)?.toDouble(),
          lng: (payload['lng'] as num?)?.toDouble(),
          locationLabel: payload['locationLabel']?.toString() ?? 'Unknown location',
          notifyAll: payload['notifyAll'] == true,
          emergencyLevel: payload['emergencyLevel']?.toString() ?? widget.emergencyLevel,
          reporterName: payload['reporterName']?.toString() ?? widget.reporterName,
        ),
        _persistSharedLocation(
          lat: (payload['lat'] as num?)?.toDouble(),
          lng: (payload['lng'] as num?)?.toDouble(),
          locationLabel: payload['locationLabel']?.toString() ?? 'Unknown location',
          notifyAll: payload['notifyAll'] == true,
          emergencyLevel: payload['emergencyLevel']?.toString() ?? widget.emergencyLevel,
          reporterName: payload['reporterName']?.toString() ?? widget.reporterName,
        ),
      ]);
      if (!silent && mounted) setState(() => _status = 'Location shared and notifications sent.');
      return true;
    } catch (e) {
      if (!silent && mounted) setState(() => _status = 'Failed to send notifications: $e');
      return false;
    }
  }

  Future<void> _determinePosition() async {
    final ok = await _ensureServiceAndPermission();
    if (!ok) return;
    Position? position;
    try {
      position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 20),
        ),
      ).timeout(const Duration(seconds: 25));
    } on TimeoutException {
      position = await Geolocator.getLastKnownPosition();
    } catch (e) {
      position = await Geolocator.getLastKnownPosition();
    }

    if (position == null) {
      setState(() => _status = 'Unable to fetch location. Please try again.');
      return;
    }

    final pos = position;
    setState(() {
      _currentPosition = pos;
      _status = 'Location fetched successfully.';
    });

    try {
      final label = await _resolveAddress(pos);
      setState(() {
        _addressController.text = _composeLabel(pos: pos, address: label);
      });
    } catch (_) {
      setState(() {
        _addressController.text = _composeLabel(pos: pos, address: null);
      });
    }

    setState(() => _sending = true);
    final locationLabel = _composeLabel(pos: pos, address: _addressController.text.trim());
    final payload = <String, dynamic>{
      'lat': pos.latitude,
      'lng': pos.longitude,
      'locationLabel': locationLabel,
      'emergencyLevel': widget.emergencyLevel,
      'notifyAll': widget.notifyAll,
      'reporterName': _reporterLabel ?? widget.reporterName,
      'queuedAt': DateTime.now().toIso8601String(),
    };

    if (!_isOnline) {
      await _queueLocation(payload);
      setState(() => _status = 'Offline: saved locally and will send when back online.');
      if (mounted) setState(() => _sending = false);
      _syncPendingQueue();
      return;
    }

    try {
      final ok = await _sendLocationOnline(payload);
      if (ok) {
        setState(() => _status = 'Location shared and notifications sent.');
      } else {
        await _queueLocation(payload);
        setState(() => _status = 'Network issue: saved locally and will retry when online.');
      }
    } catch (e) {
      await _queueLocation(payload);
      setState(() => _status = 'Failed to send, saved locally to retry: $e');
    } finally {
      if (mounted) setState(() => _sending = false);
      _syncPendingQueue();
    }
  }

  Widget _buildLocationCard() {
    final accent = _emergencyAccent();
    final bool hasLocation = _currentPosition != null || _addressController.text.trim().isNotEmpty;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: _surface.withValues(alpha: 0.96),
        border: Border.all(color: accent.withValues(alpha: 0.18)),
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.1),
            blurRadius: 26,
            offset: const Offset(0, 14),
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
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Icon(
                  Icons.location_on_rounded,
                  size: 30,
                  color: accent,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _stateTitle(),
                      style: const TextStyle(
                        color: _ink,
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      hasLocation
                          ? 'Your alert can be sent with the latest location details below.'
                          : 'Permission and GPS checks are still in progress until a valid fix is available.',
                      style: TextStyle(
                        color: _ink.withValues(alpha: 0.68),
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(22),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  hasLocation ? 'Live location' : 'Location status',
                  style: TextStyle(
                    color: accent,
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _stateDescription(),
                  style: const TextStyle(
                    color: _ink,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 320),
            child: SizedBox(
              width: double.infinity,
              height: 54,
              child: FilledButton(
                onPressed: _sending ? null : _determinePosition,
                style: FilledButton.styleFrom(
                  backgroundColor: _ink,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),
                child: _sending
                    ? Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const [
                          SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          ),
                          SizedBox(width: 12),
                          Text(
                            'Sending...',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      )
                    : Text(
                        hasLocation ? 'Refresh and Send Again' : 'Send Location',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            widget.notifyAll
                ? 'This alert will be broadcast to all target users and admins.'
                : 'This location update will be shared with PCG admins only.',
            style: TextStyle(
              color: _ink.withValues(alpha: 0.62),
              fontWeight: FontWeight.w600,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderCard() {
    final accent = _emergencyAccent();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            _ink,
            accent,
          ],
        ),
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.18),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(
                  _emergencyIcon(),
                  color: Colors.white,
                  size: 28,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  widget.emergencyLevel.toUpperCase(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Text(
            'Live emergency routing',
            style: TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Capture your current position, attach the emergency level, and push the alert to the correct recipients.',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.8),
              fontWeight: FontWeight.w600,
              fontSize: 14,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusCard() {
    if (_status.trim().isEmpty) {
      return const SizedBox.shrink();
    }

    final color = _statusColor();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(Icons.info_outline_rounded, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Status',
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _status,
                  style: const TextStyle(
                    color: _ink,
                    fontWeight: FontWeight.w700,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final padding = Responsive.pagePadding(context);
    final maxWidth = Responsive.maxContentWidth(context);
    return Scaffold(
      backgroundColor: _mist,
      appBar: AppBar(
        title: const Text(
          'Share Location',
          style: TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: 22,
            color: _ink,
            letterSpacing: -0.3,
          ),
        ),
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
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(padding, 12, padding, padding),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHeaderCard(),
                    const SizedBox(height: 16),
                    _buildLocationCard(),
                    const SizedBox(height: 14),
                    _buildStatusCard(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
