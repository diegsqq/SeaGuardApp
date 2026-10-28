import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:intl/intl.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path/path.dart' as path;
import 'package:video_player/video_player.dart';
import '../profile/recent_reports_page.dart';
import '../../utils/loading_delay.dart';
import '../../utils/responsive.dart';

enum _EvidenceType { image, video }

class _PickedMedia {
  _PickedMedia({
    required this.bytes,
    required this.name,
    required this.mime,
    required this.type,
    this.localPath,
  });

  final Uint8List bytes;
  final String name;
  final String mime;
  final _EvidenceType type;
  final String? localPath;

  bool get isImage => type == _EvidenceType.image;
  bool get isVideo => type == _EvidenceType.video;
}

class _UploadedMedia {
  _UploadedMedia({
    required this.url,
    required this.name,
    required this.mime,
    required this.type,
  });

  final String url;
  final String name;
  final String mime;
  final _EvidenceType type;

  Map<String, dynamic> toMap() => {
        'url': url,
        'name': name,
        'mime': mime,
        'type': type.name,
      };
}

class ReportActivitiesPage extends StatefulWidget {
  const ReportActivitiesPage({super.key});

  @override
  State<ReportActivitiesPage> createState() => _ReportActivitiesPageState();
}

class _ReportActivitiesPageState extends State<ReportActivitiesPage> {
  final TextEditingController locationController = TextEditingController();
  final TextEditingController dateController = TextEditingController();
  final TextEditingController descriptionController = TextEditingController();

  bool isLoadingLocation = false;
  bool isSubmitting = false;
  final List<_PickedMedia> _mediaFiles = [];
  String userFullName = "Loading...";
  Position? _reportPosition;
  bool _locationEditedByUser = false;
  bool _updatingLocationText = false;
  bool _isOnline = true;
  bool _isSyncingPending = false;
  StreamSubscription<dynamic>? _connectivitySub;
  List<Map<String, dynamic>> _pendingReports = [];
  static const String _pendingReportsKey = 'pending_illegal_reports';
  static const String _laravelBaseUrl = String.fromEnvironment('LARAVEL_WEBHOOK_BASE', defaultValue: '');
  static const String _laravelWebhookToken = String.fromEnvironment('LARAVEL_WEBHOOK_TOKEN', defaultValue: '');

  final List<String> activityTitles = [
    "Illegal Fishing",
    "Unauthorized Marine Construction",
    "Oil Spillage",
    "Illegal Dumping",
    "Dynamite Fishing",
    "Coral Destruction",
    "Marine Wildlife Poaching",
  ];
  static const int _maxPhotoEvidence = 3;
  static const int _maxVideoEvidence = 1;
  static const int _maxVideoBytes = 25 * 1024 * 1024;

  // Provisional priority definitions. Confirm final mapping with PSG/client.
  static const Map<String, String> _priorityByActivity = {
    "Illegal Fishing": "Medium",
    "Unauthorized Marine Construction": "Medium",
    "Oil Spillage": "High",
    "Illegal Dumping": "Medium",
    "Dynamite Fishing": "High",
    "Coral Destruction": "High",
    "Marine Wildlife Poaching": "High",
  };

  String? selectedTitle;
  String? selectedPriority;

  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    fetchUserFullName();
    descriptionController.addListener(_handleFormStateChanged);
    locationController.addListener(_handleLocationChanged);
    Future.delayed(const Duration(milliseconds: 300), () async {
      try {
        await fetchLocation();
      } catch (e) {
        log("Initial location fetch failed: $e");
        if (mounted) {
          setState(() => isLoadingLocation = false);
        }
      }
    });

    dateController.text = _formatIncidentDateTime(_manilaNow());
    _initConnectivityAndQueue();
  }

  @override
  void dispose() {
    _connectivitySub?.cancel();
    descriptionController.removeListener(_handleFormStateChanged);
    locationController.removeListener(_handleLocationChanged);
    locationController.dispose();
    dateController.dispose();
    descriptionController.dispose();
    super.dispose();
  }

  Future<void> fetchUserFullName() async {
    log("DEBUG: Starting fetchUserFullName");
    try {
      final user = FirebaseAuth.instance.currentUser;
      log("DEBUG: Current user: ${user?.uid}");
      if (user != null) {
        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();
        log("DEBUG: User doc exists: ${userDoc.exists}");

        if (userDoc.exists && userDoc.data() != null) {
          final data = userDoc.data()!;
          log("DEBUG: User data: $data");
          userFullName = data['fullName'] ??
              data['name'] ??
              "${data['firstName'] ?? ''} ${data['lastName'] ?? ''}".trim();
        } else {
          userFullName =
              user.displayName ?? user.email?.split('@').first ?? "Unnamed User";
        }
      } else {
        userFullName = "Unnamed User";
      }
      log("DEBUG: Final userFullName: $userFullName");
    } catch (e) {
      log(" Error fetching name: $e");
      userFullName = "Unnamed User";
    }
    setState(() {});
  }

  Future<void> fetchLocation({bool force = false}) async {
    log("DEBUG: Starting fetchLocation");
    setState(() => isLoadingLocation = true);
    if (force) {
      _locationEditedByUser = false;
    }
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      log("DEBUG: Location service enabled: $serviceEnabled");
      if (!serviceEnabled) {
        _reportPosition = null;
        _setLocationTextIfAllowed(
          "Location services are OFF. Opening settings...",
          force: force,
        );
        await Geolocator.openLocationSettings();
        setState(() => isLoadingLocation = false);
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      log("DEBUG: Initial permission: $permission");
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        log("DEBUG: Permission after request: $permission");
        if (permission == LocationPermission.denied) {
          _reportPosition = null;
          _setLocationTextIfAllowed("Permission denied.", force: force);
          setState(() => isLoadingLocation = false);
          return;
        }
      }

      if (permission == LocationPermission.deniedForever ||
          permission == LocationPermission.unableToDetermine) {
        _reportPosition = null;
        _setLocationTextIfAllowed("Permission permanently denied.", force: force);
        await Geolocator.openAppSettings();
        setState(() => isLoadingLocation = false);
        return;
      }

      log("DEBUG: Getting current position");
      Position? position;
      try {
        position = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: Duration(seconds: 20),
          ),
        ).timeout(const Duration(seconds: 25));
      } on TimeoutException {
        log("DEBUG: Position timeout, trying last known");
        position = await Geolocator.getLastKnownPosition();
      } catch (e) {
        log("DEBUG: Position error, trying last known: $e");
        position = await Geolocator.getLastKnownPosition();
      }

      if (position == null) {
        _reportPosition = null;
        _setLocationTextIfAllowed("Unable to get location. Please retry.", force: force);
        setState(() => isLoadingLocation = false);
        return;
      }

      log("DEBUG: Position: ${position.latitude}, ${position.longitude}");
      _reportPosition = position;
      final coordsText =
          "Latitude: ${position.latitude.toStringAsFixed(5)}, Longitude: ${position.longitude.toStringAsFixed(5)}";

      try {
        final placemarks = await placemarkFromCoordinates(
            position.latitude, position.longitude);
        log("DEBUG: Placemarks count: ${placemarks.length}");
        if (placemarks.isNotEmpty) {
          final p = placemarks.first;
          final address = [
            p.street,
            p.locality,
            p.administrativeArea,
            p.country
          ].where((v) => v != null && v.isNotEmpty).join(', ');

          _setLocationTextIfAllowed(address.isNotEmpty ? "$address\n$coordsText" : coordsText, force: force);
          log("DEBUG: Location text set: ${locationController.text}");
        } else {
          _setLocationTextIfAllowed(coordsText, force: force);
        }
      } catch (e) {
        log("DEBUG: Reverse geocode failed: $e");
        _setLocationTextIfAllowed(coordsText, force: force);
      }
    } catch (e) {
      _reportPosition = null;
      _setLocationTextIfAllowed("Location fetch", force: force);
      log("Location Error: $e");
    } finally {
      setState(() => isLoadingLocation = false);
    }
  }

  void _setLocationTextIfAllowed(String text, {required bool force}) {
    final current = locationController.text.trim();
    final shouldOverride = force ||
        !_locationEditedByUser ||
        current.isEmpty ||
        current.startsWith('Permission') ||
        current.startsWith('Location services') ||
        current.startsWith('Unable to get location') ||
        current == 'Location fetch';

    if (!shouldOverride) return;

    _updatingLocationText = true;
    locationController.text = text;
    _updatingLocationText = false;
    _locationEditedByUser = false;
  }

  String _priorityForActivity(String activity) {
    return _priorityByActivity[activity] ?? "Low";
  }

  String _priorityDefinition(String? priority) {
    switch (priority) {
      case "High":
        return "High: active destructive activity, hazardous spill, wildlife poaching, or immediate habitat damage.";
      case "Medium":
        return "Medium: visible violation or pollution concern that needs field review.";
      case "Low":
        return "Low: non-urgent concern with limited immediate risk.";
      default:
        return "Priority is set automatically after selecting the activity type.";
    }
  }

  int get _photoCount => _mediaFiles.where((media) => media.isImage).length;
  int get _videoCount => _mediaFiles.where((media) => media.isVideo).length;

  void _removeMediaAt(int index) {
    if (index < 0 || index >= _mediaFiles.length) return;
    setState(() => _mediaFiles.removeAt(index));
  }

  void _handleLocationChanged() {
    if (_updatingLocationText) return;
    _locationEditedByUser = true;
    _reportPosition = null;
  }

  void _handleFormStateChanged() {
    if (!mounted) return;
    setState(() {});
  }

  DateTime _manilaNow() {
    return DateTime.now().toUtc().add(const Duration(hours: 8));
  }

  String _formatIncidentDateTime(DateTime value) {
    return DateFormat('yyyy-MM-dd HH:mm').format(value);
  }

  DateTime? _parseIncidentDateTime(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;
    try {
      return DateFormat('yyyy-MM-dd HH:mm').parseStrict(trimmed);
    } catch (_) {
      return DateTime.tryParse(trimmed);
    }
  }

  Future<void> _selectIncidentDateTime() async {
    final current = _parseIncidentDateTime(dateController.text) ?? _manilaNow();
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(current.year - 2),
      lastDate: _manilaNow(),
    );
    if (pickedDate == null || !mounted) return;

    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(current),
    );
    if (pickedTime == null || !mounted) return;

    final selected = DateTime(
      pickedDate.year,
      pickedDate.month,
      pickedDate.day,
      pickedTime.hour,
      pickedTime.minute,
    );
    setState(() {
      dateController.text = _formatIncidentDateTime(selected);
    });
  }

  List<String> _missingRequiredFields() {
    final missing = <String>[];
    if (selectedTitle == null) missing.add("Activity type");
    if (_mediaFiles.isEmpty) missing.add("Evidence");
    if (dateController.text.trim().isEmpty) missing.add("Incident date and time");
    return missing;
  }

  void _showMissingFieldsMessage(List<String> missingFields) {
    final message = missingFields.length == 1 && missingFields.first == "Evidence"
        ? "Please upload at least one photo or video as evidence."
        : "Please fill: ${missingFields.join(', ')}";

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<bool> _confirmSubmitReport() async {
    const ink = Color(0xFF102A43);
    const brand = Color(0xFF0E3764);
    const warning = Color(0xFFB42318);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 22),
        backgroundColor: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.18),
                blurRadius: 28,
                offset: const Offset(0, 16),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE6F0FA),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(
                      Icons.send_rounded,
                      color: brand,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      "Submit report?",
                      style: TextStyle(
                        color: ink,
                        fontSize: 21,
                        fontWeight: FontWeight.w900,
                        height: 1.1,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              const Text(
                "Please confirm that the report details and evidence are accurate before submitting.",
                style: TextStyle(
                  color: Color(0xFF52606D),
                  fontSize: 13.5,
                  height: 1.4,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF1F0),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFFFC9C4)),
                ),
                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.gpp_maybe_outlined,
                      color: warning,
                      size: 20,
                    ),
                    SizedBox(width: 9),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "Fake reports are violations",
                            style: TextStyle(
                              color: warning,
                              fontSize: 13.2,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          SizedBox(height: 3),
                          Text(
                            "If PCG marks this report as fake or invalid, a violation may be added to your account.",
                            style: TextStyle(
                              color: Color(0xFF7A271A),
                              fontSize: 12.4,
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
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(dialogContext, false),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: ink,
                        side: const BorderSide(color: Color(0xFFD8E4F0)),
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        textStyle: const TextStyle(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      child: const Text("Cancel"),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.pop(dialogContext, true),
                      style: FilledButton.styleFrom(
                        backgroundColor: brand,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        textStyle: const TextStyle(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      child: const Text("Submit"),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    return confirmed == true;
  }

  bool _validateEvidenceLimits({bool showMessage = true}) {
    final photos = _photoCount;
    final videos = _videoCount;
    String? message;

    if (photos > _maxPhotoEvidence) {
      message = "You can upload up to $_maxPhotoEvidence photos.";
    } else if (videos > _maxVideoEvidence) {
      message = "You can upload only $_maxVideoEvidence video.";
    }

    if (message != null && showMessage && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    }
    return message == null;
  }

  Future<List<_UploadedMedia>> _uploadMedia(String uid, List<_PickedMedia> mediaFiles) async {
    final uploaded = <_UploadedMedia>[];
    for (final media in mediaFiles) {
      final fileName = "${DateTime.now().millisecondsSinceEpoch}_${path.basename(media.name)}";
      final ref = FirebaseStorage.instance.ref().child("reports/$uid/$fileName");

      FirebaseException? lastError;
      for (var attempt = 1; attempt <= 2; attempt++) {
        try {
          final uploadTask = await ref.putData(
            media.bytes,
            SettableMetadata(contentType: media.mime),
          );
          final url = await uploadTask.ref.getDownloadURL();
          uploaded.add(_UploadedMedia(
            url: url,
            name: media.name,
            mime: media.mime,
            type: media.type,
          ));
          lastError = null;
          break;
        } on FirebaseException catch (e) {
          lastError = e;
          log("DEBUG: Upload attempt $attempt failed: ${e.code} ${e.message}");
          if (attempt < 2) {
            await Future.delayed(const Duration(milliseconds: 300));
          }
        }
      }

      if (lastError != null) {
        log("DEBUG: Upload failed, storing inline data URL: ${lastError.code}");
        final dataUrl = "data:${media.mime};base64,${base64Encode(media.bytes)}";
        uploaded.add(_UploadedMedia(
          url: dataUrl,
          name: media.name,
          mime: media.mime,
          type: media.type,
        ));
      }
    }
    return uploaded;
  }

  Future<void> _initConnectivityAndQueue() async {
    await _loadPendingReports();
    await _refreshConnectivity();
    if (_isOnline) {
      _syncPendingReports();
    }
    _connectivitySub = Connectivity().onConnectivityChanged.listen((result) {
      final online = _isConnected(result);
      if (mounted) {
        setState(() => _isOnline = online);
      } else {
        _isOnline = online;
      }
      if (online) {
        _syncPendingReports();
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
    if (status is ConnectivityResult) {
      return status != ConnectivityResult.none;
    }
    if (status is List<ConnectivityResult>) {
      return status.any((r) => r != ConnectivityResult.none);
    }
    return false;
  }

  Future<void> _loadPendingReports() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getStringList(_pendingReportsKey) ?? [];
    final pending = <Map<String, dynamic>>[];
    for (final item in stored) {
      try {
        final decoded = jsonDecode(item);
        if (decoded is Map<String, dynamic>) {
          pending.add(decoded);
        }
      } catch (_) {}
    }
    if (mounted) {
      setState(() => _pendingReports = pending);
    } else {
      _pendingReports = pending;
    }
  }

  Future<void> _persistPendingReports() async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = _pendingReports.map((e) => jsonEncode(e)).toList();
    await prefs.setStringList(_pendingReportsKey, encoded);
  }

  Future<void> _queuePendingReport({
    required Map<String, dynamic> basePayload,
    required List<_PickedMedia> mediaFiles,
  }) async {
    final entry = {
      'payload': basePayload,
      'media': mediaFiles
          .map((media) => {
                'bytes': base64Encode(media.bytes),
                'name': media.name,
                'mime': media.mime,
                'type': media.type.name,
                if (media.localPath != null) 'localPath': media.localPath,
              })
          .toList(),
      'queuedAt': DateTime.now().toIso8601String(),
    };

    _pendingReports.insert(0, entry);
    await _persistPendingReports();
    if (mounted) setState(() {});
  }

  Future<void> _syncPendingReports() async {
    if (_isSyncingPending || !_isOnline || _pendingReports.isEmpty) return;
    _isSyncingPending = true;
    try {
      for (int i = _pendingReports.length - 1; i >= 0; i--) {
        final item = _pendingReports[i];
        final payload = Map<String, dynamic>.from(item['payload'] ?? {});
        if (payload.isEmpty) continue;

        final mediaData = (item['media'] as List?) ?? (item['images'] as List?) ?? [];
        final decodedMedia = <_PickedMedia>[];
        for (final img in mediaData) {
          if (img is Map<String, dynamic>) {
            final bytes = img['bytes'];
            if (bytes is String) {
              try {
                final typeName = (img['type'] ?? 'image').toString();
                decodedMedia.add(
                  _PickedMedia(
                    bytes: base64Decode(bytes),
                    name: (img['name'] ?? 'photo.jpg').toString(),
                    mime: (img['mime'] ?? 'image/jpeg').toString(),
                    type: typeName == 'video' ? _EvidenceType.video : _EvidenceType.image,
                    localPath: img['localPath']?.toString(),
                  ),
                );
              } catch (_) {}
            }
          }
        }

        final success = await _sendReportOnline(
          basePayload: payload,
          mediaFiles: decodedMedia,
        );
        if (success) {
          _pendingReports.removeAt(i);
          await _persistPendingReports();
          if (mounted) setState(() {});
        }
      }
    } finally {
      _isSyncingPending = false;
    }
  }

  Future<bool> _sendReportOnline({
    required Map<String, dynamic> basePayload,
    required List<_PickedMedia> mediaFiles,
  }) async {
    try {
      final uid = basePayload['uid']?.toString() ?? '';
      if (uid.isEmpty) return false;

      final current = FirebaseAuth.instance.currentUser;
      if (current == null || current.uid != uid) return false;

      final manilaIso = basePayload['manilaIso']?.toString();
      final manilaNow = manilaIso != null
          ? (DateTime.tryParse(manilaIso) ?? _manilaNow())
          : _manilaNow();
      final manilaString =
          basePayload['manilaTimeString']?.toString() ?? DateFormat('yyyy-MM-dd HH:mm').format(manilaNow);
      final incidentIso = basePayload['incidentAtIso']?.toString();
      final incidentAt = incidentIso != null
          ? (DateTime.tryParse(incidentIso) ?? _parseIncidentDateTime(basePayload['incidentDateTimeString']?.toString() ?? ''))
          : _parseIncidentDateTime(basePayload['incidentDateTimeString']?.toString() ?? '');
      final incidentString = basePayload['incidentDateTimeString']?.toString() ??
          (incidentAt != null ? _formatIncidentDateTime(incidentAt) : manilaString);

      final uploadedMedia = await _uploadMedia(uid, mediaFiles);
      final photoUrls = uploadedMedia
          .where((media) => media.type == _EvidenceType.image)
          .map((media) => media.url)
          .toList();
      final videoUrls = uploadedMedia
          .where((media) => media.type == _EvidenceType.video)
          .map((media) => media.url)
          .toList();
      final payload = <String, dynamic>{
        ...basePayload,
        'imageUrl': photoUrls.isNotEmpty ? photoUrls.first : null,
        'photoUrls': photoUrls,
        'videoUrl': videoUrls.isNotEmpty ? videoUrls.first : null,
        'videoUrls': videoUrls,
        'mediaUrls': uploadedMedia.map((media) => media.url).toList(),
        'evidenceFiles': uploadedMedia.map((media) => media.toMap()).toList(),
        'submittedAt': FieldValue.serverTimestamp(),
        'manilaSubmittedAt': Timestamp.fromDate(manilaNow),
        'manilaTimeString': manilaString,
        if (incidentAt != null) 'incidentAt': Timestamp.fromDate(incidentAt),
        'incidentDateTimeString': incidentString,
        'incidentDate': incidentString,
        'date': incidentString,
      };
      payload.remove('manilaIso');
      payload.remove('incidentAtIso');

      final reportRef = await FirebaseFirestore.instance.collection('reports').add(payload);
      await _sendNotifications(reportRef.id, basePayload);
      return true;
    } catch (e) {
      log("DEBUG: Sync failed: $e");
      return false;
    }
  }

  Future<void> _sendNotifications(String reportId, Map<String, dynamic> basePayload) async {
    try {
      final locationValue = (basePayload['location'] ?? 'Location not provided').toString();
      final titleValue = (basePayload['title'] ?? 'Illegal Activity').toString();
      final priorityValue = (basePayload['priority'] ?? 'Unspecified').toString();
      final incidentValue = (basePayload['incidentDateTimeString'] ?? basePayload['date'] ?? '').toString();

      final payload = {
        'type': 'illegal_report',
        'category': 'illegal',
        'title': 'Illegal Report Submitted',
        'message': 'Type: $titleValue\nPriority: $priorityValue\nIncident: $incidentValue\nLocation: $locationValue',
        'timestamp': FieldValue.serverTimestamp(),
        'isRead': false,
        'reportId': reportId,
        'uid': basePayload['uid'],
        'reporterName': basePayload['reporter'],
        'illegalType': titleValue,
        'location': locationValue,
        'priority': priorityValue,
        'incidentDateTimeString': incidentValue,
      };

      final lat = basePayload['latitude'];
      final lng = basePayload['longitude'];
      if (lat != null && lng != null) {
        payload['latitude'] = lat;
        payload['longitude'] = lng;
      }

      final notifications = FirebaseFirestore.instance.collection('notifications');
      await notifications.add({...payload, 'targetRole': 'pcg'});
      await notifications.add({...payload, 'targetRole': 'bfar'});
      await notifications.add({...payload, 'targetRole': 'pcg_mobile'});
      await _notifyLaravel(reportId, payload, targetRole: 'pcg');
      await _notifyLaravel(reportId, payload, targetRole: 'bfar');
      await _notifyLaravel(reportId, payload, targetRole: 'pcg_mobile');
    } catch (_) {}
  }

  Future<void> _notifyLaravel(
    String reportId,
    Map<String, dynamic> payload, {
    String? targetRole,
  }) async {
    if (_laravelBaseUrl.isEmpty || _laravelWebhookToken.isEmpty) return;
    try {
      final url = Uri.parse(
        _laravelBaseUrl.endsWith('/')
            ? '${_laravelBaseUrl}api/admin-notifications/report'
            : '$_laravelBaseUrl/api/admin-notifications/report',
      );
      final body = jsonEncode({
        'id': reportId,
        'title': payload['title'] ?? payload['illegalType'] ?? 'Illegal Report',
        'reporter': payload['reporterName'] ?? '',
        'priority': payload['priority'] ?? '',
        'location': payload['location'] ?? '',
        if (targetRole != null) 'targetRole': targetRole,
      });
      final res = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'X-SEAGUARD-TOKEN': _laravelWebhookToken,
        },
        body: body,
      );
      if (res.statusCode >= 400) {
        log('Laravel webhook failed: ${res.statusCode} ${res.body}');
      }
    } catch (e) {
      log('Laravel webhook error: $e');
    }
  }

  Widget _buildOfflineBanner() {
    final pendingCount = _pendingReports.length;
    final text = !_isOnline
        ? (pendingCount > 0
            ? "Offline. $pendingCount report(s) will send when you're back online."
            : "Offline. Reports will be queued and sent automatically when you're back online.")
        : "$pendingCount report(s) pending sync.";

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        border: Border.all(color: Colors.orange.shade200),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.cloud_off, color: Colors.orange.shade700),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: Colors.orange.shade800,
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _imageMimeForName(String name) {
    final ext = path.extension(name).toLowerCase().replaceAll('.', '');
    return ext == 'png'
        ? 'image/png'
        : ext == 'heic' || ext == 'heif'
            ? 'image/heic'
            : 'image/jpeg';
  }

  String _videoMimeForName(String name) {
    final ext = path.extension(name).toLowerCase().replaceAll('.', '');
    switch (ext) {
      case 'mov':
        return 'video/quicktime';
      case 'm4v':
        return 'video/x-m4v';
      case 'webm':
        return 'video/webm';
      default:
        return 'video/mp4';
    }
  }

  Future<void> _pickImages() async {
    if (_photoCount >= _maxPhotoEvidence) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("You can upload up to $_maxPhotoEvidence photos.")),
      );
      return;
    }
    final remaining = _maxPhotoEvidence - _photoCount;
    try {
      final pickedFiles = await _picker.pickMultiImage(
        maxWidth: 600,
        maxHeight: 600,
        imageQuality: 70,
      );
      if (pickedFiles.isNotEmpty) {
        final limited = pickedFiles.take(remaining);
        final incoming = <_PickedMedia>[];
        for (final f in limited) {
          try {
            final bytes = await f.readAsBytes();
            if (bytes.isEmpty) continue;
            incoming.add(_PickedMedia(
              bytes: bytes,
              name: f.name,
              mime: _imageMimeForName(f.name),
              type: _EvidenceType.image,
              localPath: f.path,
            ));
          } catch (e) {
            log("Image read error (${f.path}): $e");
          }
        }
        if (incoming.isNotEmpty) {
          setState(() => _mediaFiles.addAll(incoming));
          _validateEvidenceLimits();
        }
        if (pickedFiles.length > remaining && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Only the first $remaining photo(s) were added (max $_maxPhotoEvidence).")),
          );
        }
      }
    } catch (e) {
      log("Image pick error: $e");
    }
  }

  Future<void> _pickVideo() async {
    if (_videoCount >= _maxVideoEvidence) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("You can upload only $_maxVideoEvidence video.")),
      );
      return;
    }

    try {
      final picked = await _picker.pickVideo(
        source: ImageSource.gallery,
        maxDuration: const Duration(minutes: 2),
      );
      if (picked == null) return;

      final size = await picked.length();
      if (size > _maxVideoBytes) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Video must be 25 MB or smaller.")),
        );
        return;
      }

      final bytes = await picked.readAsBytes();
      if (bytes.isEmpty) return;
      setState(() {
        _mediaFiles.add(
          _PickedMedia(
            bytes: bytes,
            name: picked.name,
            mime: _videoMimeForName(picked.name),
            type: _EvidenceType.video,
            localPath: picked.path,
          ),
        );
      });
      _validateEvidenceLimits();
    } catch (e) {
      log("Video pick error: $e");
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Unable to add video: $e")),
      );
    }
  }

  Future<void> _showVideoPreview(_PickedMedia media) async {
    final localPath = media.localPath;
    if (localPath == null || localPath.isEmpty || !File(localPath).existsSync()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Video preview is not available for this file.")),
      );
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (_) => _VideoPreviewDialog(filePath: localPath, title: media.name),
    );
  }

  Future<void> _submitReport() async {
    log("DEBUG: Starting _submitReport");
    if (!mounted) return;

    final missingFields = _missingRequiredFields();
    if (missingFields.isNotEmpty) {
      log("DEBUG: Validation failed - missing fields");
      log(
        "DEBUG: selectedTitle: $selectedTitle, selectedPriority: $selectedPriority, "
        "location: '${locationController.text}', incidentAt: '${dateController.text}', "
        "description: '${descriptionController.text}', media: ${_mediaFiles.length}, "
        "isLoadingLocation: $isLoadingLocation, missing: $missingFields",
      );
      _showMissingFieldsMessage(missingFields);
      return;
    }

    if (!_validateEvidenceLimits()) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("You must be signed in to submit a report.")),
      );
      return;
    }

    setState(() => isSubmitting = true);
    final loadingDelay = Future<void>.delayed(appLoadingDelay);
    try {
      await _refreshConnectivity();
    } catch (_) {}

    final manilaNow = _manilaNow();
    final manilaString = DateFormat('yyyy-MM-dd HH:mm').format(manilaNow);
    final incidentAt = _parseIncidentDateTime(dateController.text);
    if (incidentAt == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please choose the incident date and time.")),
      );
      setState(() => isSubmitting = false);
      return;
    }
    final incidentString = _formatIncidentDateTime(incidentAt);
    final locationValue = locationController.text.trim().isEmpty
        ? "Location not provided"
        : locationController.text.trim();
    final pos = _reportPosition;

    final basePayload = <String, dynamic>{
      'uid': user.uid,
      'reporter': userFullName,
      'title': selectedTitle!,
      'priority': selectedPriority ?? _priorityForActivity(selectedTitle!),
      'prioritySource': 'auto',
      'location': locationValue,
      'date': incidentString,
      'incidentAtIso': incidentAt.toIso8601String(),
      'incidentDateTimeString': incidentString,
      'incidentDate': incidentString,
      'description': descriptionController.text.trim(),
      'manilaIso': manilaNow.toIso8601String(),
      'manilaTimeString': manilaString,
    };

    if (pos != null) {
      basePayload['latitude'] = pos.latitude;
      basePayload['longitude'] = pos.longitude;
    }

    final currentMedia = List<_PickedMedia>.from(_mediaFiles);

    if (!_isOnline) {
      if (currentMedia.any((media) => media.isVideo)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Video evidence needs internet. Please reconnect before submitting.")),
        );
        setState(() => isSubmitting = false);
        return;
      }

      await _queuePendingReport(basePayload: basePayload, mediaFiles: currentMedia);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("No internet: report saved offline and will sync when you're back online."),
        ),
      );
      await loadingDelay;
      if (!mounted) return;
      setState(() {
        selectedTitle = null;
        selectedPriority = null;
        descriptionController.clear();
        _mediaFiles.clear();
        isSubmitting = false;
      });
      _syncPendingReports();
      return;
    }

    try {
      final success = await _sendReportOnline(basePayload: basePayload, mediaFiles: currentMedia);
      if (!success) {
        throw Exception("Report could not be submitted.");
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Report submitted successfully! BFAR will review your report and take appropriate action.")),
      );

      setState(() {
        selectedTitle = null;
        selectedPriority = null;
        descriptionController.clear();
        _mediaFiles.clear();
      });

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const RecentReportsPage()),
      );
    } catch (e) {
      log("DEBUG: Submit error: $e");
      if (!mounted) return;
      final message = e is FirebaseException &&
              (e.code == 'unavailable' || e.code == 'network-request-failed')
          ? "No internet: report saved offline and will sync when you're back online."
          : "Error submitting report: $e";

      var handledMessage = false;
      if (message.startsWith("No internet")) {
        if (currentMedia.any((media) => media.isVideo)) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Video evidence needs internet. Please reconnect before submitting.")),
          );
          handledMessage = true;
        } else {
          await _queuePendingReport(basePayload: basePayload, mediaFiles: currentMedia);
        }
      }

      if (!handledMessage) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      }
    } finally {
      await loadingDelay;
      if (mounted) setState(() => isSubmitting = false);
      _syncPendingReports();
    }
  }

  @override
  Widget build(BuildContext context) {
    const ink = Color(0xFF102A43);
    const brand = Color(0xFF0E3764);
    const fieldBorder = Color(0xFFD6DEE8);

    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: fieldBorder),
    );
    InputDecoration decorate(
      String hint, {
      IconData? icon,
      Widget? suffix,
      String? label,
      String? helper,
    }) {
      return InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(
          color: Color(0xFF76869A),
          fontSize: 15.2,
          fontWeight: FontWeight.w700,
        ),
        prefixIcon: icon != null
            ? Icon(icon, color: const Color(0xFF5D7085), size: 21)
            : null,
        prefixIconConstraints: const BoxConstraints(minWidth: 50),
        suffixIcon: suffix,
        helperText: helper,
        helperMaxLines: 3,
        helperStyle: const TextStyle(
          color: Color(0xFF5E738A),
          fontSize: 12.4,
          height: 1.3,
          fontWeight: FontWeight.w600,
        ),
        filled: true,
        fillColor: Colors.white,
        border: border,
        enabledBorder: border,
        focusedBorder: border.copyWith(
          borderSide: const BorderSide(color: brand, width: 1.4),
        ),
        errorBorder: border.copyWith(
          borderSide: const BorderSide(color: Color(0xFFDC4C2F), width: 1.2),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      );
    }

    Widget fieldHeader(String label, {String? meta}) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(2, 0, 2, 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  color: ink,
                  fontSize: 14.3,
                  fontWeight: FontWeight.w800,
                  height: 1.15,
                ),
              ),
            ),
            if (meta != null && meta.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFEAF3FA),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: const Color(0xFFD8E8F4)),
                ),
                child: Text(
                  meta,
                  style: const TextStyle(
                    color: Color(0xFF34536F),
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    height: 1,
                  ),
                ),
              ),
          ],
        ),
      );
    }

    Widget helperText(String text) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(2, 6, 2, 0),
        child: Text(
          text,
          style: const TextStyle(
            color: Color(0xFF5E738A),
            fontSize: 12.5,
            height: 1.3,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }

    Widget actionIcon(IconData icon, {required bool enabled}) {
      final color = enabled ? brand : Colors.grey.shade500;
      return Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: enabled ? brand.withValues(alpha: 0.08) : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: color, size: 20),
      );
    }

    Widget evidenceButton({
      required IconData icon,
      required String label,
      required String meta,
      required VoidCallback? onTap,
    }) {
      return Expanded(
        child: Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onTap,
            child: Container(
              constraints: const BoxConstraints(minHeight: 64),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: fieldBorder),
              ),
              child: Row(
                children: [
                  actionIcon(icon, enabled: onTap != null),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: onTap == null ? Colors.grey.shade500 : ink,
                            fontSize: 14.2,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          meta,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFF5E738A),
                            fontSize: 11.8,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    const fieldSpacing = SizedBox(height: 18);

    final padding = Responsive.pagePadding(context);
    final maxWidth = Responsive.maxContentWidth(context);

    return Scaffold(
      backgroundColor: const Color(0xFFF5F8FB),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF5F8FB),
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        foregroundColor: ink,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          "Report Illegal Activity",
          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 20),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: const Color(0xFFE0E6EE)),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: SingleChildScrollView(
              padding: EdgeInsets.symmetric(horizontal: padding, vertical: padding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(16, 15, 16, 15),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFD8E8F4)),
                      boxShadow: [
                        BoxShadow(
                          color: brand.withValues(alpha: 0.04),
                          blurRadius: 14,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: const Color(0xFFEAF3FA),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.fact_check_outlined,
                            color: brand,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "BFAR review",
                                style: TextStyle(
                                  color: brand,
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              SizedBox(height: 3),
                              Text(
                                "Your report will be checked and routed to the proper response team.",
                                style: TextStyle(
                                  fontSize: 12.9,
                                  height: 1.33,
                                  color: Color(0xFF42627D),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (!_isOnline || _pendingReports.isNotEmpty) ...[
                    SizedBox(
                      height: Responsive.verticalSpace(context) - 6 > 0
                          ? Responsive.verticalSpace(context) - 6
                          : 0,
                    ),
                    _buildOfflineBanner(),
                  ],
                  const SizedBox(height: 20),
                  fieldHeader("Activity type"),
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    value: selectedTitle,
                    hint: Text(
                      "Select illegal activity",
                      style: TextStyle(
                        color: Colors.grey.shade500,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    items: activityTitles
                        .map((activity) => DropdownMenuItem(
                              value: activity,
                              child: Text(activity),
                            ))
                        .toList(),
                    onChanged: (value) => setState(() {
                      selectedTitle = value;
                      selectedPriority = value == null ? null : _priorityForActivity(value);
                    }),
                    decoration: decorate(
                      "Select illegal activity",
                      icon: Icons.warning_amber_rounded,
                    ),
                  ),
                  fieldSpacing,
                  fieldHeader("Priority", meta: "Auto"),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: fieldBorder),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.flag_outlined, color: Color(0xFF6B7A8C)),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                selectedPriority ?? "Choose an activity first",
                                style: TextStyle(
                                  color: selectedPriority == null ? Colors.grey.shade500 : ink,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 5),
                              Text(
                                _priorityDefinition(selectedPriority),
                                style: const TextStyle(
                                  color: Color(0xFF5E738A),
                                  fontSize: 12.6,
                                  height: 1.3,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  fieldSpacing,
                  fieldHeader("Location", meta: "Required"),
                  TextField(
                    controller: locationController,
                    minLines: 3,
                    maxLines: 6,
                    textInputAction: TextInputAction.newline,
                    decoration: decorate(
                      "Incident location",
                      icon: Icons.location_on_outlined,
                      helper: "Keep the fetched location or type the exact place.",
                    ).copyWith(
                      suffixIcon: isLoadingLocation
                          ? const Padding(
                              padding: EdgeInsets.all(12),
                              child: SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                            )
                          : IconButton(
                              icon: const Icon(Icons.refresh),
                              onPressed: () => fetchLocation(force: true),
                              color: Colors.grey.shade600,
                            ),
                    ),
                  ),
                  fieldSpacing,
                  fieldHeader(
                    "Evidence",
                    meta:
                        "$_photoCount/$_maxPhotoEvidence photos | $_videoCount/$_maxVideoEvidence video",
                  ),
                  Row(
                    children: [
                      evidenceButton(
                        icon: Icons.add_photo_alternate_outlined,
                        label: "Photos",
                        meta: "Up to $_maxPhotoEvidence",
                        onTap: _photoCount >= _maxPhotoEvidence ? null : _pickImages,
                      ),
                      const SizedBox(width: 10),
                      evidenceButton(
                        icon: Icons.videocam_outlined,
                        label: "Video",
                        meta: "1 max, 25 MB",
                        onTap: _videoCount >= _maxVideoEvidence ? null : _pickVideo,
                      ),
                    ],
                  ),
                  helperText("Required. Add at least 1 photo or video."),
                  if (_mediaFiles.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    SizedBox(
                      height: 96,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: _mediaFiles.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 8),
                        itemBuilder: (context, index) {
                          final media = _mediaFiles[index];
                          return Stack(
                            children: [
                              GestureDetector(
                                onTap: media.isVideo ? () => _showVideoPreview(media) : null,
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: Container(
                                    height: 96,
                                    width: 96,
                                    color: const Color(0xFFE6ECF2),
                                    child: media.isImage
                                        ? Image.memory(
                                            media.bytes,
                                            height: 96,
                                            width: 96,
                                            fit: BoxFit.cover,
                                          )
                                        : const Center(
                                            child: Icon(
                                              Icons.play_circle_fill_rounded,
                                              color: brand,
                                              size: 42,
                                            ),
                                          ),
                                  ),
                                ),
                              ),
                              Positioned(
                                left: 6,
                                bottom: 6,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.62),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Text(
                                    media.isVideo ? "Video" : "Photo",
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              ),
                              Positioned(
                                top: 4,
                                right: 4,
                                child: GestureDetector(
                                  onTap: () => _removeMediaAt(index),
                                  child: Container(
                                    padding: const EdgeInsets.all(3),
                                    decoration: BoxDecoration(
                                      color: Colors.black54,
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: const Icon(Icons.close, size: 14, color: Colors.white),
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ],
                  fieldSpacing,
                  fieldHeader("Incident date & time"),
                  TextField(
                    controller: dateController,
                    readOnly: true,
                    onTap: _selectIncidentDateTime,
                    decoration: decorate(
                      dateController.text.isEmpty ? "Select date and time" : dateController.text,
                      icon: Icons.event_available_outlined,
                      suffix: IconButton(
                        icon: const Icon(Icons.edit_calendar_outlined),
                        onPressed: _selectIncidentDateTime,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ),
                  fieldSpacing,
                  fieldHeader("Notes", meta: "Optional"),
                  TextField(
                    controller: descriptionController,
                    maxLines: 4,
                    decoration: decorate(
                      "What happened? Add details if needed.",
                      icon: Icons.description,
                    ),
                  ),
                  const SizedBox(height: 22),
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      onPressed: isSubmitting
                          ? null
                          : () async {
                              final missingFields = _missingRequiredFields();
                              if (missingFields.isEmpty) {
                                final confirmed = await _confirmSubmitReport();
                                if (!confirmed || !mounted) return;
                                _submitReport();
                              } else {
                                _showMissingFieldsMessage(missingFields);
                              }
                            },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: ink,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                        elevation: 0,
                      ),
                      child: isSubmitting
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.send_rounded, size: 18),
                                SizedBox(width: 9),
                                Text(
                                  "Submit Report",
                                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                                ),
                              ],
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

}

class _VideoPreviewDialog extends StatefulWidget {
  const _VideoPreviewDialog({
    required this.filePath,
    required this.title,
  });

  final String filePath;
  final String title;

  @override
  State<_VideoPreviewDialog> createState() => _VideoPreviewDialogState();
}

class _VideoPreviewDialogState extends State<_VideoPreviewDialog> {
  late final VideoPlayerController _controller;
  bool _isReady = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.file(File(widget.filePath));
    _controller.initialize().then((_) {
      if (!mounted) return;
      setState(() => _isReady = true);
      _controller.play();
    }).catchError((error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const ink = Color(0xFF102A43);
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.videocam_outlined, color: ink),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: ink,
                      fontSize: 15.5,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Container(
                color: Colors.black,
                constraints: const BoxConstraints(minHeight: 190),
                alignment: Alignment.center,
                child: _error != null
                    ? Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          "Unable to play video: $_error",
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white),
                        ),
                      )
                    : !_isReady
                        ? const SizedBox(
                            height: 28,
                            width: 28,
                            child: CircularProgressIndicator(strokeWidth: 2.4),
                          )
                        : AspectRatio(
                            aspectRatio: _controller.value.aspectRatio,
                            child: VideoPlayer(_controller),
                          ),
              ),
            ),
            const SizedBox(height: 12),
            if (_isReady)
              Row(
                children: [
                  IconButton.filled(
                    onPressed: () {
                      setState(() {
                        _controller.value.isPlaying
                            ? _controller.pause()
                            : _controller.play();
                      });
                    },
                    icon: Icon(
                      _controller.value.isPlaying
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: VideoProgressIndicator(
                      _controller,
                      allowScrubbing: true,
                      colors: const VideoProgressColors(
                        playedColor: Color(0xFF0E3764),
                        bufferedColor: Color(0xFF9DB3C8),
                        backgroundColor: Color(0xFFD9E2EC),
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
}
