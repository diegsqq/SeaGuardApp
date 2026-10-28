import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_mlkit_image_labeling/google_mlkit_image_labeling.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

import '../dashboard/navbar_screen.dart';
import '../../utils/functions_config.dart';
import '../../utils/loading_delay.dart';
import '../../utils/responsive.dart';
import 'fish_details_page.dart';

enum DetectionLaunchMode { camera, gallery }

const Duration _cameraCaptureSettleDelay = Duration(milliseconds: 280);
const double _minimumSharpnessScore = 9.0;

class DetectionScreen extends StatefulWidget {
  const DetectionScreen({super.key, this.launchMode});

  final DetectionLaunchMode? launchMode;

  @override
  State<DetectionScreen> createState() => _DetectionScreenState();
}

class _DetectionScreenState extends State<DetectionScreen> {
  int _selectedIndex = 2;
  File? _image;

  bool _isLoading = false;
  String? _resultText;

  Interpreter? _interpreter;
  List<String> _labels = [];
  bool _modelReady = false;
  bool _labelsReady = false;

  CameraController? _cameraController;
  CameraDescription? _selectedCamera;

  DetectionLaunchMode? _pendingLaunch;
  bool _cameraInitializing = false;
  String? _cameraError;

  static const int _inputSize = 224;
  static const double _mean = 127.5;
  static const double _std = 127.5;
  static const double _minSpeciesConfidence = 0.55;
  static const double _minSpeciesMargin = 0.10;
  static const double _minSpeciesAgreement = 0.58;
  static const double _minImmediateSpeciesConfidence = 0.72;
  static const double _minImmediateSpeciesMargin = 0.16;
  static const double _minImmediateSpeciesAgreement = 0.74;
  static const double _minFallbackSpeciesConfidence = 0.32;
  static const double _minFallbackSpeciesAgreement = 0.60;
  static const double _minCloudSpeciesConfidence = 0.42;
  static const double _minCloudOverrideDelta = 0.04;

  static const Set<String> _marineKeywords = {
    'fish',
    'sea creature',
    'sea life',
    'marine',
    'aquatic',
    'seafood',
    'shark',
    'ray',
    'eel',
    'tuna',
    'salmon',
    'trout',
    'snapper',
    'grouper',
    'mackerel',
    'sardine',
    'tilapia',
    'catfish',
    'barracuda',
    'carp',
    'milkfish',
    'marlin',
    'swordfish',
    'anchovy',
    'herring',
    'cod',
    'halibut',
    'octopus',
    'squid',
    'cuttlefish',
    'shrimp',
    'prawn',
    'crab',
    'lobster',
    'clam',
    'oyster',
    'mussel',
    'scallop',
    'jellyfish',
    'seahorse',
    'starfish',
    'urchin',
    'coral',
    'dolphin',
    'whale',
    'seal',
    'otter',
    'penguin',
    'turtle',
  };

  static const Set<String> _blockedGenericLabels = {
    'food',
    'dish',
    'meal',
    'snack',
    'dessert',
    'drink',
    'beverage',
    'fruit',
    'vegetable',
    'meat',
  };

  static const Set<String> _genericDetectionLabels = {
    'fish',
    'marine fish',
    'sea fish',
    'sea creature',
    'marine animal',
    'aquatic animal',
    'animal',
  };

  bool _isMarineLabel(String label) {
    final normalized = label.trim().toLowerCase();
    if (normalized.isEmpty) return false;

    if (_blockedGenericLabels.any((word) => normalized.contains(word))) {
      return false;
    }

    return _marineKeywords.any((word) => normalized.contains(word));
  }

  bool _isSpecificDetectionLabel(String label) {
    final normalized = _normalizeToken(label);
    return normalized.isNotEmpty &&
        !_genericDetectionLabels.contains(normalized) &&
        !normalized.startsWith('unknown');
  }

  ImageLabel? _bestMarineLabel(List<ImageLabel> labels) {
    if (labels.isEmpty) return null;
    final sorted = [...labels]
      ..sort((a, b) => b.confidence.compareTo(a.confidence));
    for (final label in sorted) {
      if (_isMarineLabel(label.label)) return label;
    }
    return null;
  }

  bool _isSupportedDetectionCamera(CameraDescription camera) {
    return camera.lensDirection != CameraLensDirection.front;
  }

  List<CameraDescription> _orderedCameraOptions(
    Iterable<CameraDescription> cameras,
  ) {
    final ordered = cameras.toList(growable: false);
    ordered.sort((a, b) {
      final priorityCompare = _cameraPriority(a).compareTo(_cameraPriority(b));
      if (priorityCompare != 0) return priorityCompare;

      final lensCompare = _cameraBaseLabel(a).compareTo(_cameraBaseLabel(b));
      if (lensCompare != 0) return lensCompare;

      final nameCompare = a.name.compareTo(b.name);
      if (nameCompare != 0) return nameCompare;

      return a.sensorOrientation.compareTo(b.sensorOrientation);
    });
    return ordered;
  }

  int _cameraPriority(CameraDescription camera) {
    final directionScore = switch (camera.lensDirection) {
      CameraLensDirection.back => 0,
      CameraLensDirection.external => 1,
      CameraLensDirection.front => 2,
    };

    final lensScore = switch (camera.lensType) {
      CameraLensType.wide => 0,
      CameraLensType.unknown => 1,
      CameraLensType.telephoto => 2,
      CameraLensType.ultraWide => 3,
    };

    return (directionScore * 10) + lensScore;
  }

  CameraDescription _resolvePreferredCamera(
    List<CameraDescription> cameras, {
    CameraDescription? preferredCamera,
  }) {
    final ordered = _orderedCameraOptions(cameras);
    if (preferredCamera != null) {
      for (final camera in ordered) {
        if (camera == preferredCamera || camera.name == preferredCamera.name) {
          return camera;
        }
      }
    }

    return ordered.first;
  }

  String _cameraBaseLabel(CameraDescription camera) {
    switch (camera.lensDirection) {
      case CameraLensDirection.back:
        switch (camera.lensType) {
          case CameraLensType.telephoto:
            return 'Rear Tele';
          case CameraLensType.ultraWide:
            return 'Rear Ultra';
          case CameraLensType.wide:
          case CameraLensType.unknown:
            return 'Rear Main';
        }
      case CameraLensDirection.front:
        return 'Front';
      case CameraLensDirection.external:
        return 'External';
    }
  }

  bool get _readyForTflite =>
      _modelReady && _labelsReady && _interpreter != null && _labels.isNotEmpty;

  String _cleanLabel(String raw) {
    final trimmed = raw.trim();
    final cleaned = trimmed.replaceFirst(RegExp(r'^[0-9]+\s*'), '').trim();
    return cleaned.isNotEmpty ? cleaned : trimmed;
  }

  Future<void> _initSpeciesModel() async {
    await Future.wait([_loadModel(), _loadLabels()]);
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _loadModel() async {
    try {
      _interpreter = await Interpreter.fromAsset('assets/model_unquant.tflite');
      _interpreter!.allocateTensors();
      _modelReady = true;
      debugPrint('Species model loaded.');
    } catch (e) {
      _modelReady = false;
      debugPrint('Species model load error: $e');
    }
  }

  Future<void> _loadLabels() async {
    try {
      final text = await rootBundle.loadString('assets/labels.txt');
      _labels = text
          .split('\n')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
      _labelsReady = _labels.isNotEmpty;
      debugPrint('Species labels loaded: ${_labels.length}');
    } catch (e) {
      _labelsReady = false;
      debugPrint('Species labels load error: $e');
    }
  }

  Future<void> _waitForSpeciesModelReady() async {
    if (_readyForTflite) return;
    const maxWaitMs = 10000;
    var waited = 0;
    while (!_readyForTflite && waited < maxWaitMs) {
      await Future.delayed(const Duration(milliseconds: 120));
      waited += 120;
    }
  }

  _ModelInputSpec _resolveInputSpec(Tensor tensor) {
    final shape = tensor.shape;
    final params = tensor.params;
    return _ModelInputSpec(
      width: shape.length >= 3 && shape[2] > 0 ? shape[2] : _inputSize,
      height: shape.length >= 2 && shape[1] > 0 ? shape[1] : _inputSize,
      channels: shape.isNotEmpty && shape.last > 0 ? shape.last : 3,
      type: tensor.type,
      scale: params.scale,
      zeroPoint: params.zeroPoint,
    );
  }

  List<_InferenceView> _buildInferenceViews(
    img.Image source,
    int width,
    int height,
  ) {
    final views = <_InferenceView>[];
    final sourceRatio = source.width / source.height;
    final targetRatio = width / height;

    void addView(img.Image image, double weight) {
      views.add(_InferenceView(image: image, weight: weight));
    }

    if ((sourceRatio - targetRatio).abs() < 0.03) {
      addView(
        img.copyResize(
          source,
          width: width,
          height: height,
          interpolation: img.Interpolation.average,
        ),
        1.20,
      );
    } else {
      addView(_resizeCover(source, width, height), 1.15);
      addView(_resizeContain(source, width, height), 0.80);
    }

    addView(
      _resizeFocusedCrop(source, width, height, cropScale: 0.88),
      1.10,
    );

    if ((source.width - source.height).abs() > 24) {
      addView(
        _resizeFocusedCrop(source, width, height, cropScale: 0.76),
        0.95,
      );
    }

    return views;
  }

  img.Image _resizeFocusedCrop(
    img.Image source,
    int width,
    int height, {
    double cropScale = 0.88,
  }) {
    final safeScale = cropScale.clamp(0.55, 1.0).toDouble();
    final targetRatio = width / height;
    final maxCropWidth = math.max(1, (source.width * safeScale).round()).toInt();
    final maxCropHeight = math.max(
      1,
      (source.height * safeScale).round(),
    ).toInt();

    var cropWidth = maxCropWidth;
    var cropHeight = math.max(1, (cropWidth / targetRatio).round()).toInt();

    if (cropHeight > maxCropHeight) {
      cropHeight = maxCropHeight;
      cropWidth = math.max(1, (cropHeight * targetRatio).round()).toInt();
    }

    cropWidth = cropWidth.clamp(1, source.width).toInt();
    cropHeight = cropHeight.clamp(1, source.height).toInt();

    final cropX = ((source.width - cropWidth) / 2)
        .round()
        .clamp(0, math.max(0, source.width - cropWidth))
        .toInt();
    final cropY = ((source.height - cropHeight) / 2)
        .round()
        .clamp(0, math.max(0, source.height - cropHeight))
        .toInt();

    final cropped = img.copyCrop(
      source,
      x: cropX,
      y: cropY,
      width: cropWidth,
      height: cropHeight,
    );

    return img.copyResize(
      cropped,
      width: width,
      height: height,
      interpolation: img.Interpolation.average,
    );
  }

  img.Image _resizeCover(img.Image source, int width, int height) {
    final sourceRatio = source.width / source.height;
    final targetRatio = width / height;

    var cropX = 0;
    var cropY = 0;
    var cropWidth = source.width;
    var cropHeight = source.height;

    if (sourceRatio > targetRatio) {
      cropWidth = math.max(1, (source.height * targetRatio).round()).toInt();
      cropX = ((source.width - cropWidth) / 2).round();
    } else if (sourceRatio < targetRatio) {
      cropHeight = math.max(1, (source.width / targetRatio).round()).toInt();
      cropY = ((source.height - cropHeight) / 2).round();
    }

    final cropped = img.copyCrop(
      source,
      x: cropX,
      y: cropY,
      width: cropWidth,
      height: cropHeight,
    );

    return img.copyResize(
      cropped,
      width: width,
      height: height,
      interpolation: img.Interpolation.average,
    );
  }

  img.Image _resizeContain(img.Image source, int width, int height) {
    final scale = math.min(width / source.width, height / source.height);
    final resizedWidth = math.max(1, (source.width * scale).round()).toInt();
    final resizedHeight = math.max(1, (source.height * scale).round()).toInt();
    final resized = img.copyResize(
      source,
      width: resizedWidth,
      height: resizedHeight,
      interpolation: img.Interpolation.average,
    );

    final canvas = img.Image(width: width, height: height);
    img.compositeImage(
      canvas,
      resized,
      dstX: ((width - resizedWidth) / 2).round(),
      dstY: ((height - resizedHeight) / 2).round(),
    );
    return canvas;
  }

  double _channelValue(img.Pixel pixel, int channelIndex) {
    if (channelIndex == 0) return pixel.r.toDouble();
    if (channelIndex == 1) return pixel.g.toDouble();
    return pixel.b.toDouble();
  }

  int _quantizeValue(double value, _ModelInputSpec spec) {
    final scale = spec.scale > 0 ? spec.scale : 1.0;
    final quantized = (value / scale).round() + spec.zeroPoint;

    switch (spec.type) {
      case TensorType.int8:
        return quantized.clamp(-128, 127).toInt();
      case TensorType.int16:
        return quantized.clamp(-32768, 32767).toInt();
      case TensorType.uint8:
        return quantized.clamp(0, 255).toInt();
      default:
        return quantized;
    }
  }

  Object _buildInterpreterInput(img.Image image, _ModelInputSpec spec) {
    final expectsFloat = spec.type == TensorType.float16 ||
        spec.type == TensorType.float32 ||
        spec.type == TensorType.float64;

    return List.generate(
      1,
      (_) => List.generate(
        spec.height,
        (y) => List.generate(
          spec.width,
          (x) {
            final pixel = image.getPixel(x, y);
            return List<num>.generate(spec.channels, (channelIndex) {
              final value = _channelValue(pixel, channelIndex);
              if (expectsFloat) {
                return (value - _mean) / _std;
              }
              return _quantizeValue(value, spec);
            }, growable: false);
          },
          growable: false,
        ),
        growable: false,
      ),
      growable: false,
    );
  }

  List<double> _readTensorValues(Tensor tensor) {
    final bytes = tensor.data;
    if (bytes.isEmpty) return const [];

    final byteData = ByteData.sublistView(bytes);
    final scale = tensor.params.scale;
    final zeroPoint = tensor.params.zeroPoint;

    switch (tensor.type) {
      case TensorType.float32:
        return List<double>.generate(
          bytes.lengthInBytes ~/ 4,
          (i) => byteData.getFloat32(i * 4, Endian.little),
          growable: false,
        );
      case TensorType.float64:
        return List<double>.generate(
          bytes.lengthInBytes ~/ 8,
          (i) => byteData.getFloat64(i * 8, Endian.little),
          growable: false,
        );
      case TensorType.int32:
        return List<double>.generate(
          bytes.lengthInBytes ~/ 4,
          (i) {
            final value = byteData.getInt32(i * 4, Endian.little);
            return scale > 0
                ? scale * (value - zeroPoint)
                : value.toDouble();
          },
          growable: false,
        );
      case TensorType.int16:
        return List<double>.generate(
          bytes.lengthInBytes ~/ 2,
          (i) {
            final value = byteData.getInt16(i * 2, Endian.little);
            return scale > 0
                ? scale * (value - zeroPoint)
                : value.toDouble();
          },
          growable: false,
        );
      case TensorType.int8:
        return List<double>.generate(
          bytes.lengthInBytes,
          (i) {
            final value = byteData.getInt8(i);
            return scale > 0
                ? scale * (value - zeroPoint)
                : value.toDouble();
          },
          growable: false,
        );
      case TensorType.uint8:
        return List<double>.generate(
          bytes.lengthInBytes,
          (i) {
            final value = bytes[i];
            return scale > 0
                ? scale * (value - zeroPoint)
                : value.toDouble();
          },
          growable: false,
        );
      default:
        return const [];
    }
  }

  List<double> _softmax(List<double> values) {
    if (values.isEmpty) return const [];

    final maxValue = values.reduce(math.max);
    final exponentials = values
        .map(
          (value) => math.exp(
            (value - maxValue).clamp(-60.0, 60.0).toDouble(),
          ),
        )
        .toList(growable: false);
    final total = exponentials.fold<double>(0, (sum, value) => sum + value);
    if (!total.isFinite || total <= 0) {
      return List<double>.filled(values.length, 1 / values.length);
    }

    return exponentials
        .map((value) => value / total)
        .toList(growable: false);
  }

  List<double> _normalizeScores(List<double> rawScores) {
    if (rawScores.isEmpty) return const [];

    final sanitized = rawScores
        .map((value) => value.isFinite ? value : 0.0)
        .toList(growable: false);
    final total = sanitized.fold<double>(0, (sum, value) => sum + value);
    final minValue = sanitized.reduce(math.min);
    final maxValue = sanitized.reduce(math.max);
    final looksLikeProbabilities =
        minValue >= 0 && maxValue <= 1.0 && total > 0.90 && total < 1.10;

    if (looksLikeProbabilities) {
      final safeTotal = total <= 0 ? 1.0 : total;
      return sanitized
          .map((value) => value < 0 ? 0.0 : value / safeTotal)
          .toList(growable: false);
    }

    return _softmax(sanitized);
  }

  List<double> _extractNormalizedScores(Tensor tensor, int outputCount) {
    final values = _readTensorValues(tensor);
    if (values.isEmpty) return const [];

    final usableLength = math.min(outputCount, values.length);
    if (usableLength <= 0) return const [];

    return _normalizeScores(
      values.take(usableLength).toList(growable: false),
    );
  }

  _SpeciesPrediction? _predictionFromScores(
    List<double> scores,
    List<String> labels,
  ) {
    final usableLength = math.min(scores.length, labels.length);
    if (usableLength <= 0) return null;

    var bestIdx = 0;
    var bestScore = scores[0];
    var secondScore = 0.0;

    for (var i = 1; i < usableLength; i++) {
      final score = scores[i];
      if (score > bestScore) {
        secondScore = bestScore;
        bestScore = score;
        bestIdx = i;
      } else if (score > secondScore) {
        secondScore = score;
      }
    }

    final label = _cleanLabel(labels[bestIdx]);
    if (label.isEmpty) return null;

    final margin = math.max(0.0, bestScore - secondScore);
    return _SpeciesPrediction(
      label: label,
      confidence: bestScore,
      margin: margin,
      agreement: 1.0,
      candidates: _topSpeciesCandidates(scores, labels),
      reliable:
          _isKnownSpeciesLabel(label) &&
          bestScore >= _minSpeciesConfidence &&
          margin >= _minSpeciesMargin,
    );
  }

  List<_SpeciesCandidate> _topSpeciesCandidates(
    List<double> scores,
    List<String> labels, {
    int limit = 5,
  }) {
    final usableLength = math.min(scores.length, labels.length);
    if (usableLength <= 0 || limit <= 0) return const [];

    final ranked = List<int>.generate(usableLength, (index) => index)
      ..sort((a, b) => scores[b].compareTo(scores[a]));

    final top = <_SpeciesCandidate>[];
    for (final index in ranked.take(limit)) {
      final label = _cleanLabel(labels[index]);
      if (label.isEmpty) continue;
      top.add(_SpeciesCandidate(label: label, confidence: scores[index]));
    }
    return top;
  }

  bool _acceptLocalPredictionImmediately(
    _SpeciesPrediction prediction, {
    double? sharpness,
  }) {
    final sharpEnough =
        sharpness == null || sharpness >= (_minimumSharpnessScore - 1.0);
    return _isKnownSpeciesLabel(prediction.label) &&
        prediction.confidence >= _minImmediateSpeciesConfidence &&
        prediction.margin >= _minImmediateSpeciesMargin &&
        prediction.agreement >= _minImmediateSpeciesAgreement &&
        sharpEnough;
  }

  bool _predictionContainsCandidate(
    _SpeciesPrediction prediction,
    String label, {
    int limit = 3,
  }) {
    final normalized = _normalizeToken(label);
    if (normalized.isEmpty) return false;

    return prediction.candidates.take(limit).any(
      (candidate) => _normalizeToken(candidate.label) == normalized,
    );
  }

  bool _sameSpeciesLabel(String first, String second) {
    final firstNormalized = _normalizeToken(first);
    final secondNormalized = _normalizeToken(second);
    return firstNormalized.isNotEmpty && firstNormalized == secondNormalized;
  }

  bool _isUnknownDetectionLabel(String label) {
    final normalized = _normalizeToken(label);
    return normalized.isEmpty ||
        normalized == 'unknown' ||
        normalized.startsWith('unknown ') ||
        normalized.contains('unidentified');
  }

  List<String> _productionLookupCandidates(String raw) {
    final cleaned = _cleanLabel(raw);
    if (cleaned.isEmpty) return const [];

    final lower = cleaned.toLowerCase();
    final withoutParen = cleaned.split('(').first.trim();
    final withoutComma = cleaned.split(',').first.trim();
    final candidates = <String>{
      lower,
      lower.replaceAll(' ', ''),
      lower.replaceAll(' ', '-'),
      lower.replaceAll(' ', '_'),
      _normalizeToken(cleaned),
      _normalizeToken(cleaned).replaceAll(' ', '-'),
      withoutParen.toLowerCase(),
      withoutComma.toLowerCase(),
      _normalizeToken(withoutParen).replaceAll(' ', '-'),
      _normalizeToken(withoutComma).replaceAll(' ', '-'),
    };

    return candidates.where((item) => item.trim().isNotEmpty).toList();
  }

  bool _productionDocMatches(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
    Set<String> normalizedCandidates,
  ) {
    final data = doc.data();
    final values = <String>[
      doc.id,
      (data['englishName'] ?? '').toString(),
      (data['name'] ?? '').toString(),
      (data['scientificName'] ?? '').toString(),
      (data['scientific_name'] ?? '').toString(),
      (data['localName'] ?? '').toString(),
      (data['local_name'] ?? '').toString(),
      (data['commonName'] ?? '').toString(),
    ];

    for (final value in values) {
      final normalized = _normalizeToken(value);
      if (normalized.isEmpty) continue;
      if (normalizedCandidates.contains(normalized)) return true;
    }
    return false;
  }

  Future<bool> _isSpeciesInFishProduction(String label) async {
    final cleaned = _cleanLabel(label);
    if (cleaned.isEmpty || _isUnknownDetectionLabel(cleaned)) return false;

    final stats = FirebaseFirestore.instance.collection('marine_life_stats');
    final candidates = _productionLookupCandidates(cleaned);
    final normalizedCandidates = candidates
        .map(_normalizeToken)
        .where((item) => item.isNotEmpty)
        .toSet();

    try {
      for (final docId in candidates) {
        final doc = await stats.doc(docId).get();
        if (doc.exists) return true;
      }

      final exactValues = <String>{
        cleaned,
        cleaned.split('(').first.trim(),
        cleaned.split(',').first.trim(),
      }.where((item) => item.isNotEmpty).toList();
      for (final field in const [
        'englishName',
        'name',
        'scientificName',
        'scientific_name',
        'localName',
        'local_name',
      ]) {
        for (final value in exactValues) {
          final match = await stats
              .where(field, isEqualTo: value)
              .limit(1)
              .get();
          if (match.docs.isNotEmpty) return true;
        }
      }

      final snapshot = await stats.limit(300).get();
      return snapshot.docs.any(
        (doc) => _productionDocMatches(doc, normalizedCandidates),
      );
    } on FirebaseException catch (e) {
      debugPrint(
        'Fish production lookup failed: ${e.message ?? e.code}. '
        'Skipping unusual auto-report.',
      );
      return true;
    } catch (e) {
      debugPrint('Fish production lookup failed: $e');
      return true;
    }
  }

  String _formatManilaDateTime(DateTime value) {
    String two(int input) => input.toString().padLeft(2, '0');
    return '${value.year}-${two(value.month)}-${two(value.day)} '
        '${two(value.hour)}:${two(value.minute)}:${two(value.second)}';
  }

  Future<Map<String, dynamic>> _tryBuildAutoLocationFields() async {
    const fallback = {
      'location': 'Auto-generated from AI detection; location unavailable',
      'locationCaptured': false,
    };
    if (kIsWeb) return fallback;

    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return fallback;

      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever ||
          permission == LocationPermission.unableToDetermine) {
        return fallback;
      }

      Position? position;
      try {
        position = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: Duration(seconds: 8),
          ),
        ).timeout(const Duration(seconds: 10));
      } catch (_) {
        position = await Geolocator.getLastKnownPosition();
      }

      if (position == null) return fallback;
      final latitude = position.latitude;
      final longitude = position.longitude;
      return {
        'location':
            'Latitude: ${latitude.toStringAsFixed(5)}, Longitude: ${longitude.toStringAsFixed(5)}',
        'latitude': latitude,
        'longitude': longitude,
        'locationCaptured': true,
      };
    } catch (e) {
      debugPrint('Auto sighting location capture failed: $e');
      return fallback;
    }
  }

  Future<Map<String, String?>> _uploadAutoSightingImage(
    User user,
    File imageFile,
  ) async {
    if (!await imageFile.exists()) {
      return {'imageUrl': null, 'storagePath': null};
    }

    final storagePath =
        'sightings/${user.uid}/auto_detection/${DateTime.now().millisecondsSinceEpoch}.jpg';
    final ref = FirebaseStorage.instance.ref().child(storagePath);
    await ref.putFile(
      imageFile,
      SettableMetadata(contentType: 'image/jpeg'),
    );
    return {
      'imageUrl': await ref.getDownloadURL(),
      'storagePath': storagePath,
    };
  }

  Future<String?> _autoReportSightingIfNeeded({
    required File imageFile,
    required String predictedLabel,
    required double? score,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) return null;

    final isUnknown = _isUnknownDetectionLabel(predictedLabel);
    final isUnusualInProduction = isUnknown
        ? false
        : !(await _isSpeciesInFishProduction(predictedLabel));
    if (!isUnknown && !isUnusualInProduction) return null;

    final reason = isUnknown
        ? 'unknown_species'
        : 'unusual_in_fish_production';
    String? imageUrl;
    String? storagePath;
    String? uploadError;

    try {
      final uploaded = await _uploadAutoSightingImage(user, imageFile);
      imageUrl = uploaded['imageUrl'];
      storagePath = uploaded['storagePath'];
    } catch (e) {
      uploadError = e.toString();
      debugPrint('Auto sighting image upload failed: $e');
    }

    final submittedTime = DateTime.now().toUtc().add(const Duration(hours: 8));
    final formatted = _formatManilaDateTime(submittedTime);
    final locationFields = await _tryBuildAutoLocationFields();
    final species = isUnknown ? 'Unknown species' : predictedLabel.trim();

    await FirebaseFirestore.instance.collection('sightings').add({
      'userId': user.uid,
      'species': species.isEmpty ? 'Unknown species' : species,
      'speciesProvided': !isUnknown,
      'isUnknownSpecies': isUnknown,
      'isUnusualInFishProduction': isUnusualInProduction,
      'autoReported': true,
      'autoReportReason': reason,
      'sourceModule': 'fish_detection',
      'sourceFeature': 'camera_fish_detection',
      'confidence': score,
      ...locationFields,
      'notes': isUnknown
          ? 'Automatically reported because AI could not recognize the detected marine species.'
          : 'Automatically reported because the detected species is not listed in Fish Production records.',
      'sightingAt': Timestamp.fromDate(submittedTime),
      'sightingDateTimeString': formatted,
      'reportedAt': Timestamp.fromDate(submittedTime),
      'reportedTimeString': formatted,
      'manilaDateTime': Timestamp.fromDate(submittedTime),
      'manilaTimeString': formatted,
      'imageUrl': imageUrl,
      'imageUrls': imageUrl == null ? <String>[] : <String>[imageUrl],
      'storagePath': storagePath,
      if (uploadError != null) 'imageUploadError': uploadError,
      'videoUrl': null,
      'videoUrls': const <String>[],
      'hasVideo': false,
      'status': 'pending',
      'actionStatus': 'pending',
      'createdAt': FieldValue.serverTimestamp(),
    });

    return reason;
  }

  Future<ImageLabel?> _bestMarineLabelFromMlKit(File imageFile) async {
    if (kIsWeb || !(Platform.isAndroid || Platform.isIOS)) {
      return null;
    }

    final imageLabeler = ImageLabeler(
      options: ImageLabelerOptions(confidenceThreshold: 0.2),
    );

    try {
      if (!await imageFile.exists()) {
        debugPrint('ML Kit skipped missing image file: ${imageFile.path}');
        return null;
      }
      final inputImage = InputImage.fromFile(imageFile);
      final labels = await imageLabeler.processImage(inputImage);
      return _bestMarineLabel(labels);
    } on PlatformException catch (e) {
      debugPrint('ML Kit image label fallback: ${e.code} ${e.message}');
      return null;
    } on FileSystemException catch (e) {
      debugPrint('ML Kit image file fallback: $e');
      return null;
    } catch (e) {
      debugPrint('ML Kit image label fallback: $e');
      return null;
    } finally {
      try {
        await imageLabeler.close();
      } on MissingPluginException {
        // Ignore close failures when plugin is not registered.
      }
    }
  }

  Future<_SpeciesPrediction?> _predictWithTflite(File imageFile) async {
    await _waitForSpeciesModelReady();
    if (!_readyForTflite) return null;

    final interpreter = _interpreter!;
    final labels = _labels.map(_cleanLabel).toList(growable: false);

    final imageBytes = await imageFile.readAsBytes();
    final decoded = img.decodeImage(imageBytes);
    if (decoded == null) return null;

    final oriented = img.bakeOrientation(decoded);
    final inputSpec = _resolveInputSpec(interpreter.getInputTensor(0));
    final outputTensor = interpreter.getOutputTensor(0);
    final outputCount = math.min(outputTensor.numElements(), labels.length);
    if (outputCount <= 0 || inputSpec.channels <= 0) return null;

    final views = _buildInferenceViews(
      oriented,
      inputSpec.width,
      inputSpec.height,
    );
    if (views.isEmpty) return null;

    final accumulatedScores = List<double>.filled(outputCount, 0.0);
    var totalWeight = 0.0;
    final viewPredictions = <_WeightedPrediction>[];

    for (final view in views) {
      final input = _buildInterpreterInput(view.image, inputSpec);
      interpreter.runInference([input]);
      final normalizedScores = _extractNormalizedScores(outputTensor, outputCount);
      if (normalizedScores.isEmpty) continue;

      final viewPrediction = _predictionFromScores(normalizedScores, labels);
      if (viewPrediction != null) {
        viewPredictions.add(
          _WeightedPrediction(prediction: viewPrediction, weight: view.weight),
        );
      }

      for (var i = 0; i < outputCount; i++) {
        accumulatedScores[i] += normalizedScores[i] * view.weight;
      }
      totalWeight += view.weight;
    }

    if (totalWeight <= 0) return null;

    final averagedScores = accumulatedScores
        .map((value) => value / totalWeight)
        .toList(growable: false);
    final averagedPrediction = _predictionFromScores(averagedScores, labels);
    if (averagedPrediction == null) return null;

    var matchingWeight = 0.0;
    for (final item in viewPredictions) {
      if (_normalizeToken(item.prediction.label) ==
          _normalizeToken(averagedPrediction.label)) {
        matchingWeight += item.weight;
      }
    }

    final agreement = totalWeight > 0 ? matchingWeight / totalWeight : 0.0;
    return _SpeciesPrediction(
      label: averagedPrediction.label,
      confidence: averagedPrediction.confidence,
      margin: averagedPrediction.margin,
      agreement: agreement,
      candidates: _topSpeciesCandidates(averagedScores, labels),
      reliable:
          _isKnownSpeciesLabel(averagedPrediction.label) &&
          averagedPrediction.confidence >= _minSpeciesConfidence &&
          averagedPrediction.margin >= _minSpeciesMargin &&
          agreement >= _minSpeciesAgreement,
    );
  }

  bool _isKnownSpeciesLabel(String label) {
    final normalized = _cleanLabel(label).toLowerCase();
    if (normalized.isEmpty) return false;
    return _labels.any((item) => _cleanLabel(item).toLowerCase() == normalized);
  }

  String _normalizeToken(String value) =>
      value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();

  String? _canonicalSpeciesFromText(String raw) {
    final cleaned = _cleanLabel(raw);
    if (cleaned.isEmpty) return null;

    final normalized = _normalizeToken(cleaned);
    if (normalized.isEmpty) return null;

    for (final label in _labels) {
      final normalizedLabel = _normalizeToken(_cleanLabel(label));
      if (normalizedLabel == normalized) {
        return _cleanLabel(label);
      }
    }

    final rawTokens = normalized
        .split(' ')
        .where((token) => token.length >= 3)
        .toSet();
    if (rawTokens.isEmpty) return null;

    String? best;
    var bestScore = 0.0;
    for (final label in _labels) {
      final normalizedLabel = _normalizeToken(_cleanLabel(label));
      final labelTokens = normalizedLabel
          .split(' ')
          .where((token) => token.length >= 3)
          .toSet();
      if (labelTokens.isEmpty) continue;

      final overlap = labelTokens.intersection(rawTokens).length;
      if (overlap == 0) continue;

      final coverage = overlap / labelTokens.length;
      if (coverage > bestScore) {
        bestScore = coverage;
        best = _cleanLabel(label);
      }
    }

    return bestScore >= 0.5 ? best : null;
  }

  double? _toConfidence(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    final parsed = double.tryParse(value.toString());
    return parsed;
  }

  img.Image _buildCloudFocusCrop(
    img.Image source, {
    double cropScale = 0.78,
  }) {
    final safeScale = cropScale.clamp(0.55, 1.0).toDouble();
    final cropWidth = math.max(1, (source.width * safeScale).round()).toInt();
    final cropHeight = math.max(1, (source.height * safeScale).round()).toInt();
    final cropX = ((source.width - cropWidth) / 2)
        .round()
        .clamp(0, math.max(0, source.width - cropWidth))
        .toInt();
    final cropY = ((source.height - cropHeight) / 2)
        .round()
        .clamp(0, math.max(0, source.height - cropHeight))
        .toInt();

    return img.copyCrop(
      source,
      x: cropX,
      y: cropY,
      width: cropWidth,
      height: cropHeight,
    );
  }

  Future<_SpeciesPrediction?> _resolveSpeciesWithCloudVision(
    File imageFile, {
    List<_SpeciesCandidate> localHints = const [],
  }) async {
    try {
      final bytes = await imageFile.readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded == null) return null;

      final oriented = img.bakeOrientation(decoded);
      final resized = oriented.width > 1024
          ? img.copyResize(oriented, width: 1024)
          : oriented;
      var jpg = img.encodeJpg(resized, quality: 80);
      if (jpg.length > 1500000) {
        jpg = img.encodeJpg(resized, quality: 68);
      }

      final focused = _buildCloudFocusCrop(oriented);
      final focusedResized = focused.width > 900
          ? img.copyResize(focused, width: 900)
          : focused;
      var focusedJpg = img.encodeJpg(focusedResized, quality: 82);
      if (focusedJpg.length > 1200000) {
        focusedJpg = img.encodeJpg(focusedResized, quality: 70);
      }

      final payload = <String, dynamic>{
        'imageBase64': base64Encode(jpg),
        'additionalImagesBase64': [base64Encode(focusedJpg)],
        'mimeType': 'image/jpeg',
        if (_labels.isNotEmpty)
          'candidateSpecies': _labels.map(_cleanLabel).toList(),
        if (localHints.isNotEmpty)
          'localHints': localHints
              .take(5)
              .map((candidate) => candidate.toJson())
              .toList(growable: false),
      };

      const endpointPaths = <String>[
        'ai/detect/fish',
        'ai-detect-fish',
        'aiDetectFish',
      ];

      for (final path in endpointPaths) {
        final uris = functionUriCandidates(path);
        for (final uri in uris) {
          try {
            final response = await http
                .post(
                  uri,
                  headers: const {'Content-Type': 'application/json'},
                  body: jsonEncode(payload),
                )
                .timeout(const Duration(seconds: 22));

            if (response.statusCode != 200) continue;

            final decodedBody = jsonDecode(response.body);
            if (decodedBody is! Map) continue;
            final body = Map<String, dynamic>.from(
              decodedBody.cast<String, dynamic>(),
            );

            final species = (body['species'] ?? body['label'] ?? '')
                .toString()
                .trim();
            if (species.isEmpty) continue;
            if (species.toLowerCase().startsWith('unknown')) continue;

            final canonical = _canonicalSpeciesFromText(species) ?? species;
            if (canonical.trim().isEmpty) continue;

            final confidence = _toConfidence(body['confidence']) ?? 0.35;
            return _SpeciesPrediction(
              label: canonical,
              confidence: confidence,
              margin: 1.0,
              agreement: 1.0,
              candidates: localHints,
              reliable:
                  _isSpecificDetectionLabel(canonical) &&
                  confidence >= _minFallbackSpeciesConfidence,
            );
          } catch (_) {
            // Try the next URI/path candidate.
          }
        }
      }
    } catch (_) {
      return null;
    }

    return null;
  }

  @override
  void initState() {
    super.initState();
    _pendingLaunch = widget.launchMode;

    _initSpeciesModel();
    _initializeCamera();

    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeAutoLaunch());
  }

  // -------------------------
  // CAMERA
  // -------------------------

  Future<void> _initializeCamera({CameraDescription? preferredCamera}) async {
    setState(() {
      _cameraInitializing = true;
      _cameraError = null;
    });

    try {
      final available = _orderedCameraOptions(
        (await availableCameras()).where(_isSupportedDetectionCamera),
      );
      if (available.isEmpty) {
        throw CameraException(
          'NoCamera',
          'No rear or external cameras found on device',
        );
      }

      final selectedCamera = _resolvePreferredCamera(
        available,
        preferredCamera: preferredCamera ?? _selectedCamera,
      );
      _selectedCamera = selectedCamera;

      await _cameraController?.dispose();
      _cameraController = CameraController(
        selectedCamera,
        // Use highest available resolution so saved photos look closer to the real camera feed.
        ResolutionPreset.max,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );

      await _cameraController!.initialize();
      try {
        await _cameraController!.setFocusMode(FocusMode.auto);
      } catch (_) {
        // Some devices do not expose focus controls.
      }
      try {
        await _cameraController!.setExposureMode(ExposureMode.auto);
      } catch (_) {
        // Some devices do not expose exposure controls.
      }
      await _primeCameraForDetection();

      if (!mounted) return;
      setState(() {
        _cameraInitializing = false;
        _selectedCamera = selectedCamera;
      });
      _maybeAutoLaunch();
    } catch (e) {
      debugPrint("Camera init error: $e");
      if (!mounted) return;
      setState(() {
        _cameraInitializing = false;
        _cameraError =
            'Unable to start the camera. Please check permissions and try again.';
      });
    }
  }

  Future<void> _primeCameraForDetection() async {
    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) return;

    try {
      await controller.setFocusMode(FocusMode.auto);
    } catch (_) {
      // Some devices do not expose focus controls.
    }

    try {
      if (controller.value.focusPointSupported) {
        await controller.setFocusPoint(const Offset(0.5, 0.5));
      }
    } catch (_) {
      // Ignore unsupported focus point controls.
    }

    try {
      if (controller.value.exposurePointSupported) {
        await controller.setExposurePoint(const Offset(0.5, 0.5));
      }
    } catch (_) {
      // Ignore unsupported exposure point controls.
    }

    await Future.delayed(_cameraCaptureSettleDelay);
  }

  Future<File> _writeStableDetectionImage(
    Uint8List bytes, {
    required String sourceName,
  }) async {
    if (bytes.isEmpty) {
      throw const FileSystemException('Selected image is empty.');
    }

    Uint8List outputBytes = bytes;
    final decoded = img.decodeImage(bytes);
    if (decoded != null) {
      final oriented = img.bakeOrientation(decoded);
      final longestSide = math.max(oriented.width, oriented.height);
      final normalized = longestSide > 1800
          ? img.copyResize(
              oriented,
              width: oriented.width >= oriented.height ? 1800 : null,
              height: oriented.height > oriented.width ? 1800 : null,
              interpolation: img.Interpolation.average,
            )
          : oriented;
      outputBytes = Uint8List.fromList(img.encodeJpg(normalized, quality: 90));
    }

    final dir = await Directory.systemTemp.createTemp('seaguard_detection_');
    final safeName = sourceName
        .replaceAll(RegExp(r'[^a-zA-Z0-9._-]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    final fileName = safeName.isEmpty
        ? 'detection_${DateTime.now().microsecondsSinceEpoch}.jpg'
        : '${DateTime.now().microsecondsSinceEpoch}_$safeName.jpg';
    final file = File('${dir.path}${Platform.pathSeparator}$fileName');
    await file.writeAsBytes(outputBytes, flush: true);
    return file;
  }

  Future<File> _stableDetectionFileFromXFile(XFile picked) async {
    final bytes = await picked.readAsBytes();
    return _writeStableDetectionImage(bytes, sourceName: picked.name);
  }

  Future<File> _stableDetectionFileFromFile(File file) async {
    if (!await file.exists()) {
      throw FileSystemException('Image file no longer exists.', file.path);
    }
    final bytes = await file.readAsBytes();
    return _writeStableDetectionImage(
      bytes,
      sourceName: file.uri.pathSegments.isEmpty
          ? 'capture'
          : file.uri.pathSegments.last,
    );
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);

    if (picked != null) {
      File file;
      try {
        file = await _stableDetectionFileFromXFile(picked);
      } catch (e) {
        debugPrint('Selected image prepare error: $e');
        if (!mounted) return;
        setState(() {
          _resultText =
              'Unable to read the selected image. Please choose another photo.';
        });
        return;
      }
      setState(() {
        _image = file;
        _resultText = null;
      });

      await _runModelAndNavigate(file);
    }
  }

  Future<void> _captureImage() async {
    if (_cameraInitializing) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Starting camera...')));
      return;
    }

    if (_cameraError != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_cameraError!)));
      await _initializeCamera();
      return;
    }

    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      await _initializeCamera();
      if (!mounted) return;
      if (_cameraController == null ||
          !_cameraController!.value.isInitialized) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Camera not available right now.')),
        );
        return;
      }
    }

    final imageFile = await Navigator.push<File?>(
      context,
      MaterialPageRoute(
        builder: (context) =>
            CameraScreen(cameraController: _cameraController!),
      ),
    );

    if (imageFile != null) {
      File file;
      try {
        file = await _stableDetectionFileFromFile(imageFile);
      } catch (e) {
        debugPrint('Captured image prepare error: $e');
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Unable to read this capture. Please retake it.'),
          ),
        );
        return;
      }
      setState(() {
        _image = file;
        _resultText = null;
      });

      await _runModelAndNavigate(file, fromCamera: true);
    }
  }

  // -------------------------
  // ONE SINGLE FLOW:
  // 1) run model
  // 2) navigate directly to details
  // -------------------------

  Future<void> _runModelAndNavigate(
    File imageFile, {
    bool fromCamera = false,
  }) async {
    setState(() {
      _isLoading = true;
      _resultText = null;
    });
    final loadingDelay = Future<void>.delayed(appLoadingDelay);

    try {
      String predictedLabel = 'Unknown sea creature';
      double? score;
      final imageSharpness = await _measureImageSharpness(imageFile);
      final localPrediction = await _predictWithTflite(imageFile);
      if (localPrediction != null) {
        debugPrint(
          'Local species guess: ${localPrediction.label} '
          '(confidence=${localPrediction.confidence.toStringAsFixed(3)}, '
          'margin=${localPrediction.margin.toStringAsFixed(3)}, '
          'agreement=${localPrediction.agreement.toStringAsFixed(3)}, '
          'reliable=${localPrediction.reliable})',
        );
      }

      ImageLabel? marineHint;
      final shouldAcceptLocal =
          localPrediction != null &&
          _acceptLocalPredictionImmediately(
            localPrediction,
            sharpness: imageSharpness,
          );

      if (shouldAcceptLocal) {
        predictedLabel = localPrediction.label;
        score = localPrediction.confidence;
      } else {
        final marineHintFuture = _bestMarineLabelFromMlKit(imageFile);
        final cloudPredictionFuture = _resolveSpeciesWithCloudVision(
          imageFile,
          localHints: localPrediction?.candidates ?? const [],
        );
        marineHint = await marineHintFuture;
        final cloudPrediction = await cloudPredictionFuture;
        final localLooksUsable =
            localPrediction != null &&
            _isKnownSpeciesLabel(localPrediction.label) &&
            (localPrediction.reliable ||
                (localPrediction.confidence >= _minFallbackSpeciesConfidence &&
                    localPrediction.agreement >= _minFallbackSpeciesAgreement));
        final cloudMatchesLocal =
            cloudPrediction != null &&
            localPrediction != null &&
            (_sameSpeciesLabel(cloudPrediction.label, localPrediction.label) ||
                _predictionContainsCandidate(
                  localPrediction,
                  cloudPrediction.label,
                ));

        if (cloudPrediction != null &&
            _isSpecificDetectionLabel(cloudPrediction.label) &&
            cloudPrediction.confidence >= _minCloudSpeciesConfidence &&
            (localPrediction == null ||
                !localPrediction.reliable ||
                cloudMatchesLocal ||
                cloudPrediction.confidence >=
                    localPrediction.confidence + _minCloudOverrideDelta)) {
          predictedLabel = cloudPrediction.label.trim();
          score = cloudPrediction.confidence;
        } else if (localLooksUsable &&
            (cloudPrediction == null ||
                !_isSpecificDetectionLabel(cloudPrediction.label) ||
                cloudPrediction.confidence < _minCloudSpeciesConfidence)) {
          predictedLabel = localPrediction.label;
          score = localPrediction.confidence;
        } else if (marineHint != null &&
            marineHint.label.trim().isNotEmpty) {
          predictedLabel = marineHint.label.trim();
          score = marineHint.confidence;
        }
      }

      if (!_isSpecificDetectionLabel(predictedLabel) &&
          !_isKnownSpeciesLabel(predictedLabel)) {
        predictedLabel = 'Unknown sea creature';
        score = score ?? 0;
      }

      final user = FirebaseAuth.instance.currentUser;
      final canUploadInDetails = user != null && !user.isAnonymous;
      String? autoReportReason;
      if (fromCamera) {
        try {
          autoReportReason = await _autoReportSightingIfNeeded(
            imageFile: imageFile,
            predictedLabel: predictedLabel,
            score: score,
          );
        } catch (e) {
          debugPrint('Auto marine sighting report failed: $e');
        }
      }

      await loadingDelay;
      if (!mounted) return;
      setState(() => _isLoading = false);
      if (autoReportReason != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              autoReportReason == 'unknown_species'
                  ? 'Unknown species automatically sent to Marine Sightings.'
                  : 'Unusual species automatically sent to Marine Sightings.',
            ),
          ),
        );
      }

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => FishDetailsPage(
            fishName: predictedLabel,
            predictionScore: score,
            capturedImage: imageFile,
            skipUpload: !canUploadInDetails,
          ),
        ),
      );
    } on MissingPluginException {
      await loadingDelay;
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _resultText =
            'ML Kit plugin is not initialized. Do a full restart and run on Android/iOS.';
      });
    } catch (e) {
      debugPrint("Inference/navigation error: $e");
      await loadingDelay;
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _resultText = "Error: $e";
      });
    }
  }

  void _maybeAutoLaunch() {
    if (_pendingLaunch == null) return;

    if (_pendingLaunch == DetectionLaunchMode.gallery) {
      _pendingLaunch = null;
      _pickImage();
      return;
    }

    if (_pendingLaunch == DetectionLaunchMode.camera &&
        _cameraController != null &&
        _cameraController!.value.isInitialized &&
        _cameraError == null &&
        !_cameraInitializing) {
      _pendingLaunch = null;
      _captureImage();
    }
  }

  @override
  void dispose() {
    _interpreter?.close();
    _cameraController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final padding = Responsive.pagePadding(context);
    final maxWidth = Responsive.maxContentWidth(context);
    final isBusy = _isLoading;

    return Scaffold(
      backgroundColor: const Color(0xFFF7FBFF),
      appBar: AppBar(
        title: const Text(
          'AI Detection',
          style: TextStyle(
            color: Color(0xFF102A43),
            fontSize: 27,
            fontWeight: FontWeight.w800,
            fontFamily: 'serif',
          ),
        ),
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        foregroundColor: const Color(0xFF102A43),
      ),
      bottomNavigationBar: CustomBottomNavBar(
        currentIndex: _selectedIndex,
        onTap: (i) => setState(() => _selectedIndex = i),
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFEAF4FF), Color(0xFFF8FCFF)],
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
                  padding,
                  padding,
                  padding,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color(0xFF0E3C66), Color(0xFF1E6FA7)],
                        ),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x2B0E3C66),
                            blurRadius: 18,
                            offset: Offset(0, 9),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(13),
                            ),
                            child: const Icon(
                              Icons.auto_awesome_rounded,
                              color: Colors.white,
                              size: 23,
                            ),
                          ),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Smart Species Scan',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontFamily: 'serif',
                                    fontSize: 19,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                SizedBox(height: 4),
                                Text(
                                  'Take a photo or upload from gallery for quick AI identification.',
                                  style: TextStyle(
                                    color: Color(0xFFE4F0FC),
                                    fontSize: 12.5,
                                    height: 1.32,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    GestureDetector(
                      onTap: isBusy ? null : _pickImage,
                      child: Container(
                        width: double.infinity,
                        clipBehavior: Clip.antiAlias,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.94),
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(color: const Color(0xFFCFE0F0)),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x210F2D4A),
                              blurRadius: 14,
                              offset: Offset(0, 8),
                            ),
                          ],
                        ),
                        child: AspectRatio(
                          aspectRatio: 4 / 3,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              if (_image == null)
                                const DecoratedBox(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                      colors: [
                                        Color(0xFFD9E8F7),
                                        Color(0xFFC3D8ED),
                                      ],
                                    ),
                                  ),
                                  child: Center(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.image_search_rounded,
                                          size: 76,
                                          color: Color(0xFF3D658A),
                                        ),
                                        SizedBox(height: 10),
                                        Text(
                                          'Tap to add a fish image',
                                          style: TextStyle(
                                            color: Color(0xFF244664),
                                            fontSize: 14.2,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                )
                              else
                                Image.file(_image!, fit: BoxFit.cover),
                              Positioned(
                                left: 12,
                                right: 12,
                                bottom: 12,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(
                                      0xFF0F2D4A,
                                    ).withValues(alpha: 0.70),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(
                                        Icons.touch_app_rounded,
                                        color: Colors.white,
                                        size: 16,
                                      ),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Text(
                                          _image == null
                                              ? 'Select image from gallery'
                                              : 'Tap to choose a different image',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 12.5,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
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
                    const SizedBox(height: 12),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final compact = constraints.maxWidth < 420;
                        final buttonWidth = compact
                            ? constraints.maxWidth
                            : (constraints.maxWidth - 8) / 2;
                        return Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            SizedBox(
                              width: buttonWidth,
                              height: 48,
                              child: FilledButton.icon(
                                onPressed: isBusy ? null : _captureImage,
                                style: FilledButton.styleFrom(
                                  backgroundColor: const Color(0xFF124F8A),
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  textStyle: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                icon: const Icon(Icons.camera_alt_rounded),
                                label: const Text('Camera Scan'),
                              ),
                            ),
                            SizedBox(
                              width: buttonWidth,
                              height: 48,
                              child: OutlinedButton.icon(
                                onPressed: isBusy ? null : _pickImage,
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: const Color(0xFF124F8A),
                                  backgroundColor: Colors.white.withValues(
                                    alpha: 0.85,
                                  ),
                                  side: const BorderSide(
                                    color: Color(0xFFB7CCE1),
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  textStyle: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                icon: const Icon(Icons.photo_library_rounded),
                                label: const Text('Gallery'),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 12),
                    if (_cameraError != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFECEB),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: const Color(0xFFF3C2BE)),
                          ),
                          child: Text(
                            _cameraError!,
                            style: const TextStyle(
                              color: Color(0xFF8A2E2E),
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    if (isBusy)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.90),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: const Color(0xFFCFE0F0)),
                          ),
                          child: const Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  SizedBox(
                                    height: 16,
                                    width: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                                  SizedBox(width: 8),
                                  Text(
                                    'Processing image...',
                                    style: TextStyle(
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF102A43),
                                    ),
                                  ),
                                ],
                              ),
                              SizedBox(height: 10),
                              ClipRRect(
                                borderRadius: BorderRadius.all(
                                  Radius.circular(999),
                                ),
                                child: LinearProgressIndicator(minHeight: 5),
                              ),
                            ],
                          ),
                        ),
                      )
                    else if (_resultText != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.9),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: const Color(0xFFCFE0F0)),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                _resultText!.startsWith('Error')
                                    ? Icons.error_outline_rounded
                                    : Icons.info_outline_rounded,
                                color: _resultText!.startsWith('Error')
                                    ? const Color(0xFFB33A3A)
                                    : const Color(0xFF165E9A),
                                size: 18,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _resultText!,
                                  style: const TextStyle(
                                    color: Color(0xFF2A3E52),
                                    fontSize: 12.9,
                                    fontWeight: FontWeight.w600,
                                    height: 1.36,
                                  ),
                                ),
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
      ),
    );
  }
}

class _SpeciesPrediction {
  const _SpeciesPrediction({
    required this.label,
    required this.confidence,
    required this.margin,
    required this.agreement,
    this.candidates = const [],
    required this.reliable,
  });

  final String label;
  final double confidence;
  final double margin;
  final double agreement;
  final List<_SpeciesCandidate> candidates;
  final bool reliable;
}

class _SpeciesCandidate {
  const _SpeciesCandidate({required this.label, required this.confidence});

  final String label;
  final double confidence;

  Map<String, dynamic> toJson() => {
    'label': label,
    'confidence': confidence,
  };
}

class _WeightedPrediction {
  const _WeightedPrediction({required this.prediction, required this.weight});

  final _SpeciesPrediction prediction;
  final double weight;
}

class _ModelInputSpec {
  const _ModelInputSpec({
    required this.width,
    required this.height,
    required this.channels,
    required this.type,
    required this.scale,
    required this.zeroPoint,
  });

  final int width;
  final int height;
  final int channels;
  final TensorType type;
  final double scale;
  final int zeroPoint;
}

class _InferenceView {
  const _InferenceView({required this.image, required this.weight});

  final img.Image image;
  final double weight;
}

Future<double?> _measureImageSharpness(File imageFile) async {
  final imageBytes = await imageFile.readAsBytes();
  final decoded = img.decodeImage(imageBytes);
  if (decoded == null) return null;

  final oriented = img.bakeOrientation(decoded);
  if (oriented.width < 3 || oriented.height < 3) return null;

  final longestSide = math.max(oriented.width, oriented.height);
  final sample = longestSide > 320
      ? img.copyResize(
          oriented,
          width: oriented.width >= oriented.height ? 320 : null,
          height: oriented.height > oriented.width ? 320 : null,
          interpolation: img.Interpolation.linear,
        )
      : oriented;

  double edgeStrengthTotal = 0;
  var sampleCount = 0;
  for (var y = 1; y < sample.height - 1; y += 2) {
    for (var x = 1; x < sample.width - 1; x += 2) {
      final left = _pixelLuminance(sample.getPixel(x - 1, y));
      final right = _pixelLuminance(sample.getPixel(x + 1, y));
      final top = _pixelLuminance(sample.getPixel(x, y - 1));
      final bottom = _pixelLuminance(sample.getPixel(x, y + 1));
      final gradientX = right - left;
      final gradientY = bottom - top;
      edgeStrengthTotal += math.sqrt(
        gradientX * gradientX + gradientY * gradientY,
      );
      sampleCount += 1;
    }
  }

  if (sampleCount == 0) return null;
  return edgeStrengthTotal / sampleCount;
}

double _pixelLuminance(img.Pixel pixel) {
  return (0.299 * pixel.r) + (0.587 * pixel.g) + (0.114 * pixel.b);
}

// -------------------------
// CAMERA SCREEN (unchanged)
// -------------------------

class CameraScreen extends StatefulWidget {
  final CameraController cameraController;

  const CameraScreen({super.key, required this.cameraController});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  bool _flashOn = false;
  bool _saving = false;

  Future<void> _toggleFlash() async {
    try {
      _flashOn = !_flashOn;
      await widget.cameraController.setFlashMode(
        _flashOn ? FlashMode.torch : FlashMode.off,
      );
      setState(() {});
    } catch (e) {
      debugPrint("Flash toggle error: $e");
      setState(() => _flashOn = false);
    }
  }

  Future<void> _prepareCapture() async {
    try {
      await widget.cameraController.setFocusMode(FocusMode.auto);
    } catch (_) {
      // Some devices do not expose focus controls.
    }

    try {
      if (widget.cameraController.value.focusPointSupported) {
        await widget.cameraController.setFocusPoint(const Offset(0.5, 0.5));
      }
    } catch (_) {
      // Ignore unsupported focus point controls.
    }

    try {
      if (widget.cameraController.value.exposurePointSupported) {
        await widget.cameraController.setExposurePoint(const Offset(0.5, 0.5));
      }
    } catch (_) {
      // Ignore unsupported exposure point controls.
    }

    await Future.delayed(_cameraCaptureSettleDelay);
  }

  Future<bool> _confirmSoftImageIfNeeded(File imageFile) async {
    final sharpness = await _measureImageSharpness(imageFile);
    if (!mounted || sharpness == null || sharpness >= _minimumSharpnessScore) {
      return true;
    }

    final usePhoto = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Retake this photo?'),
        content: const Text(
          'This shot looks a bit blurry, which can reduce fish detection accuracy. '
          'Retake for a sharper scan or continue with this photo.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Retake'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Use Photo'),
          ),
        ],
      ),
    );

    return usePhoto ?? false;
  }

  Future<void> _takePicture() async {
    if (_saving || !widget.cameraController.value.isInitialized) return;
    setState(() => _saving = true);

    try {
      await _prepareCapture();
      final file = await widget.cameraController.takePicture();
      final captured = File(file.path);
      final shouldUsePhoto = await _confirmSoftImageIfNeeded(captured);
      if (!shouldUsePhoto || !mounted) return;
      Navigator.pop(context, captured);
    } catch (e) {
      debugPrint("Capture error: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to capture image.')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.cameraController.value.isInitialized) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Center(child: CircularProgressIndicator(color: Colors.white)),
        ),
      );
    }

    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: ClipRect(
                child: FittedBox(
                  fit: BoxFit.cover,
                  child: SizedBox(
                    width: size.width,
                    height:
                        size.width / widget.cameraController.value.aspectRatio,
                    child: CameraPreview(widget.cameraController),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 12,
              left: 12,
              right: 12,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: const Icon(
                      Icons.close,
                      color: Colors.white,
                      size: 28,
                    ),
                    onPressed: () => Navigator.pop(context),
                  ),
                  IconButton(
                    icon: Icon(
                      _flashOn ? Icons.flash_on : Icons.flash_off,
                      color: Colors.white,
                      size: 24,
                    ),
                    onPressed: _toggleFlash,
                  ),
                ],
              ),
            ),
            Positioned(
              top: 72,
              left: 18,
              right: 18,
              child: IgnorePointer(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.34),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.15),
                    ),
                  ),
                  child: const Row(
                    children: [
                      Icon(
                        Icons.center_focus_strong_rounded,
                        color: Colors.white,
                        size: 18,
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Center the fish, hold steady, and keep the subject sharp before capturing.',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            height: 1.35,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Align(
              alignment: Alignment.bottomCenter,
              child: Container(
                padding: const EdgeInsets.only(bottom: 24, top: 12),
                child: GestureDetector(
                  onTap: _takePicture,
                  child: Container(
                    width: 78,
                    height: 78,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 6),
                      color: _saving
                          ? Colors.white.withValues(alpha: 0.15)
                          : Colors.white.withValues(alpha: 0.05),
                    ),
                    child: const Center(
                      child: Icon(
                        Icons.camera_alt,
                        color: Colors.black87,
                        size: 28,
                      ),
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
}
