import 'dart:convert';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../l10n/app_localizations.dart';
import '../utils/responsive.dart';
import '../screens/philippine_locations.dart';

class AdminPcgManagementPage extends StatefulWidget {
  const AdminPcgManagementPage({super.key});

  @override
  State<AdminPcgManagementPage> createState() => _AdminPcgManagementPageState();
}
class _AdminPcgManagementPageState extends State<AdminPcgManagementPage> {
  bool _resettingId = false;
  String? _currentUserId;
  String? _station;
  bool _isWebAdmin = false;
  bool _loadingUser = true;
  String? _reviewingApprovalId;

  AppLocalizations get _l => AppLocalizations.of(context)!;

  @override
  void dispose() {
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _loadCurrentUser();
  }

  Query<Map<String, dynamic>> _pcgQuery() {
    // Fetch a reasonable slice of users; we filter PCG roles client-side to allow mixed role strings.
    return FirebaseFirestore.instance.collection('users').limit(200);
  }

  ImageProvider<Object>? _avatarImageProvider(Map<String, dynamic> data) {
    final base64Value = (data['profileImageBase64'] ?? '').toString().trim();
    if (base64Value.isNotEmpty) {
      try {
        return MemoryImage(base64Decode(base64Value));
      } catch (_) {}
    }

    final imageUrl = (data['profileImageUrl'] ??
            data['photo_url'] ??
            data['authPhotoUrl'] ??
            data['avatarUrl'])
        ?.toString()
        .trim();
    if (imageUrl != null && imageUrl.isNotEmpty) {
      return NetworkImage(imageUrl);
    }

    return null;
  }

  Future<void> _showChangePasswordDialog(
    BuildContext context, {
    required String email,
    required String userId,
  }) async {
    final l = _l;
    final currentController = TextEditingController();
    final newController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    await showDialog(
      context: context,
      builder: (ctx) {
        bool saving = false;
        bool showCurrentPassword = false;
        bool showNewPassword = false;

        Future<void> handleChange(StateSetter setDialogState) async {
          if (!formKey.currentState!.validate()) return;
          final trimmedEmail = email.trim();

          if (trimmedEmail.isEmpty) {
            Navigator.pop(ctx);
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(l.userDoesNotHaveAnEmailOnRecord)),
            );
            return;
          }

          final user = FirebaseAuth.instance.currentUser;
          if (user == null) {
            Navigator.pop(ctx);
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(l.noUserIsCurrentlySignedIn)),
            );
            return;
          }

          // Admins cannot directly change another user's password; send a reset email instead.
          if (user.uid != userId) {
            Navigator.pop(ctx);
            await _sendResetEmail(trimmedEmail);
            return;
          }

          try {
            setDialogState(() => saving = true);
            final credential = EmailAuthProvider.credential(
              email: trimmedEmail,
              password: currentController.text,
            );
            await user.reauthenticateWithCredential(credential);
            await user.updatePassword(newController.text);
            if (!mounted) return;
            Navigator.pop(ctx);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(l.passwordUpdatedSuccessfully)),
            );
          } on FirebaseAuthException catch (e) {
            if (!mounted) return;
            setDialogState(() => saving = false);
            String message;
            switch (e.code) {
              case 'wrong-password':
                message = l.currentPasswordIsIncorrect;
                break;
              case 'requires-recent-login':
                message =
                    l.pleaseLogInAgainBeforeChangingYourPasswordForSecurityReasons;
                break;
              case 'user-mismatch':
                message = l.adminPcgSignedInUserMismatch;
                break;
              default:
                message = e.message ?? l.adminPcgPasswordUpdateFailedPrefix;
                break;
            }
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(message)),
            );
          } catch (e) {
            if (!mounted) return;
            setDialogState(() => saving = false);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('${l.adminPcgPasswordUpdateFailedPrefix}: $e'),
              ),
            );
          }
        }

        return StatefulBuilder(
          builder: (dialogCtx, setDialogState) {
            InputDecoration passwordFieldDecoration({
              required String label,
              required IconData icon,
              required bool obscured,
              required VoidCallback onToggle,
            }) {
              return InputDecoration(
                labelText: label,
                prefixIcon: Icon(
                  icon,
                  size: 20,
                  color: const Color(0xFF5B7083),
                ),
                suffixIcon: IconButton(
                  onPressed: onToggle,
                  icon: Icon(
                    obscured
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    color: const Color(0xFF627D98),
                  ),
                ),
                filled: true,
                fillColor: const Color(0xFFF7FBFE),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: const BorderSide(color: Color(0xFFD7E6F5)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: const BorderSide(
                    color: Color(0xFF0A4D68),
                    width: 1.4,
                  ),
                ),
                labelStyle: const TextStyle(
                  color: Color(0xFF627D98),
                  fontWeight: FontWeight.w600,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 18,
                ),
              );
            }

            return AlertDialog(
              backgroundColor: Colors.white,
              surfaceTintColor: Colors.transparent,
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 24,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(28),
              ),
              titlePadding: const EdgeInsets.fromLTRB(22, 20, 22, 10),
              contentPadding: const EdgeInsets.fromLTRB(22, 0, 22, 12),
              actionsPadding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
              title: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: const Color(0xFFEAF3FF),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(
                      Icons.lock_reset_rounded,
                      color: Color(0xFF0A4D68),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      l.changePassword,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF102A43),
                      ),
                    ),
                  ),
                ],
              ),
              content: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l.adminPcgPasswordChangeDescription,
                      style: const TextStyle(
                        fontSize: 13.2,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF627D98),
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 18),
                    TextFormField(
                      controller: currentController,
                      obscureText: !showCurrentPassword,
                      decoration: passwordFieldDecoration(
                        label: l.currentPassword,
                        icon: Icons.key_rounded,
                        obscured: !showCurrentPassword,
                        onToggle: () => setDialogState(() {
                          showCurrentPassword = !showCurrentPassword;
                        }),
                      ),
                      validator: (v) => (v == null || v.isEmpty)
                          ? l.pleaseEnterYourPassword
                          : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: newController,
                      obscureText: !showNewPassword,
                      decoration: passwordFieldDecoration(
                        label: l.newPassword,
                        icon: Icons.lock_outline_rounded,
                        obscured: !showNewPassword,
                        onToggle: () => setDialogState(() {
                          showNewPassword = !showNewPassword;
                        }),
                      ),
                      validator: (v) => (v == null || v.length < 6)
                          ? l.passwordMustBeAtLeast6Characters
                          : null,
                    ),
                    const SizedBox(height: 14),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF7FBFE),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFDCEAF4)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.info_outline_rounded,
                            size: 18,
                            color: Color(0xFF154A79),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              l.adminPcgPasswordSafetyHint,
                              style: const TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF486581),
                                height: 1.35,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogCtx),
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFF627D98),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                  ),
                  child: Text(
                    l.cancel,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                FilledButton(
                  onPressed: saving ? null : () => handleChange(setDialogState),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF0A4D68),
                    foregroundColor: Colors.white,
                    minimumSize: const Size(126, 48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          l.updatePassword,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _openEditSheet(QueryDocumentSnapshot<Map<String, dynamic>> doc) async {
    final l = _l;
    final data = doc.data();
    const accentColor = Color(0xFF0A4D68);
    final nameController = TextEditingController(
      text: (data['fullName'] ?? data['name'] ?? data['station'] ?? '').toString(),
    );
    final emailController = TextEditingController(text: (data['email'] ?? '').toString());
    final contactController = TextEditingController(text: (data['contact_number'] ?? '').toString());
    final stationController = TextEditingController(text: (data['station'] ?? '').toString());
    String? selectedRegion = (data['region'] ?? '').toString().trim().isEmpty ? null : (data['region'] ?? '').toString();
    String? selectedProvince =
        (data['province'] ?? '').toString().trim().isEmpty ? null : (data['province'] ?? '').toString();
    String? selectedMunicipality =
        (data['municipality'] ?? '').toString().trim().isEmpty ? null : (data['municipality'] ?? '').toString();
    final formKey = GlobalKey<FormState>();
    String initialsForName(String name) {
      final parts = name.trim().split(RegExp(r'\s+')).where((e) => e.isNotEmpty).toList();
      if (parts.isEmpty) return '?';
      final first = parts.first;
      final last = parts.length > 1 ? parts.last : '';
      final firstChar = first.isNotEmpty ? first.substring(0, 1).toUpperCase() : '';
      final lastChar = last.isNotEmpty ? last.substring(0, 1).toUpperCase() : '';
      final combined = (firstChar + lastChar).trim();
      return combined.isEmpty ? '?' : combined;
    }

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
        builder: (sheetContext) {
          bool saving = false;
          File? avatarFile;
          String? avatarUrl = (data['profileImageUrl'] ??
                  data['photo_url'] ??
                  data['authPhotoUrl'] ??
                  data['avatarUrl'])
              ?.toString();

          return StatefulBuilder(
            builder: (context, setModalState) {
              Future<void> save() async {
                if (!formKey.currentState!.validate()) return;
                final trimmedEmail = emailController.text.trim();
                final trimmedContact = contactController.text.trim();
                final existingEmail = (data['email'] ?? '').toString().trim();
                final existingContact = (data['contact_number'] ?? '').toString().trim();
                final emailChanged = trimmedEmail.isNotEmpty && trimmedEmail != existingEmail;
                final contactChanged = trimmedContact.isNotEmpty && trimmedContact != existingContact;
                final avatarChanged = avatarFile != null;
                String addCacheBuster(String url) {
                  final separator = url.contains('?') ? '&' : '?';
                  return '$url${separator}v=${DateTime.now().millisecondsSinceEpoch}';
                }
                final payload = <String, dynamic>{
                  'fullName': nameController.text.trim(),
                  'email': trimmedEmail,
                  'contact_number': trimmedContact,
                  'station': stationController.text.trim(),
                  'region': selectedRegion ?? '',
                  'province': selectedProvince ?? '',
                  'municipality': selectedMunicipality ?? '',
                }..removeWhere((key, value) => value is String && value.trim().isEmpty);
                final hadFieldChanges = payload.isNotEmpty;

                if (payload.isEmpty && !avatarChanged) {
                  ScaffoldMessenger.of(sheetContext).showSnackBar(
                    SnackBar(content: Text(l.adminPcgNothingToUpdate)),
                  );
                  return;
                }

                setModalState(() => saving = true);
                try {
                // Mark email/contact as unverified only when they actually change.
                final confirmationFlags = <String, dynamic>{};
                if (emailChanged) {
                  confirmationFlags.addAll({
                    'email_verified': false,
                    'email_confirmation_required': true,
                  });
                }
                if (contactChanged) {
                  confirmationFlags.addAll({
                    'contact_verified': false,
                    'contact_confirmation_required': true,
                  });
                }

                // Upload avatar if changed
                bool photoUpdated = false;
                bool photoUsedInlineFallback = false;
                String? photoError;
                if (avatarFile != null && await avatarFile!.exists()) {
                  Future<void> uploadTo(String storagePath) async {
                    final ref = FirebaseStorage.instance.ref().child(storagePath);
                    await ref.putFile(avatarFile!, SettableMetadata(contentType: 'image/jpeg'));
                    avatarUrl = await ref.getDownloadURL();
                    avatarUrl = addCacheBuster(avatarUrl!);
                    payload['profileImageUrl'] = avatarUrl;
                    payload['photo_url'] = avatarUrl;
                    payload['avatarUrl'] = avatarUrl;
                    payload['profileImageBase64'] = FieldValue.delete();
                    photoUpdated = true;
                    setModalState(() {}); // refresh preview with new URL
                  }

                  final primaryPath = 'users/${doc.id}/profile.jpg';
                  try {
                    await uploadTo(primaryPath);
                  } on FirebaseException catch (e) {
                    // If editing another account and rules block writing their folder, try an admin-owned folder.
                    if (e.code == 'unauthorized' && _currentUserId != null && _currentUserId != doc.id) {
                      final fallbackPath = 'users/${_currentUserId}/managed/${doc.id}/profile.jpg';
                      try {
                        await uploadTo(fallbackPath);
                      } catch (e2) {
                        photoError = e2.toString();
                      }
                    } else {
                      photoError = e.message ?? e.toString();
                    }
                  } catch (e) {
                    photoError = e.toString();
                  }
                }

                if (photoError != null && avatarFile != null && await avatarFile!.exists()) {
                  payload['profileImageUrl'] = FieldValue.delete();
                  payload['photo_url'] = FieldValue.delete();
                  payload['avatarUrl'] = FieldValue.delete();
                  payload['profileImageBase64'] = base64Encode(await avatarFile!.readAsBytes());
                  avatarUrl = null;
                  photoUpdated = true;
                  photoUsedInlineFallback = true;
                  photoError = null;
                }

                if (photoError != null && !hadFieldChanges) {
                  setModalState(() => saving = false);
                  ScaffoldMessenger.of(sheetContext).showSnackBar(
                    SnackBar(
                      content: Text(
                        '${l.adminPcgPhotoUploadFailedPrefix}: $photoError',
                      ),
                    ),
                  );
                  return;
                }

                await doc.reference.set(
                  {
                    ...payload,
                    ...confirmationFlags,
                  },
                  SetOptions(merge: true),
                );
                if (!mounted || !sheetContext.mounted) return;
                Navigator.of(sheetContext).pop();
                String successMessage;
                if (photoUsedInlineFallback) {
                  successMessage = l.adminPcgProfilePhotoUpdated;
                } else if (photoError != null) {
                  successMessage = hadFieldChanges
                      ? '${l.adminPcgDetailsSavedButPhotoNotUpdatedPrefix}: $photoError'
                      : '${l.adminPcgPhotoNotUpdatedPrefix}: $photoError';
                } else if (photoUpdated) {
                  successMessage = l.adminPcgProfilePhotoUpdated;
                } else {
                  successMessage = l.adminPcgAccountDetailsUpdated;
                }
                if (emailChanged && contactChanged) {
                  successMessage =
                      '$successMessage ${l.adminPcgEmailAndContactUpdatedConfirmBoth}';
                } else if (emailChanged) {
                  successMessage =
                      '$successMessage ${l.adminPcgEmailUpdatedConfirm}';
                } else if (contactChanged) {
                  successMessage =
                      '$successMessage ${l.adminPcgContactUpdatedConfirm}';
                }
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(successMessage)),
                );
              } catch (e) {
                if (!mounted || !sheetContext.mounted) return;
                setModalState(() => saving = false);
                ScaffoldMessenger.of(sheetContext).showSnackBar(
                  SnackBar(
                    content: Text('${l.adminPcgUpdateFailedPrefix}: $e'),
                  ),
                );
              }
            }

            InputDecoration inputDecoration({
              required String label,
              required IconData icon,
            }) {
              return InputDecoration(
                labelText: label,
                prefixIcon: Icon(
                  icon,
                  size: 20,
                  color: const Color(0xFF5B7083),
                ),
                filled: true,
                fillColor: const Color(0xFFF7FBFE),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: const BorderSide(color: Color(0xFFD7E6F5)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: const BorderSide(
                    color: accentColor,
                    width: 1.4,
                  ),
                ),
                floatingLabelStyle: const TextStyle(
                  color: accentColor,
                  fontWeight: FontWeight.w700,
                ),
                labelStyle: const TextStyle(
                  color: Color(0xFF627D98),
                  fontWeight: FontWeight.w600,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 18,
                ),
              );
            }

            Widget textField({
              required TextEditingController controller,
              required String label,
              required IconData icon,
              TextInputType? keyboardType,
              String? Function(String?)? validator,
              ValueChanged<String>? onChanged,
            }) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: TextFormField(
                  controller: controller,
                  keyboardType: keyboardType,
                  onChanged: onChanged,
                  validator: validator,
                  decoration: inputDecoration(label: label, icon: icon),
                ),
              );
            }

            Widget sectionHeader(String title, String subtitle) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF102A43),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 12.8,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF627D98),
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              );
            }

            final mediaQuery = MediaQuery.of(sheetContext);
            final double bottomInset = mediaQuery.viewInsets.bottom;
            final remoteAvatarUrl = avatarUrl?.trim();
            ImageProvider<Object>? avatarPreview;
            if (avatarFile != null) {
              avatarPreview = FileImage(avatarFile!);
            } else if (remoteAvatarUrl != null && remoteAvatarUrl.isNotEmpty) {
              avatarPreview = NetworkImage(remoteAvatarUrl);
            }

            return FractionallySizedBox(
              heightFactor: 1,
              child: AnimatedPadding(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                padding: EdgeInsets.only(bottom: bottomInset),
                child: Container(
                  color: const Color(0xFFF1F6FA),
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 560),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                        child: Material(
                          color: Colors.white,
                          elevation: 18,
                          shadowColor: const Color(0xFF0A3558).withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(32),
                          clipBehavior: Clip.antiAlias,
                          child: SingleChildScrollView(
                            child: Form(
                              key: formKey,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 22),
                                    decoration: const BoxDecoration(
                                      gradient: LinearGradient(
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                        colors: [
                                          Color(0xFF083A64),
                                          Color(0xFF0F6A86),
                                        ],
                                      ),
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Center(
                                          child: Container(
                                            width: 42,
                                            height: 5,
                                            decoration: BoxDecoration(
                                              color: Colors.white.withValues(alpha: 0.34),
                                              borderRadius: BorderRadius.circular(999),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: 18),
                                        Row(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Stack(
                                              clipBehavior: Clip.none,
                                              children: [
                                                CircleAvatar(
                                                  radius: 34,
                                                  backgroundColor: Colors.white.withValues(alpha: 0.18),
                                                  backgroundImage: avatarPreview,
                                                  child: avatarPreview == null
                                                      ? Text(
                                                          initialsForName(nameController.text),
                                                          style: const TextStyle(
                                                            color: Colors.white,
                                                            fontWeight: FontWeight.w900,
                                                            fontSize: 18,
                                                          ),
                                                        )
                                                      : null,
                                                ),
                                                Positioned(
                                                  right: -2,
                                                  bottom: -2,
                                                  child: Material(
                                                    color: Colors.transparent,
                                                    child: InkWell(
                                                      onTap: saving
                                                          ? null
                                                          : () async {
                                                              final picked = await ImagePicker().pickImage(
                                                                source: ImageSource.gallery,
                                                              );
                                                              if (picked != null) {
                                                                setModalState(() {
                                                                  avatarFile = File(picked.path);
                                                                });
                                                              }
                                                            },
                                                      borderRadius: BorderRadius.circular(999),
                                                      child: Ink(
                                                        padding: const EdgeInsets.all(8),
                                                        decoration: const BoxDecoration(
                                                          color: Colors.white,
                                                          shape: BoxShape.circle,
                                                        ),
                                                        child: const Icon(
                                                          Icons.photo_camera_rounded,
                                                          size: 18,
                                                          color: accentColor,
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(width: 16),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    l.adminPcgEditAccountTitle,
                                                    style: const TextStyle(
                                                      fontSize: 22,
                                                      fontWeight: FontWeight.w900,
                                                      color: Colors.white,
                                                      height: 1.05,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 8),
                                                  Text(
                                                    l.adminPcgEditSheetSubtitle,
                                                    style: TextStyle(
                                                      fontSize: 13.2,
                                                      fontWeight: FontWeight.w500,
                                                      color: Colors.white.withValues(alpha: 0.86),
                                                      height: 1.4,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            const SizedBox(width: 10),
                                            Material(
                                              color: Colors.transparent,
                                              child: InkWell(
                                                onTap: saving
                                                    ? null
                                                    : () => Navigator.of(sheetContext).pop(),
                                                borderRadius: BorderRadius.circular(16),
                                                child: Ink(
                                                  width: 40,
                                                  height: 40,
                                                  decoration: BoxDecoration(
                                                    color: Colors.white.withValues(alpha: 0.12),
                                                    borderRadius: BorderRadius.circular(16),
                                                  ),
                                                  child: const Icon(
                                                    Icons.close_rounded,
                                                    color: Colors.white,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        sectionHeader(
                                          l.adminPcgAccountIdentity,
                                          l.adminPcgAccountIdentitySubtitle,
                                        ),
                                        textField(
                                          controller: nameController,
                                          label: l.adminPcgFullName,
                                          icon: Icons.person_outline_rounded,
                                          onChanged: (_) => setModalState(() {}),
                                        ),
                                        textField(
                                          controller: emailController,
                                          label: 'Email',
                                          icon: Icons.email_outlined,
                                          keyboardType: TextInputType.emailAddress,
                                          validator: (value) {
                                            if (value == null || value.trim().isEmpty) return null;
                                            final email = value.trim();
                                            final valid = RegExp(r'^[^@]+@[^@]+\.[^@]+$').hasMatch(email);
                                            return valid ? null : l.adminPcgEnterValidEmail;
                                          },
                                        ),
                                        textField(
                                          controller: contactController,
                                          label: l.adminPcgContactNumber,
                                          icon: Icons.phone_outlined,
                                          keyboardType: TextInputType.phone,
                                        ),
                                        Container(
                                          width: double.infinity,
                                          margin: const EdgeInsets.only(bottom: 18),
                                          padding: const EdgeInsets.all(14),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFF7FBFE),
                                            borderRadius: BorderRadius.circular(18),
                                            border: Border.all(
                                              color: const Color(0xFFDCEAF4),
                                            ),
                                          ),
                                          child: Row(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              const Icon(
                                                Icons.info_outline_rounded,
                                                size: 18,
                                                color: Color(0xFF154A79),
                                              ),
                                              const SizedBox(width: 10),
                                              Expanded(
                                                child: Text(
                                                  l.adminPcgContactConfirmationHint,
                                                  style: const TextStyle(
                                                    fontSize: 12.6,
                                                    fontWeight: FontWeight.w600,
                                                    color: Color(0xFF486581),
                                                    height: 1.35,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        sectionHeader(
                                          l.adminPcgLocationAssignment,
                                          l.adminPcgLocationAssignmentSubtitle,
                                        ),
                                        DropdownButtonFormField<String>(
                                          value: selectedRegion,
                                          decoration: inputDecoration(
                                            label: l.region,
                                            icon: Icons.public,
                                          ),
                                          items: locationData.keys
                                              .map<DropdownMenuItem<String>>(
                                                (region) => DropdownMenuItem<String>(
                                                  value: region,
                                                  child: Text(region),
                                                ),
                                              )
                                              .toList(),
                                          onChanged: (value) {
                                            setModalState(() {
                                              selectedRegion = value;
                                              selectedProvince = null;
                                              selectedMunicipality = null;
                                            });
                                          },
                                        ),
                                        const SizedBox(height: 12),
                                        DropdownButtonFormField<String>(
                                          value: selectedProvince,
                                          decoration: inputDecoration(
                                            label: l.province,
                                            icon: Icons.map_outlined,
                                          ),
                                          items: (selectedRegion == null
                                                  ? <String>[]
                                                  : locationData[selectedRegion!]!.keys.toList())
                                              .map<DropdownMenuItem<String>>(
                                                (province) => DropdownMenuItem<String>(
                                                  value: province,
                                                  child: Text(province),
                                                ),
                                              )
                                              .toList(),
                                          onChanged: (value) {
                                            setModalState(() {
                                              selectedProvince = value;
                                              selectedMunicipality = null;
                                            });
                                          },
                                        ),
                                        const SizedBox(height: 12),
                                        DropdownButtonFormField<String>(
                                          value: selectedMunicipality,
                                          decoration: inputDecoration(
                                            label: l.municipalityCity,
                                            icon: Icons.location_city_outlined,
                                          ),
                                          items: (selectedRegion == null || selectedProvince == null)
                                              ? const <DropdownMenuItem<String>>[]
                                              : locationData[selectedRegion!]![selectedProvince!]!.keys
                                                  .map<DropdownMenuItem<String>>(
                                                    (municipality) => DropdownMenuItem<String>(
                                                      value: municipality,
                                                      child: Text(municipality),
                                                    ),
                                                  )
                                                  .toList(),
                                          onChanged: (value) {
                                            setModalState(() {
                                              selectedMunicipality = value;
                                            });
                                          },
                                        ),
                                        const SizedBox(height: 12),
                                        textField(
                                          controller: stationController,
                                          label: l.adminPcgStationLabel,
                                          icon: Icons.anchor_rounded,
                                        ),
                                        const SizedBox(height: 10),
                                        Row(
                                          children: [
                                            Expanded(
                                              child: OutlinedButton(
                                                onPressed: saving
                                                    ? null
                                                    : () => Navigator.of(sheetContext).pop(),
                                                style: OutlinedButton.styleFrom(
                                                  foregroundColor: const Color(0xFF5B7083),
                                                  side: const BorderSide(
                                                    color: Color(0xFFD7E6F5),
                                                  ),
                                                  minimumSize: const Size.fromHeight(54),
                                                  shape: RoundedRectangleBorder(
                                                    borderRadius: BorderRadius.circular(18),
                                                  ),
                                                ),
                                                child: Text(
                                                  l.cancel,
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              flex: 2,
                                              child: FilledButton.icon(
                                                onPressed: saving ? null : save,
                                                style: FilledButton.styleFrom(
                                                  backgroundColor: accentColor,
                                                  foregroundColor: Colors.white,
                                                  disabledBackgroundColor: accentColor,
                                                  minimumSize: const Size.fromHeight(54),
                                                  shape: RoundedRectangleBorder(
                                                    borderRadius: BorderRadius.circular(18),
                                                  ),
                                                ),
                                                icon: saving
                                                    ? const SizedBox(
                                                        width: 18,
                                                        height: 18,
                                                        child: CircularProgressIndicator(
                                                          strokeWidth: 2.2,
                                                          valueColor: AlwaysStoppedAnimation<Color>(
                                                            Colors.white,
                                                          ),
                                                        ),
                                                      )
                                                    : const Icon(Icons.save_rounded),
                                                label: Text(
                                                  saving
                                                      ? l.adminPcgSavingChanges
                                                      : l.save,
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.w800,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
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
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _sendResetEmail(String? email) async {
    final l = _l;
    if (email == null || email.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.adminPcgNoEmailForPasswordReset)),
      );
      return;
    }
    setState(() => _resettingId = true);
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email.trim());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.adminPcgPasswordResetSent(email))),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${l.adminPcgResetFailedPrefix}: $e')),
      );
    } finally {
      if (mounted) setState(() => _resettingId = false);
    }
  }

  Future<void> _loadCurrentUser() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        _currentUserId = user.uid;
        final snap = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
        final data = snap.data() ?? {};
        final role = (data['role'] ?? '').toString().toLowerCase();
        final roleLabel = (data['roleLabel'] ?? data['role_label'] ?? '').toString().toLowerCase();
        _station = data['station']?.toString();
        _isWebAdmin = role.contains('web-admin') || roleLabel.contains('web-admin');
      }
    } catch (_) {
      _station = null;
      _isWebAdmin = false;
    } finally {
      if (mounted) setState(() => _loadingUser = false);
    }
  }

  String _pcgApprovalStatus(Map<String, dynamic> data) {
    final status = (data['pcgApprovalStatus'] ??
            data['registrationStatus'] ??
            data['approvalStatus'] ??
            '')
        .toString()
        .trim()
        .toLowerCase();
    if (status == 'pending' || status == 'rejected' || status == 'declined') {
      return status == 'declined' ? 'rejected' : status;
    }
    return 'approved';
  }

  String _pcgApprovalLabel(String status) {
    switch (status) {
      case 'pending':
        return 'Pending approval';
      case 'rejected':
        return 'Rejected';
      default:
        return 'Approved';
    }
  }

  Color _pcgApprovalBackground(String status) {
    switch (status) {
      case 'pending':
        return const Color(0xFFFFF2CC);
      case 'rejected':
        return const Color(0xFFFFE0DC);
      default:
        return const Color(0xFFE7F8EE);
    }
  }

  Color _pcgApprovalForeground(String status) {
    switch (status) {
      case 'pending':
        return const Color(0xFF8A6116);
      case 'rejected':
        return const Color(0xFFB42318);
      default:
        return const Color(0xFF1D9B5E);
    }
  }

  Future<void> _updatePcgApprovalStatus(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
    String status,
  ) async {
    if (_reviewingApprovalId != null) return;

    final approving = status == 'approved';
    final admin = FirebaseAuth.instance.currentUser;
    setState(() => _reviewingApprovalId = doc.id);

    try {
      final updates = <String, dynamic>{
        'pcgApprovalStatus': status,
        'registrationStatus': status,
        'approvalStatus': status,
        'reviewedAt': FieldValue.serverTimestamp(),
        'reviewedBy': admin?.uid ?? '',
        'reviewedByEmail': admin?.email ?? '',
        'updated_at': FieldValue.serverTimestamp(),
        'active': true,
        if (approving) ...{
          'approvedAt': FieldValue.serverTimestamp(),
          'approvedBy': admin?.uid ?? '',
          'approvedByEmail': admin?.email ?? '',
        } else ...{
          'rejectedAt': FieldValue.serverTimestamp(),
          'rejectedBy': admin?.uid ?? '',
          'rejectedByEmail': admin?.email ?? '',
        },
      };

      final db = FirebaseFirestore.instance;
      final requestRef = db.collection('pcg_registration_requests').doc(doc.id);
      final requestNotificationRef =
          db.collection('notifications').doc('pcg_registration_request_${doc.id}');

      await doc.reference.update(updates);
      if (approving) {
        await Future.wait([
          requestRef.delete(),
          requestNotificationRef.delete(),
        ]);
      } else {
        await Future.wait([
          requestRef.set({
            'status': status,
            'approvalStatus': status,
            'reviewedAt': FieldValue.serverTimestamp(),
            'reviewedBy': admin?.uid ?? '',
            'reviewedByEmail': admin?.email ?? '',
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true)),
          requestNotificationRef.set({
            'status': status,
            'approvalStatus': status,
            'isRead': true,
            'reviewedAt': FieldValue.serverTimestamp(),
            'reviewedBy': admin?.uid ?? '',
            'reviewedByEmail': admin?.email ?? '',
          }, SetOptions(merge: true)),
        ]);
      }

      await db.collection('notifications').add({
        'targetUserId': doc.id,
        'uid': doc.id,
        'type': 'pcg_registration_review',
        'category': 'pcg_registration',
        'title': approving
            ? 'PCG registration approved'
            : 'PCG registration rejected',
        'message': approving
            ? 'Your PCG registration has been approved. You can now sign in to the PCG admin dashboard.'
            : 'Your PCG registration was rejected. Please contact a PCG admin for assistance.',
        'timestamp': FieldValue.serverTimestamp(),
        'isRead': false,
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            approving
                ? 'PCG registration approved.'
                : 'PCG registration rejected.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not update approval status: $e')),
      );
    } finally {
      if (mounted) setState(() => _reviewingApprovalId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final padding = Responsive.pagePadding(context);
    final maxWidth = Responsive.maxContentWidth(context, maxWidth: 820);

    return Scaffold(
      backgroundColor: const Color(0xFFEAF4F8),
      appBar: AppBar(
        title: const Text(
          'Account Management & Registration',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.2,
          ),
        ),
        backgroundColor: const Color(0xFFEAF4F8),
        foregroundColor: const Color(0xFF102A43),
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _buildEditProfileBody(padding, maxWidth),
    );
  }

  Widget _buildEditProfileBody(double padding, double maxWidth) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFFF8FCFF),
            Color(0xFFEAF4F8),
          ],
        ),
      ),
      child: Stack(
        children: [
          _buildBackgroundOrb(
            top: -88,
            right: -72,
            size: 220,
            colors: const [
              Color(0x2913A4B4),
              Color(0x12103B66),
            ],
          ),
          _buildBackgroundOrb(
            top: 210,
            left: -92,
            size: 170,
            colors: const [
              Color(0x175BC0EB),
              Color(0x0A0A3558),
            ],
          ),
          SafeArea(
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxWidth),
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(
                    padding,
                    12,
                    padding,
                    padding + 12,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildPageHero(),
                      const SizedBox(height: 18),
                      _buildManagedAccountsSection(),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildManagedAccountsSection() {
    final l = _l;
    if (_loadingUser) {
      return _buildStateCard(
        child: const Padding(
          padding: EdgeInsets.symmetric(vertical: 48),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _pcgQuery().snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _buildStateCard(
            child: _buildStateMessage(
              icon: Icons.error_outline_rounded,
              message: l.adminPcgFailedToLoadAccounts,
            ),
          );
        }

        if (!snapshot.hasData) {
          return _buildStateCard(
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 48),
              child: Center(child: CircularProgressIndicator()),
            ),
          );
        }

        final docs = _buildVisiblePcgDocs(snapshot.data!.docs);
        if (docs.isEmpty) {
          return _buildStateCard(
            child: _buildStateMessage(
              icon: Icons.info_outline_rounded,
              message: l.adminPcgNoAccountsFound,
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Text(
                docs.length == 1
                    ? l.adminPcgManagedAccountSingular
                    : l.adminPcgManagedAccountPlural,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF34506A),
                  letterSpacing: 0.25,
                ),
              ),
            ),
            const SizedBox(height: 12),
            ...docs.map(_buildManagedAccountCard),
          ],
        );
      },
    );
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _buildVisiblePcgDocs(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> source,
  ) {
    bool isPcgUser(Map<String, dynamic> data) {
      bool matches(String raw) {
        final value = raw.toLowerCase();
        return value.contains('pcg') ||
            value.contains('coast guard') ||
            value.contains('sub-admin') ||
            value.contains('sub admin') ||
            value.contains('subadmin') ||
            value.contains('web-admin');
      }

      final role = (data['role'] ?? '').toString();
      final roleLabel = (data['roleLabel'] ?? data['role_label'] ?? '').toString();
      return matches(role) || matches(roleLabel);
    }

    var docs = source.where((doc) => isPcgUser(doc.data())).toList();

    if (!_isWebAdmin) {
      final stationNorm = (_station ?? '').toLowerCase().trim();
      if (stationNorm.isNotEmpty) {
        docs = docs.where((doc) {
          final station = (doc.data()['station'] ?? '')
              .toString()
              .toLowerCase()
              .trim();
          return station == stationNorm;
        }).toList();
      } else if (_currentUserId != null) {
        docs = docs.where((doc) => doc.id == _currentUserId).toList();
      } else {
        docs = [];
      }
    }

    docs.sort((a, b) {
      final aIsCurrent = a.id == _currentUserId;
      final bIsCurrent = b.id == _currentUserId;
      if (aIsCurrent && !bIsCurrent) return -1;
      if (!aIsCurrent && bIsCurrent) return 1;
      int statusPriority(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
        switch (_pcgApprovalStatus(doc.data())) {
          case 'pending':
            return 0;
          case 'rejected':
            return 1;
          default:
            return 2;
        }
      }

      final statusCompare = statusPriority(a).compareTo(statusPriority(b));
      if (statusCompare != 0) return statusCompare;
      final aName = (a.data()['fullName'] ?? a.data()['name'] ?? a.data()['station'] ?? '')
          .toString()
          .toLowerCase();
      final bName = (b.data()['fullName'] ?? b.data()['name'] ?? b.data()['station'] ?? '')
          .toString()
          .toLowerCase();
      return aName.compareTo(bName);
    });

    return docs;
  }

  Widget _buildBackgroundOrb({
    required double size,
    required List<Color> colors,
    double? top,
    double? left,
    double? right,
  }) {
    return Positioned(
      top: top,
      left: left,
      right: right,
      child: IgnorePointer(
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: colors,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPageHero() {
    final l = _l;
    final scopeLabel = _isWebAdmin
        ? l.adminPcgWebAdminAccess
        : (_station?.trim().isNotEmpty == true
              ? l.adminPcgStationScope(_station!.trim())
              : l.adminPcgPersonalAccountAccess);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF083A64),
            Color(0xFF0F6A86),
          ],
        ),
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF083A64).withValues(alpha: 0.22),
            blurRadius: 24,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            top: -28,
            right: -18,
            child: Container(
              width: 110,
              height: 110,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.08),
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  scopeLabel,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.9),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                l.adminPcgManagementTitle,
                style: const TextStyle(
                  fontSize: 27,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  height: 1.05,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                _isWebAdmin
                    ? l.adminPcgManagementSubtitleWebAdmin
                    : l.adminPcgManagementSubtitleAssigned,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w500,
                  height: 1.45,
                  color: Colors.white.withValues(alpha: 0.86),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStateCard({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0xFFD7E6F5)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0A3558).withValues(alpha: 0.07),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _buildStateMessage({
    required IconData icon,
    required String message,
  }) {
    return Column(
      children: [
        Container(
          width: 58,
          height: 58,
          decoration: const BoxDecoration(
            color: Color(0xFFEAF3FF),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: const Color(0xFF154A79)),
        ),
        const SizedBox(height: 14),
        Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 14,
            color: Color(0xFF243B53),
            fontWeight: FontWeight.w700,
            height: 1.35,
          ),
        ),
      ],
    );
  }

  Widget _buildManagedAccountCard(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final l = _l;
    final data = doc.data();
    const accentColor = Color(0xFF0A4D68);
    const inkColor = Color(0xFF102A43);
    final name =
        (data['fullName'] ?? data['name'] ?? data['station'] ?? '').toString();
    final email = (data['email'] ?? '').toString().trim();
    final contact = (data['contact_number'] ?? '').toString().trim();
    final station = (data['station'] ?? '').toString().trim();
    final region = (data['region'] ?? '').toString().trim();
    final province = (data['province'] ?? '').toString().trim();
    final municipality = (data['municipality'] ?? '').toString().trim();
    final role = (data['roleLabel'] ?? data['role_label'] ?? data['role'] ?? '')
        .toString()
        .trim();
    final displayName = name.isEmpty ? l.adminPcgUserFallback : name;
    final locationSummary = [region, province, municipality]
        .where((value) => value.isNotEmpty)
        .join(' | ');
    final avatarImage = _avatarImageProvider(data);
    final hasImage = avatarImage != null;
    final isOwnAccount = _currentUserId != null && _currentUserId == doc.id;
    final approvalStatus = _pcgApprovalStatus(data);
    final headerStatusLabel =
        isOwnAccount ? l.adminPcgMyAccount : _pcgApprovalLabel(approvalStatus);
    final headerStatusBg = isOwnAccount
        ? const Color(0xFFE7F8EE)
        : _pcgApprovalBackground(approvalStatus);
    final headerStatusFg = isOwnAccount
        ? const Color(0xFF1D9B5E)
        : _pcgApprovalForeground(approvalStatus);

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0xFFD7E6F5)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0A3558).withValues(alpha: 0.07),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFFF8FCFF),
                  Color(0xFFF2F8FC),
                ],
              ),
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: const Color(0xFFE6F1F7),
                  foregroundColor: accentColor,
                  backgroundImage: avatarImage,
                  child: hasImage
                      ? null
                      : Text(
                          _initials(
                            displayName.isNotEmpty
                                ? displayName
                                : (station.isNotEmpty ? station : 'PCG'),
                          ),
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 14,
                          ),
                        ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        displayName,
                        style: const TextStyle(
                          fontSize: 21,
                          fontWeight: FontWeight.w900,
                          color: inkColor,
                          height: 1.05,
                        ),
                      ),
                      if (station.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          l.adminPcgStationLabel,
                          style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF627D98),
                            letterSpacing: 0.35,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          station,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF486581),
                          ),
                        ),
                      ],
                      if (locationSummary.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          locationSummary,
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF627D98),
                            height: 1.35,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 11,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: headerStatusBg,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    headerStatusLabel,
                    style: TextStyle(
                      color: headerStatusFg,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    if (email.isNotEmpty)
                      _buildInfoChip(
                        icon: Icons.email_outlined,
                        label: email,
                        color: const Color(0xFF154A79),
                      ),
                    if (contact.isNotEmpty)
                      _buildInfoChip(
                        icon: Icons.phone_outlined,
                        label: contact,
                        color: const Color(0xFF0F6A86),
                      ),
                    if (role.isNotEmpty)
                      _buildInfoChip(
                        icon: Icons.verified_user_outlined,
                        label: role,
                        color: const Color(0xFF2D8C72),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF7FBFE),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFFDCEAF4)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l.adminPcgAssignmentDetails,
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800,
                          color: inkColor,
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (station.isNotEmpty)
                        _buildDetailRow(
                          label: l.adminPcgPcgStationLabel,
                          value: station,
                        ),
                      if (region.isNotEmpty)
                        _buildDetailRow(label: l.region, value: region),
                      if (province.isNotEmpty)
                        _buildDetailRow(label: l.province, value: province),
                      if (municipality.isNotEmpty)
                        _buildDetailRow(
                          label: l.municipalityCity,
                          value: municipality,
                          isLast: true,
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                _buildAccountActions(
                  doc: doc,
                  email: email,
                  isOwnAccount: isOwnAccount,
                  approvalStatus: approvalStatus,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAccountActions({
    required QueryDocumentSnapshot<Map<String, dynamic>> doc,
    required String email,
    required bool isOwnAccount,
    required String approvalStatus,
  }) {
    final l = _l;
    const accentColor = Color(0xFF0A4D68);

    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 460;
        final busy = _reviewingApprovalId == doc.id;
        final needsReview =
            !isOwnAccount && (approvalStatus == 'pending' || approvalStatus == 'rejected');

        final approveButton = FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF1D9B5E),
            foregroundColor: Colors.white,
            minimumSize: const Size.fromHeight(50),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          onPressed: busy
              ? null
              : () => _updatePcgApprovalStatus(doc, 'approved'),
          icon: busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.verified_user_rounded, size: 18),
          label: const Text(
            'Approve',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
        );

        final rejectButton = OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFFB42318),
            side: const BorderSide(color: Color(0xFFF5B7AE)),
            minimumSize: const Size.fromHeight(50),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          onPressed: busy
              ? null
              : () => _updatePcgApprovalStatus(doc, 'rejected'),
          icon: const Icon(Icons.block_rounded, size: 18),
          label: const Text(
            'Reject',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
        );

        final editButton = FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: accentColor,
            foregroundColor: Colors.white,
            minimumSize: const Size.fromHeight(50),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          onPressed: () => _openEditSheet(doc),
          icon: const Icon(Icons.edit_rounded, size: 18),
          label: Text(
            l.adminPcgEditInfo,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        );

        final passwordButton = OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFF5E4DB2),
            side: const BorderSide(color: Color(0xFFD8D2F8)),
            minimumSize: const Size.fromHeight(50),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          onPressed: _resettingId
              ? null
              : () {
                  if (!isOwnAccount) {
                    _sendResetEmail(email);
                    return;
                  }
                  _showChangePasswordDialog(
                    context,
                    email: email,
                    userId: doc.id,
                  );
                },
          icon: _resettingId
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.lock_reset_rounded, size: 18),
          label: Text(
            _resettingId ? l.adminPcgPleaseWait : l.changePassword,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        );

        final deleteButton = TextButton.icon(
          style: TextButton.styleFrom(
            foregroundColor: const Color(0xFFB42318),
            minimumSize: const Size.fromHeight(50),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          onPressed: () => _confirmDeleteAccount(doc),
          icon: const Icon(Icons.delete_outline_rounded, size: 18),
          label: Text(
            l.adminPcgDelete,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        );

        Widget reviewControls() {
          if (!needsReview) return const SizedBox.shrink();
          final reviewLabel = approvalStatus == 'pending'
              ? 'Review this PCG registration before dashboard access is enabled.'
              : 'This PCG registration was rejected. Approve it to restore dashboard access.';

          return Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _pcgApprovalBackground(approvalStatus),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: _pcgApprovalForeground(approvalStatus)
                    .withValues(alpha: 0.18),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      approvalStatus == 'pending'
                          ? Icons.pending_actions_rounded
                          : Icons.block_rounded,
                      color: _pcgApprovalForeground(approvalStatus),
                      size: 19,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        reviewLabel,
                        style: TextStyle(
                          color: _pcgApprovalForeground(approvalStatus),
                          fontSize: 12.8,
                          fontWeight: FontWeight.w700,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                if (narrow)
                  Column(
                    children: [
                      SizedBox(width: double.infinity, child: approveButton),
                      if (approvalStatus == 'pending') ...[
                        const SizedBox(height: 8),
                        SizedBox(width: double.infinity, child: rejectButton),
                      ],
                    ],
                  )
                else
                  Row(
                    children: [
                      Expanded(child: approveButton),
                      if (approvalStatus == 'pending') ...[
                        const SizedBox(width: 10),
                        Expanded(child: rejectButton),
                      ],
                    ],
                  ),
              ],
            ),
          );
        }

        if (narrow) {
          return Column(
            children: [
              reviewControls(),
              SizedBox(width: double.infinity, child: editButton),
              const SizedBox(height: 10),
              SizedBox(width: double.infinity, child: passwordButton),
              const SizedBox(height: 6),
              SizedBox(width: double.infinity, child: deleteButton),
            ],
          );
        }

        return Row(
          children: [
            Expanded(
              child: Column(
                children: [
                  reviewControls(),
                  Row(
                    children: [
                      Expanded(child: editButton),
                      const SizedBox(width: 10),
                      Expanded(child: passwordButton),
                      const SizedBox(width: 6),
                      deleteButton,
                    ],
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildInfoChip({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 7),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 250),
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow({
    required String label,
    required String value,
    bool isLast = false,
  }) {
    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 1),
            child: Icon(
              Icons.place_outlined,
              size: 17,
              color: Color(0xFF627D98),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: const TextStyle(
                  fontSize: 13.5,
                  height: 1.35,
                  color: Color(0xFF243B53),
                ),
                children: [
                  TextSpan(
                    text: '$label: ',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  TextSpan(
                    text: value,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _initials(String value) {
    final parts = value
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.isEmpty) return 'P';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return '${parts.first.substring(0, 1)}${parts[1].substring(0, 1)}'
        .toUpperCase();
  }

  Future<void> _confirmDeleteAccount(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) async {
    final l = _l;
    const accentColor = Color(0xFF0A4D68);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: const Color(0xFFF4F6FB),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text(
          l.adminPcgDeleteAccountQuestion,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        content: Text(
          l.adminPcgDeleteAccountMessage,
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: Text(
              l.cancel,
              style: TextStyle(color: Colors.grey.shade700),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: accentColor,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            ),
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: Text(l.adminPcgDelete),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await doc.reference.delete();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l.adminPcgAccountRemoved)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${l.adminPcgDeleteFailedPrefix}: $e')),
        );
      }
    }
  }

  // ignore: unused_element
  Widget _legacyBuild(BuildContext context) {
    final padding = Responsive.pagePadding(context);
    final maxWidth = Responsive.maxContentWidth(context, maxWidth: 1100);
    const accentColor = Color(0xFF0A4D68);
    final muted = Colors.black.withAlpha(166);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Profile'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 1,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(padding, 12, padding, padding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_loadingUser)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: CircularProgressIndicator(),
                      ),
                    )
                  else
                    StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                      stream: _pcgQuery().snapshots(),
                      builder: (context, snapshot) {
                        if (snapshot.hasError) {
                          return const Text('Failed to load accounts.');
                        }
                        if (!snapshot.hasData) {
                          return const Center(child: CircularProgressIndicator());
                        }
                        // Filter to PCG-related roles client-side to catch varied role strings.
                        bool isPcgUser(Map<String, dynamic> data) {
                          bool matches(String raw) {
                            final v = raw.toLowerCase();
                            return v.contains('pcg') ||
                                v.contains('coast guard') ||
                                v.contains('sub-admin') ||
                                v.contains('sub admin') ||
                                v.contains('subadmin') ||
                                v.contains('web-admin');
                          }

                          final role = (data['role'] ?? '').toString();
                          final roleLabel = (data['roleLabel'] ?? data['role_label'] ?? '').toString();
                          return matches(role) || matches(roleLabel);
                        }

                        var docs = snapshot.data!.docs.where((doc) => isPcgUser(doc.data())).toList();
                        if (!_isWebAdmin) {
                          final stationNorm = (_station ?? '').toLowerCase().trim();
                          if (stationNorm.isNotEmpty) {
                            docs = docs
                                .where((doc) {
                                  final s = (doc.data()['station'] ?? '').toString().toLowerCase().trim();
                                  return s == stationNorm;
                                })
                                .toList();
                          } else if (_currentUserId != null) {
                            // When station is unknown, show only the current user's account.
                            docs = docs.where((doc) => doc.id == _currentUserId).toList();
                          } else {
                            docs = [];
                          }
                        }
                        if (docs.isEmpty) {
                          return Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(16),
                            margin: const EdgeInsets.only(top: 12),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: Colors.grey.shade200),
                            ),
                            child: Row(
                              children: const [
                                Icon(Icons.info_outline, color: Colors.black54),
                                SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    'No PCG accounts found. Add a PCG user to manage their access here.',
                                    style: TextStyle(color: Colors.black87),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ...docs.map((doc) {
                              final data = doc.data();
                            final name = (data['fullName'] ?? data['name'] ?? data['station'] ?? '').toString();
                              final email = (data['email'] ?? '').toString();
                              final contact = (data['contact_number'] ?? '').toString();
                              final station = (data['station'] ?? '').toString();
                            final region = (data['region'] ?? '').toString();
                            final province = (data['province'] ?? '').toString();
                            final municipality = (data['municipality'] ?? '').toString();
                            final location = [region, province, municipality].where((e) => e.trim().isNotEmpty).join(' • ');

                            String initials(String value) {
                              final parts = value.trim().split(' ');
                              if (parts.length >= 2) {
                                return (parts[0].isNotEmpty ? parts[0][0] : '') +
                                    (parts[1].isNotEmpty ? parts[1][0] : '');
                              }
                              return value.isNotEmpty ? value[0] : 'P';
                            }

                            return Container(
                              width: double.infinity,
                              margin: const EdgeInsets.symmetric(vertical: 8),
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: Colors.grey.shade200),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withAlpha(10),
                                    blurRadius: 10,
                                    offset: const Offset(0, 6),
                                  ),
                                ],
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    crossAxisAlignment: CrossAxisAlignment.center,
                                    children: [
                                      CircleAvatar(
                                        radius: 24,
                                        backgroundColor: accentColor.withAlpha(31),
                                        foregroundColor: accentColor,
                                        backgroundImage: _avatarImageProvider(data),
                                        child: _avatarImageProvider(data) != null
                                            ? null
                                            : Text(
                                                initials(name.isNotEmpty ? name : (station.isNotEmpty ? station : 'PCG')),
                                                style: const TextStyle(fontWeight: FontWeight.w700),
                                              ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              name.isEmpty ? 'PCG User' : name,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w800,
                                                fontSize: 16,
                                              ),
                                            ),
                                            if (station.isNotEmpty)
                                              Padding(
                                                padding: const EdgeInsets.only(top: 2),
                                                child: Text(
                                                  'Station: $station',
                                                  style: TextStyle(fontSize: 13, color: muted),
                                                ),
                                              ),
                                            if (location.isNotEmpty)
                                              Padding(
                                                padding: const EdgeInsets.only(top: 2),
                                                child: Text(
                                                  location,
                                                  style: TextStyle(fontSize: 12.5, color: muted),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox.shrink(),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      if (email.isNotEmpty)
                                        Padding(
                                          padding: const EdgeInsets.only(bottom: 6),
                                          child: Row(
                                            children: [
                                              Icon(Icons.email_outlined, size: 16, color: muted),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: Text(
                                                  email,
                                                  style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      if (contact.isNotEmpty)
                                        Padding(
                                          padding: const EdgeInsets.only(bottom: 6),
                                          child: Row(
                                            children: [
                                              Icon(Icons.phone_outlined, size: 16, color: muted),
                                              const SizedBox(width: 8),
                                              Text(
                                                contact,
                                                style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
                                              ),
                                            ],
                                          ),
                                        ),
                                      if (station.isNotEmpty || region.isNotEmpty || province.isNotEmpty || municipality.isNotEmpty)
                                        Padding(
                                          padding: const EdgeInsets.only(top: 6),
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              if (station.isNotEmpty)
                                                Padding(
                                                  padding: const EdgeInsets.only(bottom: 4),
                                                  child: Row(
                                                    children: [
                                                      Icon(Icons.location_city_outlined, size: 16, color: muted),
                                                      const SizedBox(width: 8),
                                                      Expanded(
                                                        child: Text(
                                                          'PCG Station: $station',
                                                          style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              if (region.isNotEmpty)
                                                Padding(
                                                  padding: const EdgeInsets.only(bottom: 4),
                                                  child: Row(
                                                    children: [
                                                      Icon(Icons.public, size: 16, color: muted),
                                                      const SizedBox(width: 8),
                                                      Expanded(
                                                        child: Text(
                                                          'Region: $region',
                                                          style: TextStyle(fontSize: 13, color: muted),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              if (province.isNotEmpty)
                                                Padding(
                                                  padding: const EdgeInsets.only(bottom: 4),
                                                  child: Row(
                                                    children: [
                                                      Icon(Icons.map_outlined, size: 16, color: muted),
                                                      const SizedBox(width: 8),
                                                      Expanded(
                                                        child: Text(
                                                          'Province: $province',
                                                          style: TextStyle(fontSize: 13, color: muted),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              if (municipality.isNotEmpty)
                                                Row(
                                                  children: [
                                                    Icon(Icons.location_on_outlined, size: 16, color: muted),
                                                    const SizedBox(width: 8),
                                                    Expanded(
                                                      child: Text(
                                                        'City/Municipality: $municipality',
                                                        style: TextStyle(fontSize: 13, color: muted),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                            ],
                                          ),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [
                                      ElevatedButton.icon(
                                        style: ElevatedButton.styleFrom(
                                          elevation: 0,
                                          backgroundColor: accentColor,
                                          foregroundColor: Colors.white,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(999),
                                          ),
                                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                        ),
                                        icon: const Icon(Icons.edit, size: 18),
                                        onPressed: () => _openEditSheet(doc),
                                        label: const Text('Edit info'),
                                      ),
                                      OutlinedButton(
                                        style: OutlinedButton.styleFrom(
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                        ),
                                        onPressed: _resettingId
                                            ? null
                                            : () {
                                                final isOwnAccount = _currentUserId != null && _currentUserId == doc.id;
                                                if (!isOwnAccount) {
                                                  _sendResetEmail(email);
                                                  return;
                                                }
                                                _showChangePasswordDialog(
                                                  context,
                                                  email: email,
                                                  userId: doc.id,
                                                );
                                              },
                                        child: Text(_resettingId ? 'Please wait...' : 'Change password'),
                                      ),
                                      TextButton(
                                        style: TextButton.styleFrom(
                                          foregroundColor: Colors.red.shade700,
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                        ),
                                        onPressed: () async {
                                          final confirmed = await showDialog<bool>(
                                            context: context,
                                            builder: (dialogCtx) => AlertDialog(
                                              backgroundColor: const Color(0xFFF4F6FB),
                                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                                              title: const Text(
                                                'Delete account?',
                                                style: TextStyle(fontWeight: FontWeight.w800),
                                              ),
                                              content: const Text(
                                                'Are you sure you want to delete this account? This action cannot be undone.',
                                              ),
                                              actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                                              actions: [
                                                TextButton(
                                                  onPressed: () => Navigator.pop(dialogCtx, false),
                                                  child: Text(
                                                    'Cancel',
                                                    style: TextStyle(color: Colors.grey.shade700),
                                                  ),
                                                ),
                                                ElevatedButton(
                                                  style: ElevatedButton.styleFrom(
                                                    backgroundColor: accentColor,
                                                    foregroundColor: Colors.white,
                                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                                                  ),
                                                  onPressed: () => Navigator.pop(dialogCtx, true),
                                                  child: const Text('Delete'),
                                                ),
                                              ],
                                            ),
                                          );
                                          if (confirmed != true) return;
                                          try {
                                            await doc.reference.delete();
                                            if (mounted) {
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                const SnackBar(content: Text('Account removed from Firestore.')),
                                              );
                                            }
                                          } catch (e) {
                                            if (mounted) {
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                SnackBar(content: Text('Delete failed: $e')),
                                              );
                                            }
                                          }
                                        },
                                        child: const Text('Delete'),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            );
                          }),
                          ],
                        );
                      },
                    ),
                  const SizedBox(height: 24),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
