import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import '../../utils/loading_delay.dart';
import '../../utils/responsive.dart';
import '../profile/terms_and_condition_page.dart';

class GoogleFaceScanScreen extends StatefulWidget {
  final User user;
  final String role;
  final String roleLabel;
  final String idImagePath;
  final String? idBackImagePath;
  final String? idType;
  final Map<String, dynamic>? existingData;
  final String provider;
  final String providerLabel;
  final String providerId;

  const GoogleFaceScanScreen({
    super.key,
    required this.user,
    required this.role,
    required this.roleLabel,
    required this.idImagePath,
    this.idBackImagePath,
    this.idType,
    this.existingData,
    this.provider = 'google',
    this.providerLabel = 'google',
    this.providerId = 'google',
  });

  @override
  State<GoogleFaceScanScreen> createState() => _GoogleFaceScanScreenState();
}

class _GoogleFaceScanScreenState extends State<GoogleFaceScanScreen> {
  final ImagePicker _picker = ImagePicker();
  File? _faceImage;
  bool _isSubmitting = false;
  bool _uploadingFace = false;

  // TODO: Replace with your real FaceHub credentials/endpoints.
  static const String _facehubApiKey = '6f98c95d-5fab-42be-898c-155af3f6c030';
  static const String _facehubEndpoint = 'https://api.facehub.io/verify';

  void _showMessage(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _pickFace() async {
    final picked = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 85,
      preferredCameraDevice: CameraDevice.front,
    );
    if (picked != null) {
      setState(() => _faceImage = File(picked.path));
    }
  }

  Future<String?> _uploadFile(String path, String storagePath, {required bool isFace}) async {
    final file = File(path);
    if (!await file.exists()) return null;
    try {
      if (mounted && isFace) {
        setState(() => _uploadingFace = true);
      }
      final ref = FirebaseStorage.instance.ref().child(storagePath);
      await ref.putFile(file, SettableMetadata(contentType: 'image/jpeg'));
      return await ref.getDownloadURL();
    } finally {
      if (mounted && isFace) {
        setState(() => _uploadingFace = false);
      }
    }
  }

  Future<bool> _verifyWithFaceHub(File faceFile) async {
    if (_facehubApiKey.isEmpty || _facehubEndpoint.isEmpty) {
      // Skip FaceHub if not configured.
      return true;
    }
    try {
      final request = http.MultipartRequest('POST', Uri.parse(_facehubEndpoint))
        ..headers['Authorization'] = 'Bearer $_facehubApiKey'
        ..fields['user_id'] = widget.user.uid
        ..fields['flow'] = 'signup'
        ..files.add(await http.MultipartFile.fromPath('face', faceFile.path, contentType: MediaType('image', 'jpeg')));

      final streamed = await request.send();
      final response = await http.Response.fromStream(streamed);
      if (response.statusCode != 200) {
        _showMessage('Face verification failed (code ${response.statusCode}).');
        return false;
      }
      final body = response.body.toLowerCase();
      // Simple heuristic; adapt to real FaceHub schema.
      final ok = body.contains('verified') || body.contains('"passed":true') || body.contains('"match":true');
      if (!ok) {
        _showMessage('Face verification did not pass. Please retry in better lighting.');
      }
      return ok;
    } catch (e) {
      _showMessage('FaceHub error: $e');
      return false;
    }
  }

  Future<void> _submit() async {
    if (_faceImage == null) {
      _showMessage('Please scan your face to continue.');
      return;
    }
    if (_isSubmitting) return;

    final idFile = File(widget.idImagePath);
    if (!idFile.existsSync()) {
      _showMessage('ID image not found. Please retake your ID photo.');
      return;
    }
    File? idBackFile;
    if (widget.idBackImagePath != null) {
      final tmp = File(widget.idBackImagePath!);
      if (tmp.existsSync()) {
        idBackFile = tmp;
      }
    }

    setState(() => _isSubmitting = true);
    final loadingDelay = Future<void>.delayed(appLoadingDelay);

    try {
      final faceOk = await _verifyWithFaceHub(_faceImage!);
      if (!faceOk) {
        return;
      }

      final uid = widget.user.uid;
      final docRef = FirebaseFirestore.instance.collection('users').doc(uid);
      final idUrl = await _uploadFile(idFile.path, 'user_ids/${uid}_front.jpg', isFace: false);
      String? idBackUrl;
      if (idBackFile != null) {
        idBackUrl = await _uploadFile(idBackFile.path, 'user_ids/${uid}_back.jpg', isFace: false);
      }
      final faceUrl = await _uploadFile(_faceImage!.path, 'user_faces/$uid.jpg', isFace: true);

      if (idUrl == null) {
        _showMessage('Failed to upload ID image. Please try again.');
        return;
      }
      if (faceUrl == null) {
        _showMessage('Failed to upload face scan. Please try again.');
        return;
      }

      final updates = <String, dynamic>{
        'email': (widget.user.email ?? '').trim(),
        'provider': widget.provider,
        'providerLabel': widget.providerLabel,
        'provider_id': widget.providerId,
        'role': widget.role,
        'roleLabel': widget.roleLabel,
        'authPhotoUrl': widget.user.photoURL,
        'profileImageUrl': widget.user.photoURL,
        'photo_url': widget.user.photoURL,
        'email_verified': widget.user.emailVerified,
        'idVerificationUrl': idUrl,
        if (idBackUrl != null) 'idVerificationBackUrl': idBackUrl,
        if (widget.idType != null) 'idType': widget.idType,
        'faceVerificationUrl': faceUrl,
        'verificationStatus': 'submitted',
        'verificationSource': 'google_signup',
        'verificationSubmittedAt': FieldValue.serverTimestamp(),
        'updated_at': FieldValue.serverTimestamp(),
      };

      await docRef.set(updates, SetOptions(merge: true));

      final snap = await docRef.get();
      final data = snap.data() ?? widget.existingData ?? const <String, dynamic>{};
      final accepted = (data['acceptedTerms'] == true) || (data['termsAcceptedAt'] != null);

      if (!mounted) return;

      if (accepted) {
        Navigator.pushNamedAndRemoveUntil(context, '/dashboard', (_) => false);
      } else {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => const TermsAndConditionPage(
              continueRouteName: '/dashboard',
            ),
          ),
        );
      }
    } catch (e) {
      _showMessage('Unable to submit verification: $e');
    } finally {
      await loadingDelay;
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final padding = Responsive.pagePadding(context);
    final vertical = Responsive.verticalSpace(context);
    final maxWidth = Responsive.maxContentWidth(context, maxWidth: 680);
    const accent = Color(0xFF1A2B4C);
    const surface = Color.fromRGBO(255, 255, 255, 0.96);
    final muted = Colors.black.withOpacity(0.65);

    return Scaffold(
      backgroundColor: const Color.fromRGBO(219, 228, 237, 1),
      appBar: AppBar(
        title: const Text('Verify your identity'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 1,
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color.fromRGBO(219, 228, 237, 1),
                    Color.fromRGBO(219, 228, 237, 0.5),
                  ],
                ),
              ),
              child: SingleChildScrollView(
                padding: EdgeInsets.all(padding),
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                child: Container(
                  padding: EdgeInsets.all(padding + 6),
                  decoration: BoxDecoration(
                    color: surface,
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: Colors.black12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.06),
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
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: accent.withOpacity(0.12),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(Icons.verified_user, color: accent),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Face scan',
                                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Use your front camera to complete verification.',
                                  style: TextStyle(color: muted, fontSize: 13.5),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: vertical),
                      _UploadCard(
                        title: 'Step 2 \u00b7 Face scan',
                        subtitle: 'Use your front camera in good lighting.',
                        file: _faceImage,
                        onCamera: _isSubmitting ? null : _pickFace,
                        uploading: _uploadingFace,
                      ),
                      SizedBox(height: vertical),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _isSubmitting ? null : _submit,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: accent,
                            foregroundColor: Colors.white,
                            minimumSize: const Size.fromHeight(52),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            elevation: 2,
                            textStyle: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          child: _isSubmitting
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                  ),
                                )
                              : const Text('Submit verification'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _UploadCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final File? file;
  final VoidCallback? onCamera;
  final bool uploading;

  const _UploadCard({
    required this.title,
    required this.subtitle,
    required this.file,
    required this.onCamera,
    required this.uploading,
  });

  @override
  Widget build(BuildContext context) {
    final border = RoundedRectangleBorder(borderRadius: BorderRadius.circular(16));
    return Card(
      shape: border,
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(subtitle, style: TextStyle(color: Colors.grey.shade700)),
            const SizedBox(height: 10),
            Container(
              height: 170,
              width: double.infinity,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                color: Colors.grey.shade100,
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: file == null
                    ? Icon(Icons.image, size: 48, color: Colors.grey.shade400)
                    : Image.file(file!, fit: BoxFit.cover),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: uploading ? null : onCamera,
                    icon: uploading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.camera_alt),
                    label: const Text('Camera'),
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
