import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:image/image.dart' as img;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../dashboard/navbar_screen.dart';
import '../dashboard/dashboard_screen.dart';
import '../detection/detection_screen.dart';
import '../community/community_screen.dart';
import '../notification_page.dart';
import '../profile/profile_page.dart';
import '../../utils/responsive.dart';
import '../../utils/loading_delay.dart';
import '../../utils/community_moderation.dart';

class CreatePostScreen extends StatefulWidget {
  const CreatePostScreen({super.key});

  @override
  State<CreatePostScreen> createState() => _CreatePostScreenState();
}

class _CreatePostScreenState extends State<CreatePostScreen> {
  int _selectedIndex = 1;
  final TextEditingController _controller = TextEditingController();
  bool _isLoading = false;
  final List<File> _selectedImages = [];
  String? _profileImageUrl;
  String? _profileImageBase64;
  String? _locationText;
  String? _fullName;
  String? _userId;
  String? _userRole;
  String? _authPhotoUrl;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _postStatusSub;
  bool _autoLocationTried = false;
  bool _postAnonymously = false;

  String _roleBucket(String? raw) {
    final r = (raw ?? '').toLowerCase().trim();
    if (r.contains('pcg') || r.contains('web-admin') || r.contains('sub-admin'))
      return 'pcg';
    if (r.contains('bfar')) return 'bfar';
    if (r.contains('fish')) return 'fisherman';
    if (r.contains('admin')) return 'admin';
    if (r.contains('resident')) return 'resident';
    return 'resident';
  }

  String _roleLabel(String? raw) {
    final bucket = _roleBucket(raw);
    final lower = (raw ?? '').toLowerCase();
    switch (bucket) {
      case 'pcg':
        if (lower.contains('sub') || lower.contains('web-admin')) {
          return 'PCG Sub-Admin';
        }
        return 'PCG';
      case 'bfar':
        if (lower.contains('web-admin')) return 'BFAR Web Admin';
        return 'BFAR';
      case 'fisherman':
        return 'Fisherman';
      case 'admin':
        return 'Admin';
      default:
        return 'Resident';
    }
  }

  bool? _parseBoolFlag(dynamic value) {
    if (value == null) return null;
    if (value is bool) return value;

    final normalized = value.toString().trim().toLowerCase();
    if (normalized == 'true') return true;
    if (normalized == 'false') return false;
    return null;
  }

  String _normalizeModerationStatus(dynamic value) {
    final normalized = (value ?? '').toString().trim().toLowerCase();
    if (normalized.isEmpty) return '';

    if (normalized == 'approved' ||
        normalized == 'approve' ||
        normalized == 'published' ||
        normalized == 'visible') {
      return 'approved';
    }

    if (normalized == 'declined' ||
        normalized == 'rejected' ||
        normalized == 'denied') {
      return 'declined';
    }

    if (normalized == 'pending' ||
        normalized == 'review' ||
        normalized == 'under_review' ||
        normalized == 'under review' ||
        normalized.contains('pending')) {
      return 'pending';
    }

    return normalized;
  }

  String _postModerationStatus(Map<String, dynamic> post) {
    bool hasPendingSignal = false;

    for (final value in [
      post['status'],
      post['approvalStatus'],
      post['moderationStatus'],
      post['reviewStatus'],
    ]) {
      final status = _normalizeModerationStatus(value);
      if (status == 'approved' || status == 'declined') return status;
      if (status == 'pending') hasPendingSignal = true;
    }

    for (final value in [
      post['approved'],
      post['isApproved'],
      post['published'],
      post['isPublished'],
      post['visible'],
      post['isVisible'],
    ]) {
      final approved = _parseBoolFlag(value);
      if (approved == true) return 'approved';
      if (approved == false) hasPendingSignal = true;
    }

    return hasPendingSignal ? 'pending' : '';
  }

  @override
  void initState() {
    super.initState();
    _loadUserFullName();
    _prefetchLocation();
  }

  @override
  void dispose() {
    _postStatusSub?.cancel();
    super.dispose();
  }

  Future<void> _loadUserFullName() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        _userId = user.uid;
        _authPhotoUrl = user.photoURL;

        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();
        if (userDoc.exists) {
          final data = userDoc.data()!;
          final firstName = data['firstName'] ?? '';
          final lastName = data['lastName'] ?? '';
          final fullName =
              data['fullName'] ??
              (firstName.isNotEmpty || lastName.isNotEmpty
                  ? "$firstName $lastName".trim()
                  : data['name'] ??
                        user.displayName ??
                        user.email?.split('@').first ??
                        "User");

          setState(() {
            _fullName = fullName;
            _profileImageBase64 = data['profileImageBase64'];
            _profileImageUrl = data['profileImageUrl'];
            _userRole = data['role'] ?? data['category'];
          });
        } else {
          setState(() {
            _fullName =
                user.displayName ?? user.email?.split('@').first ?? "User";
          });
        }
        _listenForPostStatus();
      }
    } catch (e) {
      debugPrint("Failed to load full name: $e");
      setState(() {
        _fullName = "User";
      });
    }
  }

  void _onItemTapped(int index) {
    if (index == _selectedIndex) return;
    Widget screen;
    switch (index) {
      case 0:
        screen = const DashboardScreen();
        break;
      case 1:
        screen = const CommunityScreen();
        break;
      case 2:
        screen = const DetectionScreen();
        break;
      case 3:
        screen = const NotificationPage();
        break;
      case 4:
        screen = const ProfilePage();
        break;
      default:
        screen = const CommunityScreen();
    }
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => screen),
      (route) => false,
    );
  }

  void _listenForPostStatus() {
    if (_userId == null) return;
    if (_postStatusSub != null) return;

    _postStatusSub = FirebaseFirestore.instance
        .collection('community_posts')
        .where('user_id', isEqualTo: _userId)
        .snapshots()
        .listen(
          (snapshot) async {
            for (final doc in snapshot.docs) {
              final data = doc.data();
              final status = _postModerationStatus(data);
              if (status != 'approved' && status != 'declined') continue;
              final notified = data['statusNotified'] == true;
              if (notified) continue;

              final postId = doc.id;
              final title = status == 'approved'
                  ? 'Post Approved'
                  : 'Post Declined';
              final message = status == 'approved'
                  ? 'Your community post has been approved and published.'
                  : 'Your community post was declined by a BFAR admin.';
              final postTitle = (data['title'] ?? '').toString().trim();
              final content = (data['content'] ?? '').toString().trim();
              final preview = postTitle.isNotEmpty
                  ? postTitle
                  : (content.length > 80
                        ? '${content.substring(0, 77)}...'
                        : content);
              final body = preview.isNotEmpty ? '$message\n$preview' : message;

              try {
                await _createNotification(
                  targetUserId: _userId!,
                  title: title,
                  message: body,
                  extra: {
                    'type': 'community_post_status',
                    'category': 'community',
                    'communityPostId': postId,
                    'status': status,
                  },
                );
                await FirebaseFirestore.instance
                    .collection('community_posts')
                    .doc(postId)
                    .update({'statusNotified': true});
              } catch (e) {
                debugPrint('Failed to send status notification: $e');
              }
            }
          },
          onError: (e) {
            debugPrint('Post status listener error: $e');
          },
        );
  }

  Future<void> _createNotification({
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
    } catch (e) {
      debugPrint('Failed to create notification: $e');
    }
  }

  void _showToast({
    required String title,
    required String message,
    bool success = true,
  }) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    final bgColor = success ? const Color(0xFF0F5E4B) : const Color(0xFF7A271A);
    final accentColor =
        success ? const Color(0xFFDDF8EC) : const Color(0xFFFFE4E0);

    messenger.showSnackBar(
      SnackBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        padding: EdgeInsets.zero,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 18),
        duration: const Duration(seconds: 4),
        content: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: bgColor.withValues(alpha: 0.24),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(
                  success
                      ? Icons.check_circle_rounded
                      : Icons.info_outline_rounded,
                  color: accentColor,
                  size: 21,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      message,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.92),
                        fontSize: 13.4,
                        fontWeight: FontWeight.w600,
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickImage() async {
    final remainingBeforePick = 4 - _selectedImages.length;
    if (remainingBeforePick <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You can attach up to 4 images.')),
      );
      return;
    }

    final picker = ImagePicker();
    final pickedFiles = await picker.pickMultiImage();
    if (pickedFiles.isEmpty) return;

    // Allow up to 4 images; newly picked images are appended until the cap.
    final remaining = 4 - _selectedImages.length;
    final toAdd = pickedFiles.take(remaining).map((p) => File(p.path)).toList();
    if (toAdd.isEmpty) return;

    setState(() {
      _selectedImages.addAll(toAdd);
    });

    if (toAdd.length < pickedFiles.length) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Only ${toAdd.length} added (max 4 images).')),
      );
    }
  }

  Future<void> _prefetchLocation() async {
    if (_autoLocationTried || _locationText != null) return;
    _autoLocationTried = true;
    try {
      await _getLocation(silent: true);
    } catch (e) {
      debugPrint('Prefetch location failed: $e');
    }
  }

  Future<void> _getLocation({bool silent = false}) async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (!silent) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Location services are disabled")),
        );
      }
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        if (!silent) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Location permission denied")),
          );
        }
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      if (!silent) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Location permission permanently denied"),
          ),
        );
      }
      return;
    }

    final position = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );

    String? readableLocation;
    try {
      final placemarks = await placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );
      if (placemarks.isNotEmpty) {
        final place = placemarks.first;
        final rawParts = <String?>[
          place.subLocality,
          place.locality,
          place.subAdministrativeArea,
          place.administrativeArea,
          place.country,
        ];
        final parts = rawParts
            .whereType<String>()
            .map((p) => p.trim())
            .where((p) => p.isNotEmpty)
            .toList();
        if (parts.isNotEmpty) {
          readableLocation = parts.join(', ');
        }
      }
    } catch (e) {
      debugPrint('Reverse geocoding failed: $e');
    }

    setState(() {
      _locationText =
          readableLocation ??
          "Lat: ${position.latitude.toStringAsFixed(4)}, Long: ${position.longitude.toStringAsFixed(4)}";
    });
  }

  Future<String> _encodeImageForUpload(File file) async {
    try {
      final bytes = await file.readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded == null) {
        // Fallback: raw base64 (may be larger, but better than failing).
        return "data:image/jpeg;base64,${base64Encode(bytes)}";
      }
      // Constrain size to keep Firestore payload under limits while preserving aspect ratio.
      const maxDim = 900;
      int targetWidth = decoded.width;
      int targetHeight = decoded.height;
      if (decoded.width > maxDim || decoded.height > maxDim) {
        final scale =
            (decoded.width > decoded.height ? decoded.width : decoded.height) /
            maxDim;
        targetWidth = (decoded.width / scale).round().clamp(1, maxDim);
        targetHeight = (decoded.height / scale).round().clamp(1, maxDim);
      }
      final resized = img.copyResize(
        decoded,
        width: targetWidth,
        height: targetHeight,
      );
      final jpg = img.encodeJpg(resized, quality: 65);
      return "data:image/jpeg;base64,${base64Encode(jpg)}";
    } catch (e) {
      debugPrint('Image encode failed: $e');
      final bytes = await file.readAsBytes();
      return "data:image/jpeg;base64,${base64Encode(bytes)}";
    }
  }

  Future<bool> _confirmPostSubmission({
    required bool anonymous,
    required bool hasImages,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Post to community?'),
        content: Text(
          anonymous
              ? 'Your post will appear as Anonymous. Admins can still see your identity for moderation.'
              : hasImages
                  ? 'Submit this post with the selected photo(s) for BFAR review?'
                  : 'Submit this post for BFAR review?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Post'),
          ),
        ],
      ),
    );
    return result == true;
  }

  Future<void> _submitPost() async {
    final text = _controller.text.trim();
    if (text.isEmpty && _selectedImages.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please add some content or an image")),
      );
      return;
    }
    if (_userId == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("User not logged in")));
      return;
    }
    if (CommunityModeration.containsProfanity(text)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(CommunityModeration.messageFor('posting'))),
      );
      return;
    }
    final confirmed = await _confirmPostSubmission(
      anonymous: _postAnonymously,
      hasImages: _selectedImages.isNotEmpty,
    );
    if (!confirmed || !mounted) return;

    setState(() => _isLoading = true);
    final loadingDelay = Future<void>.delayed(appLoadingDelay);

    try {
      String? imageData;
      final List<String> imageDataList = [];
      for (final imgFile in _selectedImages) {
        final data = await _encodeImageForUpload(imgFile);
        imageDataList.add(data);
      }
      if (imageDataList.isNotEmpty) {
        imageData = imageDataList.first;
      }

      final normalizedRole = _roleLabel(_userRole);
      final authorName = (_fullName ?? "User").trim();
      final publicName = _postAnonymously ? "Anonymous" : authorName;

      final posts = FirebaseFirestore.instance.collection('community_posts');
      final docRef = await posts.add({
        'content': text,
        'user_id': _userId,
        'username': publicName,
        'isAnonymous': _postAnonymously,
        'anonymous': _postAnonymously,
        'authorName': authorName,
        'authorDisplayName': authorName,
        'authorUserId': _userId,
        'adminUsername': authorName,
        'adminUserRole': normalizedRole,
        'category': normalizedRole,
        'status': 'pending',
        'approved': false,
        'statusNotified': false,
        if (_locationText != null) 'location': _locationText,
        if (imageData != null) 'image': imageData,
        if (imageDataList.isNotEmpty) 'images': imageDataList,
        if (!_postAnonymously && _profileImageBase64 != null)
          'profileImageBase64': _profileImageBase64,
        if (!_postAnonymously && _profileImageUrl != null)
          'profileImageUrl': _profileImageUrl,
        if (!_postAnonymously && _authPhotoUrl != null)
          'authPhotoUrl': _authPhotoUrl,
        if (_profileImageBase64 != null)
          'adminProfileImageBase64': _profileImageBase64,
        if (_profileImageUrl != null) 'adminProfileImageUrl': _profileImageUrl,
        if (_authPhotoUrl != null) 'adminAuthPhotoUrl': _authPhotoUrl,
        'created_at': FieldValue.serverTimestamp(),
        'createdAt': FieldValue.serverTimestamp(),
      });

      // Notify BFAR web admins that a user submitted a post for review.
      try {
        final notifications = FirebaseFirestore.instance.collection(
          'notifications',
        );
        final preview = text.isNotEmpty
            ? (text.length > 120 ? '${text.substring(0, 117)}...' : text)
            : (imageDataList.isNotEmpty
                  ? 'User attached ${imageDataList.length} image${imageDataList.length > 1 ? 's' : ''}.'
                  : 'User submitted a post.');
        await notifications.add({
          'title': 'Community post pending review',
          'message':
              '$authorName submitted a post for BFAR approval.\n$preview',
          'timestamp': FieldValue.serverTimestamp(),
          'isRead': false,
          'type': 'community_post_pending',
          'category': 'community',
          'targetRole': 'web-admin-bfar',
          'communityPostId': docRef.id,
          'postUserId': _userId,
          'authorName': authorName,
          'isAnonymous': _postAnonymously,
        });
      } catch (e) {
        debugPrint('Failed to notify BFAR admins: $e');
      }

      _showToast(
        title: 'Post Submitted',
        message: "BFAR will review it and notify you after approval.",
      );
      _controller.clear();
      setState(() {
        _selectedImages.clear();
        _locationText = null;
        _postAnonymously = false;
      });
    } catch (e) {
      debugPrint("Post submission error: $e");
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Failed to submit: $e")));
    } finally {
      await loadingDelay;
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Widget _buildComposerAction({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
  }) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 20, color: const Color(0xFF1E5E90)),
      label: Text(
        label,
        style: const TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: 13.5,
          color: Color(0xFF133D5C),
        ),
      ),
      style: OutlinedButton.styleFrom(
        backgroundColor: const Color(0xFFF8FCFF),
        foregroundColor: const Color(0xFF133D5C),
        side: const BorderSide(color: Color(0xFFD0DFEE)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        alignment: Alignment.centerLeft,
      ),
    );
  }

  Widget _buildRemoveImageButton(VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(20),
        ),
        padding: const EdgeInsets.all(6),
        child: const Icon(Icons.close, color: Colors.white, size: 16),
      ),
    );
  }

  Widget _buildSelectedMediaPreview() {
    if (_selectedImages.isEmpty) return const SizedBox.shrink();

    if (_selectedImages.length == 1) {
      return SizedBox(
        height: 220,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Stack(
            children: [
              Positioned.fill(
                child: Image.file(_selectedImages.first, fit: BoxFit.cover),
              ),
              Positioned(
                top: 8,
                right: 8,
                child: _buildRemoveImageButton(() {
                  setState(() => _selectedImages.clear());
                }),
              ),
            ],
          ),
        ),
      );
    }

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 1.15,
      ),
      itemCount: _selectedImages.length,
      itemBuilder: (context, index) {
        final file = _selectedImages[index];
        return ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Stack(
            children: [
              Positioned.fill(child: Image.file(file, fit: BoxFit.cover)),
              Positioned(
                top: 8,
                right: 8,
                child: _buildRemoveImageButton(() {
                  setState(() => _selectedImages.removeAt(index));
                }),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final padding = Responsive.pagePadding(context);
    final maxWidth = Responsive.maxContentWidth(context);
    final vertical = Responsive.verticalSpace(context);
    final roleLabel = _roleLabel(_userRole);
    final hasDraft =
        _controller.text.trim().isNotEmpty || _selectedImages.isNotEmpty;

    return Scaffold(
      backgroundColor: const Color(0xFFF3F7FC),
      appBar: AppBar(
        title: const Text(
          'Create Post',
          style: TextStyle(
            fontSize: 34,
            fontWeight: FontWeight.w900,
            color: Color(0xFF102A43),
            letterSpacing: 0.2,
          ),
        ),
        titleSpacing: 0,
        backgroundColor: const Color(0xFFF3F7FC),
        foregroundColor: const Color(0xFF102A43),
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      bottomNavigationBar: CustomBottomNavBar(
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                padding,
                vertical * 0.6,
                padding,
                padding + 14,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFFFFFFFF), Color(0xFFF6FAFF)],
                      ),
                      border: Border.all(color: const Color(0xFFD3E2F0)),
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(
                            0xFF0A3556,
                          ).withValues(alpha: 0.08),
                          blurRadius: 24,
                          offset: const Offset(0, 12),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE8F4FF),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: const Color(0xFFCAE1F8)),
                          ),
                          child: const Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.verified_user_outlined,
                                size: 18,
                                color: Color(0xFF1A5C8B),
                              ),
                              SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  "Posts are reviewed by BFAR admins before they appear in the community.",
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    color: Color(0xFF184260),
                                    fontWeight: FontWeight.w600,
                                    height: 1.25,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            CircleAvatar(
                              radius: 22,
                              backgroundColor: const Color(0xFFD5E4F1),
                              backgroundImage: _profileImageBase64 != null
                                  ? MemoryImage(
                                      base64Decode(_profileImageBase64!),
                                    )
                                  : (_profileImageUrl != null
                                        ? NetworkImage(_profileImageUrl!)
                                        : null),
                              child:
                                  (_profileImageBase64 == null &&
                                      _profileImageUrl == null)
                                  ? const Icon(
                                      Icons.person,
                                      size: 18,
                                      color: Color(0xFF1D4B6F),
                                    )
                                  : null,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _fullName ?? "Loading...",
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 16,
                                      color: Color(0xFF102A43),
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 4),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFE8F1FB),
                                      borderRadius: BorderRadius.circular(30),
                                    ),
                                    child: Text(
                                      roleLabel,
                                      style: const TextStyle(
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w700,
                                        color: Color(0xFF1C4B71),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _controller,
                          onChanged: (_) => setState(() {}),
                          minLines: 5,
                          maxLines: 8,
                          decoration: const InputDecoration(
                            hintText: "What's on your mind?",
                            hintStyle: TextStyle(
                              color: Color(0xFF6A8198),
                              fontWeight: FontWeight.w500,
                            ),
                            filled: true,
                            fillColor: Color(0xFFF8FBFF),
                            contentPadding: EdgeInsets.fromLTRB(16, 14, 16, 14),
                            enabledBorder: OutlineInputBorder(
                              borderSide: BorderSide(color: Color(0xFFD0DFEE)),
                              borderRadius: BorderRadius.all(
                                Radius.circular(16),
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderSide: BorderSide(
                                color: Color(0xFF1E5E90),
                                width: 1.4,
                              ),
                              borderRadius: BorderRadius.all(
                                Radius.circular(16),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Container(
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FCFF),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: const Color(0xFFD0DFEE),
                            ),
                          ),
                          child: SwitchListTile.adaptive(
                            value: _postAnonymously,
                            onChanged: (value) =>
                                setState(() => _postAnonymously = value),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 2,
                            ),
                            activeColor: const Color(0xFF0A3556),
                            title: const Text(
                              'Post anonymously',
                              style: TextStyle(
                                color: Color(0xFF133D5C),
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            subtitle: const Text(
                              'Shown as Anonymous. Admins can still review your identity.',
                              style: TextStyle(
                                color: Color(0xFF6A8198),
                                fontSize: 12.2,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                        if (_selectedImages.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Text(
                            "Attached photos (${_selectedImages.length}/4)",
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF1C4B71),
                            ),
                          ),
                          const SizedBox(height: 8),
                          _buildSelectedMediaPreview(),
                        ],
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: _locationText == null
                                ? const Color(0xFFF5F8FC)
                                : const Color(0xFFEAF4FF),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: _locationText == null
                                  ? const Color(0xFFDCE6F1)
                                  : const Color(0xFFC6DCF2),
                            ),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.location_on_rounded,
                                size: 18,
                                color: Color(0xFF1E5E90),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _locationText ??
                                      "Add your location to improve local context.",
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600,
                                    color: _locationText == null
                                        ? const Color(0xFF6D8195)
                                        : const Color(0xFF184260),
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: _buildComposerAction(
                                icon: Icons.image_outlined,
                                label: "Add Photo",
                                onPressed: _pickImage,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _buildComposerAction(
                                icon: Icons.location_on_outlined,
                                label: _locationText == null
                                    ? "Use Location"
                                    : "Refresh Location",
                                onPressed: () => _getLocation(),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: vertical),
                  SizedBox(
                    height: 54,
                    child: ElevatedButton.icon(
                      onPressed: (_isLoading || !hasDraft) ? null : _submitPost,
                      icon: _isLoading
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2.2,
                              ),
                            )
                          : const Icon(
                              Icons.send_rounded,
                              color: Colors.white,
                              size: 18,
                            ),
                      label: Text(
                        _isLoading ? "Posting..." : "Post to Community",
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0A3556),
                        disabledBackgroundColor: const Color(0xFFB9CADB),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
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
