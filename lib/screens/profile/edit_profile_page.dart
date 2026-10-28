import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import '../../l10n/app_localizations.dart';
import '../philippine_locations.dart';
import 'change_username.dart';

class EditProfilePage extends StatefulWidget {
  final Map<String, dynamic> userData;

  const EditProfilePage({super.key, required this.userData});

  @override
  State<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<EditProfilePage> {
  static const Color _ink = Color(0xFF102A43);
  static const Color _mutedInk = Color(0xFF486581);
  static const Color _brand = Color(0xFF0F3D69);
  static const Color _bgTop = Color(0xFFEAF3FF);
  static const Color _bgBottom = Color(0xFFF7FBFF);

  final _formKey = GlobalKey<FormState>();

  final TextEditingController firstNameController = TextEditingController();
  final TextEditingController lastNameController = TextEditingController();
  final TextEditingController birthdateController = TextEditingController();
  final TextEditingController emailController = TextEditingController();
  final TextEditingController mobileNumberController = TextEditingController();

  String? selectedRole;
  String? selectedGender;
  String? selectedRegion;
  String? selectedProvince;
  String? selectedMunicipality;
  String? selectedBarangay;

  List<String> provinceList = [];
  List<String> municipalityList = [];
  List<String> barangayList = [];

  File? _profileImage;
  String? _profileImageUrl;
  String? _profileImageBase64;
  bool _isSaving = false;

  String _withCacheBuster(String url) {
    final separator = url.contains('?') ? '&' : '?';
    return '$url${separator}v=${DateTime.now().millisecondsSinceEpoch}';
  }

  String _capitalize(String text) {
    if (text.isEmpty) return text;
    return text
        .split(' ')
        .map(
          (word) => word.isNotEmpty
              ? word[0].toUpperCase() + word.substring(1).toLowerCase()
              : word,
        )
        .join(' ');
  }

  String _firstNonEmptyValue(List<dynamic> candidates) {
    for (final value in candidates) {
      final text = (value ?? '').toString().trim();
      if (text.isNotEmpty) return text;
    }
    return '';
  }

  String _displayPhone(String value) {
    final cleaned = value.replaceAll(RegExp(r'[\s-]'), '').trim();
    if (cleaned.startsWith('+63') && cleaned.length == 13) {
      return '0${cleaned.substring(3)}';
    }
    return cleaned;
  }

  Future<void> _refreshEmailField() async {
    final authUser = FirebaseAuth.instance.currentUser;
    if (authUser == null) return;

    String firestoreEmail = '';
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(authUser.uid)
          .get();
      final data = doc.data() ?? <String, dynamic>{};
      final username = (data['username'] ?? '').toString().trim();
      firestoreEmail = _firstNonEmptyValue([
        data['email'],
        username.contains('@') ? username : '',
      ]);
    } catch (_) {}

    final resolved = _firstNonEmptyValue([firestoreEmail, authUser.email]);
    if (!mounted) return;
    setState(() {
      emailController.text = resolved;
    });
  }

  Future<void> _openEmailChangeFlow() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ChangeUsernamePage()),
    );
    await _refreshEmailField();
  }

  Future<void> _refreshMobileNumberField() async {
    final authUser = FirebaseAuth.instance.currentUser;
    if (authUser == null) return;

    String firestorePhone = '';
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(authUser.uid)
          .get();
      final data = doc.data() ?? <String, dynamic>{};
      firestorePhone = _firstNonEmptyValue([
        data['contact_number'],
        data['contactNumber'],
        data['phoneNumber'],
        data['phone'],
        data['mobile'],
        data['contact'],
      ]);
    } catch (_) {}

    final resolved = _firstNonEmptyValue([
      authUser.phoneNumber,
      firestorePhone,
    ]);
    if (!mounted) return;
    setState(() {
      mobileNumberController.text = _displayPhone(resolved);
    });
  }

  Future<void> _openMobileChangeFlow() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const ChangeUsernamePage(mobileOnly: true),
      ),
    );
    await _refreshMobileNumberField();
  }

  @override
  void initState() {
    super.initState();
    final authUser = FirebaseAuth.instance.currentUser;
    firstNameController.text = _capitalize(widget.userData['firstName'] ?? '');
    lastNameController.text = _capitalize(widget.userData['lastName'] ?? '');
    birthdateController.text = (widget.userData['birthdate'] ?? '').toString();
    emailController.text = _firstNonEmptyValue([
      widget.userData['email'],
      (widget.userData['username'] ?? '').toString().contains('@')
          ? widget.userData['username']
          : '',
      authUser?.email,
    ]);
    mobileNumberController.text = _displayPhone(
      _firstNonEmptyValue([
        widget.userData['contact_number'],
        widget.userData['contactNumber'],
        widget.userData['phoneNumber'],
        widget.userData['phone'],
        widget.userData['mobile'],
        widget.userData['contact'],
        authUser?.phoneNumber,
      ]),
    );

    selectedGender = widget.userData['gender'];
    selectedRole = widget.userData['role'];
    selectedRegion = widget.userData['region'];
    selectedProvince = widget.userData['province'];
    selectedMunicipality = widget.userData['municipality'];
    selectedBarangay = widget.userData['barangay'];

    _profileImageUrl = widget.userData['profileImageUrl'];
    _profileImageBase64 = widget.userData['profileImageBase64'];

    firstNameController.addListener(() {
      final text = firstNameController.text;
      final capitalized = _capitalize(text);
      if (text != capitalized) {
        final currentSelection = firstNameController.selection;
        firstNameController.value = firstNameController.value.copyWith(
          text: capitalized,
          selection: currentSelection,
        );
      }
    });

    lastNameController.addListener(() {
      final text = lastNameController.text;
      final capitalized = _capitalize(text);
      if (text != capitalized) {
        final currentSelection = lastNameController.selection;
        lastNameController.value = lastNameController.value.copyWith(
          text: capitalized,
          selection: currentSelection,
        );
      }
    });

    _updateProvinceList();
    _updateMunicipalityList();
    _updateBarangayList();
  }

  @override
  void dispose() {
    firstNameController.dispose();
    lastNameController.dispose();
    birthdateController.dispose();
    emailController.dispose();
    mobileNumberController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
      maxWidth: 1600,
      maxHeight: 1600,
    );
    if (picked != null) {
      setState(() {
        _profileImage = File(picked.path);
      });
    }
  }

  void _updateProvinceList() {
    if (selectedRegion != null && locationData.containsKey(selectedRegion)) {
      provinceList = locationData[selectedRegion]!.keys.toList();
    } else {
      provinceList = [];
    }

    if (selectedProvince != null && !provinceList.contains(selectedProvince)) {
      selectedProvince = null;
      selectedMunicipality = null;
      selectedBarangay = null;
    }
  }

  void _updateMunicipalityList() {
    if (selectedRegion != null && selectedProvince != null) {
      municipalityList =
          locationData[selectedRegion]?[selectedProvince]?.keys.toList() ?? [];
    } else {
      municipalityList = [];
    }

    if (selectedMunicipality != null &&
        !municipalityList.contains(selectedMunicipality)) {
      selectedMunicipality = null;
      selectedBarangay = null;
    }
  }

  void _updateBarangayList() {
    if (selectedRegion != null &&
        selectedProvince != null &&
        selectedMunicipality != null) {
      final raw =
          locationData[selectedRegion]?[selectedProvince]?[selectedMunicipality];
      barangayList = raw != null ? List<String>.from(raw) : [];
    } else {
      barangayList = [];
    }

    if (selectedBarangay != null && !barangayList.contains(selectedBarangay)) {
      selectedBarangay = null;
    }
  }

  void _selectBirthdate() async {
    DateTime initial =
        DateTime.tryParse(birthdateController.text) ?? DateTime(2000);
    DateTime? pickedDate = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
    );
    if (pickedDate != null) {
      birthdateController.text = pickedDate.toIso8601String().split('T')[0];
    }
  }

  Future<Uint8List> _prepareProfileImageBytes(File imageFile) async {
    final rawBytes = await imageFile.readAsBytes();
    try {
      final decoded = img.decodeImage(rawBytes);
      if (decoded == null) return rawBytes;

      final needsResize = decoded.width > 1600 || decoded.height > 1600;
      final normalized = needsResize
          ? img.copyResize(
              decoded,
              width: decoded.width >= decoded.height ? 1600 : null,
              height: decoded.height > decoded.width ? 1600 : null,
              interpolation: img.Interpolation.average,
            )
          : decoded;

      return Uint8List.fromList(img.encodeJpg(normalized, quality: 85));
    } catch (_) {
      return rawBytes;
    }
  }

  Future<String> _uploadProfileImage(Uint8List imageBytes, String uid) async {
    final storageRef = FirebaseStorage.instance.ref().child(
      'users/$uid/profile.jpg',
    );

    FirebaseException? lastError;
    for (var attempt = 1; attempt <= 2; attempt++) {
      try {
        await storageRef.putData(
          imageBytes,
          SettableMetadata(contentType: 'image/jpeg'),
        );
        lastError = null;
        break;
      } on FirebaseException catch (e) {
        lastError = e;
        debugPrint(
          'Profile image upload attempt $attempt failed: ${e.code} ${e.message}',
        );
        if (attempt < 2) {
          await Future.delayed(const Duration(milliseconds: 300));
        }
      }
    }

    if (lastError != null) {
      throw lastError;
    }

    final downloadUrl = await storageRef.getDownloadURL();
    return _withCacheBuster(downloadUrl);
  }

  Future<void> _saveProfile() async {
    if (_formKey.currentState!.validate()) {
      setState(() {
        _isSaving = true;
      });
      try {
        final user = FirebaseAuth.instance.currentUser;
        if (user == null) throw Exception("User not logged in.");
        final uid = user.uid;

        final Map<String, dynamic> updatedData = {
          'firstName': _capitalize(firstNameController.text.trim()),
          'lastName': _capitalize(lastNameController.text.trim()),
          'birthdate': birthdateController.text,
          'gender': selectedGender,
          'role': selectedRole,
          'region': selectedRegion,
          'province': selectedProvince,
          'municipality': selectedMunicipality,
          'barangay': selectedBarangay,
        };

        var usedInlineImageFallback = false;

        if (_profileImage != null && await _profileImage!.exists()) {
          final imageBytes = await _prepareProfileImageBytes(_profileImage!);
          try {
            final downloadUrl = await _uploadProfileImage(imageBytes, uid);
            updatedData['profileImageUrl'] = downloadUrl;
            updatedData['photo_url'] = downloadUrl;
            updatedData['avatarUrl'] = downloadUrl;
            updatedData['profileImageBase64'] = FieldValue.delete();
            _profileImageUrl = downloadUrl;
            _profileImageBase64 = null;
          } on FirebaseException catch (e) {
            final inlineBase64 = base64Encode(imageBytes);
            updatedData['profileImageUrl'] = FieldValue.delete();
            updatedData['photo_url'] = FieldValue.delete();
            updatedData['avatarUrl'] = FieldValue.delete();
            updatedData['profileImageBase64'] = inlineBase64;
            usedInlineImageFallback = true;
            _profileImageUrl = null;
            _profileImageBase64 = inlineBase64;
            debugPrint(
              'Profile image upload failed (${e.code}): ${e.message}. Saving inline fallback instead.',
            );
          } catch (e) {
            final inlineBase64 = base64Encode(imageBytes);
            updatedData['profileImageUrl'] = FieldValue.delete();
            updatedData['photo_url'] = FieldValue.delete();
            updatedData['avatarUrl'] = FieldValue.delete();
            updatedData['profileImageBase64'] = inlineBase64;
            usedInlineImageFallback = true;
            _profileImageUrl = null;
            _profileImageBase64 = inlineBase64;
            debugPrint(
              'Profile image upload failed unexpectedly: $e. Saving inline fallback instead.',
            );
          }
        }

        await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .update(updatedData);

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              usedInlineImageFallback
                  ? 'Profile updated. Photo was saved with offline fallback because cloud upload failed.'
                  : AppLocalizations.of(context)!.profileUpdatedSuccessfully,
            ),
          ),
        );
        Navigator.pop(context, true);
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              "${AppLocalizations.of(context)!.errorPrefix}: ${e.toString()}",
            ),
          ),
        );
      } finally {
        if (mounted) {
          setState(() {
            _isSaving = false;
          });
        }
      }
    }
  }

  InputDecoration getInputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      filled: true,
      fillColor: Colors.white.withValues(alpha: 0.9),
      labelStyle: const TextStyle(
        color: Color(0xFF627D98),
        fontWeight: FontWeight.w600,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFD3E2F2)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFD3E2F2)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: _brand, width: 1.6),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: const Color(0xFFEAF3FF),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Icon(icon, size: 17, color: _brand),
        ),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            color: _ink,
            fontSize: 16.5,
          ),
        ),
      ],
    );
  }

  Widget _buildDropdown<T>({
    required String label,
    required T? value,
    required List<T> items,
    required Function(T?) onChanged,
  }) {
    final safeValue = (value != null && !items.contains(value)) ? null : value;

    return DropdownButtonFormField<T>(
      initialValue: safeValue,
      items: items.map((T item) {
        return DropdownMenuItem<T>(value: item, child: Text(item.toString()));
      }).toList(),
      onChanged: (val) => onChanged(val),
      decoration: getInputDecoration(label),
    );
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final width = media.size.width;
    final horizontalPadding = width > 600 ? 32.0 : 16.0;
    final maxCardWidth = width > 900 ? 720.0 : 620.0;
    final fullName = '${firstNameController.text} ${lastNameController.text}'
        .trim();
    final profileName = fullName.isEmpty ? 'SeaGuard User' : fullName;
    final roleLabel = (selectedRole ?? widget.userData['role'] ?? 'Resident')
        .toString();

    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: _ink,
        scrolledUnderElevation: 0,
        titleSpacing: 0,
        centerTitle: false,
        title: Text(
          AppLocalizations.of(context)!.editProfile,
          style: const TextStyle(
            color: _ink,
            fontWeight: FontWeight.w900,
            fontSize: 29,
            letterSpacing: 0.2,
          ),
        ),
        iconTheme: const IconThemeData(color: _ink),
        actions: [
          FilledButton(
            onPressed: _isSaving ? null : _saveProfile,
            style: FilledButton.styleFrom(
              backgroundColor: _brand,
              foregroundColor: Colors.white,
              disabledBackgroundColor: const Color(0xFFB0B8C5),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(11),
              ),
              visualDensity: VisualDensity.compact,
              textStyle: const TextStyle(fontWeight: FontWeight.w700),
            ),
            child: _isSaving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : Text(AppLocalizations.of(context)!.save),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [_bgTop, _bgBottom],
          ),
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxCardWidth),
            child: Form(
              key: _formKey,
              child: ListView(
                padding: EdgeInsets.symmetric(
                  horizontal: horizontalPadding,
                  vertical: 18,
                ),
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Colors.white, Color(0xFFF2F8FF)],
                      ),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: const Color(0xFFD4E4F4)),
                      boxShadow: [
                        BoxShadow(
                          color: _ink.withValues(alpha: 0.06),
                          blurRadius: 14,
                          offset: const Offset(0, 7),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Stack(
                          children: [
                            CircleAvatar(
                              radius: 48,
                              backgroundColor: const Color(0xFFE8EBF3),
                              backgroundImage: _profileImage != null
                                  ? FileImage(_profileImage!)
                                  : (_profileImageBase64 != null
                                        ? MemoryImage(
                                                base64Decode(
                                                  _profileImageBase64!,
                                                ),
                                              )
                                              as ImageProvider
                                        : (_profileImageUrl != null
                                              ? NetworkImage(_profileImageUrl!)
                                                    as ImageProvider
                                              : null)),
                              child:
                                  (_profileImage == null &&
                                      _profileImageUrl == null &&
                                      _profileImageBase64 == null)
                                  ? const Icon(
                                      Icons.person,
                                      size: 52,
                                      color: Color(0xFF9AA3B5),
                                    )
                                  : null,
                            ),
                            Positioned(
                              bottom: 2,
                              right: 2,
                              child: Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  onTap: _pickImage,
                                  borderRadius: BorderRadius.circular(999),
                                  child: Ink(
                                    padding: const EdgeInsets.all(7),
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: Colors.white,
                                      border: Border.all(
                                        color: const Color(0xFFD3E2F2),
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: _ink.withValues(alpha: 0.14),
                                          blurRadius: 7,
                                          offset: const Offset(0, 3),
                                        ),
                                      ],
                                    ),
                                    child: const Icon(
                                      Icons.edit,
                                      size: 17,
                                      color: _ink,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                profileName,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 20,
                                  color: _ink,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                roleLabel,
                                style: const TextStyle(
                                  color: _mutedInk,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                'Tap the edit icon on your photo to update picture.',
                                style: TextStyle(
                                  color: Color(0xFF627D98),
                                  fontWeight: FontWeight.w500,
                                  fontSize: 12.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFFD4E4F4)),
                      boxShadow: [
                        BoxShadow(
                          color: _ink.withValues(alpha: 0.05),
                          blurRadius: 12,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        _buildSectionHeader(
                          'Basic Information',
                          Icons.badge_outlined,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: firstNameController,
                          decoration: getInputDecoration(
                            AppLocalizations.of(context)!.firstName,
                          ),
                          validator: (value) => value!.isEmpty
                              ? AppLocalizations.of(context)!.enterFirstName
                              : null,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: lastNameController,
                          decoration: getInputDecoration(
                            AppLocalizations.of(context)!.lastName,
                          ),
                          validator: (value) => value!.isEmpty
                              ? AppLocalizations.of(context)!.enterLastName
                              : null,
                        ),
                        const SizedBox(height: 16),
                        _buildSectionHeader(
                          'Contact',
                          Icons.alternate_email_rounded,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: emailController,
                          readOnly: true,
                          keyboardType: TextInputType.emailAddress,
                          onTap: _openEmailChangeFlow,
                          decoration: getInputDecoration('Email').copyWith(
                            helperText: 'Tap to change via verification',
                            helperStyle: const TextStyle(color: _mutedInk),
                            suffixIcon: IconButton(
                              icon: const Icon(
                                Icons.open_in_new,
                                color: _mutedInk,
                              ),
                              onPressed: _openEmailChangeFlow,
                              tooltip: 'Change Email',
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: mobileNumberController,
                          readOnly: true,
                          keyboardType: TextInputType.phone,
                          onTap: _openMobileChangeFlow,
                          decoration: getInputDecoration('Mobile Number')
                              .copyWith(
                                helperText:
                                    'Tap to change via OTP verification',
                                helperStyle: const TextStyle(color: _mutedInk),
                                suffixIcon: IconButton(
                                  icon: const Icon(
                                    Icons.open_in_new,
                                    color: _mutedInk,
                                  ),
                                  onPressed: _openMobileChangeFlow,
                                  tooltip: 'Change Mobile Number',
                                ),
                              ),
                        ),
                        const SizedBox(height: 16),
                        _buildSectionHeader(
                          'Personal Details',
                          Icons.person_outline_rounded,
                        ),
                        const SizedBox(height: 12),
                        _buildDropdown<String>(
                          label: AppLocalizations.of(context)!.role,
                          value: selectedRole,
                          items: [
                            AppLocalizations.of(context)!.userRole,
                            AppLocalizations.of(context)!.fisherman,
                          ],
                          onChanged: (val) =>
                              setState(() => selectedRole = val),
                        ),
                        const SizedBox(height: 12),
                        _buildDropdown<String>(
                          label: AppLocalizations.of(context)!.gender,
                          value: selectedGender,
                          items: [
                            AppLocalizations.of(context)!.male,
                            AppLocalizations.of(context)!.female,
                          ],
                          onChanged: (val) =>
                              setState(() => selectedGender = val),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: birthdateController,
                          readOnly: true,
                          decoration:
                              getInputDecoration(
                                AppLocalizations.of(context)!.birthdate,
                              ).copyWith(
                                suffixIcon: const Icon(
                                  Icons.calendar_today,
                                  color: _mutedInk,
                                ),
                              ),
                          onTap: _selectBirthdate,
                        ),
                        const SizedBox(height: 16),
                        _buildSectionHeader(
                          'Location',
                          Icons.location_on_outlined,
                        ),
                        const SizedBox(height: 12),
                        _buildDropdown<String>(
                          label: AppLocalizations.of(context)!.region,
                          value: selectedRegion,
                          items: locationData.keys.toList(),
                          onChanged: (val) {
                            setState(() {
                              selectedRegion = val;
                              selectedProvince = null;
                              selectedMunicipality = null;
                              selectedBarangay = null;
                              _updateProvinceList();
                              _updateMunicipalityList();
                              _updateBarangayList();
                            });
                          },
                        ),
                        const SizedBox(height: 12),
                        _buildDropdown<String>(
                          label: AppLocalizations.of(context)!.province,
                          value: selectedProvince,
                          items: provinceList,
                          onChanged: (val) {
                            setState(() {
                              selectedProvince = val;
                              selectedMunicipality = null;
                              selectedBarangay = null;
                              _updateMunicipalityList();
                              _updateBarangayList();
                            });
                          },
                        ),
                        const SizedBox(height: 12),
                        _buildDropdown<String>(
                          label: AppLocalizations.of(context)!.municipalityCity,
                          value: selectedMunicipality,
                          items: municipalityList,
                          onChanged: (val) {
                            setState(() {
                              selectedMunicipality = val;
                              selectedBarangay = null;
                              _updateBarangayList();
                            });
                          },
                        ),
                        const SizedBox(height: 12),
                        _buildDropdown<String>(
                          label: AppLocalizations.of(context)!.barangay,
                          value: selectedBarangay,
                          items: barangayList,
                          onChanged: (val) =>
                              setState(() => selectedBarangay = val),
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
    );
  }
}
