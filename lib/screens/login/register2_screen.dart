import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../l10n/app_localizations.dart';
import '../../utils/loading_delay.dart';
import '../../utils/responsive.dart';
import '../philippine_locations.dart';
import 'otp_verification_screen.dart';

class Register2Screen extends StatefulWidget {
  final String email;
  final String password;
  final String contactNumber;
  final bool phoneVerified;
  final bool emailPreverified;

  const Register2Screen({
    super.key,
    required this.email,
    required this.password,
    required this.contactNumber,
    this.phoneVerified = false,
    this.emailPreverified = false,
  });

  @override
  State<Register2Screen> createState() => _Register2ScreenState();
}

class _Register2ScreenState extends State<Register2Screen> {
  static final RegExp _uppercaseRegex = RegExp(r'[A-Z]');
  static final RegExp _digitRegex = RegExp(r'\d');
  static final RegExp _symbolRegex = RegExp(r'[^\w\s]');

  final firstNameController = TextEditingController();
  final lastNameController = TextEditingController();
  final birthDateController = TextEditingController();
  static const String _defaultRole = 'user';
  static const String _defaultRoleLabel = 'Community Member';

  String? selectedGender = 'Female';
  DateTime? selectedBirthDate;

  String? selectedRegion;
  String? selectedProvince;
  String? selectedMunicipality;
  String? selectedBarangay;

  bool isSubmitting = false;

  @override
  void initState() {
    super.initState();
    firstNameController.addListener(() {
      _capitalizeAllWords(firstNameController);
    });

    lastNameController.addListener(() {
      _capitalizeAllWords(lastNameController);
    });
  }

  @override
  void dispose() {
    firstNameController.dispose();
    lastNameController.dispose();
    birthDateController.dispose();
    super.dispose();
  }

  void _capitalizeAllWords(TextEditingController controller) {
    final text = controller.text;
    if (text.isEmpty) return;

    final formatted = text
        .split(' ')
        .map(
          (word) => word.isNotEmpty
              ? word[0].toUpperCase() + word.substring(1).toLowerCase()
              : '',
        )
        .join(' ');

    if (formatted != text) {
      final cursorPos = controller.selection.baseOffset;
      controller.value = TextEditingValue(
        text: formatted,
        selection: TextSelection.collapsed(offset: cursorPos),
      );
    }
  }

  void _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(2000),
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() {
        selectedBirthDate = picked;
        birthDateController.text = DateFormat('MM/dd/yyyy').format(picked);
      });
    }
  }

  String formatPhoneNumber(String number) {
    number = number.replaceAll(RegExp(r'\s+|-'), '');
    if (number.startsWith('09')) {
      return number.replaceFirst('0', '+63');
    } else if (number.startsWith('+63')) {
      return number;
    } else if (number.startsWith('9') && number.length == 10) {
      return '+63$number';
    } else {
      return number;
    }
  }

  List<String> getRegions() => locationData.keys.toList();
  List<String> getProvinces() => selectedRegion == null
      ? []
      : locationData[selectedRegion!]!.keys.toList();
  List<String> getMunicipalities() =>
      (selectedRegion == null || selectedProvince == null)
      ? []
      : locationData[selectedRegion!]![selectedProvince!]!.keys.toList();
  List<String> getBarangays() =>
      (selectedRegion == null ||
          selectedProvince == null ||
          selectedMunicipality == null)
      ? []
      : locationData[selectedRegion!]![selectedProvince!]![selectedMunicipality!] ??
            [];

  void _showMessage(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  bool _isStrongPassword(String password) {
    return password.length >= 8 &&
        _uppercaseRegex.hasMatch(password) &&
        _digitRegex.hasMatch(password) &&
        _symbolRegex.hasMatch(password);
  }

  String get _strongPasswordMessage =>
      'Use at least 8 characters with 1 uppercase letter, 1 number, and 1 symbol.';

  Set<String> _phoneCandidates(String contact) {
    final raw = contact.trim();
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    final candidates = <String>{if (raw.isNotEmpty) raw};

    if (digits.startsWith('63') && digits.length == 12) {
      candidates.add('+$digits');
      candidates.add('0${digits.substring(2)}');
      candidates.add(digits.substring(2));
    } else if (digits.startsWith('09') && digits.length == 11) {
      candidates.add(digits);
      candidates.add('+63${digits.substring(1)}');
      candidates.add(digits.substring(1));
    } else if (digits.startsWith('9') && digits.length == 10) {
      candidates.add(digits);
      candidates.add('0$digits');
      candidates.add('+63$digits');
    }

    return candidates.where((value) => value.trim().isNotEmpty).toSet();
  }

  Future<bool> _contactNumberExists(String contact, {String? ignoreUserId}) async {
    if (contact.isEmpty) return false;
    final candidates = _phoneCandidates(contact);
    const fields = [
      'contact_number',
      'contactNumber',
      'phoneNumber',
      'phone',
      'mobile',
    ];

    for (final field in fields) {
      for (final candidate in candidates) {
        final snap = await FirebaseFirestore.instance
            .collection('users')
            .where(field, isEqualTo: candidate)
            .limit(10)
            .get();
        final existsElsewhere = snap.docs.any((doc) => doc.id != ignoreUserId);
        if (existsElsewhere) return true;
      }
    }

    return false;
  }

  bool _isPcgUserData(Map<String, dynamic> data) {
    final combined =
        '${data['role'] ?? ''} ${data['roleLabel'] ?? data['role_label'] ?? ''}'
            .toLowerCase();
    return combined.contains('pcg') ||
        combined.contains('coast guard') ||
        combined.contains('sub-admin') ||
        combined.contains('sub admin') ||
        combined.contains('subadmin');
  }

  Future<bool> _stopIfPcgSignup(User user) async {
    final snap = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();
    if (!_isPcgUserData(snap.data() ?? const <String, dynamic>{})) {
      return false;
    }

    await FirebaseAuth.instance.signOut();
    if (!mounted) return true;
    _showMessage(
      'PCG accounts are created by the web PCG admin. Please sign in from Login.',
    );
    Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false);
    return true;
  }

  String _friendlyAuthError(FirebaseAuthException e) {
    switch (e.code) {
      case 'email-already-in-use':
        return 'Email is already in use. Please sign in or use another email.';
      case 'invalid-email':
        return 'Please enter a valid email address.';
      case 'weak-password':
        return _strongPasswordMessage;
      case 'operation-not-allowed':
        return 'Email sign-up is currently disabled. Please contact support.';
      case 'too-many-requests':
        return 'Too many attempts. Please try again later.';
      case 'network-request-failed':
        return 'Network error. Check your connection and try again.';
      default:
        return e.message ??
            'Unable to complete registration. Please try again.';
    }
  }

  Future<void> _register() async {
    if (isSubmitting) return;
    if (firstNameController.text.isEmpty ||
        lastNameController.text.isEmpty ||
        selectedBirthDate == null ||
        selectedGender == null ||
        selectedRegion == null ||
        selectedProvince == null ||
        selectedMunicipality == null ||
        selectedBarangay == null) {
      _showMessage(
        AppLocalizations.of(context)!.pleaseCompleteAllRequiredFields,
      );
      return;
    }

    final today = DateTime.now();
    final age =
        today.year -
        selectedBirthDate!.year -
        ((today.month < selectedBirthDate!.month ||
                (today.month == selectedBirthDate!.month &&
                    today.day < selectedBirthDate!.day))
            ? 1
            : 0);

    const minAge = 12;
    if (age < minAge) {
      _showMessage(
        AppLocalizations.of(context)!.youMustBeAtLeast18YearsOldToRegister,
      );
      return;
    }

    final formattedContact = formatPhoneNumber(widget.contactNumber);
    final trimmedEmail = widget.email.trim().toLowerCase();

    final firstName = firstNameController.text.trim();
    final lastName = lastNameController.text.trim();
    final birthdate = selectedBirthDate == null
        ? null
        : DateFormat('yyyy-MM-dd').format(selectedBirthDate!);

    final userData = {
      'email': trimmedEmail,
      'contact_number': formattedContact,
      if (formattedContact.isNotEmpty) 'contactNumber': formattedContact,
      if (formattedContact.isNotEmpty) 'phoneNumber': formattedContact,
      if (formattedContact.isNotEmpty) 'phone': formattedContact,
      if (formattedContact.isNotEmpty) 'mobile': formattedContact,
      if (formattedContact.isNotEmpty) 'contact_verified': true,
      if (formattedContact.isNotEmpty) 'contact_confirmation_required': false,
      'first_name': firstName,
      'last_name': lastName,
      'firstName': firstName,
      'lastName': lastName,
      'birth_date': selectedBirthDate?.toIso8601String(),
      'birthdate': birthdate,
      'gender': selectedGender,
      'role': _defaultRole,
      'roleLabel': _defaultRoleLabel,
      'region': selectedRegion,
      'province': selectedProvince,
      'municipality': selectedMunicipality,
      'barangay': selectedBarangay,
      'created_at': FieldValue.serverTimestamp(),
    };

    setState(() => isSubmitting = true);
    final loadingDelay = Future<void>.delayed(appLoadingDelay);

    try {

      if (trimmedEmail.isNotEmpty && !widget.emailPreverified) {
        final methods = await FirebaseAuth.instance.fetchSignInMethodsForEmail(
          trimmedEmail,
        );
        // Ignore email-link providers; only block if a real sign-in method exists.
        final usableMethods = methods.where((m) => m != 'emailLink').toList();
        if (usableMethods.isNotEmpty) {
          final providerHint = usableMethods.contains('google.com')
              ? ' with Google'
              : usableMethods.contains('facebook.com')
              ? ' with Facebook'
              : '';
          _showMessage(
            'Email is already in use$providerHint. Please sign in with that account or use another email.',
          );
          return;
        }
      }

      User? verifiedPhoneUser;
      if (widget.phoneVerified && formattedContact.isNotEmpty) {
        verifiedPhoneUser = FirebaseAuth.instance.currentUser;
        final authPhone = verifiedPhoneUser?.phoneNumber ?? '';
        if (verifiedPhoneUser == null ||
            !_phoneCandidates(formattedContact).contains(authPhone)) {
          _showMessage('Phone verification expired. Please restart signup.');
          return;
        }
      }

      if (formattedContact.isNotEmpty) {
        final exists = await _contactNumberExists(
          formattedContact,
          ignoreUserId: verifiedPhoneUser?.uid,
        );
        if (exists) {
          _showMessage(
            'Mobile number is already in use. Please use a different number.',
          );
          return;
        }
      }

      if (trimmedEmail.isNotEmpty) {
        final currentUser = FirebaseAuth.instance.currentUser;
        final isPrecreatedAccount =
            widget.emailPreverified &&
            currentUser != null &&
            (currentUser.email ?? '').toLowerCase() == trimmedEmail;

        if (isPrecreatedAccount) {
          if (!(currentUser.emailVerified)) {
            _showMessage('Please verify your email to continue.');
            return;
          }

          if (await _stopIfPcgSignup(currentUser)) return;

          await FirebaseFirestore.instance
              .collection('users')
              .doc(currentUser.uid)
              .set({
                ...userData,
                'email_verified': true,
                'updated_at': FieldValue.serverTimestamp(),
              }, SetOptions(merge: true));

          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Registration complete. You can now log in.'),
            ),
          );
          await FirebaseAuth.instance.signOut();
          if (!mounted) return;
          Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false);
          return;
        }

        if (!_isStrongPassword(widget.password)) {
          _showMessage(_strongPasswordMessage);
          return;
        }

        final credential = await FirebaseAuth.instance
            .createUserWithEmailAndPassword(
              email: trimmedEmail,
              password: widget.password,
            );

        await FirebaseFirestore.instance
            .collection('users')
            .doc(credential.user!.uid)
            .set(userData, SetOptions(merge: true));

        // Send verification email and stop auto-login; user must verify then log in.
        await credential.user!.sendEmailVerification();

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Verification link sent. Please verify your email, then log in.',
            ),
          ),
        );
        await FirebaseAuth.instance.signOut();
        if (!mounted) return;
        Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false);
        return;
      } else {
        if (widget.phoneVerified) {
          final currentUser =
              verifiedPhoneUser ?? FirebaseAuth.instance.currentUser;
          if (currentUser == null) {
            _showMessage('Session expired. Please restart signup.');
            return;
          }

          if (await _stopIfPcgSignup(currentUser)) return;

          await FirebaseFirestore.instance
              .collection('users')
              .doc(currentUser.uid)
              .set(userData, SetOptions(merge: true));

          await FirebaseAuth.instance.signOut();
          if (!mounted) return;
          Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false);
        } else {
          if (!mounted) return;
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => OTPVerificationScreen(
                phoneNumber: formattedContact,
                userData: userData,
              ),
            ),
          );
        }
      }
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      if (e.code == 'email-already-in-use') {
        try {
          final methods = await FirebaseAuth.instance
              .fetchSignInMethodsForEmail(trimmedEmail);
          final providerHint = methods.contains('google.com')
              ? ' with Google'
              : methods.contains('facebook.com')
              ? ' with Facebook'
              : '';
          _showMessage(
            'Email is already in use$providerHint. Please sign in with that account or use another email.',
          );
        } catch (_) {
          _showMessage(_friendlyAuthError(e));
        }
      } else {
        _showMessage(_friendlyAuthError(e));
      }
    } catch (e) {
      if (!mounted) return;
      _showMessage('Error: $e');
    } finally {
      await loadingDelay;
      if (mounted) setState(() => isSubmitting = false);
    }
  }

  InputDecoration buildInputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      floatingLabelBehavior: FloatingLabelBehavior.auto,
      filled: true,
      fillColor: const Color.fromARGB(153, 255, 255, 255),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Colors.black26),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final padding = Responsive.pagePadding(context);
    final vertical = Responsive.verticalSpace(context);
    final maxWidth = Responsive.maxContentWidth(context, maxWidth: 600);
    final logoHeight = Responsive.value<double>(
      context,
      mobile: 70,
      tablet: 80,
      desktop: 90,
    );

    return Scaffold(
      backgroundColor: const Color.fromRGBO(219, 228, 237, 1),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: SingleChildScrollView(
              padding: EdgeInsets.all(padding),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              child: Container(
                padding: EdgeInsets.all(padding + 6),
                decoration: BoxDecoration(
                  color: const Color.fromRGBO(255, 255, 255, 0.95),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.black26),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      l10n.personalInformation,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: vertical),
                    Image.asset(
                      'assets/image.png',
                      height: logoHeight,
                      fit: BoxFit.contain,
                    ),
                    SizedBox(height: vertical + 6),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final isNarrow = constraints.maxWidth < 420;
                        if (isNarrow) {
                          return Column(
                            children: [
                              TextField(
                                controller: firstNameController,
                                decoration: buildInputDecoration(
                                  l10n.firstName,
                                ),
                              ),
                              const SizedBox(height: 12),
                              TextField(
                                controller: lastNameController,
                                decoration: buildInputDecoration(l10n.lastName),
                              ),
                            ],
                          );
                        }

                        return Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: firstNameController,
                                decoration: buildInputDecoration(
                                  l10n.firstName,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: TextField(
                                controller: lastNameController,
                                decoration: buildInputDecoration(l10n.lastName),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: birthDateController,
                      readOnly: true,
                      onTap: _pickDate,
                      decoration: buildInputDecoration(
                        l10n.birthdate,
                      ).copyWith(suffixIcon: const Icon(Icons.calendar_today)),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: selectedGender,
                      decoration: buildInputDecoration(l10n.gender),
                      items: ['Female', 'Male']
                          .map(
                            (g) => DropdownMenuItem(
                              value: g,
                              child: Text(
                                g == 'Female' ? l10n.female : l10n.male,
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (val) => setState(() => selectedGender = val),
                    ),
                    const SizedBox(height: 12),
                    _buildDropdown(l10n.region, selectedRegion, getRegions(), (
                      val,
                    ) {
                      setState(() {
                        selectedRegion = val;
                        selectedProvince = null;
                        selectedMunicipality = null;
                        selectedBarangay = null;
                      });
                    }),
                    const SizedBox(height: 12),
                    _buildDropdown(
                      l10n.province,
                      selectedProvince,
                      getProvinces(),
                      (val) {
                        setState(() {
                          selectedProvince = val;
                          selectedMunicipality = null;
                          selectedBarangay = null;
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    _buildDropdown(
                      l10n.municipalityCity,
                      selectedMunicipality,
                      getMunicipalities(),
                      (val) {
                        setState(() {
                          selectedMunicipality = val;
                          selectedBarangay = null;
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    _buildDropdown(
                      l10n.barangay,
                      selectedBarangay,
                      getBarangays(),
                      (val) {
                        setState(() => selectedBarangay = val);
                      },
                    ),
                    SizedBox(height: vertical + 4),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final isNarrow = constraints.maxWidth < 420;
                        if (isNarrow) {
                          return Column(
                            children: [
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton(
                                  onPressed: () => Navigator.pop(context),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFFDCE3F0),
                                    foregroundColor: Colors.black87,
                                    elevation: 4,
                                    shadowColor: Colors.black26,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(30),
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 16,
                                    ),
                                  ),
                                  child: Text(l10n.back),
                                ),
                              ),
                              const SizedBox(height: 12),
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton(
                                  onPressed: isSubmitting ? null : _register,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF1A2B4C),
                                    foregroundColor: Colors.white,
                                    elevation: 4,
                                    shadowColor: Colors.black26,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(30),
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 16,
                                    ),
                                  ),
                                  child: const Text('Continue'),
                                ),
                              ),
                            ],
                          );
                        }

                        return Row(
                          children: [
                            Expanded(
                              child: ElevatedButton(
                                onPressed: () => Navigator.pop(context),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFFDCE3F0),
                                  foregroundColor: Colors.black87,
                                  elevation: 4,
                                  shadowColor: Colors.black26,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(30),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 16,
                                  ),
                                ),
                                child: Text(l10n.back),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: ElevatedButton(
                                onPressed: isSubmitting ? null : _register,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF1A2B4C),
                                  foregroundColor: Colors.white,
                                  elevation: 4,
                                  shadowColor: Colors.black26,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(30),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 16,
                                  ),
                                ),
                                child: const Text('Continue'),
                              ),
                            ),
                          ],
                        );
                      },
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

  Widget _buildDropdown(
    String label,
    String? value,
    List<String> items,
    ValueChanged<String?> onChanged,
  ) {
    return DropdownButtonFormField<String>(
      value: value,
      decoration: buildInputDecoration(label),
      items: items
          .map((item) => DropdownMenuItem(value: item, child: Text(item)))
          .toList(),
      onChanged: onChanged,
    );
  }
}
