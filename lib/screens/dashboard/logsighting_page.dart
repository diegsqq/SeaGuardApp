import 'dart:convert';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:intl/intl.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:path/path.dart' as p;
import 'package:video_player/video_player.dart';
import '../../utils/loading_delay.dart';
import '../../utils/responsive.dart';
import 'dashboard_screen.dart';

class LogSightingPage extends StatefulWidget {
  const LogSightingPage({
    super.key,
    this.initialSpecies,
    this.initialImage,
  });

  final String? initialSpecies;
  final File? initialImage;

  @override
  State<LogSightingPage> createState() => _LogSightingPageState();
}

class _LogSightingPageState extends State<LogSightingPage> {
  static const Color _ink = Color(0xFF102A43);
  static const Color _brand = Color(0xFF0E3764);
  static const Color _fieldFill = Color(0xFFF8FAFC);
  static const Color _fieldBorder = Color(0xFFD6DEE8);
  static const Color _muted = Color(0xFF6B7A8C);
  static const int _maxImageUploads = 3;
  static const int _maxVideoUploads = 1;
  static const int _maxVideoBytes = 25 * 1024 * 1024;
  static const TextStyle _fieldTextStyle = TextStyle(
    color: _ink,
    fontSize: 16.5,
    fontWeight: FontWeight.w700,
    height: 1.25,
  );

  static const List<String> _invalidLocationStates = [
    'Location services are OFF',
    'Location permission denied',
    'Location permission permanently denied',
    'Location fetch failed',
  ];

  final _speciesController = TextEditingController();
  final _locationController = TextEditingController();
  final _notesController = TextEditingController();
  DateTime? _selectedDateTime;
  List<File> _selectedImages = [];
  File? _selectedVideo;
  bool _isSubmitting = false;
  bool _isFetchingLocation = false;

  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _selectedDateTime = _manilaNow();
    final species = widget.initialSpecies?.trim();
    if (species != null && species.isNotEmpty) {
      _speciesController.text = species;
    }
    final image = widget.initialImage;
    if (image != null) {
      _selectedImages = [image];
    }
  }

  @override
  void dispose() {
    _speciesController.dispose();
    _locationController.dispose();
    _notesController.dispose();
    super.dispose();
  }
  DateTime _toManilaTime(DateTime utcTime) {
    return utcTime.add(const Duration(hours: 8));
  }
  DateTime _manilaNow() => _toManilaTime(DateTime.now().toUtc());

  String _formatSightingDateTime(DateTime value) {
    return DateFormat('yyyy-MM-dd HH:mm').format(value);
  }

  Future<void> _selectSightingDateTime() async {
    final current = _selectedDateTime ?? _manilaNow();
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

    setState(() {
      _selectedDateTime = DateTime(
        pickedDate.year,
        pickedDate.month,
        pickedDate.day,
        pickedTime.hour,
        pickedTime.minute,
      );
    });
  }

  bool _hasValidLocation() {
    final location = _locationController.text.trim();
    if (location.isEmpty) return false;
    return !_invalidLocationStates.contains(location);
  }

  void _showLocationRequiredMessage() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("Location is required. Type it manually or use the fetch button before submitting."),
      ),
    );
  }

  Future<bool> _confirmSubmitSighting() async {
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
                      Icons.visibility_rounded,
                      color: _brand,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      "Submit sighting?",
                      style: TextStyle(
                        color: _ink,
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
                "Are you sure to submit sighting? Please confirm that the details and photo evidence are accurate.",
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
                      color: Color(0xFFB42318),
                      size: 20,
                    ),
                    SizedBox(width: 9),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "Fake sightings are violations",
                            style: TextStyle(
                              color: Color(0xFFB42318),
                              fontSize: 13.2,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          SizedBox(height: 3),
                          Text(
                            "If BFAR marks this log sighting as fake or invalid, a violation may be added to your account.",
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
                        foregroundColor: _ink,
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
                        backgroundColor: _brand,
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

  Future<void> _pickImages() async {
    final pickedFiles = await _picker.pickMultiImage();
    if (pickedFiles.isEmpty) return;

    final limited = pickedFiles
        .take(_maxImageUploads)
        .map((f) => File(f.path))
        .toList();
    setState(() => _selectedImages = limited);
    if (pickedFiles.length > _maxImageUploads && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Only the first 3 photos were added."),
        ),
      );
    }
  }

  String _videoMimeForPath(String path) {
    switch (p.extension(path).toLowerCase()) {
      case '.mov':
        return 'video/quicktime';
      case '.m4v':
        return 'video/x-m4v';
      case '.webm':
        return 'video/webm';
      default:
        return 'video/mp4';
    }
  }

  Future<void> _pickVideo() async {
    if (_selectedVideo != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Only 1 video can be uploaded.")),
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

      setState(() => _selectedVideo = File(picked.path));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Unable to add video: $e")),
      );
    }
  }

  Future<void> _showVideoPreview() async {
    final video = _selectedVideo;
    if (video == null || !await video.exists()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Video preview is not available.")),
      );
      return;
    }

    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => _VideoPreviewDialog(
        file: video,
        title: p.basename(video.path),
      ),
    );
  }

  Future<void> _fetchLocation() async {
    setState(() => _isFetchingLocation = true);
    final loadingDelay = Future<void>.delayed(appLoadingDelay);
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _locationController.text = "Location services are OFF";
        return;
      }
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          _locationController.text = "Location permission denied";
          return;
        }
      }
      if (permission == LocationPermission.deniedForever) {
        _locationController.text = "Location permission permanently denied";
        return;
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 12),
        ),
      ).timeout(const Duration(seconds: 15));

      final placemarks = await placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );
      if (placemarks.isNotEmpty) {
        final p = placemarks.first;
        _locationController.text =
            '${p.street}, ${p.locality}, ${p.administrativeArea}, ${p.country}';
      } else {
        _locationController.text =
            '${position.latitude.toStringAsFixed(5)}, ${position.longitude.toStringAsFixed(5)}';
      }
    } catch (e) {
      _locationController.text = "Location fetch failed";
    } finally {
      await loadingDelay;
      if (mounted) setState(() => _isFetchingLocation = false);
    }
  }
  Future<List<String>> _uploadImages(User user) async {
    if (_selectedImages.isEmpty) return [];

    final urls = <String>[];

    for (final image in _selectedImages) {
      if (!await image.exists()) continue;

      String? downloadUrl;

      try {
        final fileName = "${DateTime.now().millisecondsSinceEpoch}_${p.basename(image.path)}";
        final ref = FirebaseStorage.instance.ref().child("sightings/${user.uid}/$fileName");
        final task = await ref.putFile(image);
        if (task.state == TaskState.success) {
          downloadUrl = await ref.getDownloadURL();
        }
      } catch (e) {
        debugPrint("Image upload failed, using inline data URL fallback: $e");
      }

      if (downloadUrl == null) {
        try {
          final bytes = await image.readAsBytes();
          final b64 = base64Encode(bytes);
          downloadUrl = "data:image/jpeg;base64,$b64";
        } catch (e) {
          debugPrint("Base64 fallback failed: $e");
        }
      }

      if (downloadUrl != null && downloadUrl.isNotEmpty) {
        urls.add(downloadUrl);
      }
    }

    return urls;
  }

  Future<String?> _uploadVideo(User user) async {
    final video = _selectedVideo;
    if (video == null) return null;
    if (!await video.exists()) return null;

    final fileName =
        "${DateTime.now().millisecondsSinceEpoch}_${p.basename(video.path)}";
    final ref = FirebaseStorage.instance.ref().child(
      "sightings/${user.uid}/videos/$fileName",
    );
    final task = await ref.putFile(
      video,
      SettableMetadata(contentType: _videoMimeForPath(video.path)),
    );
    if (task.state != TaskState.success) return null;
    return ref.getDownloadURL();
  }

  Future<void> _submitForm() async {
    if (_isSubmitting) return;

    final species = _speciesController.text.trim();
    final submittedSpecies = species.isEmpty ? "Unknown species" : species;
    final location = _locationController.text.trim();
    final notes = _notesController.text.trim();

    if (!_hasValidLocation()) {
      _showLocationRequiredMessage();
      return;
    }
    if (_selectedImages.length > _maxImageUploads) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("You can upload up to 3 photos only.")),
      );
      return;
    }
    if (_selectedImages.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please attach at least one photo of the sighting.")),
      );
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("You must be signed in to log a sighting.")),
      );
      return;
    }

    final confirmed = await _confirmSubmitSighting();
    if (!confirmed || !mounted) return;

    setState(() => _isSubmitting = true);
    final loadingDelay = Future<void>.delayed(appLoadingDelay);

    try {
      List<String> imageUrls = [];
      if (_selectedImages.isNotEmpty) {
        imageUrls = await _uploadImages(user);
      }
      final videoUrl = await _uploadVideo(user);
      final videoUrls = videoUrl == null ? <String>[] : <String>[videoUrl];

      double? latitude;
      double? longitude;
      final parts = location.split(',');
      if (location.isNotEmpty && parts.length == 2) {
        latitude = double.tryParse(parts[0].trim());
        longitude = double.tryParse(parts[1].trim());
      }

      final submittedTime = _manilaNow();
      final sightingTime = _selectedDateTime ?? submittedTime;
      final submittedFormatted = DateFormat('yyyy-MM-dd HH:mm:ss').format(submittedTime);
      final sightingFormatted = DateFormat('yyyy-MM-dd HH:mm:ss').format(sightingTime);

      await FirebaseFirestore.instance.collection("sightings").add({
        "userId": user.uid,
        "species": submittedSpecies,
        "speciesProvided": species.isNotEmpty,
        "isUnknownSpecies": species.isEmpty,
        "location": location,
        "latitude": latitude,
        "longitude": longitude,
        if (notes.isNotEmpty) "notes": notes,
        "sightingAt": Timestamp.fromDate(sightingTime),
        "sightingDateTimeString": sightingFormatted,
        "reportedAt": Timestamp.fromDate(submittedTime),
        "reportedTimeString": submittedFormatted,
        "manilaDateTime": Timestamp.fromDate(sightingTime),
        "manilaTimeString": sightingFormatted,
        "imageUrl": imageUrls.isNotEmpty ? imageUrls.first : null,
        "imageUrls": imageUrls,
        "videoUrl": videoUrl,
        "videoUrls": videoUrls,
        "hasVideo": videoUrls.isNotEmpty,
        "status": "pending",
        "actionStatus": "pending",
        "createdAt": FieldValue.serverTimestamp(),
      });

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Report submitted at $submittedFormatted (Manila time)"),
          backgroundColor: Colors.indigo[800],
        ),
      );

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const SubmissionSuccessPage()),
      );
    } on FirebaseException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Failed to submit sighting: ${e.message ?? e.code}")),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Failed to submit sighting: $e")),
      );
    } finally {
      await loadingDelay;
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Widget _fieldHeader(String label, {String? meta}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 0, 2, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: _ink,
                fontSize: 14.8,
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

  Widget _helperText(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 6, 2, 0),
      child: Text(
        text,
        style: const TextStyle(
          color: Color(0xFF5E738A),
          fontSize: 12.7,
          fontWeight: FontWeight.w600,
          height: 1.3,
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(
    String hint,
    IconData icon, {
    Widget? suffix,
  }) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: _fieldBorder),
    );
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(
        color: Color(0xFF76869A),
        fontSize: 15.4,
        fontWeight: FontWeight.w700,
      ),
      prefixIcon: Icon(icon, color: const Color(0xFF5D7085), size: 21),
      prefixIconConstraints: const BoxConstraints(minWidth: 50),
      suffixIcon: suffix,
      hintMaxLines: 2,
      filled: true,
      fillColor: Colors.white,
      border: border,
      enabledBorder: border,
      focusedBorder: border.copyWith(
        borderSide: const BorderSide(color: _brand, width: 1.4),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    );
  }

  Widget _trailingActionIcon(IconData icon) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: _brand.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(11),
      ),
      child: Icon(icon, color: _brand, size: 21),
    );
  }

  Widget _buildSelectedImagesPreview(Size size) {
    final images = _selectedImages.take(3).toList();
    if (images.isEmpty) return const SizedBox.shrink();

    if (images.length == 1) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.file(
          images.first,
          height: size.height * 0.25,
          width: double.infinity,
          fit: BoxFit.cover,
        ),
      );
    }

    const double previewHeight = 120;
    return SizedBox(
      height: previewHeight,
      child: Row(
        children: images
            .asMap()
            .entries
            .map(
              (entry) => Expanded(
                child: Padding(
                  padding: EdgeInsets.only(
                    left: entry.key == 0 ? 0 : 8,
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.file(
                      entry.value,
                      height: previewHeight,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
              ),
            )
            .toList(),
      ),
    );
  }

  Widget _buildVideoSelector() {
    final video = _selectedVideo;
    if (video == null) {
      return Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: _pickVideo,
          child: Container(
            constraints: const BoxConstraints(minHeight: 58),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _fieldBorder),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.videocam_outlined,
                  color: Color(0xFF5D7085),
                  size: 24,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    "Add video",
                    style: const TextStyle(
                      color: Color(0xFF76869A),
                      fontSize: 15.4,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                _trailingActionIcon(Icons.video_call_outlined),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _fieldBorder),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: _brand.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.movie_outlined, color: _brand),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              p.basename(video.path),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: _ink,
                fontSize: 15.8,
                fontWeight: FontWeight.w800,
                height: 1.25,
              ),
            ),
          ),
          IconButton(
            onPressed: _showVideoPreview,
            icon: const Icon(Icons.play_circle_outline, color: _brand),
            tooltip: "Preview video",
          ),
          IconButton(
            onPressed: () => setState(() => _selectedVideo = null),
            icon: const Icon(Icons.close, color: _muted),
            tooltip: "Remove video",
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final padding = Responsive.pagePadding(context);
    final selectedDateText = _selectedDateTime != null
        ? _formatSightingDateTime(_selectedDateTime!)
        : "";
    const fieldSpacing = SizedBox(height: 14);

    return Scaffold(
      backgroundColor: const Color(0xFFF5F8FB),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF5F8FB),
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        foregroundColor: _ink,
        title: const Text(
          "Log Sighting",
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w900,
            height: 1.1,
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: _fieldBorder),
        ),
      ),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: Responsive.maxContentWidth(context),
            ),
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                padding,
                16,
                padding,
                28,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(16, 15, 16, 15),
                    margin: const EdgeInsets.only(bottom: 18),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFD8E8F4)),
                      boxShadow: [
                        BoxShadow(
                          color: _brand.withValues(alpha: 0.04),
                          blurRadius: 14,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          height: 36,
                          width: 36,
                          decoration: BoxDecoration(
                            color: const Color(0xFFEAF3FA),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.fact_check_outlined,
                            color: _brand,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Review notice',
                                style: TextStyle(
                                  fontSize: 14.8,
                                  fontWeight: FontWeight.w800,
                                  color: _brand,
                                ),
                              ),
                              SizedBox(height: 4),
                              Text(
                                'BFAR will review your sighting. Clear photos and details help responders verify it faster.',
                                style: TextStyle(
                                  fontSize: 12.8,
                                  color: Color(0xFF42627D),
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
                  _fieldHeader("Species", meta: "Optional"),
                  TextField(
                    controller: _speciesController,
                    style: _fieldTextStyle,
                    textInputAction: TextInputAction.next,
                    decoration: _inputDecoration(
                      "Species name, if known",
                      FontAwesomeIcons.fish,
                    ),
                  ),
                  _helperText("Leave blank if you are not sure."),
                  fieldSpacing,
                  _fieldHeader("Location", meta: "Required"),
                  TextField(
                    controller: _locationController,
                    style: _fieldTextStyle,
                    minLines: 1,
                    maxLines: 3,
                    textInputAction: TextInputAction.next,
                    decoration: _inputDecoration(
                      "Type location or use map",
                      Icons.location_on,
                      suffix: _isFetchingLocation
                          ? const Padding(
                              padding: EdgeInsets.all(12),
                              child: SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                            )
                          : IconButton(
                              onPressed: _fetchLocation,
                              icon: const Icon(
                                Icons.map_outlined,
                                color: _muted,
                              ),
                              tooltip: "Fetch current location",
                            ),
                    ),
                  ),
                  _helperText("Enter the place manually or tap the map icon."),
                  fieldSpacing,
                  _fieldHeader(
                    "Photos",
                    meta: "${_selectedImages.length}/$_maxImageUploads",
                  ),
                  Material(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: _pickImages,
                      child: Container(
                        constraints: const BoxConstraints(minHeight: 58),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 11,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: _fieldBorder),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.photo_camera_outlined,
                              color: Color(0xFF5D7085),
                              size: 22,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                _selectedImages.isNotEmpty
                                    ? "${_selectedImages.length} photo${_selectedImages.length > 1 ? 's' : ''} selected"
                                    : "Add clear photos",
                                style: TextStyle(
                                  color: _selectedImages.isNotEmpty
                                      ? _ink
                                      : const Color(0xFF76869A),
                                  fontWeight: _selectedImages.isNotEmpty
                                      ? FontWeight.w800
                                      : FontWeight.w700,
                                  fontSize: 15.4,
                                ),
                              ),
                            ),
                            _trailingActionIcon(
                              Icons.add_photo_alternate_outlined,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  _helperText("Required. Add at least 1 clear photo. Max 3."),
                  if (_selectedImages.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    _buildSelectedImagesPreview(size),
                  ],
                  fieldSpacing,
                  _fieldHeader(
                    "Video",
                    meta:
                        "${_selectedVideo == null ? 0 : 1}/$_maxVideoUploads",
                  ),
                  _buildVideoSelector(),
                  _helperText("Optional. Max 1 video, up to 25 MB."),
                  fieldSpacing,
                  _fieldHeader("Date & time"),
                  TextField(
                    readOnly: true,
                    onTap: _selectSightingDateTime,
                    controller: TextEditingController(text: selectedDateText),
                    style: _fieldTextStyle,
                    decoration: _inputDecoration(
                      selectedDateText.isEmpty
                          ? "Select sighting date and time"
                          : selectedDateText,
                      Icons.event_available_outlined,
                      suffix: IconButton(
                        onPressed: _selectSightingDateTime,
                        icon: const Icon(
                          Icons.edit_calendar_outlined,
                          color: _muted,
                        ),
                        tooltip: "Select sighting date and time",
                      ),
                    ),
                  ),
                  _helperText("When you saw it."),
                  fieldSpacing,
                  _fieldHeader("Description", meta: "Optional"),
                  TextField(
                    controller: _notesController,
                    style: _fieldTextStyle,
                    textInputAction: TextInputAction.newline,
                    minLines: 3,
                    maxLines: 4,
                    decoration: _inputDecoration(
                      "Behavior, size, condition, or notes",
                      Icons.edit,
                    ),
                  ),
                  _helperText("Add helpful details for review."),
                  const SizedBox(height: 22),
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: ElevatedButton(
                      onPressed: _isSubmitting ? null : _submitForm,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _ink,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                        elevation: 0,
                      ),
                      child: _isSubmitting
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor:
                                    AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : const Text(
                              "Submit Sighting",
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                              ),
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
    required this.file,
    required this.title,
  });

  final File file;
  final String title;

  @override
  State<_VideoPreviewDialog> createState() => _VideoPreviewDialogState();
}

class _VideoPreviewDialogState extends State<_VideoPreviewDialog> {
  late final VideoPlayerController _controller;
  bool _ready = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.file(widget.file);
    _controller.initialize().then((_) {
      if (!mounted) return;
      setState(() => _ready = true);
    }).catchError((e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
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
      insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
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
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                  tooltip: "Close",
                ),
              ],
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Container(
                color: Colors.black,
                width: double.infinity,
                constraints: const BoxConstraints(minHeight: 190),
                child: _error != null
                    ? Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          "Unable to play video: $_error",
                          style: const TextStyle(color: Colors.white),
                        ),
                      )
                    : !_ready
                    ? const Center(child: CircularProgressIndicator())
                    : AspectRatio(
                        aspectRatio: _controller.value.aspectRatio == 0
                            ? 16 / 9
                            : _controller.value.aspectRatio,
                        child: VideoPlayer(_controller),
                      ),
              ),
            ),
            if (_ready && _error == null) ...[
              const SizedBox(height: 10),
              VideoProgressIndicator(
                _controller,
                allowScrubbing: true,
                padding: const EdgeInsets.symmetric(vertical: 6),
              ),
              Align(
                alignment: Alignment.center,
                child: FilledButton.icon(
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
                  label: Text(
                    _controller.value.isPlaying ? "Pause" : "Play",
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class SubmissionSuccessPage extends StatefulWidget {
  const SubmissionSuccessPage({super.key});

  @override
  State<SubmissionSuccessPage> createState() => _SubmissionSuccessPageState();
}

class _SubmissionSuccessPageState extends State<SubmissionSuccessPage> {
  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(seconds: 2), _goToDashboard);
  }

  void _goToDashboard() {
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const DashboardScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final textScale = size.width * 0.045;

    return Scaffold(
      backgroundColor: const Color(0xFFD8E2F0),
      body: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: size.width * 0.8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            decoration: BoxDecoration(
              color: const Color(0xFFD8E2F0),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black12,
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  "Thank you! Your marine sighting has been submitted for review and analysis.",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: textScale,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  "Redirecting to dashboard...",
                  style: TextStyle(fontSize: 12, color: Colors.black54),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
