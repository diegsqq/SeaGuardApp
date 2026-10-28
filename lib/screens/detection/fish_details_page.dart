import 'dart:io';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../dashboard/logsighting_page.dart';
import '../../utils/functions_config.dart';
import '../../utils/responsive.dart';

class FishDetailsPage extends StatefulWidget {
  const FishDetailsPage({
    super.key,
    required this.fishName,
    this.displayName,
    this.predictionScore,

    /// Mobile (Android/iOS)
    this.capturedImage,

    /// Web / cross-platform
    this.capturedBytes,

    /// If you already uploaded elsewhere OR passed from DetectionScreen upload
    this.capturedImageUrl,

    /// If you already created a detection document before navigating here
    this.detectionId,
    this.skipUpload = false,
  });

  final String fishName;
  final String? displayName;
  final double? predictionScore;

  final File? capturedImage;
  final Uint8List? capturedBytes;

  final String? capturedImageUrl;
  final String? detectionId;
  final bool skipUpload;

  @override
  State<FishDetailsPage> createState() => _FishDetailsPageState();
}

class _FishDetailsPageState extends State<FishDetailsPage> {
  static Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>? _allSpecies;
  late final Future<Map<String, dynamic>?> _speciesFuture;
  final Map<String, Future<String?>> _storageUrlCache = {};
  final Map<String, Future<String?>> _downloadUrlCache = {};

  static const Map<String, String> _photoOverrides = {
    // Fallbacks when the species doc has no usable photo url
    'apolemichthys-trimaculatus':
        'https://www.fishbase.se/images/thumbnails/jpg/tn_Aptri_uc.jpg',
  };

  bool _asking = false;
  bool _savingImage = false;
  bool _autoBriefLoading = false;
  String _autoBriefContext = '';
  String _autoBriefText = '';
  String _autoBriefSource = '';
  String? _expandedChipKey;

  /// Saved/loaded from Firestore detections
  String _finalDetectionId = '';
  String _detectionImageUrl = '';

  bool get _isUnknownSpecies {
    final normalized = widget.fishName
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .trim();
    return normalized.isEmpty ||
        normalized == 'unknown' ||
        normalized.startsWith('unknown ') ||
        normalized.contains('unidentified');
  }

  String get _sightingSpeciesName {
    final name = widget.fishName.trim();
    return name.isEmpty ? 'Unknown sea creature' : name;
  }

  @override
  void initState() {
    super.initState();
    _speciesFuture = _fetchSpecies(widget.fishName)
        .timeout(const Duration(seconds: 8), onTimeout: () => null)
        .catchError((e) {
          debugPrint('Species lookup error: $e');
          return null;
        });
    _finalDetectionId = (widget.detectionId ?? '').trim();

    // If passed from previous screen, use it immediately
    final passedUrl = (widget.capturedImageUrl ?? '').trim();
    if (passedUrl.isNotEmpty) {
      _detectionImageUrl = _resolveImageUrl(passedUrl);
    }

    // If we already have a detectionId, load imageUrl from Firestore (more reliable)
    if (_finalDetectionId.isNotEmpty) {
      _loadDetectionImageUrl(_finalDetectionId);
    } else {
      // Otherwise, if user passed a capture but no id and no url, create a detection + upload now
      _maybeCreateDetectionAndUpload();
    }
  }

  // ------------------------------
  // ✅ FIREBASE CONNECT (UPLOAD + SAVE)
  // ------------------------------

  Future<Uint8List?> _readCapturedImageBytes() async {
    final capturedBytes = widget.capturedBytes;
    if (capturedBytes != null && capturedBytes.isNotEmpty) {
      return capturedBytes;
    }

    if (kIsWeb || widget.capturedImage == null) return null;

    try {
      final file = widget.capturedImage!;
      if (!await file.exists()) return null;
      final bytes = await file.readAsBytes();
      return bytes.isEmpty ? null : bytes;
    } catch (e) {
      debugPrint('Failed to read captured image bytes: $e');
      return null;
    }
  }

  String _inlineImageDataUrl(
    Uint8List bytes, {
    String mimeType = 'image/jpeg',
  }) => 'data:$mimeType;base64,${base64Encode(bytes)}';

  bool _isDataImageUrl(String value) =>
      value.trimLeft().toLowerCase().startsWith('data:image');

  Uint8List? _decodeDataImageUrl(String value) {
    if (!_isDataImageUrl(value)) return null;
    try {
      final parts = value.split(',');
      final encoded = parts.length > 1
          ? parts.sublist(1).join(',')
          : parts.first.replaceFirst(
              RegExp(r'^data:image/[^;]+;base64,', caseSensitive: false),
              '',
            );
      if (encoded.isEmpty) return null;
      return base64Decode(encoded);
    } catch (_) {
      return null;
    }
  }

  Future<void> _maybeCreateDetectionAndUpload() async {
    // If already have a URL, no need to upload
    if (_detectionImageUrl.trim().isNotEmpty) return;
    if (widget.skipUpload) return;

    // If no capture at all, nothing to upload
    final hasFile = widget.capturedImage != null;
    final hasBytes =
        widget.capturedBytes != null && widget.capturedBytes!.isNotEmpty;
    if (!hasFile && !hasBytes) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) return;

    setState(() => _savingImage = true);

    try {
      final capturedBytes = await _readCapturedImageBytes();
      if (capturedBytes == null || capturedBytes.isEmpty) return;
      final unknownSpecies = _isUnknownSpecies;

      // 1) create a Firestore detection doc (to get an id)
      final docRef = await FirebaseFirestore.instance
          .collection('detections')
          .add({
            'predictedFishName': widget.fishName,
            'displayName': widget.displayName,
            'confidence': widget.predictionScore,
            'createdAt': FieldValue.serverTimestamp(),
            'userId': user.uid,
            'imageUrl': null,
            'storagePath': null,
            'isUnknownSpecies': unknownSpecies,
            'researchUse': unknownSpecies,
            'researchStatus': unknownSpecies ? 'needs_review' : 'identified',
            'sourceModule': 'fish_detection',
          });

      _finalDetectionId = docRef.id;

      // 2) upload to Firebase Storage using bytes, which is more reliable
      final storagePath = 'detections/${user.uid}/$_finalDetectionId.jpg';
      final storageRef = FirebaseStorage.instance.ref().child(storagePath);

      FirebaseException? lastError;
      for (var attempt = 1; attempt <= 2; attempt++) {
        try {
          await storageRef.putData(
            capturedBytes,
            SettableMetadata(contentType: 'image/jpeg'),
          );
          lastError = null;
          break;
        } on FirebaseException catch (e) {
          lastError = e;
          debugPrint(
            'Detection upload attempt $attempt failed: ${e.code} ${e.message}',
          );
          if (attempt < 2) {
            await Future.delayed(const Duration(milliseconds: 300));
          }
        }
      }

      if (lastError != null) {
        final inlineUrl = _inlineImageDataUrl(capturedBytes);
        await docRef.update({
          'imageUrl': inlineUrl,
          'storagePath': storagePath,
          'uploadState': 'inline-fallback',
          'uploadErrorCode': lastError.code,
          if ((lastError.message ?? '').trim().isNotEmpty)
            'uploadErrorMessage': lastError.message,
        });

        if (!mounted) return;
        setState(() => _detectionImageUrl = inlineUrl);
        return;
      }

      String savedImageRef = storagePath;
      try {
        savedImageRef = await storageRef.getDownloadURL();
      } catch (e) {
        debugPrint('Detection upload saved but URL lookup failed: $e');
      }

      // 3) update Firestore detection doc with imageUrl/storagePath
      await docRef.update({
        'imageUrl': savedImageRef,
        'storagePath': storagePath,
        'uploadState': 'uploaded',
        'uploadErrorCode': FieldValue.delete(),
        'uploadErrorMessage': FieldValue.delete(),
      });

      if (!mounted) return;
      setState(
        () => _detectionImageUrl = _resolveImageUrl(
          savedImageRef,
          allowStoragePath: true,
        ),
      );
    } catch (e) {
      debugPrint('Upload/save failed: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to save this detection right now.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _savingImage = false);
    }
  }

  Future<void> _loadDetectionImageUrl(String detectionId) async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('detections')
          .doc(detectionId)
          .get();
      if (!snap.exists) return;
      final data = snap.data() ?? {};
      final url = (data['imageUrl'] ?? '').toString().trim();
      final storagePath = (data['storagePath'] ?? '').toString().trim();
      final userId = (data['userId'] ?? '').toString();

      final candidates = <String>[
        url,
        storagePath,
        if (userId.isNotEmpty) 'detections/$userId/$detectionId.jpg',
        if (userId.isNotEmpty) 'detections/$userId/$detectionId.jpeg',
        if (userId.isNotEmpty) 'detections/$userId/$detectionId.png',
      ].where((e) => e.trim().isNotEmpty).toList();

      for (final candidate in candidates) {
        final resolved = await _resolveDownloadUrl(candidate);
        if (resolved != null && resolved.isNotEmpty) {
          if (!mounted) return;
          setState(() => _detectionImageUrl = resolved);
          return;
        }
      }
    } catch (e) {
      debugPrint('Failed to load detection image url: $e');
    }
  }

  void _openSightingLogForDetection() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => LogSightingPage(
          initialSpecies: _sightingSpeciesName,
          initialImage: widget.capturedImage,
        ),
      ),
    );
  }

  Rect? _sharePositionOrigin() {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  Future<XFile?> _buildShareImage({
    List<String> imageCandidates = const [],
  }) async {
    final capturedFile = widget.capturedImage;
    if (!kIsWeb && capturedFile != null && await capturedFile.exists()) {
      return XFile(capturedFile.path, mimeType: 'image/jpeg');
    }

    final capturedBytes = widget.capturedBytes;
    if (capturedBytes != null && capturedBytes.isNotEmpty) {
      return XFile.fromData(
        capturedBytes,
        mimeType: 'image/jpeg',
        name: 'fish_capture.jpg',
      );
    }

    for (final raw in imageCandidates) {
      final payload = await _loadShareImagePayload(raw);
      if (payload == null) continue;

      return XFile.fromData(
        payload.bytes,
        mimeType: payload.mimeType,
        name: payload.fileName,
      );
    }

    return null;
  }

  Future<void> _shareFishDetails({
    required String englishName,
    required String shareText,
    List<String> imageCandidates = const [],
  }) async {
    final text = shareText.trim().isEmpty ? englishName.trim() : shareText.trim();
    final subject = englishName.trim().isEmpty
        ? 'Detection result'
        : 'Detection result: ${englishName.trim()}';

    try {
      final shareImage = await _buildShareImage(
        imageCandidates: imageCandidates,
      );
      final shareOrigin = _sharePositionOrigin();

      if (shareImage != null) {
        await Share.shareXFiles(
          [shareImage],
          text: text,
          subject: subject,
          sharePositionOrigin: shareOrigin,
        );
        return;
      }

      await Share.share(
        text,
        subject: subject,
        sharePositionOrigin: shareOrigin,
      );
    } catch (e) {
      debugPrint('Share failed: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to share right now. Please try again.'),
        ),
      );
    }
  }

  Future<_ShareImagePayload?> _loadShareImagePayload(String raw) async {
    final normalized = _resolveImageUrl(raw, allowStoragePath: true);
    if (normalized.isEmpty) return null;

    if (_isDataImageUrl(normalized)) {
      final bytes = _decodeDataImageUrl(normalized);
      if (bytes == null || bytes.isEmpty) return null;
      final mimeType = _mimeTypeFromImageSource(normalized);
      return _ShareImagePayload(
        bytes: bytes,
        mimeType: mimeType,
        fileName: 'fish_result.${_imageExtensionForMime(mimeType)}',
      );
    }

    final resolved = await _resolveDownloadUrl(normalized);
    final candidateUrl = (resolved ?? normalized).trim();
    final uri = Uri.tryParse(candidateUrl);
    final isHttp =
        uri != null && (uri.scheme == 'http' || uri.scheme == 'https');
    if (!isHttp) return null;

    try {
      final response = await http
          .get(uri)
          .timeout(const Duration(seconds: 12));
      if (response.statusCode != 200 || response.bodyBytes.isEmpty) {
        return null;
      }

      final headerMimeType = (response.headers['content-type'] ?? '')
          .split(';')
          .first
          .trim();
      final mimeType = headerMimeType.startsWith('image/')
          ? headerMimeType
          : _mimeTypeFromImageSource(candidateUrl);

      return _ShareImagePayload(
        bytes: response.bodyBytes,
        mimeType: mimeType,
        fileName: 'fish_result.${_imageExtensionForMime(mimeType)}',
      );
    } catch (e) {
      debugPrint('Share image download failed: $e');
      return null;
    }
  }

  String _mimeTypeFromImageSource(String raw) {
    final trimmed = raw.trim().toLowerCase();
    final dataMatch = RegExp(r'^data:(image/[^;,]+)', caseSensitive: false)
        .firstMatch(trimmed);
    final dataMimeType = dataMatch?.group(1)?.trim();
    if (dataMimeType != null && dataMimeType.isNotEmpty) {
      return dataMimeType;
    }

    if (trimmed.endsWith('.png')) return 'image/png';
    if (trimmed.endsWith('.webp')) return 'image/webp';
    if (trimmed.endsWith('.gif')) return 'image/gif';
    return 'image/jpeg';
  }

  String _imageExtensionForMime(String mimeType) {
    switch (mimeType.toLowerCase()) {
      case 'image/png':
        return 'png';
      case 'image/webp':
        return 'webp';
      case 'image/gif':
        return 'gif';
      default:
        return 'jpg';
    }
  }

  // ------------------------------
  // AI RESPONSES (HTTP -> OFFLINE FALLBACK)
  // ------------------------------

  Future<_AiAnswer> _askFishAssistant({
    required String question,
    required String context,
  }) async {
    final payload = _buildFishPayload(question: question, context: context);

    final httpReply = await _askFishAssistantHttp(payload);
    if (httpReply != null) return httpReply;

    return _AiAnswer(
      answer: _offlineFishFallback(question: question, context: context),
      source: 'local',
    );
  }

  Map<String, dynamic> _buildFishPayload({
    required String question,
    required String context,
  }) {
    final fishName = _contextField(context, 'Fish name');
    final scientificName = _contextField(context, 'Scientific name');
    final localName = _contextField(context, 'Local name');
    final family = _contextField(context, 'Family');
    final habitat = _contextField(context, 'Habitat');
    final diet = _contextField(context, 'Diet');
    final summary = _contextField(context, 'Summary');
    final confidence = _contextField(context, 'Prediction confidence');
    final capturedImage = _contextField(context, 'Captured image');

    final englishName = fishName.isNotEmpty
        ? fishName
        : (widget.displayName?.trim().isNotEmpty == true
              ? widget.displayName!.trim()
              : widget.fishName.trim());
    final imageUrl = capturedImage.isNotEmpty
        ? capturedImage
        : (_detectionImageUrl.isNotEmpty
              ? _detectionImageUrl
              : (widget.capturedImageUrl ?? '').trim());

    return <String, dynamic>{
      'question': question.trim(),
      'englishName': englishName,
      if (scientificName.isNotEmpty) 'scientificName': scientificName,
      if (localName.isNotEmpty) 'localName': localName,
      if (family.isNotEmpty) 'family': family,
      if (habitat.isNotEmpty) 'habitat': habitat,
      if (diet.isNotEmpty) 'diet': diet,
      if (summary.isNotEmpty) 'description': summary,
      if (imageUrl.isNotEmpty) 'imageUrl': imageUrl,
      if (localName.isNotEmpty || family.isNotEmpty || confidence.isNotEmpty)
        'shareText': [
          if (localName.isNotEmpty) 'Local name: $localName',
          if (family.isNotEmpty) 'Family: $family',
          if (confidence.isNotEmpty) 'Prediction confidence: $confidence',
        ].join('\n'),
      'history': const <Map<String, String>>[],
    };
  }

  String _contextField(String context, String label) {
    final regex = RegExp(
      '^${RegExp.escape(label)}:\\s*(.*)\$',
      multiLine: true,
      caseSensitive: false,
    );
    final match = regex.firstMatch(context);
    return (match?.group(1) ?? '').trim();
  }

  Future<_AiAnswer?> _askFishAssistantHttp(Map<String, dynamic> payload) async {
    // Support both flat function IDs and nested export paths.
    const endpoints = <String>[
      'ai/ask/fish',
      'ai-ask-fish',
      'aiAskFish',
      'ai/assistant',
      'ai-assistant',
      'aiAssistant',
    ];
    final errors = <String>[];

    for (final path in endpoints) {
      final uris = functionUriCandidates(path);
      for (final uri in uris) {
        try {
          final resp = await http
              .post(
                uri,
                headers: const {'Content-Type': 'application/json'},
                body: jsonEncode(payload),
              )
              .timeout(const Duration(seconds: 12));
          if (resp.statusCode != 200) {
            errors.add('$path@${uri.host}: HTTP ${resp.statusCode}');
            continue;
          }

          final decoded = jsonDecode(resp.body);
          if (decoded is! Map) {
            errors.add('$path@${uri.host}: invalid JSON payload');
            continue;
          }

          final body = Map<String, dynamic>.from(
            decoded.cast<String, dynamic>(),
          );
          final answer =
              (body['answer'] ??
                      (body['data'] is Map ? body['data']['answer'] : null))
                  .toString()
                  .trim();
          if (answer.isEmpty) continue;
          final source = (body['source'] ?? 'http').toString();
          return _AiAnswer(answer: answer, source: source);
        } catch (e) {
          errors.add('$path@${uri.host}: $e');
        }
      }
    }

    debugPrint('AI fish HTTP unavailable -> offline. ${errors.join(' | ')}');
    return null;
  }

  bool _containsAny(String text, List<String> keywords) {
    for (final keyword in keywords) {
      if (text.contains(keyword)) return true;
    }
    return false;
  }

  String _inferMarineGroup({
    required String fishName,
    required String scientificName,
    required String family,
    required String summary,
  }) {
    final combined = [
      fishName,
      scientificName,
      family,
      summary,
    ].where((value) => value.trim().isNotEmpty).join(' ').toLowerCase();

    const rayKeywords = <String>[
      'ray',
      'stingray',
      'manta',
      'mobula',
      'eagle ray',
      'sawfish',
      'rajidae',
      'dasyatidae',
      'mobulidae',
      'myliobatidae',
      'pristidae',
      'rhinopteridae',
      'torpedinidae',
      'narcinidae',
    ];
    if (_containsAny(combined, rayKeywords)) {
      return 'ray';
    }

    const sharkKeywords = <String>[
      'shark',
      'thresher',
      'hammerhead',
      'mako',
      'dogfish',
      'catshark',
      'wobbegong',
      'nurse shark',
      'whale shark',
      'angel shark',
      'bull shark',
      'tiger shark',
      'reef shark',
      'basking shark',
      'alopias',
      'isurus',
      'lamna',
      'carcharhin',
      'sphyrna',
      'rhincodon',
      'orectolobus',
      'squalus',
      'alopiidae',
      'carcharhinidae',
      'lamnidae',
      'sphyrnidae',
      'rhincodontidae',
      'squalidae',
      'scyliorhinidae',
      'orectolobidae',
      'hexanchidae',
      'ginglymostomatidae',
      'hemiscylliidae',
      'heterodontidae',
    ];
    if (_containsAny(combined, sharkKeywords)) {
      return 'shark';
    }

    return 'fish';
  }

  String? _offlineIdentityAnswer({
    required String questionLower,
    required String fishName,
    required String scientificName,
    required String family,
    required String summary,
    required bool wantEat,
    required bool wantHandle,
    required bool wantProtection,
    required bool wantBrief,
  }) {
    final asksIdentity = _containsAny(questionLower, const [
      'what is this',
      'what is it',
      'what fish is this',
      'what species is this',
      'what species is it',
      'fish or shark',
      'shark or fish',
      'is this a shark',
      'is it a shark',
      'is this shark',
      'is it shark',
      'is this a fish',
      'is it a fish',
      'is this fish',
      'is it fish',
    ]);
    if (!asksIdentity || wantEat || wantHandle || wantProtection || wantBrief) {
      return null;
    }

    final group = _inferMarineGroup(
      fishName: fishName,
      scientificName: scientificName,
      family: family,
      summary: summary,
    );
    final speciesLine = fishName.isNotEmpty
        ? scientificName.isNotEmpty
              ? 'This appears to be $fishName ($scientificName).'
              : 'This appears to be $fishName.'
        : 'I can only give a general ID from the saved details.';

    if (group == 'shark') {
      return '$speciesLine It is a shark. Sharks are fish, so "shark" is the more precise answer.';
    }
    if (group == 'ray') {
      return '$speciesLine It is a ray, not a shark. Rays are fish and are closely related to sharks.';
    }
    return '$speciesLine It is a fish, not a shark.';
  }

  String? _offlineProtectionAnswer({
    required String questionLower,
    required String fishName,
    required String scientificName,
    required String family,
    required String summary,
    required bool wantEat,
    required bool wantHandle,
    required bool wantBrief,
  }) {
    final wantProtection = _containsAny(questionLower, const [
      'endangered',
      'protected',
      'illegal',
      'conservation',
      'can i keep',
      'can we keep',
      'can i sell',
      'can we sell',
    ]);
    if (!wantProtection || wantEat || wantHandle || wantBrief) {
      return null;
    }

    final group = _inferMarineGroup(
      fishName: fishName,
      scientificName: scientificName,
      family: family,
      summary: summary,
    );
    final subject = fishName.isNotEmpty ? fishName : 'This catch';
    final riskNote = group == 'shark' || group == 'ray'
        ? 'Many sharks and rays have catch, landing, or size restrictions.'
        : 'Protection rules can still vary by species, size, season, and location.';
    return '$subject protection status cannot be confirmed offline. $riskNote Check BFAR, DENR, and your local fishery rules before keeping, landing, or selling it.';
  }


  String _offlineFishFallback({
    required String question,
    required String context,
  }) {
    final fishName = _contextField(context, 'Fish name').isNotEmpty
        ? _contextField(context, 'Fish name')
        : widget.fishName;
    final scientificName = _contextField(context, 'Scientific name');
    final family = _contextField(context, 'Family');
    final habitat = _contextField(context, 'Habitat');
    final diet = _contextField(context, 'Diet');
    final summary = _contextField(context, 'Summary');
    final lower = question.toLowerCase();
    final wantEat = lower.contains('eat') ||
        lower.contains('edible') ||
        lower.contains('safe to eat');
    final wantHandle = lower.contains('handle') ||
        lower.contains('prepare') ||
        lower.contains('cook') ||
        lower.contains('clean');
    final wantBrief = lower.contains('brief') ||
        lower.contains('summary') ||
        lower.contains('guide');

    final identityAnswer = _offlineIdentityAnswer(
      questionLower: lower,
      fishName: fishName,
      scientificName: scientificName,
      family: family,
      summary: summary,
      wantEat: wantEat,
      wantHandle: wantHandle,
      wantProtection: _containsAny(lower, const [
        'endangered',
        'protected',
        'illegal',
        'conservation',
        'can i keep',
        'can we keep',
        'can i sell',
        'can we sell',
      ]),
      wantBrief: wantBrief,
    );
    if (identityAnswer != null) {
      return identityAnswer;
    }

    final protectionAnswer = _offlineProtectionAnswer(
      questionLower: lower,
      fishName: fishName,
      scientificName: scientificName,
      family: family,
      summary: summary,
      wantEat: wantEat,
      wantHandle: wantHandle,
      wantBrief: wantBrief,
    );
    if (protectionAnswer != null) {
      return protectionAnswer;
    }

    final lines = <String>[];
    lines.add('Quick guide for $fishName:');
    if (summary.isNotEmpty) lines.add(summary);
    if (habitat.isNotEmpty) lines.add('Habitat: $habitat');
    if (diet.isNotEmpty) lines.add('Diet: $diet');
    lines.add(
      'Safety first: check local advisories before catching or eating.',
    );
    lines.add('Handle safely: chill catch quickly and cook thoroughly.');
    if (lower.contains('eat') || lower.contains('safe')) {
      lines.add(
        'If conditions are unclear, avoid eating until local guidance confirms safety.',
      );
    }
    lines.add('Share your location and fish size for a more exact answer.');
    return lines.join('\n');
  }

  String _buildFishContext({
    required String englishName,
    required String scientificName,
    required String localName,
    required String family,
    required String habitat,
    required String diet,
    required String summary,
  }) {
    final b = StringBuffer()..writeln('Fish name: $englishName');
    if (scientificName.isNotEmpty) {
      b.writeln('Scientific name: $scientificName');
    }
    if (localName.isNotEmpty) b.writeln('Local name: $localName');
    if (family.isNotEmpty) b.writeln('Family: $family');
    if (habitat.isNotEmpty) b.writeln('Habitat: $habitat');
    if (diet.isNotEmpty) b.writeln('Diet: $diet');
    if (summary.isNotEmpty) b.writeln('Summary: $summary');
    if (widget.predictionScore != null) {
      final score = (widget.predictionScore! * 100)
          .clamp(0, 100)
          .toStringAsFixed(1);
      b.writeln('Prediction confidence: $score%');
    }
    final imageUrl = _detectionImageUrl.isNotEmpty
        ? _detectionImageUrl
        : (widget.capturedImageUrl ?? '').trim();
    if (imageUrl.isNotEmpty) b.writeln('Captured image: $imageUrl');
    return b.toString().trim();
  }

  void _maybeGenerateAutoBrief(String contextText) {
    final normalized = contextText.trim();
    if (normalized.isEmpty) return;
    if (_autoBriefContext == normalized &&
        (_autoBriefLoading || _autoBriefText.isNotEmpty)) {
      return;
    }
    _autoBriefContext = normalized;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _generateAutoBrief(contextText: normalized, force: true);
    });
  }


  Future<void> _generateAutoBrief({
    required String contextText,
    bool force = false,
  }) async {
    if (_autoBriefLoading) return;
    if (!force &&
        _autoBriefText.isNotEmpty &&
        _autoBriefContext == contextText) {
      return;
    }

    setState(() {
      _autoBriefLoading = true;
      if (force) {
        _autoBriefText = '';
        _autoBriefSource = '';
      }
    });

    try {
      final reply = await _askFishAssistant(
        question:
            'Give a short fish brief with safety-to-eat guidance first, then handling and conservation notes.',
        context: contextText,
      );
      if (!mounted) return;
      setState(() {
        _autoBriefText = reply.answer.trim();
        _autoBriefSource = reply.source;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _autoBriefText = _offlineFishFallback(
          question: 'General fish brief',
          context: contextText,
        );
        _autoBriefSource = 'local';
      });
      debugPrint('Auto brief failed: $e');
    } finally {
      if (mounted) {
        setState(() => _autoBriefLoading = false);
      }
    }
  }

  Future<void> _showAskDialog({required String contextText}) async {
    final controller = TextEditingController();
    final focusNode = FocusNode();
    final quickPrompts = <String>[
      'Is this fish safe to eat?',
      'Is it endangered or protected?',
      'How should I handle it safely?',
    ];

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.6),
      builder: (sheetContext) {
        return DraggableScrollableSheet(
          initialChildSize: 0.995,
          maxChildSize: 0.995,
          minChildSize: 0.72,
          expand: false,
          builder: (ctx, scrollController) {
            return SafeArea(
              child: StatefulBuilder(
                builder: (innerContext, setSheetState) {
                  void submit() {
                    final q = controller.text.trim();
                    if (q.isEmpty) {
                      focusNode.requestFocus();
                      return;
                    }
                    Navigator.of(sheetContext).pop();
                    Future.microtask(() => _handleAsk(q, contextText));
                  }

                  return Container(
                    margin: const EdgeInsets.fromLTRB(12, 6, 12, 0),
                    padding: EdgeInsets.fromLTRB(
                      18,
                      12,
                      18,
                      18 + MediaQuery.of(sheetContext).viewInsets.bottom,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(24),
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFFF8FBFF), Color(0xFFECEFF5)],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.12),
                          blurRadius: 24,
                          offset: const Offset(0, 16),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Center(
                          child: Container(
                            width: 44,
                            height: 4,
                            decoration: BoxDecoration(
                              color: Colors.grey.shade400,
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Colors.blue.shade50,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.smart_toy_outlined,
                                color: Colors.blueAccent,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: const [
                                Text(
                                  'Ask AI Assistant',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                SizedBox(height: 2),
                                Text(
                                  'Guidance for this fish',
                                  style: TextStyle(
                                    color: Colors.black54,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                            const Spacer(),
                            IconButton(
                              onPressed: () => Navigator.of(sheetContext).pop(),
                              icon: const Icon(Icons.close),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Get quick guidance about this fish - safety, conservation, and handling tips.',
                          style: TextStyle(color: Colors.grey.shade700),
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: quickPrompts
                              .map(
                                (p) => ActionChip(
                                  label: Text(
                                    p,
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                  onPressed: () {
                                    controller.text = p;
                                    controller.selection =
                                        TextSelection.fromPosition(
                                          TextPosition(
                                            offset: controller.text.length,
                                          ),
                                        );
                                    focusNode.requestFocus();
                                  },
                                ),
                              )
                              .toList(),
                        ),
                        const SizedBox(height: 14),
                        ConstrainedBox(
                          constraints: const BoxConstraints(
                            minHeight: 64,
                            maxHeight: 140,
                          ),
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: Colors.grey.shade300),
                            ),
                            child: TextField(
                              controller: controller,
                              focusNode: focusNode,
                              maxLines: 4,
                              minLines: 1,
                              textInputAction: TextInputAction.send,
                              onSubmitted: (_) => submit(),
                              decoration: const InputDecoration(
                                hintText: 'Ask a question about this fish...',
                                border: InputBorder.none,
                                isCollapsed: true,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            TextButton(
                              onPressed: () => Navigator.of(sheetContext).pop(),
                              child: const Text('Cancel'),
                            ),
                            const Spacer(),
                            FilledButton.icon(
                              onPressed: _asking ? null : submit,
                              icon: const Icon(
                                Icons.smart_toy_outlined,
                                size: 18,
                              ),
                              label: Text(_asking ? 'Asking...' : 'Ask'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _handleAsk(String rawQuestion, String contextText) async {
    final q = rawQuestion.trim();
    if (q.isEmpty) return;

    setState(() => _asking = true);

    try {
      final reply = await _askFishAssistant(question: q, context: contextText);
      if (!mounted) return;
      await _showAnswerSheet(
        question: q,
        answer: reply.answer,
        contextText: contextText,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('AI error: $e')));
    } finally {
      if (mounted) setState(() => _asking = false);
    }
  }

  String _confidenceLabel(double? raw) {
    if (raw == null) return '';
    final normalized = raw > 1 ? raw / 100 : raw;
    final pct = (normalized.clamp(0, 1) * 100);
    final text = pct >= 99.5 ? pct.toStringAsFixed(0) : pct.toStringAsFixed(1);
    return '$text% match';
  }

  String _shortChipText(String value, {int maxChars = 34}) {
    final clean = value.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (clean.length <= maxChars) return clean;
    return '${clean.substring(0, maxChars - 1).trim()}...';
  }

  Widget _buildInfoChip({
    required String chipKey,
    required IconData icon,
    required String text,
    String? fullText,
    Color background = const Color(0xFFEAF2FF),
    Color foreground = const Color(0xFF1D4B88),
  }) {
    final chipMaxWidth = Responsive.value<double>(
      context,
      mobile: 300,
      tablet: 420,
      desktop: 520,
    );
    final cleanFull = (fullText ?? '').trim();
    final canExpand = cleanFull.isNotEmpty && cleanFull != text;
    final isExpanded = _expandedChipKey == chipKey;
    final display = isExpanded ? cleanFull : text;

    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: chipMaxWidth),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: canExpand
              ? () {
                  setState(() {
                    _expandedChipKey = isExpanded ? null : chipKey;
                  });
                }
              : null,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: foreground.withValues(alpha: 0.18)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 14, color: foreground),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    display,
                    maxLines: isExpanded ? 4 : 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: foreground,
                    ),
                  ),
                ),
                if (canExpand) ...[
                  const SizedBox(width: 4),
                  Icon(
                    isExpanded ? Icons.expand_less : Icons.expand_more,
                    size: 14,
                    color: foreground.withValues(alpha: 0.8),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle({
    required IconData icon,
    required String title,
    String? subtitle,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 30,
          height: 30,
          decoration: const BoxDecoration(
            color: Color(0xFFE9F2FF),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 16, color: Color(0xFF1D4B88)),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF173655),
                ),
              ),
              if (subtitle != null && subtitle.trim().isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle.trim(),
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF5E7185),
                    height: 1.25,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  // ------------------------------
  // UI
  // ------------------------------

  @override
  Widget build(BuildContext context) {
    final padding = Responsive.pagePadding(context);
    final maxWidth = Responsive.maxContentWidth(context, maxWidth: 920);
    final verticalGap = Responsive.verticalSpace(context);

    return Scaffold(
      backgroundColor: const Color(0xFFF3F7FC),
      appBar: AppBar(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: const Color(0xFFF3F7FC),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF0F2B46)),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'AI Detection',
          style: TextStyle(
            color: Color(0xFF0F2B46),
            fontWeight: FontWeight.w900,
            fontSize: 33,
            letterSpacing: 0.2,
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: const Color(0xFFD8E3F0)),
        ),
      ),
      body: SafeArea(
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFFF8FCFF), Color(0xFFF1F7FE), Color(0xFFE9F1FB)],
            ),
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth),
              child: FutureBuilder<Map<String, dynamic>?>(
                future: _speciesFuture,
                builder: (context, snapshot) {
                  final fallbackName =
                      widget.displayName?.trim().isNotEmpty == true
                      ? widget.displayName!.trim()
                      : widget.fishName;
                  final fallbackImage = _buildBestImage(
                    speciesImageUrl: null,
                    speciesStoragePaths: const [],
                    forceNetworkUrl: _detectionImageUrl.isNotEmpty
                        ? _detectionImageUrl
                        : widget.capturedImageUrl,
                    capturedBytes: widget.capturedBytes,
                    capturedFile: widget.capturedImage,
                    capturedImageUrl: _detectionImageUrl.isNotEmpty
                        ? _detectionImageUrl
                        : widget.capturedImageUrl,
                  );
                  if (snapshot.hasError) {
                    return _fallbackDetails(
                      context: context,
                      padding: padding,
                      maxWidth: maxWidth,
                      name: fallbackName,
                      notes: [
                        'Unable to load fish info right now. Showing your capture only.',
                        '${snapshot.error}',
                      ],
                      image: fallbackImage,
                    );
                  }

                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return _fallbackDetails(
                      context: context,
                      padding: padding,
                      maxWidth: maxWidth,
                      name: fallbackName,
                      notes: ['Loading fish info...'],
                      image: fallbackImage,
                      pulse: true,
                    );
                  }

                  final data = snapshot.data;

                  // FishBase (species database) photo
                  final speciesImageSource = _speciesImageSource(data);
                  final speciesImageUrl = speciesImageSource.directUrl;

                  final resultImageUrl = _detectionImageUrl.isNotEmpty
                      ? _detectionImageUrl
                      : widget.capturedImageUrl;
                  final fallbackHeroImage = _buildBestImage(
                    speciesImageUrl: speciesImageUrl,
                    speciesStoragePaths: speciesImageSource.storagePaths,
                    forceNetworkUrl: resultImageUrl,
                    capturedBytes: widget.capturedBytes,
                    capturedFile: widget.capturedImage,
                    capturedImageUrl: resultImageUrl,
                  );
                  if (data == null || data.isEmpty) {
                    return _fallbackDetails(
                      context: context,
                      padding: padding,
                      maxWidth: maxWidth,
                      name: fallbackName,
                      notes: ['No database entry found for this fish.'],
                      image: fallbackImage,
                    );
                  }

                  final englishName = (data['englishName'] ?? widget.fishName)
                      .toString();
                  final localName = (data['localName'] ?? '').toString();
                  final scientificName = (data['scientificName'] ?? '')
                      .toString();
                  final family = (data['family'] ?? '').toString();
                  final habitat = (data['habitat'] ?? data['location'] ?? '')
                      .toString();
                  final about = (data['about'] ?? '').toString().trim();
                  final description = (data['description'] ?? '')
                      .toString()
                      .trim();
                  final diet = (data['diet'] ?? '').toString();
                  final culinary = (data['culinary'] ?? '').toString();
                  final updatedAt = _formatUpdatedAt(data['updatedAt']);

                  final fallbackSummary =
                      'The fish in the image is a $englishName${scientificName.isNotEmpty ? ' ($scientificName)' : ''}.';
                  final summary = about.isNotEmpty
                      ? about
                      : (description.isNotEmpty
                            ? description
                            : fallbackSummary);
                  final contextText = _buildFishContext(
                    englishName: englishName,
                    scientificName: scientificName,
                    localName: localName,
                    family: family,
                    habitat: habitat,
                    diet: diet,
                    summary: summary,
                  );
                  _maybeGenerateAutoBrief(contextText);
                  final imageWidget = fallbackHeroImage;
                  final confidenceLabel = _confidenceLabel(
                    widget.predictionScore,
                  );

                  final shareText = StringBuffer()
                    ..write('Detection result: $englishName')
                    ..write(
                      scientificName.isNotEmpty ? ' ($scientificName)' : '',
                    )
                    ..write(
                      confidenceLabel.isNotEmpty
                          ? '\nConfidence: $confidenceLabel'
                          : '',
                    )
                    ..write(
                      localName.isNotEmpty ? '\nLocal name: $localName' : '',
                    )
                    ..write(family.isNotEmpty ? '\nFamily: $family' : '')
                    ..write(habitat.isNotEmpty ? '\nHabitat: $habitat' : '')
                    ..write(summary.isNotEmpty ? '\nAbout: $summary' : '')
                    ..write(diet.isNotEmpty ? '\nDiet: $diet' : '')
                    ..write(
                      culinary.isNotEmpty ? '\nCulinary use: $culinary' : '',
                    );
                  final shareImageCandidates = <String>{
                    if (speciesImageUrl.isNotEmpty) speciesImageUrl,
                    ...speciesImageSource.storagePaths,
                    if (_detectionImageUrl.isNotEmpty) _detectionImageUrl,
                    if ((widget.capturedImageUrl ?? '').trim().isNotEmpty)
                      widget.capturedImageUrl!.trim(),
                  }.toList();

                  final facts = <MapEntry<String, String>>[
                    if (localName.isNotEmpty) MapEntry('Local name', localName),
                    if (family.isNotEmpty) MapEntry('Family', family),
                    if (habitat.isNotEmpty) MapEntry('Habitat', habitat),
                    if (diet.isNotEmpty) MapEntry('Diet', diet),
                    if (culinary.isNotEmpty) MapEntry('Culinary use', culinary),
                    if (updatedAt.isNotEmpty) MapEntry('Updated', updatedAt),
                  ];
                  final titleSize = Responsive.value<double>(
                    context,
                    mobile: 34,
                    tablet: 40,
                    desktop: 44,
                  );
                  final subtitleSize = Responsive.value<double>(
                    context,
                    mobile: 14,
                    tablet: 15,
                    desktop: 16,
                  );
                  final summarySize = Responsive.value<double>(
                    context,
                    mobile: 14.5,
                    tablet: 15.5,
                    desktop: 16.5,
                  );

                  return Stack(
                    children: [
                      SingleChildScrollView(
                        padding: EdgeInsets.fromLTRB(
                          padding,
                          padding,
                          padding,
                          padding + 108,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 12,
                              ),
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    Color(0xFF0B3C64),
                                    Color(0xFF125283),
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(18),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(
                                      0xFF0A3556,
                                    ).withValues(alpha: 0.16),
                                    blurRadius: 16,
                                    offset: const Offset(0, 8),
                                  ),
                                ],
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 34,
                                    height: 34,
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(
                                        alpha: 0.16,
                                      ),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.auto_awesome_rounded,
                                      color: Colors.white,
                                      size: 18,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  const Expanded(
                                    child: Text(
                                      'Detected species',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 15,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                  if (confidenceLabel.isNotEmpty)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 6,
                                      ),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF1D9C62),
                                        borderRadius: BorderRadius.circular(
                                          999,
                                        ),
                                        border: Border.all(
                                          color: Colors.white.withValues(
                                            alpha: 0.22,
                                          ),
                                        ),
                                      ),
                                      child: Text(
                                        confidenceLabel,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            SizedBox(height: verticalGap),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    Color(0xFF062E52),
                                    Color(0xFF0F4F7C),
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(24),
                                border: Border.all(
                                  color: const Color(0xFF1C5A89),
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(
                                      0xFF0A3556,
                                    ).withValues(alpha: 0.18),
                                    blurRadius: 20,
                                    offset: const Offset(0, 10),
                                  ),
                                ],
                              ),
                              child: Stack(
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(16),
                                    child: imageWidget,
                                  ),
                                  if (_savingImage)
                                    Positioned.fill(
                                      child: Container(
                                        color: Colors.black.withValues(
                                          alpha: 0.14,
                                        ),
                                        alignment: Alignment.center,
                                        child:
                                            const CircularProgressIndicator(),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            SizedBox(height: verticalGap),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.fromLTRB(
                                16,
                                15,
                                16,
                                14,
                              ),
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    Color(0xFFFFFFFF),
                                    Color(0xFFF3F8FF),
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(22),
                                border: Border.all(
                                  color: const Color(0xFFD7E6F6),
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(
                                      0xFF0A3556,
                                    ).withValues(alpha: 0.05),
                                    blurRadius: 14,
                                    offset: const Offset(0, 6),
                                  ),
                                ],
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    englishName,
                                    style: TextStyle(
                                      fontSize: titleSize,
                                      fontWeight: FontWeight.w900,
                                      height: 1.05,
                                      color: const Color(0xFF102A43),
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [
                                      if (localName.isNotEmpty)
                                        _buildInfoChip(
                                          chipKey: 'local_name',
                                          icon: Icons.place_outlined,
                                          text:
                                              'Local: ${_shortChipText(localName)}',
                                          fullText: localName,
                                        ),
                                      if (confidenceLabel.isNotEmpty)
                                        _buildInfoChip(
                                          chipKey: 'confidence',
                                          icon: Icons.verified_outlined,
                                          text: confidenceLabel,
                                          background: const Color(0xFFE8F8EF),
                                          foreground: const Color(0xFF177245),
                                        ),
                                    ],
                                  ),
                                  if (scientificName.isNotEmpty) ...[
                                    const SizedBox(height: 10),
                                    Text(
                                      scientificName,
                                      style: TextStyle(
                                        fontSize: subtitleSize,
                                        fontStyle: FontStyle.italic,
                                        color: const Color(0xFF52667A),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            SizedBox(height: verticalGap),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.fromLTRB(
                                14,
                                12,
                                14,
                                14,
                              ),
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    Color(0xFFFFFFFF),
                                    Color(0xFFF5FAFF),
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: const Color(0xFFD7E6F6),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _buildSectionTitle(
                                    icon: Icons.info_outline,
                                    title: 'Species Overview',
                                    subtitle:
                                        'Quick profile generated from species records.',
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    summary,
                                    style: TextStyle(
                                      fontSize: summarySize,
                                      height: 1.52,
                                      color: const Color(0xFF1F2937),
                                    ),
                                  ),
                                  if (family.isNotEmpty ||
                                      habitat.isNotEmpty ||
                                      diet.isNotEmpty) ...[
                                    const SizedBox(height: 12),
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: [
                                        if (family.isNotEmpty)
                                          _buildInfoChip(
                                            chipKey: 'family',
                                            icon: Icons.category_outlined,
                                            text: _shortChipText(family),
                                            fullText: family,
                                          ),
                                        if (habitat.isNotEmpty)
                                          _buildInfoChip(
                                            chipKey: 'habitat',
                                            icon: Icons.waves_outlined,
                                            text: _shortChipText(
                                              habitat,
                                              maxChars: 38,
                                            ),
                                            fullText: habitat,
                                          ),
                                        if (diet.isNotEmpty)
                                          _buildInfoChip(
                                            chipKey: 'diet',
                                            icon: Icons.restaurant_outlined,
                                            text: _shortChipText(
                                              diet,
                                              maxChars: 34,
                                            ),
                                            fullText: diet,
                                          ),
                                      ],
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            SizedBox(height: verticalGap),
                            _buildAutoBriefCard(contextText),
                            if (facts.isNotEmpty) ...[
                              SizedBox(height: verticalGap),
                              Text(
                                'Field notes',
                                style: TextStyle(
                                  fontSize: Responsive.value<double>(
                                    context,
                                    mobile: 14,
                                    tablet: 15,
                                    desktop: 15,
                                  ),
                                  fontWeight: FontWeight.w800,
                                  color: const Color(0xFF1F2937),
                                ),
                              ),
                              const SizedBox(height: 10),
                              LayoutBuilder(
                                builder: (context, constraints) =>
                                    _buildFactsGrid(
                                      facts: facts,
                                      contentWidth: constraints.maxWidth,
                                    ),
                              ),
                            ],
                            SizedBox(height: verticalGap),
                            SizedBox(
                              width: double.infinity,
                              child: _buildActionDock(
                                onCaptureTap: () => Navigator.pop(context),
                                onShareTap: () => _shareFishDetails(
                                  englishName: englishName,
                                  shareText: shareText.toString(),
                                  imageCandidates: shareImageCandidates,
                                ),
                                onAskTap: _asking
                                    ? null
                                    : () => _showAskDialog(
                                        contextText: contextText,
                                      ),
                                asking: _asking,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (_asking)
                        Positioned.fill(
                          child: IgnorePointer(
                            child: Container(
                              color: Colors.black.withValues(alpha: 0.05),
                              alignment: Alignment.center,
                              child: const CircularProgressIndicator(),
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFactsGrid({
    required List<MapEntry<String, String>> facts,
    required double contentWidth,
  }) {
    final compact = contentWidth < 360;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(12, compact ? 8 : 10, 12, compact ? 10 : 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFDCE8F8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < facts.length; i++) ...[
            if (i > 0)
              Divider(
                height: compact ? 14 : 18,
                color: const Color(0xFFE4ECF9),
              ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: compact ? 92 : 110,
                  child: Text(
                    facts[i].key.toUpperCase(),
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.3,
                      color: Color(0xFF1D4B88),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    facts[i].value,
                    style: const TextStyle(
                      fontSize: 13.5,
                      height: 1.35,
                      color: Color(0xFF1F2937),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildActionDock({
    required VoidCallback onCaptureTap,
    required VoidCallback onShareTap,
    required VoidCallback? onAskTap,
    required bool asking,
  }) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: Responsive.isSmall(context) ? 10 : 14,
        vertical: Responsive.isSmall(context) ? 8 : 10,
      ),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF0A3556), Color(0xFF0F4670)],
        ),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: const Color(0xFF205E8B), width: 1),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0A3556).withValues(alpha: 0.22),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          _dockIconButton(
            onTap: onCaptureTap,
            icon: Icons.photo_camera_outlined,
          ),
          const SizedBox(width: 10),
          _dockIconButton(onTap: onShareTap, icon: Icons.ios_share_outlined),
          const SizedBox(width: 12),
          Container(width: 1, height: 24, color: Colors.white24),
          const SizedBox(width: 12),
          Expanded(
            child: InkWell(
              onTap: onAskTap,
              borderRadius: BorderRadius.circular(18),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Flexible(
                      child: Text(
                        asking ? 'Asking...' : 'Ask AI',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: onAskTap == null ? Colors.white54 : Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Icon(
                      Icons.smart_toy_outlined,
                      size: 18,
                      color: onAskTap == null ? Colors.white54 : Colors.white,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _dockIconButton({
    required VoidCallback onTap,
    required IconData icon,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.16),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: Colors.white, size: 19),
        ),
      ),
    );
  }

  Widget _buildAutoBriefCard(String contextText) {
    final showLoading = _autoBriefLoading && _autoBriefText.trim().isEmpty;
    final showText = _autoBriefText.trim().isNotEmpty;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFF8FBFF), Color(0xFFF2F6FD)],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFD7E3F5)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: const BoxDecoration(
                  color: Color(0xFFEAF1FF),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.auto_awesome,
                  size: 15,
                  color: Color(0xFF1D4B88),
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                'AI Fish Brief',
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF1F2937),
                ),
              ),
              const Spacer(),
              IconButton(
                onPressed: _autoBriefLoading
                    ? null
                    : () => _generateAutoBrief(
                        contextText: contextText,
                        force: true,
                      ),
                icon: const Icon(Icons.refresh, size: 18),
                tooltip: 'Regenerate',
                visualDensity: VisualDensity.compact,
                style: IconButton.styleFrom(
                  foregroundColor: const Color(0xFF1D4B88),
                  backgroundColor: const Color(0xFFEAF1FF),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (showLoading)
            const Row(
              children: [
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 8),
                Expanded(child: Text('Generating fish guidance...')),
              ],
            )
          else if (showText)
            SelectableText(
              _autoBriefText,
              style: const TextStyle(
                fontSize: 13.5,
                height: 1.48,
                color: Color(0xFF1F2937),
              ),
            )
          else
            const Text(
              'Tap refresh to generate guidance for this fish.',
              style: TextStyle(fontSize: 13, color: Color(0xFF6B7280)),
            ),
          if (_autoBriefSource.isNotEmpty &&
              _autoBriefSource.toLowerCase() != 'local' &&
              _autoBriefSource.toLowerCase() != 'offline')
            Padding(
              padding: const EdgeInsets.only(top: 8),

            ),
        ],
      ),
    );
  }

  // ------------------------------
  // IMAGE PRIORITY (ONLINE/SPECIES FIRST)
  // ------------------------------

  Widget _buildBestImage({
    String? speciesImageUrl,
    required List<String> speciesStoragePaths,
    String? forceNetworkUrl,
    required Uint8List? capturedBytes,
    required File? capturedFile,
    required String? capturedImageUrl,
  }) {
    Widget loadingOverlay(Widget child) => Stack(
      children: [
        child,
        Positioned.fill(
          child: Container(
            color: Colors.black.withValues(alpha: 0.04),
            alignment: Alignment.center,
            child: const SizedBox(
              height: 26,
              width: 26,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        ),
      ],
    );

    Widget wrap(Widget child) =>
        ClipRRect(borderRadius: BorderRadius.circular(12), child: child);

    Widget networkOrStorageImage(
      String raw, {
      required double height,
      BoxFit fit = BoxFit.cover,
      required Widget fallback,
    }) {
      final normalized = _resolveImageUrl(raw, allowStoragePath: true);
      if (normalized.isEmpty) return fallback;
      if (_isDataImageUrl(normalized)) {
        final bytes = _decodeDataImageUrl(normalized);
        if (bytes == null) return fallback;
        return Image.memory(
          bytes,
          width: double.infinity,
          height: height,
          alignment: Alignment.center,
          fit: fit,
          errorBuilder: (_, __, ___) => fallback,
        );
      }
      final uri = Uri.tryParse(normalized);
      final isHttp =
          uri != null && (uri.scheme == 'http' || uri.scheme == 'https');

      if (isHttp) {
        return Image.network(
          normalized,
          width: double.infinity,
          height: height,
          alignment: Alignment.center,
          fit: fit,
          errorBuilder: (_, __, ___) => fallback,
        );
      }

      return FutureBuilder<String?>(
        future: _resolveDownloadUrl(normalized),
        builder: (context, snapshot) {
          final resolved = snapshot.data ?? '';
          if (resolved.isNotEmpty) {
            if (_isDataImageUrl(resolved)) {
              final bytes = _decodeDataImageUrl(resolved);
              if (bytes != null) {
                return Image.memory(
                  bytes,
                  width: double.infinity,
                  height: height,
                  alignment: Alignment.center,
                  fit: fit,
                  errorBuilder: (_, __, ___) => fallback,
                );
              }
            }

            return Image.network(
              resolved,
              width: double.infinity,
              height: height,
              alignment: Alignment.center,
              fit: fit,
              errorBuilder: (_, __, ___) => fallback,
            );
          }

          if (snapshot.connectionState == ConnectionState.waiting) {
            return loadingOverlay(fallback);
          }

          return fallback;
        },
      );
    }

    Widget? detectionOrCaptured() {
      // 1) Local capture (fast, matches what the user just saw)
      if (capturedBytes != null && capturedBytes.isNotEmpty) {
        return wrap(
          Image.memory(
            capturedBytes,
            width: double.infinity,
            height: 200,
            alignment: Alignment.center,
            fit: BoxFit.cover,
          ),
        );
      }

      if (!kIsWeb && capturedFile != null) {
        return wrap(
          Image.file(
            capturedFile,
            width: double.infinity,
            height: 200,
            alignment: Alignment.center,
            fit: BoxFit.cover,
          ),
        );
      }

      // 2) Cloud URL that was saved for this detection
      final forceUrl = (forceNetworkUrl ?? '').trim();
      if (forceUrl.isNotEmpty) {
        return wrap(
          networkOrStorageImage(
            forceUrl,
            height: 200,
            fit: BoxFit.cover,
            fallback: const Icon(Icons.broken_image, size: 60),
          ),
        );
      }

      // 3) Uploaded URL passed in (should match storage/Firebase)
      final uploadedUrl = (capturedImageUrl ?? '').trim();
      if (uploadedUrl.isNotEmpty) {
        return wrap(
          networkOrStorageImage(
            uploadedUrl,
            height: 200,
            fit: BoxFit.cover,
            fallback: const Icon(Icons.broken_image, size: 60),
          ),
        );
      }

      return null;
    }

    Widget placeholder() => SizedBox(
      width: double.infinity,
      height: 200,
      child: Center(
        child: Icon(
          Icons.image_not_supported,
          size: 60,
          color: Colors.grey.shade600,
        ),
      ),
    );

    Widget storageImage(Widget fallback) {
      if (speciesStoragePaths.isEmpty) return fallback;

      final primary = speciesStoragePaths.first;
      final fallbacks = speciesStoragePaths.skip(1).toList();

      return FutureBuilder<String?>(
        future: _getStorageUrl(primary, fallbacks),
        builder: (context, snapshot) {
          final resolved = snapshot.data ?? '';
          if (resolved.isNotEmpty) {
            return wrap(
              Container(
                color: const Color(0xFF0A2F54),
                child: Image.network(
                  resolved,
                  width: double.infinity,
                  height: 200,
                  alignment: Alignment.center,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => fallback,
                ),
              ),
            );
          }

          if (snapshot.connectionState == ConnectionState.waiting) {
            return Stack(
              children: [
                fallback,
                Positioned.fill(
                  child: Container(
                    color: Colors.black.withValues(alpha: 0.04),
                    alignment: Alignment.center,
                    child: const SizedBox(
                      height: 26,
                      width: 26,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                ),
              ],
            );
          }

          return fallback;
        },
      );
    }

    final detectionImage = detectionOrCaptured();
    final fallback = placeholder();
    final photoFallback = detectionImage ?? fallback;

    // 1) Reference/species image (direct URL)
    final directSpeciesUrl = (speciesImageUrl ?? '').trim();
    if (directSpeciesUrl.isNotEmpty) {
      return wrap(
        Container(
          color: const Color(0xFF0A2F54),
          child: networkOrStorageImage(
            directSpeciesUrl,
            height: 200,
            fit: BoxFit.contain,
            fallback: storageImage(photoFallback),
          ),
        ),
      );
    }

    // 2) Try Firebase Storage paths for species reference image
    if (speciesStoragePaths.isNotEmpty) {
      return storageImage(photoFallback);
    }

    // 3) Fall back to the detected/captured image
    if (detectionImage != null) return detectionImage;

    // 4) Last resort placeholder
    return fallback;
  }

  Future<String?> _getStorageUrl(String primary, List<String> fallbacks) {
    final cacheKey = [primary, ...fallbacks].join('|');
    if (_storageUrlCache.containsKey(cacheKey)) {
      return _storageUrlCache[cacheKey]!;
    }

    final future = () async {
      for (final candidate in [primary, ...fallbacks]) {
        final url = await _tryStoragePath(candidate);
        if (url != null && url.isNotEmpty) return url;
      }
      return null;
    }();

    _storageUrlCache[cacheKey] = future;
    return future;
  }

  Future<String?> _tryStoragePath(String path) async {
    if (path.isEmpty) return null;
    try {
      final ref = path.startsWith('gs://')
          ? FirebaseStorage.instance.refFromURL(path)
          : FirebaseStorage.instance.ref(path);
      return await ref.getDownloadURL();
    } catch (_) {
      return null;
    }
  }

  Future<String?> _resolveDownloadUrl(String raw) {
    final normalized = _resolveImageUrl(raw, allowStoragePath: true);
    if (normalized.isEmpty) return Future.value(null);
    if (_isDataImageUrl(normalized)) return Future.value(normalized);

    final uri = Uri.tryParse(normalized);
    if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
      return Future.value(normalized);
    }

    if (_downloadUrlCache.containsKey(normalized)) {
      return _downloadUrlCache[normalized]!;
    }

    final future = () async {
      try {
        final ref = normalized.startsWith('gs://')
            ? FirebaseStorage.instance.refFromURL(normalized)
            : FirebaseStorage.instance.ref(normalized);
        return await ref.getDownloadURL();
      } catch (_) {
        return null;
      }
    }();

    _downloadUrlCache[normalized] = future;
    return future;
  }

  // ------------------------------
  // FIRESTORE SPECIES LOOKUP
  // ------------------------------

  String _slug(String input) {
    final lower = input.toLowerCase();
    final cleaned = lower.replaceAll(RegExp(r'[^a-z0-9]+'), '-');
    return cleaned
        .replaceAll(RegExp('-+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
  }

  Future<Map<String, dynamic>?> _fetchSpecies(String name) async {
    try {
      final species = FirebaseFirestore.instance.collection('species_database');
      final stats = FirebaseFirestore.instance.collection('marine_life_stats');
      final cleaned = name.trim();
      final lowerName = cleaned.toLowerCase();
      final withoutParen = cleaned.split('(').first.trim();
      final withoutComma = cleaned.split(',').first.trim();
      final slug = _slug(cleaned);
      final slugNoParen = _slug(withoutParen);
      final slugNoComma = _slug(withoutComma);
      final altCompact = lowerName.replaceAll(' ', '');

      final candidates = <String>{
        slug,
        lowerName,
        cleaned.replaceAll(' ', '-').toLowerCase(),
        slugNoParen,
        slugNoComma,
        altCompact,
        withoutParen.toLowerCase(),
        withoutComma.toLowerCase(),
      }.where((s) => s.isNotEmpty).toList();

      for (final docId in candidates) {
        final doc = await species.doc(docId).get();
        if (doc.exists) {
          final data = doc.data();
          if (data != null) return {...data, 'id': doc.id};
        }
      }

      final englishMatch = await species
          .where('englishName', isEqualTo: cleaned)
          .limit(1)
          .get();
      if (englishMatch.docs.isNotEmpty) {
        final doc = englishMatch.docs.first;
        final data = doc.data();
        return {...data, 'id': doc.id};
      }

      final sciMatch = await species
          .where('scientificName', isEqualTo: cleaned)
          .limit(1)
          .get();
      if (sciMatch.docs.isNotEmpty) {
        final doc = sciMatch.docs.first;
        final data = doc.data();
        return {...data, 'id': doc.id};
      }

      // Try marine_life_stats (fish production data)
      for (final docId in candidates) {
        final doc = await stats.doc(docId).get();
        if (doc.exists) {
          final data = _normalizeStatsDoc(doc);
          if (data != null) return data;
        }
      }

      final englishProd = await stats
          .where('englishName', isEqualTo: cleaned)
          .limit(1)
          .get();
      if (englishProd.docs.isNotEmpty) {
        final doc = englishProd.docs.first;
        final data = _normalizeStatsDoc(doc);
        if (data != null) return data;
      }

      final nameProd = await stats
          .where('name', isEqualTo: cleaned)
          .limit(1)
          .get();
      if (nameProd.docs.isNotEmpty) {
        final doc = nameProd.docs.first;
        final data = _normalizeStatsDoc(doc);
        if (data != null) return data;
      }

      final statsDocs = await stats.get();
      final bestStats = _bestMatch(statsDocs.docs, lowerName);
      if (bestStats != null) {
        final data = _normalizeStatsDoc(bestStats);
        if (data != null) return data;
      }

      _allSpecies ??= species.get().then((snap) => snap.docs);
      final docs = await _allSpecies!;
      final best = _bestMatch(docs, lowerName);
      if (best != null) return {...best.data(), 'id': best.id};

      return null;
    } on FirebaseException catch (e) {
      final code = e.code.toLowerCase();
      if (code == 'permission-denied' ||
          code == 'unauthenticated' ||
          code == 'unauthorized') {
        debugPrint('Species lookup blocked by rules: ${e.message ?? e.code}');
        return null;
      }
      debugPrint('Species lookup failed: ${e.message ?? e.code}');
      return null;
    } catch (e) {
      debugPrint('Species lookup failed: $e');
      return null;
    }
  }

  Map<String, dynamic>? _normalizeStatsDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    if (data == null) return null;
    final english = (data['englishName'] ?? data['name'] ?? doc.id).toString();
    final photo = (data['photo'] ?? data['imageUrl'] ?? data['image'] ?? '')
        .toString();
    return {
      ...data,
      'id': doc.id,
      'englishName': english,
      'name': english,
      'photo': photo,
      'photoRaw': photo,
    };
  }

  QueryDocumentSnapshot<Map<String, dynamic>>? _bestMatch(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    String needle,
  ) {
    QueryDocumentSnapshot<Map<String, dynamic>>? bestDoc;
    double bestScore = 0;

    String normalize(String s) => s.toLowerCase().trim();
    String compact(String s) => normalize(s).replaceAll(' ', '');

    for (final doc in docs) {
      final data = doc.data();
      final id = doc.id;
      final english = (data['englishName'] ?? '').toString();
      final scientific = (data['scientificName'] ?? '').toString();

      final fields = <String>[
        id,
        _slug(id),
        english,
        scientific,
        _slug(english),
        _slug(scientific),
        compact(english),
        compact(scientific),
      ].where((s) => s.isNotEmpty).toList();

      for (final field in fields) {
        final f = normalize(field);
        final score = _similarityScore(f, needle);
        if (score > bestScore) {
          bestScore = score;
          bestDoc = doc;
        }
      }
    }

    return bestScore >= 0.25 ? bestDoc : null;
  }

  Future<void> _showAnswerSheet({
    required String question,
    required String answer,
    required String contextText,
  }) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _AnswerPage(
          initialQuestion: question,
          initialAnswer: answer,
          contextText: contextText,
          ask: ({required String question, required String context}) async {
            final reply = await _askFishAssistant(
              question: question,
              context: context,
            );
            return reply.answer;
          },
        ),
      ),
    );
    // Legacy bottom-sheet implementation kept for reference; unreachable after full-page push.
    return;
    /* 
    final trimmedQuestion = question.trim();
    final followUpController = TextEditingController();
    final followUpFocus = FocusNode();
    String currentAnswer = answer;
    String currentQuestion = trimmedQuestion;
    bool isLoading = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.6),
      builder: (sheetContext) {
        return DraggableScrollableSheet(
          initialChildSize: 0.995,
          maxChildSize: 0.995,
          minChildSize: 0.72,
          expand: false,
          builder: (ctx, scrollController) {
            return SafeArea(
              child: StatefulBuilder(
                builder: (innerContext, setSheetState) {
                  Future<void> submitFollowUp() async {
                    final next = followUpController.text.trim();
                    if (next.isEmpty) {
                      followUpFocus.requestFocus();
                      return;
                    }
                    setSheetState(() => isLoading = true);
                    try {
                      final newAnswer = await _askGemini(question: next, context: contextText);
                      if (!mounted) return;
                      setSheetState(() {
                        currentQuestion = next;
                        currentAnswer = newAnswer;
                        isLoading = false;
                        followUpController.clear();
                      });
                    } catch (e) {
                      if (!mounted) return;
                      setSheetState(() => isLoading = false);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('AI error: $e')),
                      );
                    }
                  }

                  return Container(
                    margin: const EdgeInsets.fromLTRB(12, 6, 12, 0),
                    padding: EdgeInsets.fromLTRB(
                      18,
                      12,
                      18,
                      18 + MediaQuery.of(sheetContext).viewInsets.bottom,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(24),
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Color(0xFFF8FBFF),
                          Color(0xFFECEFF5),
                        ],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.12),
                          blurRadius: 24,
                          offset: const Offset(0, 16),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Center(
                          child: Container(
                            width: 44,
                            height: 4,
                            decoration: BoxDecoration(
                              color: Colors.grey.shade400,
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Colors.blue.shade50,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.smart_toy_outlined, color: Colors.blueAccent),
                            ),
                            const SizedBox(width: 12),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: const [
                                Text(
                                  'AI Assistant',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                SizedBox(height: 2),
                                Text(
                                  'Guidance for this fish',
                                  style: TextStyle(color: Colors.black54, fontSize: 13),
                                ),
                              ],
                            ),
                            const Spacer(),
                            IconButton(
                              onPressed: () => Navigator.of(sheetContext).pop(),
                              icon: const Icon(Icons.close),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        if (trimmedQuestion.isNotEmpty) ...[
                          const Text(
                            'Your question',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: Colors.grey.shade200),
                            ),

                          const SizedBox(height: 14),
                        ],
                        const Text(
                          'Response',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Expanded(
                          child: Stack(
                            children: [
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: Colors.grey.shade200),
                                ),
                                child: SingleChildScrollView(
                                  controller: scrollController,
                                  child: SelectableText(
                                    currentAnswer.trim().isEmpty ? 'No response.' : currentAnswer.trim(),
                                    style: const TextStyle(
                                      fontSize: 14,
                                      height: 1.55,
                                      color: Colors.black,
                                    ),
                                  ),
                                ),
                              ),
                              if (isLoading)
                                Positioned.fill(
                                  child: IgnorePointer(
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: Colors.white.withValues(alpha: 0.6),
                                        borderRadius: BorderRadius.circular(16),
                                      ),
                                      alignment: Alignment.center,
                                      child: const CircularProgressIndicator(strokeWidth: 2),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                        const Text(
                          'Reply or ask again',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: Colors.grey.shade200),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Row(
                            children: [
                              const Icon(Icons.edit_outlined, color: Colors.black54, size: 18),
                              const SizedBox(width: 8),
                              Expanded(
                                child: TextField(
                                  controller: followUpController,
                                  focusNode: followUpFocus,
                                  minLines: 1,
                                  maxLines: 4,
                                  textInputAction: TextInputAction.send,
                                  onSubmitted: (_) => isLoading ? null : submitFollowUp(),
                                  decoration: const InputDecoration(
                                    hintText: 'Type a follow-up question...',
                                    border: InputBorder.none,
                                  ),
                                ),
                              ),
                              IconButton(
                                onPressed: isLoading ? null : submitFollowUp,
                                icon: const Icon(Icons.send_rounded, color: Colors.blueAccent),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            OutlinedButton.icon(
                              onPressed: () async {
                                await Clipboard.setData(ClipboardData(text: currentAnswer));
                                if (!mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Copied response')),
                                );
                              },
                              icon: const Icon(Icons.copy, size: 18),
                              label: const Text('Copy'),
                            ),
                            const Spacer(),
                            FilledButton.icon(
                              onPressed: () => Navigator.of(sheetContext).pop(),
                              icon: const Icon(Icons.check_circle_outline, size: 18),
                              label: const Text('Done'),
                              style: FilledButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),
            );
          },
        );
      },
    );
    */
  }

  double _similarityScore(String haystack, String needle) {
    if (haystack == needle) return 1.0;
    if (haystack.startsWith(needle) || needle.startsWith(haystack)) return 0.8;
    if (haystack.contains(needle)) return 0.6;
    if (needle.contains(haystack)) return 0.5;
    return 0.0;
  }

  String _formatUpdatedAt(dynamic value) {
    DateTime? date;
    if (value is Timestamp) date = value.toDate();
    if (value is DateTime) date = value;
    if (value is String && value.isNotEmpty) date = DateTime.tryParse(value);
    if (date == null) return '';
    return DateFormat('MMM d, yyyy').format(date);
  }

  Widget _fallbackDetails({
    required BuildContext context,
    required double padding,
    required double maxWidth,
    required String name,
    required List<String> notes,
    required Widget image,
    bool pulse = false,
  }) {
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: SingleChildScrollView(
          padding: EdgeInsets.all(padding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.grey.shade200),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: image,
              ),
              SizedBox(height: Responsive.verticalSpace(context)),
              Text(
                name,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 12),
              ...notes.map(
                (line) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: pulse
                      ? _shimmerText(line)
                      : Text(line, textAlign: TextAlign.center),
                ),
              ),
              if (_isUnknownSpecies && !pulse) ...[
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _openSightingLogForDetection,
                    icon: const Icon(Icons.add_location_alt_outlined),
                    label: const Text('Log as Sighting'),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF0F4670),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 13,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _shimmerText(String text) {
    return ShaderMask(
      shaderCallback: (bounds) => const LinearGradient(
        colors: [Colors.black26, Colors.black54, Colors.black26],
        stops: [0.1, 0.5, 0.9],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        tileMode: TileMode.clamp,
      ).createShader(bounds),
      blendMode: BlendMode.srcATop,
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(color: Colors.black54),
      ),
    );
  }

  _SpeciesImageSource _speciesImageSource(Map<String, dynamic>? data) {
    final id = (data?['id'] ?? '').toString();
    final rawCandidates = <String>[
      (data?['photo'] ?? '').toString(),
      (data?['imageUrl'] ?? '').toString(),
      (data?['image'] ?? '').toString(),
      (data?['photoRaw'] ?? '').toString(),
      _photoOverrides[id] ?? '',
    ];

    final storagePaths = <String>[];
    String directUrl = '';

    for (final raw in rawCandidates) {
      final normalized = _resolveImageUrl(raw, allowStoragePath: true);
      if (normalized.isEmpty) continue;

      final uri = Uri.tryParse(normalized);
      final isHttp =
          uri != null && (uri.scheme == 'http' || uri.scheme == 'https');
      if (isHttp) {
        directUrl = normalized;
        break;
      }

      if (!storagePaths.contains(normalized)) {
        storagePaths.add(normalized);
      }
    }

    return _SpeciesImageSource(
      directUrl: directUrl,
      storagePaths: storagePaths,
    );
  }

  String _resolveImageUrl(String raw, {bool allowStoragePath = false}) {
    var trimmed = raw.trim();
    if (trimmed.isEmpty) return '';

    if (trimmed.startsWith('=IMAGE(')) {
      final extracted = _extractUrlFromImageFormula(trimmed);
      if (extracted != null && extracted.isNotEmpty) {
        trimmed = extracted;
      }
    }

    if (allowStoragePath) {
      final lower = trimmed.toLowerCase();
      const storagePrefixes = [
        'species_database/',
        'marine_life_stats/',
        'detections/',
      ];
      if (lower.startsWith('gs://')) return trimmed;
      if (!trimmed.contains('://')) {
        final hasKnownPrefix = storagePrefixes.any((p) => lower.startsWith(p));
        if (hasKnownPrefix) return trimmed;
      }
    }

    try {
      var uri = Uri.parse(trimmed);
      if (uri.scheme == 'http') uri = uri.replace(scheme: 'https');
      return uri.toString();
    } catch (_) {
      if (allowStoragePath &&
          (trimmed.startsWith('gs://') || !trimmed.contains('://'))) {
        return trimmed;
      }
      return '';
    }
  }

  String? _extractUrlFromImageFormula(String formula) {
    final regex = RegExp(
      "=IMAGE\\([\"']([^\"']+)[\"'].*\\)",
      caseSensitive: false,
    );
    final match = regex.firstMatch(formula);
    if (match != null && match.groupCount >= 1) {
      final inner = match.group(1);
      if (inner != null && inner.trim().isNotEmpty) {
        return inner.trim();
      }
    }
    return null;
  }
}

class _AiAnswer {
  final String answer;
  final String source;

  _AiAnswer({required this.answer, required this.source});
}

class _ShareImagePayload {
  final Uint8List bytes;
  final String mimeType;
  final String fileName;

  const _ShareImagePayload({
    required this.bytes,
    required this.mimeType,
    required this.fileName,
  });
}

class _AnswerPage extends StatefulWidget {
  final String initialQuestion;
  final String initialAnswer;
  final String contextText;
  final Future<String> Function({
    required String question,
    required String context,
  })
  ask;

  const _AnswerPage({
    required this.initialQuestion,
    required this.initialAnswer,
    required this.contextText,
    required this.ask,
  });

  @override
  State<_AnswerPage> createState() => _AnswerPageState();
}

class _AnswerPageState extends State<_AnswerPage> {
  late String _currentQuestion;
  late String _currentAnswer;
  final _followUpController = TextEditingController();
  final _responseScrollController = ScrollController();
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _currentQuestion = widget.initialQuestion.trim();
    _currentAnswer = widget.initialAnswer;
  }

  @override
  void dispose() {
    _followUpController.dispose();
    _responseScrollController.dispose();
    super.dispose();
  }

  Future<void> _submitFollowUp() async {
    final next = _followUpController.text.trim();
    if (next.isEmpty) return;

    final previousQuestion = _currentQuestion;
    final previousAnswer = _currentAnswer;

    setState(() {
      _loading = true;
      _currentQuestion = next;
      _currentAnswer = '';
    });
    _jumpToTop();
    try {
      final answer = await widget.ask(
        question: next,
        context: widget.contextText,
      );
      if (!mounted) return;
      setState(() {
        _currentAnswer = answer.trim().isEmpty
            ? 'No response received. Try asking in a different way.'
            : answer.trim();
        _followUpController.clear();
      });
      _jumpToTop();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _currentQuestion = previousQuestion;
        _currentAnswer = previousAnswer;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('AI error: $e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _jumpToTop() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_responseScrollController.hasClients) return;
      _responseScrollController.jumpTo(0);
    });
  }

  Future<void> _copyResponse() async {
    final text = _currentAnswer.trim();
    if (text.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Copied response')));
  }

  Widget _sectionTitle(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: Colors.black87,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F7FB),
      appBar: AppBar(
        title: const Text('AI Assistant'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_currentQuestion.isNotEmpty) ...[
                _sectionTitle('Your question'),
                const SizedBox(height: 6),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Text(
                    _currentQuestion,
                    style: const TextStyle(
                      fontSize: 15,
                      height: 1.35,
                      color: Colors.black87,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              Row(
                children: [
                  _sectionTitle('Response'),
                  const Spacer(),
                  if (_loading)
                    Text(
                      'Generating...',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.blueGrey.shade600,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Expanded(
                child: Stack(
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: SingleChildScrollView(
                        controller: _responseScrollController,
                        child: SelectableText(
                          _currentAnswer.trim().isEmpty
                              ? 'Ask a question to get a detailed answer.'
                              : _currentAnswer.trim(),
                          style: const TextStyle(
                            fontSize: 14.5,
                            height: 1.55,
                            color: Colors.black87,
                          ),
                        ),
                      ),
                    ),
                    if (_loading)
                      Positioned.fill(
                        child: IgnorePointer(
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.8),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            alignment: Alignment.center,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const SizedBox(
                                  width: 28,
                                  height: 28,
                                  child: CircularProgressIndicator(strokeWidth: 2.4),
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  'Preparing a better answer...',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.blueGrey.shade700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: _currentAnswer.trim().isEmpty || _loading
                        ? null
                        : _copyResponse,
                    icon: const Icon(Icons.copy, size: 18),
                    label: const Text('Copy'),
                  ),
                  const Spacer(),
                  Text(
                    _loading ? 'AI is working...' : 'Ask a follow-up below',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: Colors.blueGrey.shade600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: TextField(
                  controller: _followUpController,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _loading ? null : _submitFollowUp(),
                  decoration: InputDecoration(
                    hintText: 'Type a follow-up question...',
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 14,
                    ),
                    suffixIcon: _loading
                        ? const Padding(
                            padding: EdgeInsets.all(14),
                            child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2.2),
                            ),
                          )
                        : IconButton(
                            onPressed: _submitFollowUp,
                            icon: const Icon(Icons.send_rounded),
                          ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SpeciesImageSource {
  final String directUrl;
  final List<String> storagePaths;

  _SpeciesImageSource({required this.directUrl, required this.storagePaths});
}


