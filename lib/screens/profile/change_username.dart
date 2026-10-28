import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../l10n/app_localizations.dart';
import '../../utils/loading_delay.dart';
import 'change_phone_otp_screen.dart';

class ChangeUsernamePage extends StatefulWidget {
  final bool mobileOnly;

  const ChangeUsernamePage({super.key, this.mobileOnly = false});

  @override
  State<ChangeUsernamePage> createState() => _ChangeUsernamePageState();
}

class _ChangeUsernamePageState extends State<ChangeUsernamePage> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final passwordController = TextEditingController();
  final usernameController = TextEditingController();

  static final RegExp _emailRegex = RegExp(r'^[\w\.-]+@[\w\.-]+\.\w+$');
  static final RegExp _phoneRegex = RegExp(r'^(09|\+639)\d{9}$');

  String? _currentEmail;
  String? _currentPhoneNormalized;
  bool isVerified = false;
  bool showPasswordField = false;
  bool obscurePassword = true;
  bool isSubmitting = false;
  String displayUsername = 'Loading...';
  String displayMobile = 'Not set';
  bool _hasEmail = false;
  bool _hasMobile = false;
  bool _emailVerified = false;
  bool _mobileVerified = false;
  bool _emailPending = false;
  bool _mobilePending = false;

  @override
  void initState() {
    super.initState();
    _loadUser();
  }

  Future<void> _loadUser() async {
    final user = _auth.currentUser;
    final email = user?.email;
    final phone = user?.phoneNumber;
    String firestorePhone = '';
    String firestoreUsername = '';
    Map<String, dynamic> userData = const {};

    final uid = user?.uid;
    if (uid != null) {
      try {
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .get();
        userData = doc.data() ?? <String, dynamic>{};
        firestoreUsername = (userData['username'] ?? '').toString().trim();
        firestorePhone = (userData['contact_number'] ??
                userData['contactNumber'] ??
                userData['phoneNumber'] ??
                userData['phone'] ??
                userData['mobile'] ??
                userData['contact'] ??
                '')
            .toString()
            .trim();
      } catch (_) {}
    }

    final resolvedPhone = (phone ?? '').trim().isNotEmpty
        ? phone!
        : firestorePhone;
    _currentEmail = email;
    _currentPhoneNormalized = resolvedPhone.isNotEmpty
        ? _normalizePhoneInput(resolvedPhone)
        : null;

    if (!mounted) return;
    setState(() {
      _hasEmail = email != null && email.trim().isNotEmpty;
      _hasMobile = resolvedPhone.isNotEmpty;
      _emailVerified =
          (user?.emailVerified ?? false) || userData['email_verified'] == true;
      _emailPending =
          userData['email_confirmation_required'] == true && !_emailVerified;

      final authPhoneNormalized = _normalizePhoneInput((user?.phoneNumber ?? ''));
      _mobileVerified = userData['contact_verified'] == true ||
          (_currentPhoneNormalized != null &&
              _currentPhoneNormalized!.isNotEmpty &&
              authPhoneNormalized.isNotEmpty &&
              authPhoneNormalized == _currentPhoneNormalized);
      _mobilePending =
          userData['contact_confirmation_required'] == true && !_mobileVerified;

      displayMobile = resolvedPhone.isNotEmpty
          ? _maskPhone(resolvedPhone)
          : 'Not set';
      if (widget.mobileOnly) {
        if (resolvedPhone.isNotEmpty) {
          displayUsername = _maskPhone(resolvedPhone);
        } else if (email != null && email.isNotEmpty) {
          displayUsername = _maskEmail(email);
        } else {
          displayUsername = AppLocalizations.of(context)!.unknown;
        }
      } else {
        if (firestoreUsername.isNotEmpty) {
          final usernameAsPhone = _normalizePhoneInput(firestoreUsername);
          if (firestoreUsername.contains('@')) {
            displayUsername = _maskEmail(firestoreUsername);
          } else if (usernameAsPhone.isNotEmpty) {
            displayUsername = _maskPhone(firestoreUsername);
          } else {
            displayUsername = firestoreUsername;
          }
        } else if (email != null && email.isNotEmpty) {
          displayUsername = _maskEmail(email);
        } else if (resolvedPhone.isNotEmpty) {
          displayUsername = _maskPhone(resolvedPhone);
        } else {
          displayUsername = AppLocalizations.of(context)!.unknown;
        }
      }
    });
  }

  String _maskEmail(String email) {
    final parts = email.split('@');
    if (parts.length != 2) return email;
    final name = parts[0];
    final domain = parts[1];
    final visible = name.length >= 4 ? name.substring(name.length - 4) : name;
    final masked = '*' * (name.length - visible.length) + visible;
    return '$masked@$domain';
  }

  String _maskPhone(String phone) {
    if (phone.startsWith('+63')) {
      phone = '0${phone.substring(3)}';
    }
    if (phone.length != 11 || !phone.startsWith('09')) {
      return phone;
    }
    return '${phone.substring(0, 2)}** *** ${phone.substring(7)}';
  }

  Future<void> _verifyPassword() async {
    final user = _auth.currentUser;
    final password = passwordController.text.trim();

    if (password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.pleaseEnterYourPassword),
        ),
      );
      return;
    }

    try {
      final cred = EmailAuthProvider.credential(
        email: user?.email ?? '',
        password: password,
      );
      await user?.reauthenticateWithCredential(cred);

      setState(() {
        isVerified = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.passwordVerified)),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.incorrectPassword),
        ),
      );
    }
  }

  Future<void> _updateUserFields(Map<String, dynamic> updates) async {
    final user = _auth.currentUser;
    if (user == null) return;

    await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .update(updates);
  }

  String _normalizePhoneInput(String input) {
    var cleaned = input.replaceAll(RegExp(r'[^0-9+]'), '');
    if (cleaned.startsWith('+639') && cleaned.length == 13) {
      return '+63${cleaned.substring(3)}';
    }
    if (cleaned.startsWith('09') && cleaned.length == 11) {
      return '+63${cleaned.substring(1)}';
    }
    if (cleaned.startsWith('9') && cleaned.length == 10) {
      return '+63$cleaned';
    }
    return '';
  }

  Future<bool> _emailExistsElsewhere(String email) async {
    final uid = _auth.currentUser?.uid;
    final snap = await FirebaseFirestore.instance
        .collection('users')
        .where('email', isEqualTo: email)
        .limit(1)
        .get();
    if (snap.docs.isEmpty) return false;
    if (uid == null) return true;
    return snap.docs.first.id != uid;
  }

  Future<bool> _phoneExistsElsewhere(String formattedPhone) async {
    final uid = _auth.currentUser?.uid;
    final snap = await FirebaseFirestore.instance
        .collection('users')
        .where('contact_number', isEqualTo: formattedPhone)
        .limit(1)
        .get();
    if (snap.docs.isEmpty) return false;
    if (uid == null) return true;
    return snap.docs.first.id != uid;
  }

  String _friendlyEmailError(FirebaseAuthException e) {
    switch (e.code) {
      case 'invalid-email':
        return 'Please enter a valid email address.';
      case 'email-already-in-use':
        return 'That email is already in use. Try signing in instead.';
      case 'requires-recent-login':
        return AppLocalizations.of(
          context,
        )!.pleaseVerifyYourPasswordAgainBeforeChangingEmail;
      default:
        return e.message ?? AppLocalizations.of(context)!.failedToUpdateEmail;
    }
  }

  String _friendlyPhoneError(FirebaseAuthException e) {
    final message = (e.message ?? '').toUpperCase();
    switch (e.code) {
      case 'invalid-phone-number':
        return 'Invalid phone number. Use 09XXXXXXXXX or +63XXXXXXXXX.';
      case 'billing-not-enabled':
        return 'Phone OTP billing is not enabled for this Firebase project.';
      case 'app-not-authorized':
        return 'App not authorized. Add your SHA-1/SHA-256 to Firebase and rebuild.';
      case 'too-many-requests':
        return 'Too many attempts. Please try again later.';
      case 'network-request-failed':
        return 'Network error. Check your connection and try again.';
      default:
        if (message.contains('BILLING_NOT_ENABLED')) {
          return 'Phone OTP billing is not active yet for this Firebase project. Check the linked billing account and try again shortly.';
        }
        return e.message ?? AppLocalizations.of(context)!.verificationFailed;
    }
  }

  // ✅ FIXED EMAIL CHANGE LOGIC
  Future<void> _verifyEmailChange(String newEmail) async {
    final user = _auth.currentUser;
    if (user == null) return;

    if (!_emailRegex.hasMatch(newEmail)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid email address.')),
      );
      return;
    }

    if (isSubmitting) return;
    setState(() => isSubmitting = true);
    final loadingDelay = Future<void>.delayed(appLoadingDelay);

    try {
      if (_currentEmail != null &&
          _currentEmail!.toLowerCase() == newEmail.toLowerCase()) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('You are already using this email.')),
        );
        return;
      }

      final existsElsewhere = await _emailExistsElsewhere(newEmail);
      if (existsElsewhere) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('That email is already in use by another account.'),
          ),
        );
        return;
      }

      final methods = await _auth.fetchSignInMethodsForEmail(newEmail);
      if (methods.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'That email is already in use. Try signing in instead.',
            ),
          ),
        );
        return;
      }

      // Step 1: Update email with verification
      await user.verifyBeforeUpdateEmail(newEmail);

      // Step 2: Update Firestore
      await _updateUserFields({'email': newEmail, 'username': newEmail});

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(
              context,
            )!.emailUpdatedAVerificationEmailHasBeenSentToYourNewAddressPleaseVerifyIt,
          ),
        ),
      );
    } on FirebaseAuthException catch (e) {
      final message = _friendlyEmailError(e);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } finally {
      await loadingDelay;
      if (mounted) setState(() => isSubmitting = false);
    }
  }

  Future<void> _verifyPhoneChange(String phone) async {
    if (isSubmitting) return;
    final normalized = _normalizePhoneInput(phone);

    if (normalized.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Enter a valid Philippine number (09XXXXXXXXX or +63XXXXXXXXX).',
          ),
        ),
      );
      return;
    }

    if (_currentPhoneNormalized != null &&
        _currentPhoneNormalized == normalized) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You are already using this mobile number.'),
        ),
      );
      return;
    }

    final displayPhone = '0${normalized.substring(3)}';

    setState(() => isSubmitting = true);
    final loadingDelay = Future<void>.delayed(appLoadingDelay);

    final existsElsewhere = await _phoneExistsElsewhere(normalized);
    if (existsElsewhere) {
      await loadingDelay;
      if (!mounted) return;
      setState(() => isSubmitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('That mobile number is already in use.')),
      );
      return;
    }

    await _auth.verifyPhoneNumber(
      phoneNumber: normalized,
      verificationCompleted: (PhoneAuthCredential credential) async {
        await _auth.currentUser?.updatePhoneNumber(credential);
        await _updateUserFields({
          'contact_number': normalized,
          'username': displayPhone,
        });
        await loadingDelay;
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context)!.phoneNumberVerifiedSuccessfully,
            ),
          ),
        );
        setState(() => isSubmitting = false);
      },
      verificationFailed: (FirebaseAuthException e) async {
        await loadingDelay;
        if (!mounted) return;
        setState(() => isSubmitting = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_friendlyPhoneError(e))));
      },
      codeSent: (String verificationId, int? resendToken) async {
        await loadingDelay;
        if (!mounted) return;
        setState(() => isSubmitting = false);
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ChangePhoneOtpScreen(
              verificationId: verificationId,
              displayPhone: displayPhone,
              normalizedPhone: normalized,
            ),
          ),
        );
      },
      codeAutoRetrievalTimeout: (_) {},
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.mobileOnly
        ? 'Change Mobile Number'
        : AppLocalizations.of(context)!.changeUsernameTitle;

    return Scaffold(
      backgroundColor: const Color(0xFFF3F7FC),
      appBar: AppBar(
        title: Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            color: Color(0xFF102A43),
            fontSize: 28,
          ),
        ),
        backgroundColor: const Color(0xFFF3F7FC),
        foregroundColor: const Color(0xFF102A43),
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 260),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        child: isVerified ? _buildVerifiedScreen() : _buildVerifyPasswordScreen(),
      ),
    );
  }

  Widget _buildVerifyPasswordScreen() {
    final actionText = showPasswordField
        ? AppLocalizations.of(context)!.verify
        : (widget.mobileOnly
              ? 'Change Mobile Number'
              : AppLocalizations.of(context)!.changeUsername);

    return ListView(
      key: const ValueKey('verify-step'),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      children: [
        _buildHeaderCard(
          icon: showPasswordField
              ? Icons.lock_person_outlined
              : Icons.verified_user_outlined,
          title: widget.mobileOnly
              ? 'Secure mobile update'
              : 'Secure username update',
          subtitle: showPasswordField
              ? 'Confirm your current password to continue.'
              : 'Review your current account identity before making changes.',
        ),
        const SizedBox(height: 16),
        if (!widget.mobileOnly)
          _buildIdentityCard(
            label: AppLocalizations.of(context)!.currentUsername,
            value: displayUsername,
            hasValue: _hasEmail,
            verified: _emailVerified,
            pending: _emailPending,
          ),
        if (widget.mobileOnly)
          _buildIdentityCard(
            label: 'Current Mobile Number',
            value: displayMobile,
            hasValue: _hasMobile,
            verified: _mobileVerified,
            pending: _mobilePending,
          ),
        if (showPasswordField) ...[
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFD7E6F5)),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF0F2548).withValues(alpha: 0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppLocalizations.of(context)!.enterPasswordForVerification,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14.5,
                    color: Color(0xFF102A43),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: passwordController,
                  obscureText: obscurePassword,
                  decoration: InputDecoration(
                    hintText: AppLocalizations.of(context)!.password,
                    filled: true,
                    fillColor: const Color(0xFFF8FAFD),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 16,
                    ),
                    prefixIcon: const Icon(
                      Icons.lock_outline_rounded,
                      size: 19,
                      color: Color(0xFF627D98),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: Color(0xFFBCCCDC)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(
                        color: Color(0xFF2F6FB0),
                        width: 1.4,
                      ),
                    ),
                    suffixIcon: IconButton(
                      icon: Icon(
                        obscurePassword ? Icons.visibility_off : Icons.visibility,
                        color: const Color(0xFF627D98),
                      ),
                      onPressed: () =>
                          setState(() => obscurePassword = !obscurePassword),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          height: 52,
          child: FilledButton.icon(
            onPressed: () {
              if (!showPasswordField) {
                setState(() => showPasswordField = true);
              } else {
                _verifyPassword();
              }
            },
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF0F2548),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            icon: Icon(
              showPasswordField
                  ? Icons.verified_user_outlined
                  : Icons.arrow_forward_rounded,
            ),
            label: Text(
              actionText,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 15.5,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHeaderCard({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.white, Color(0xFFF0F7FF)],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFD7E6F5)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F2548).withValues(alpha: 0.06),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFFE9F2FF),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: const Color(0xFF154A79)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF102A43),
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: Color(0xFF486581),
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIdentityCard({
    required String label,
    required String value,
    required bool hasValue,
    required bool verified,
    required bool pending,
  }) {
    final verification = _verificationInfo(
      hasValue: hasValue,
      verified: verified,
      pending: pending,
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFD7E6F5)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F2548).withValues(alpha: 0.05),
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
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: Color(0xFF102A43),
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: verification.background,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      verification.icon,
                      size: 13,
                      color: verification.foreground,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      verification.label,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: verification.foreground,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              color: hasValue ? const Color(0xFF243B53) : const Color(0xFF627D98),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  _VerificationInfo _verificationInfo({
    required bool hasValue,
    required bool verified,
    required bool pending,
  }) {
    if (!hasValue) {
      return const _VerificationInfo(
        label: 'Not set',
        icon: Icons.remove_circle_outline,
        background: Color(0xFFECEFF3),
        foreground: Color(0xFF6B7280),
      );
    }
    if (verified) {
      return const _VerificationInfo(
        label: 'Verified',
        icon: Icons.check_circle_outline,
        background: Color(0xFFEAF8EE),
        foreground: Color(0xFF1F7A3E),
      );
    }
    if (pending) {
      return const _VerificationInfo(
        label: 'Pending',
        icon: Icons.hourglass_top_rounded,
        background: Color(0xFFFFF4DD),
        foreground: Color(0xFF9A6700),
      );
    }
    return const _VerificationInfo(
      label: 'Not verified',
      icon: Icons.error_outline,
      background: Color(0xFFFFEAEA),
      foreground: Color(0xFFB3261E),
    );
  }

  Widget _buildVerifiedScreen() {
    final label = widget.mobileOnly
        ? 'New mobile number'
        : AppLocalizations.of(context)!.newEmailOrMobileNumber;
    final hint = widget.mobileOnly
        ? 'Enter new mobile number'
        : AppLocalizations.of(context)!.enterNewEmailOrMobileNumber;

    return ListView(
      key: const ValueKey('update-step'),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      children: [
        _buildHeaderCard(
          icon: Icons.edit_note_rounded,
          title: widget.mobileOnly ? 'Update your mobile number' : 'Update username',
          subtitle: widget.mobileOnly
              ? 'We will verify the new number before saving.'
              : 'Enter a valid email or Philippine mobile number.',
        ),
        const SizedBox(height: 16),
        _buildIdentityCard(
          label: widget.mobileOnly
              ? 'Current Mobile Number'
              : AppLocalizations.of(context)!.currentUsername,
          value: widget.mobileOnly ? displayMobile : displayUsername,
          hasValue: widget.mobileOnly ? _hasMobile : _hasEmail,
          verified: widget.mobileOnly ? _mobileVerified : _emailVerified,
          pending: widget.mobileOnly ? _mobilePending : _emailPending,
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFD7E6F5)),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF0F2548).withValues(alpha: 0.05),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14.5,
                  color: Color(0xFF102A43),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: usernameController,
                keyboardType: widget.mobileOnly
                    ? TextInputType.phone
                    : TextInputType.emailAddress,
                decoration: InputDecoration(
                  hintText: hint,
                  filled: true,
                  fillColor: const Color(0xFFF8FAFD),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 16,
                  ),
                  prefixIcon: Icon(
                    widget.mobileOnly
                        ? Icons.phone_android_outlined
                        : Icons.alternate_email_rounded,
                    size: 19,
                    color: const Color(0xFF627D98),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: Color(0xFFBCCCDC)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(
                      color: Color(0xFF2F6FB0),
                      width: 1.4,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                widget.mobileOnly
                    ? 'Format: 09XXXXXXXXX or +63XXXXXXXXXX'
                    : 'Accepted: email address or Philippine mobile number',
                style: const TextStyle(
                  fontSize: 12.5,
                  color: Color(0xFF627D98),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 22),
        SizedBox(
          width: double.infinity,
          height: 52,
          child: FilledButton.icon(
            onPressed: isSubmitting
                ? null
                : () {
                    final input = usernameController.text.trim();
                    if (input.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            AppLocalizations.of(context)!.pleaseEnterSomething,
                          ),
                        ),
                      );
                      return;
                    }

                    if (widget.mobileOnly) {
                      if (_phoneRegex.hasMatch(input)) {
                        _verifyPhoneChange(input);
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Enter a valid Philippine number (09XXXXXXXXX or +63XXXXXXXXX).',
                            ),
                          ),
                        );
                      }
                      return;
                    }

                    if (input.contains('@')) {
                      _verifyEmailChange(input);
                    } else if (_phoneRegex.hasMatch(input)) {
                      _verifyPhoneChange(input);
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            AppLocalizations.of(
                              context,
                            )!.enterAValidEmailOrPhilippineNumber,
                          ),
                        ),
                      );
                    }
                  },
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF0F2548),
              disabledBackgroundColor: const Color(0xFF0F2548).withValues(
                alpha: 0.65,
              ),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            icon: isSubmitting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.verified_rounded),
            label: Text(
              isSubmitting
                  ? 'Please wait...'
                  : AppLocalizations.of(context)!.verifyUpdate,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 15.5,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _VerificationInfo {
  final String label;
  final IconData icon;
  final Color background;
  final Color foreground;

  const _VerificationInfo({
    required this.label,
    required this.icon,
    required this.background,
    required this.foreground,
  });
}
