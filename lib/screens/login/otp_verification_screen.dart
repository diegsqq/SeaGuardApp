import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../Admin/terms_conditions_page.dart';
import '../../utils/responsive.dart';
import '../profile/terms_and_condition_page.dart';

class OTPVerificationScreen extends StatefulWidget {
  final String phoneNumber;
  @Deprecated('No longer used; kept for backward compatibility.')
  final String? pinId;
  final Map<String, dynamic> userData;
  final bool loginMode; // true when used for sign-in instead of sign-up
  final String? linkEmail; // pseudo/real email to link for password logins
  final String? linkPassword; // password to link after OTP
  final bool deferCompletion; // when true, stop after verification and return to caller
  final bool linkToCurrentUser; // when true, link OTP to the signed-in user
  final bool createPcgApprovalRequest;

  const OTPVerificationScreen({
    super.key,
    required this.phoneNumber,
    this.pinId,
    required this.userData,
    this.loginMode = false,
    this.linkEmail,
    this.linkPassword,
    this.deferCompletion = false,
    this.linkToCurrentUser = false,
    this.createPcgApprovalRequest = false,
  });

  @override
  State<OTPVerificationScreen> createState() => _OTPVerificationScreenState();
}

class _OTPVerificationScreenState extends State<OTPVerificationScreen> {
  String? _verificationId;
  int? _forceResendingToken;
  final List<FocusNode> focusNodes = List.generate(6, (_) => FocusNode());
  final List<TextEditingController> controllers = List.generate(6, (_) => TextEditingController());

  bool isSendingCode = false;
  bool isVerifying = false;
  bool _isCompletingSignup = false;
  int secondsRemaining = 120;
  Timer? countdownTimer;

  @override
  void initState() {
    super.initState();
    _sendCode();
  }

  String _displayPhone(String phone) {
    if (phone.startsWith('+63') && phone.length > 3) {
      return '0${phone.substring(3)}';
    }
    return phone;
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  String _friendlyPhoneAuthError(FirebaseAuthException e) {
    final message = (e.message ?? '').toUpperCase();
    switch (e.code) {
      case 'invalid-phone-number':
        return 'Invalid phone number.';
      case 'invalid-verification-code':
        return 'Invalid OTP code. Please check the code and try again.';
      case 'session-expired':
        return 'This OTP has expired. Please request a new code.';
      case 'operation-not-allowed':
        return 'Phone sign-in is not enabled. Enable it in Firebase Authentication.';
      case 'billing-not-enabled':
        return 'Phone OTP billing is not enabled for this Firebase project.';
      case 'app-not-authorized':
        return 'App not authorized. Add your SHA-1/SHA-256 to Firebase and rebuild.';
      case 'too-many-requests':
        return 'Too many attempts. Please try again later.';
      case 'quota-exceeded':
        return 'SMS quota exceeded. Please try again later.';
      case 'network-request-failed':
        return 'Network error. Check your connection and try again.';
      case 'credential-already-in-use':
        return 'This mobile number is already linked to another account.';
      case 'provider-already-linked':
        return 'This account already has a verified mobile number.';
      case 'requires-recent-login':
        return 'Session expired. Please restart signup and verify again.';
      default:
        if (message.contains('BILLING_NOT_ENABLED')) {
          return 'Phone OTP billing is not active yet for this Firebase project. Check the linked billing account and try again shortly.';
        }
        return e.message ?? 'Verification failed. Please try again.';
    }
  }

  bool _isAdminRole(String? role) {
    if (role == null) return false;
    final normalized = role.toLowerCase();
    return normalized.contains('admin') || normalized.contains('pcg');
  }

  bool _isPcgRole(String? role, [String? roleLabel]) {
    final combined = '${role ?? ''} ${roleLabel ?? ''}'.toLowerCase();
    return combined.contains('pcg') ||
        combined.contains('coast guard') ||
        combined.contains('sub-admin') ||
        combined.contains('sub admin') ||
        combined.contains('subadmin');
  }

  String _pcgApprovalStatus(Map<String, dynamic> data) {
    return (data['pcgApprovalStatus'] ??
            data['registrationStatus'] ??
            data['approvalStatus'] ??
            '')
        .toString()
        .trim()
        .toLowerCase();
  }

  bool _isPcgApproved(Map<String, dynamic> data) {
    final status = _pcgApprovalStatus(data);
    return status.isEmpty || status == 'approved';
  }

  String _pcgApprovalMessage(String status) {
    if (status == 'rejected' || status == 'declined') {
      return 'Your PCG registration was rejected. Please contact a PCG admin.';
    }
    return 'Your PCG registration is pending approval. Please wait for a PCG admin to approve your account.';
  }

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

  Future<User?> _resolveVerifiedPhoneUser(
    PhoneAuthCredential credential,
  ) async {
    if (!widget.linkToCurrentUser) {
      final userCredential =
          await FirebaseAuth.instance.signInWithCredential(credential);
      return userCredential.user;
    }

    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      _showSnack('Session expired. Please restart signup.');
      return null;
    }

    final phoneCandidates = _phoneCandidates(widget.phoneNumber);
    final existingPhone = currentUser.phoneNumber ?? '';
    if (existingPhone.isNotEmpty && phoneCandidates.contains(existingPhone)) {
      await currentUser.reload();
      return FirebaseAuth.instance.currentUser ?? currentUser;
    }

    final linkedCredential = await currentUser.linkWithCredential(credential);
    final linkedUser = linkedCredential.user;
    await linkedUser?.reload();
    return FirebaseAuth.instance.currentUser ?? linkedUser;
  }

  Future<void> _routeAfterLogin(User user, {String? fallbackRole}) async {
    String derivedRole = fallbackRole ?? 'user';
    bool isActive = true;
    bool acceptedTerms = false;
    Map<String, dynamic> userData = {};

    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      userData = snap.data() ?? {};
      if (userData['active'] == false) {
        isActive = false;
      }
      derivedRole = (userData['role'] ?? derivedRole).toString();
      acceptedTerms =
          userData['acceptedTerms'] == true ||
          userData['termsAcceptedAt'] != null;
    } catch (_) {}

    if (!mounted) return;

    if (!isActive) {
      await FirebaseAuth.instance.signOut();
      _showSnack('Your account is deactivated. Please contact an administrator.');
      return;
    }

    if (_isPcgRole(
          derivedRole,
          (userData['roleLabel'] ?? userData['role_label'] ?? '').toString(),
        ) &&
        !_isPcgApproved(userData)) {
      await FirebaseAuth.instance.signOut();
      _showSnack(_pcgApprovalMessage(_pcgApprovalStatus(userData)));
      return;
    }

    final isAdmin = _isAdminRole(derivedRole);
    final continueRoute = isAdmin ? '/adminDashboard' : '/dashboard';

    if (!acceptedTerms) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(
          builder: (_) => isAdmin
              ? const TermsConditionsPage(
                  continueRouteName: '/adminDashboard',
                )
              : const TermsAndConditionPage(
                  continueRouteName: '/dashboard',
                ),
        ),
        (_) => false,
      );
      return;
    }

    Navigator.pushNamedAndRemoveUntil(context, continueRoute, (_) => false);
  }

  void startTimer() {
    countdownTimer?.cancel();
    secondsRemaining = secondsRemaining <= 0 ? 120 : secondsRemaining;
    countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      setState(() {
        if (secondsRemaining > 0) {
          secondsRemaining--;
        } else {
          timer.cancel();
        }
      });
    });
  }

  Future<void> _sendPcgApprovalRequest({
    required String userId,
    required Map<String, dynamic> userData,
  }) async {
    if (!widget.createPcgApprovalRequest || userId.trim().isEmpty) return;

    final combinedRole =
        '${userData['role'] ?? ''} ${userData['roleLabel'] ?? userData['role_label'] ?? ''}'
            .toLowerCase();
    final status = (userData['pcgApprovalStatus'] ??
            userData['registrationStatus'] ??
            userData['approvalStatus'] ??
            '')
        .toString()
        .toLowerCase();
    if (!combinedRole.contains('pcg') || status != 'pending') return;

    final fullName = (userData['fullName'] ?? '').toString().trim();
    final email = (userData['email'] ?? '').toString().trim();
    final station = (userData['station'] ?? '').toString().trim();
    final region = (userData['region'] ?? '').toString().trim();
    final province = (userData['province'] ?? '').toString().trim();
    final municipality = (userData['municipality'] ?? '').toString().trim();
    final location = [
      municipality,
      province,
      region,
    ].where((value) => value.isNotEmpty).join(', ');
    final displayName = fullName.isNotEmpty ? fullName : 'A PCG registrant';

    final payload = <String, dynamic>{
      'targetRole': 'web-admin-pcg',
      'title': 'PCG registration request',
      'message':
          '$displayName requested PCG Sub-admin access${station.isNotEmpty ? ' for $station' : ''}. Review this request on the PCG web admin.',
      'type': 'pcg_registration_request',
      'category': 'pcg_registration',
      'pcgUserId': userId,
      'userId': userId,
      'requesterName': fullName,
      'requesterEmail': email,
      'station': station,
      'region': region,
      'province': province,
      'municipality': municipality,
      'location': location,
      'status': 'pending',
      'approvalStatus': 'pending',
      'timestamp': FieldValue.serverTimestamp(),
      'createdAt': FieldValue.serverTimestamp(),
      'isRead': false,
    };

    final db = FirebaseFirestore.instance;
    await Future.wait([
      db
          .collection('notifications')
          .doc('pcg_registration_request_$userId')
          .set(payload, SetOptions(merge: true)),
      db.collection('pcg_registration_requests').doc(userId).set(
        {
          ...payload,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      ),
    ]);
  }

  Future<void> _sendCode({bool isResend = false}) async {
    if (isSendingCode) return;

    setState(() {
      isSendingCode = true;
      secondsRemaining = 120;
    });
    startTimer();

    try {
      await FirebaseAuth.instance.verifyPhoneNumber(
        phoneNumber: widget.phoneNumber,
        timeout: const Duration(seconds: 60),
        forceResendingToken: isResend ? _forceResendingToken : null,
        verificationCompleted: (PhoneAuthCredential credential) async {
          try {
            final user = await _resolveVerifiedPhoneUser(credential);
            if (user == null) return;
            await _completeSignup(user);
          } on FirebaseAuthException catch (e) {
            if (!mounted) return;
            _showSnack(_friendlyPhoneAuthError(e));
          } catch (e) {
            if (!mounted) return;
            _showSnack('Verification failed: ${e.toString()}');
          } finally {
            if (mounted) setState(() => isSendingCode = false);
          }
        },
        verificationFailed: (FirebaseAuthException e) {
          if (!mounted) return;
          countdownTimer?.cancel();
          setState(() {
            isSendingCode = false;
            secondsRemaining = 0;
          });
          _showSnack(_friendlyPhoneAuthError(e));
        },
        codeSent: (String verificationId, int? resendToken) {
          if (!mounted) return;
          setState(() {
            _verificationId = verificationId;
            _forceResendingToken = resendToken;
            isSendingCode = false;
          });
          _showSnack('OTP sent to your number.');
        },
        codeAutoRetrievalTimeout: (String verificationId) {
          _verificationId = verificationId;
          if (mounted && isSendingCode) setState(() => isSendingCode = false);
        },
      );
    } catch (e) {
      if (!mounted) return;
      countdownTimer?.cancel();
      setState(() {
        isSendingCode = false;
        secondsRemaining = 0;
      });
      _showSnack('Failed to send OTP: ${e.toString()}');
    }
  }

  Future<void> _completeSignup(User user) async {
    if (_isCompletingSignup) return;
    _isCompletingSignup = true;

    try {
      if (widget.deferCompletion) {
        Navigator.pop(context, true);
        return;
      }

      final uid = user.uid;
      final Map<String, dynamic> dataToSave = Map<String, dynamic>.from(widget.userData);
      dataToSave.remove('idImageLocalPath');
      dataToSave.remove('faceImageLocalPath');

      Future<void> linkEmailPassword() async {
        final email = widget.linkEmail?.trim() ?? '';
        final password = widget.linkPassword ?? '';
        if (email.isEmpty || password.isEmpty) return;
        try {
          final methods = await FirebaseAuth.instance.fetchSignInMethodsForEmail(email);
          if (methods.contains('password')) return;
          final cred = EmailAuthProvider.credential(email: email, password: password);
          await user.linkWithCredential(cred);
          await FirebaseFirestore.instance.collection('users').doc(uid).set(
            {'email': email},
            SetOptions(merge: true),
          );
        } catch (e) {
          debugPrint('linkEmailPassword failed: $e');
        }
      }

      Future<void> ensureUserDoc() async {
        final docRef = FirebaseFirestore.instance.collection('users').doc(uid);
        final snap = await docRef.get();
        final updates = <String, dynamic>{};
        final displayPhone = _displayPhone(widget.phoneNumber);

        if (!snap.exists) {
          updates['contact_number'] = widget.phoneNumber;
          updates['username'] = displayPhone;
          updates['created_at'] = FieldValue.serverTimestamp();
        } else {
          final data = snap.data() ?? {};
          if ((data['contact_number'] ?? '').toString().isEmpty) {
            updates['contact_number'] = widget.phoneNumber;
          }
          if ((data['username'] ?? '').toString().isEmpty) {
            updates['username'] = displayPhone;
          }
          final email = widget.linkEmail?.trim() ?? '';
          if (email.isNotEmpty && (data['email'] ?? '').toString().isEmpty) {
            updates['email'] = email;
          }
        }

        if (updates.isNotEmpty) {
          await docRef.set(updates, SetOptions(merge: true));
        }
      }

      // For login flow, skip creating/updating user data and go straight to dashboard.
      if (widget.loginMode) {
        await ensureUserDoc();
        await linkEmailPassword();
        String role = 'user';
        try {
          final snap = await FirebaseFirestore.instance
              .collection('users')
              .doc(uid)
              .get();
          final data = snap.data() ?? {};
          role = data['role']?.toString() ?? 'user';
        } catch (_) {}

        await _routeAfterLogin(user, fallbackRole: role);
        return;
      }

      final docRef = FirebaseFirestore.instance.collection('users').doc(uid);
      await docRef.set(dataToSave, SetOptions(merge: true));
      await _sendPcgApprovalRequest(userId: uid, userData: dataToSave);

      await FirebaseAuth.instance.signOut();
      if (!mounted) return;
      Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false);
    } finally {
      _isCompletingSignup = false;
    }
  }

  Future<void> _verifyOTP() async {
    final otp = controllers.map((c) => c.text.trim()).join();

    if ((_verificationId ?? '').isEmpty) {
      _showSnack('Verification ID missing. Please resend code.');
      return;
    }

    if (otp.length != 6) {
      _showSnack('Enter 6-digit code');
      return;
    }

    setState(() => isVerifying = true);

    try {
      final credential = PhoneAuthProvider.credential(
        verificationId: _verificationId!,
        smsCode: otp,
      );
      final user = await _resolveVerifiedPhoneUser(credential);
      if (user == null) return;
      await _completeSignup(user);
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      _showSnack(_friendlyPhoneAuthError(e));
    } catch (e) {
      if (!mounted) return;
      _showSnack('Verification failed: ${e.toString()}');
    } finally {
      if (mounted) setState(() => isVerifying = false);
    }
  }

  Future<void> _resendCode() async {
    for (var c in controllers) {
      c.clear();
    }
    await _sendCode(isResend: true);
  }

  Widget _buildOtpFields() {
    return LayoutBuilder(
      builder: (context, constraints) {
        const digitsCount = 6;
        const gap = 10.0;
        final totalGap = gap * (digitsCount - 1);
        final fieldWidth = ((constraints.maxWidth - totalGap) / digitsCount).clamp(36.0, 54.0);

        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(digitsCount, (index) {
            return SizedBox(
              width: fieldWidth,
              child: TextField(
                controller: controllers[index],
                focusNode: focusNodes[index],
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                maxLength: 1,
                style: const TextStyle(fontSize: 24),
                decoration: InputDecoration(
                  counterText: "",
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: const BorderSide(color: Colors.indigo),
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                onChanged: (value) {
                  final v = value.trim();
                  if (v.length > 1) {
                    final digits = v.split('');
                    for (int i = 0; i < digits.length && i + index < digitsCount; i++) {
                      controllers[index + i].text = digits[i];
                    }
                    final filled = controllers.map((c) => c.text).join();
                    if (filled.length == digitsCount) {
                      FocusScope.of(context).unfocus();
                    } else {
                      final next = index + v.length;
                      if (next < digitsCount) {
                        FocusScope.of(context).requestFocus(focusNodes[next]);
                      }
                    }
                    return;
                  }

                  if (v.isNotEmpty && index < digitsCount - 1) {
                    FocusScope.of(context).requestFocus(focusNodes[index + 1]);
                  } else if (v.isEmpty && index > 0) {
                    FocusScope.of(context).requestFocus(focusNodes[index - 1]);
                  }
                },
              ),
            );
          }),
        );
      },
    );
  }

  @override
  void dispose() {
    countdownTimer?.cancel();
    for (var c in controllers) {
      c.dispose();
    }
    for (var f in focusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final minutes = secondsRemaining ~/ 60;
    final seconds = secondsRemaining % 60;
    final padding = Responsive.pagePadding(context);
    final maxWidth = Responsive.maxContentWidth(context, maxWidth: 420);

    return Scaffold(
      appBar: AppBar(
        title: const Text("Verification"),
        leading: const BackButton(),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(
                    padding,
                    padding,
                    padding,
                    padding + MediaQuery.of(context).viewInsets.bottom,
                  ),
                  keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: constraints.maxHeight),
                    child: IntrinsicHeight(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          SizedBox(height: Responsive.verticalSpace(context)),
                          const Text(
                            "Verification",
                            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            "We've sent a 6-digit code to:",
                            style: TextStyle(color: Colors.grey[600]),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            widget.phoneNumber,
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                          ),
                          SizedBox(height: Responsive.verticalSpace(context) + 10),
                          _buildOtpFields(),
                          const SizedBox(height: 20),
                          Text(
                            "Code expires in ${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}",
                            style: const TextStyle(color: Colors.grey),
                          ),
                          const SizedBox(height: 10),
                          TextButton(
                            onPressed: (secondsRemaining == 0 && !isSendingCode) ? _resendCode : null,
                            child: Text(
                              isSendingCode ? "Sending..." : "Resend Code",
                              style: TextStyle(
                                color: secondsRemaining == 0 ? Colors.indigo[900] : Colors.grey,
                              ),
                            ),
                          ),
                          const Spacer(),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: isVerifying ? null : _verifyOTP,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.indigo[900],
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: Text(
                                isVerifying ? "Verifying..." : "Verify",
                                style: const TextStyle(fontSize: 18),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
