import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../l10n/app_localizations.dart';
import '../../utils/responsive.dart';
import 'email_verification_screen.dart';
import 'google_role_selection_screen.dart';
import 'otp_verification_screen.dart';
import 'register2_screen.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  static final RegExp _emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
  static final RegExp _phoneRegex = RegExp(r'^(09\d{9}|\+639\d{9})$');
  static final RegExp _uppercaseRegex = RegExp(r'[A-Z]');
  static final RegExp _digitRegex = RegExp(r'\d');
  static final RegExp _symbolRegex = RegExp(r'[^\w\s]');

  static const Color _ink = Color(0xFF102A43);
  static const Color _mutedInk = Color(0xFF486581);
  static const Color _brand = Color(0xFF0F6A86);
  static const Color _brandDeep = Color(0xFF083A64);
  static const Color _brandSoft = Color(0xFFE7F7FB);
  static const Color _bgTop = Color(0xFFF8FCFF);
  static const Color _bgBottom = Color(0xFFEAF4F8);
  static const Color _cardBorder = Color(0xFFD6E7EF);
  static const Color _inputBorder = Color(0xFFD3E1EB);

  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  final confirmPasswordController = TextEditingController();
  late final Listenable _formListenable = Listenable.merge([
    emailController,
    passwordController,
    confirmPasswordController,
  ]);

  bool obscurePassword = true;
  bool obscureConfirmPassword = true;
  bool _isGoogleSigningIn = false;
  bool _isProcessingNext = false;

  bool get isButtonEnabled {
    final input = emailController.text.trim();
    final password = passwordController.text.trim();
    final confirmPassword = confirmPasswordController.text.trim();
    final isEmail = _emailRegex.hasMatch(input);
    final isPhone = _phoneRegex.hasMatch(input);
    return (isEmail || isPhone) &&
        password.length >= 8 &&
        confirmPassword.isNotEmpty &&
        password == confirmPassword;
  }

  bool _isStrongPassword(String password) {
    return password.length >= 8 &&
        _uppercaseRegex.hasMatch(password) &&
        _digitRegex.hasMatch(password) &&
        _symbolRegex.hasMatch(password);
  }

  String get _strongPasswordMessage =>
      'Use at least 8 characters with 1 uppercase letter, 1 number, and 1 symbol.';

  bool _validatePasswordFields() {
    final password = passwordController.text.trim();
    final confirmPassword = confirmPasswordController.text.trim();

    if (!_isStrongPassword(password)) {
      _showSnack(_strongPasswordMessage);
      return false;
    }

    if (confirmPassword.isEmpty) {
      _showSnack('Please confirm your password.');
      return false;
    }

    if (password != confirmPassword) {
      _showSnack('Passwords do not match.');
      return false;
    }

    return true;
  }

  String _normalizePhoneNumber(String input) {
    final trimmed = input.trim();
    if (trimmed.startsWith('09')) {
      return '+63${trimmed.substring(1)}';
    }
    return trimmed;
  }

  String _verificationNote(BuildContext context) {
    return Localizations.localeOf(context).languageCode == 'fil'
        ? 'Isang verification email o SMS ang ipapadala pagkatapos ng susunod na hakbang.'
        : 'A verification email or SMS will be sent after the next step.';
  }

  String _heroSubtitle(BuildContext context) {
    return Localizations.localeOf(context).languageCode == 'fil'
        ? 'Gamitin ang iyong email o mobile number upang simulan ang verification at ma-secure ang iyong access.'
        : 'Use your email or mobile number to begin verification and secure your access.';
  }

  void _showSnack(String message) {
    if (!context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        padding: EdgeInsets.zero,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 18),
        content: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF083A64), Color(0xFF0F6A86)],
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: _brandDeep.withValues(alpha: 0.22),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.info_outline_rounded,
                  color: Color(0xFFDDF8FF),
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  message,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    height: 1.35,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<bool> _verifyEmailFlow(String email, String password) async {
    try {
      final auth = FirebaseAuth.instance;
      final methods = await auth.fetchSignInMethodsForEmail(email);

      if (methods.isNotEmpty && !methods.contains('password')) {
        _showSnack(
          'Email is already registered. Please sign in with the linked provider.',
        );
        return false;
      }

      if (!methods.contains('password') && !_isStrongPassword(password)) {
        _showSnack(_strongPasswordMessage);
        return false;
      }

      bool createdNewUser = false;
      UserCredential credential;

      if (methods.contains('password')) {
        credential = await auth.signInWithEmailAndPassword(
          email: email,
          password: password,
        );
      } else {
        credential = await auth.createUserWithEmailAndPassword(
          email: email,
          password: password,
        );
        createdNewUser = true;
      }

      final user = credential.user;
      if (user == null) {
        _showSnack('Unable to start email verification. Please try again.');
        return false;
      }

      await user.reload();
      final isAlreadyVerified = user.emailVerified;
      if (!isAlreadyVerified) {
        await user.sendEmailVerification();
      }

      if (isAlreadyVerified) return true;

      final verified = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => EmailVerificationScreen(
            user: user,
            createdNewUser: createdNewUser,
          ),
        ),
      );

      if (verified == true) return true;

      if (createdNewUser) {
        try {
          await user.delete();
        } catch (_) {}
      }
      await FirebaseAuth.instance.signOut();
      return false;
    } on FirebaseAuthException catch (e) {
      final message = switch (e.code) {
        'invalid-email' => 'Please enter a valid email address.',
        'wrong-password' => 'Incorrect password for this email.',
        'email-already-in-use' => 'Email already in use. Try signing in.',
        'user-disabled' =>
          'This account has been disabled. Please contact an administrator.',
        'weak-password' => _strongPasswordMessage,
        'too-many-requests' => 'Too many attempts. Please try again later.',
        _ => e.message ?? 'Unable to verify email right now.',
      };
      _showSnack(message);
      return false;
    } catch (e) {
      _showSnack('Unexpected error: $e');
      return false;
    }
  }

  Future<void> _goToPersonalInfo() async {
    if (!isButtonEnabled || _isProcessingNext) return;
    setState(() => _isProcessingNext = true);
    try {
      final input = emailController.text.trim();
      final password = passwordController.text.trim();
      final isEmail = input.contains('@');
      final contactNumber = isEmail ? '' : _normalizePhoneNumber(input);

      if (!_validatePasswordFields()) return;

      if (isEmail) {
        final emailVerified = await _verifyEmailFlow(
          input.toLowerCase(),
          password,
        );
        if (!emailVerified) return;
      } else {
        if (!_isStrongPassword(password)) {
          _showSnack(_strongPasswordMessage);
          return;
        }

        if (!mounted) return;
        final phoneVerified = await Navigator.push<bool>(
          context,
          MaterialPageRoute(
            builder: (_) => OTPVerificationScreen(
              phoneNumber: contactNumber,
              userData: const {'deferCompletion': true},
              deferCompletion: true,
            ),
          ),
        );
        if (phoneVerified != true) return;
      }

      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => Register2Screen(
            email: isEmail ? input.toLowerCase() : '',
            contactNumber: contactNumber,
            password: password,
            phoneVerified: !isEmail,
            emailPreverified: isEmail,
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _isProcessingNext = false);
    }
  }

  Future<User> _reloadCurrentUser(User user) async {
    await user.reload();
    return FirebaseAuth.instance.currentUser ?? user;
  }

  bool _hasGoogleProvider(User user) {
    return user.providerData.any(
      (provider) => provider.providerId == 'google.com',
    );
  }

  Future<User?> _showGoogleEmailVerification(User user) async {
    final refreshedUser = await _reloadCurrentUser(user);

    if (!refreshedUser.emailVerified) {
      try {
        await refreshedUser.sendEmailVerification();
      } on FirebaseAuthException catch (e) {
        if (e.code == 'too-many-requests') {
          _showSnack(
            'Firebase blocked another email for now. Use the latest verification link, or wait before resending.',
          );
        } else {
          _showSnack(e.message ?? 'Unable to send verification email right now.');
          return null;
        }
      } catch (_) {
        _showSnack('Unable to send verification email right now.');
        return null;
      }
    }

    await Future<void>.delayed(const Duration(milliseconds: 300));
    if (!mounted) return null;
    final verified = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => EmailVerificationScreen(
          user: refreshedUser,
          createdNewUser: false,
          autoContinueWhenVerified: false,
        ),
      ),
    );

    if (verified != true) {
      await FirebaseAuth.instance.signOut();
      return null;
    }

    return _reloadCurrentUser(refreshedUser);
  }

  Future<User?> _verifyGoogleEmailBeforeRoleSelection(User user) async {
    var refreshedUser = await _reloadCurrentUser(user);

    if (!_hasGoogleProvider(refreshedUser)) {
      _showSnack('Please sign in with Google to continue.');
      return null;
    }

    try {
      final callable = FirebaseFunctions.instance.httpsCallable(
        'prepareGoogleEmailVerification',
      );
      await callable.call();
      await refreshedUser.getIdToken(true);
      refreshedUser = await _reloadCurrentUser(refreshedUser);
    } on FirebaseFunctionsException catch (e) {
      final message = switch (e.code) {
        'unauthenticated' => 'Please sign in again to verify your email.',
        'failed-precondition' =>
          'Email verification reset is only available for Google accounts.',
        'not-found' || 'unimplemented' =>
          'Google email verification is not deployed yet. Please deploy the Firebase function and try again.',
        'unavailable' =>
          'Google email verification is temporarily unavailable. Please try again later.',
        _ => e.message ?? 'Unable to start email verification right now.',
      };
      _showSnack(message);
      await FirebaseAuth.instance.signOut();
      return null;
    } catch (_) {
      _showSnack('Unable to start email verification right now.');
      await FirebaseAuth.instance.signOut();
      return null;
    }

    if (refreshedUser.emailVerified) {
      await Future<void>.delayed(const Duration(milliseconds: 600));
      refreshedUser = await _reloadCurrentUser(refreshedUser);
    }

    if (refreshedUser.emailVerified) {
      _showSnack(
        'Unable to start Google email verification. Please try again later.',
      );
      await FirebaseAuth.instance.signOut();
      return null;
    }

    return _showGoogleEmailVerification(refreshedUser);
  }

  Future<void> _signInWithGoogle() async {
    if (_isGoogleSigningIn || _isProcessingNext) return;
    setState(() => _isGoogleSigningIn = true);
    final googleSignIn = GoogleSignIn.standard();
    try {
      await googleSignIn.signOut();
      final GoogleSignInAccount? googleUser = await googleSignIn.signIn();
      if (googleUser == null) return;

      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;

      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final userCredential = await FirebaseAuth.instance.signInWithCredential(
        credential,
      );

      final signedInUser = userCredential.user;
      if (signedInUser != null) {
        await signedInUser.reload();
        final user = FirebaseAuth.instance.currentUser ?? signedInUser;
        if (!mounted) return;

        final verifiedUser = await _verifyGoogleEmailBeforeRoleSelection(user);
        if (verifiedUser == null || !mounted) {
          await googleSignIn.signOut();
          return;
        }

        final fullName = (verifiedUser.displayName ?? '').trim();
        final nameParts = fullName
            .split(RegExp(r'\s+'))
            .where((p) => p.trim().isNotEmpty)
            .toList();
        final firstName = nameParts.isNotEmpty ? nameParts.first : '';
        final lastName = nameParts.length > 1
            ? nameParts.sublist(1).join(' ')
            : '';

        final docRef = FirebaseFirestore.instance
            .collection('users')
            .doc(verifiedUser.uid);
        final docSnap = await docRef.get();
        final existing = docSnap.data() ?? const <String, dynamic>{};

        final updates = <String, dynamic>{
          'email': (verifiedUser.email ?? '').trim(),
          'provider': 'google',
          'providerLabel': 'google',
          'provider_id': 'google',
          'email_verified': verifiedUser.emailVerified,
          'email_confirmation_required': !verifiedUser.emailVerified,
          'email_verified_at': verifiedUser.emailVerified
              ? FieldValue.serverTimestamp()
              : null,
          'name': fullName,
          'fullName': fullName,
          'firstName': firstName,
          'lastName': lastName,
          'first_name': firstName,
          'last_name': lastName,
          'authPhotoUrl': verifiedUser.photoURL,
          'profileImageUrl': verifiedUser.photoURL,
          'photo_url': verifiedUser.photoURL,
          'updated_at': FieldValue.serverTimestamp(),
        };

        if (!docSnap.exists) {
          updates['created_at'] = FieldValue.serverTimestamp();
        }

        await docRef.set(updates, SetOptions(merge: true));

        if (!mounted) return;
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => GoogleRoleSelectionScreen(
              user: verifiedUser,
              existingData: {
                ...existing,
                ...updates,
              },
            ),
          ),
        );
      }
    } on FirebaseAuthException catch (e) {
      debugPrint('Google Sign-In auth error: ${e.code}');
      await FirebaseAuth.instance.signOut();
      await googleSignIn.signOut();
      final message = switch (e.code) {
        'user-disabled' =>
          'This account has been disabled. Please contact an administrator.',
        'account-exists-with-different-credential' =>
          'This email is already linked to another sign-in method.',
        'invalid-credential' ||
        'invalid-login-credentials' =>
          'Google Sign-In could not be verified. Please try again.',
        'operation-not-allowed' =>
          'Google Sign-In is currently disabled. Please contact support.',
        'too-many-requests' => 'Too many attempts. Please try again later.',
        'network-request-failed' =>
          'Network error. Check your connection and try again.',
        _ => 'Google Sign-In failed. Please try again.',
      };
      if (mounted) _showSnack(message);
    } on FirebaseException catch (e) {
      debugPrint('Google Sign-In Firebase error: ${e.plugin}/${e.code} ${e.message}');
      await FirebaseAuth.instance.signOut();
      await googleSignIn.signOut();
      final message = switch (e.code) {
        'permission-denied' =>
          'Google Sign-In could not save your account yet. Please check Firebase rules.',
        'unavailable' =>
          'Google Sign-In service is temporarily unavailable. Please try again.',
        _ => e.message ?? 'Google Sign-In failed. Please try again.',
      };
      if (mounted) _showSnack(message);
    } catch (e) {
      debugPrint('Google Sign-In error: $e');
      await FirebaseAuth.instance.signOut();
      await googleSignIn.signOut();
      if (mounted) {
        _showSnack('Google Sign-In failed. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _isGoogleSigningIn = false);
    }
  }

  InputDecoration _buildInputDecoration({
    required String hintText,
    required IconData icon,
    String? helperText,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      hintText: hintText,
      hintStyle: const TextStyle(
        color: Color(0xFF7B8794),
        fontSize: 15.5,
        fontWeight: FontWeight.w500,
      ),
      filled: true,
      fillColor: Colors.white,
      prefixIcon: Icon(icon, color: _brand, size: 21),
      suffixIcon: suffixIcon,
      helperText: helperText,
      helperMaxLines: 2,
      helperStyle: const TextStyle(
        color: _mutedInk,
        fontSize: 12.5,
        fontWeight: FontWeight.w500,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(20),
        borderSide: const BorderSide(color: _inputBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(20),
        borderSide: const BorderSide(color: _brand, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(20),
        borderSide: const BorderSide(color: Colors.redAccent),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(20),
        borderSide: const BorderSide(color: Colors.redAccent, width: 1.4),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
    );
  }

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    confirmPasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final padding = Responsive.pagePadding(context);
    final maxWidth = Responsive.maxContentWidth(context, maxWidth: 460);
    final vertical = Responsive.verticalSpace(context);

    return Scaffold(
      backgroundColor: _bgBottom,
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [_bgTop, _bgBottom],
          ),
        ),
        child: Stack(
          children: [
            _buildBackgroundOrb(
              top: -90,
              right: -76,
              size: 230,
              colors: const [Color(0x3313A4B4), Color(0x12103B66)],
            ),
            _buildBackgroundOrb(
              top: 250,
              left: -92,
              size: 190,
              colors: const [Color(0x195BC0EB), Color(0x0D0A3558)],
            ),
            SafeArea(
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxWidth),
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    padding: EdgeInsets.fromLTRB(
                      padding,
                      vertical,
                      padding,
                      vertical * 1.3,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildHeroCard(l10n),
                        const SizedBox(height: 18),
                        Container(
                          padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.96),
                            borderRadius: BorderRadius.circular(28),
                            border: Border.all(color: _cardBorder),
                            boxShadow: [
                              BoxShadow(
                                color: _brandDeep.withValues(alpha: 0.08),
                                blurRadius: 20,
                                offset: const Offset(0, 10),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _buildFieldLabel(l10n.emailOrMobileNumber),
                              const SizedBox(height: 8),
                              TextField(
                                controller: emailController,
                                keyboardType: TextInputType.emailAddress,
                                textInputAction: TextInputAction.next,
                                decoration: _buildInputDecoration(
                                  hintText: l10n.enterYourEmailOrNumber,
                                  icon: Icons.mail_outline_rounded,
                                ),
                              ),
                              const SizedBox(height: 16),
                              _buildFieldLabel(l10n.password),
                              const SizedBox(height: 8),
                              TextField(
                                controller: passwordController,
                                obscureText: obscurePassword,
                                textInputAction: TextInputAction.next,
                                decoration: _buildInputDecoration(
                                  hintText: l10n.enterYourPassword,
                                  icon: Icons.lock_outline_rounded,
                                  helperText:
                                      'Minimum 8 characters, with 1 uppercase letter, 1 number, and 1 symbol.',
                                  suffixIcon: IconButton(
                                    icon: Icon(
                                      obscurePassword
                                          ? Icons.visibility_off_outlined
                                          : Icons.visibility_outlined,
                                      color: _mutedInk,
                                    ),
                                    onPressed: () => setState(
                                      () => obscurePassword = !obscurePassword,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 16),
                              _buildFieldLabel('Confirm Password'),
                              const SizedBox(height: 8),
                              TextField(
                                controller: confirmPasswordController,
                                obscureText: obscureConfirmPassword,
                                textInputAction: TextInputAction.done,
                                onSubmitted: (_) {
                                  if (isButtonEnabled && !_isProcessingNext) {
                                    _goToPersonalInfo();
                                  }
                                },
                                decoration: _buildInputDecoration(
                                  hintText: 'Re-enter your password',
                                  icon: Icons.lock_reset_rounded,
                                  helperText: 'Must match the password above.',
                                  suffixIcon: IconButton(
                                    icon: Icon(
                                      obscureConfirmPassword
                                          ? Icons.visibility_off_outlined
                                          : Icons.visibility_outlined,
                                      color: _mutedInk,
                                    ),
                                    onPressed: () => setState(
                                      () => obscureConfirmPassword =
                                          !obscureConfirmPassword,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 16),
                              AnimatedBuilder(
                                animation: _formListenable,
                                builder: (context, child) {
                                  return FilledButton(
                                    onPressed:
                                        isButtonEnabled && !_isProcessingNext
                                        ? _goToPersonalInfo
                                        : null,
                                    style: FilledButton.styleFrom(
                                      backgroundColor: _brandDeep,
                                      disabledBackgroundColor: const Color(
                                        0xFFB8C3CD,
                                      ),
                                      foregroundColor: Colors.white,
                                      minimumSize: const Size.fromHeight(58),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(18),
                                      ),
                                    ),
                                    child: _isProcessingNext
                                        ? const SizedBox(
                                            width: 20,
                                            height: 20,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2.2,
                                              valueColor:
                                                  AlwaysStoppedAnimation<Color>(
                                                    Colors.white,
                                                  ),
                                            ),
                                          )
                                        : child ?? const SizedBox.shrink(),
                                  );
                                },
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      l10n.next,
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    const Icon(
                                      Icons.arrow_forward_rounded,
                                      size: 18,
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 12),
                              _buildInfoCard(_verificationNote(context)),
                              const SizedBox(height: 20),
                              _buildDivider(l10n.orContinueWith),
                              const SizedBox(height: 18),
                              OutlinedButton(
                                onPressed: _isGoogleSigningIn
                                    ? null
                                    : _signInWithGoogle,
                                style: OutlinedButton.styleFrom(
                                  minimumSize: const Size.fromHeight(56),
                                  backgroundColor: Colors.white,
                                  foregroundColor: _brandDeep,
                                  side: const BorderSide(color: _inputBorder),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(18),
                                  ),
                                ),
                                child: _isGoogleSigningIn
                                    ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2.2,
                                        ),
                                      )
                                    : Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Container(
                                            width: 32,
                                            height: 32,
                                            alignment: Alignment.center,
                                            decoration: BoxDecoration(
                                              color: const Color(0xFFF4F7FB),
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                            ),
                                            child: const Text(
                                              'G',
                                              style: TextStyle(
                                                color: _brandDeep,
                                                fontSize: 17,
                                                fontWeight: FontWeight.w900,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                          Text(
                                            l10n.google,
                                            style: const TextStyle(
                                              fontSize: 15,
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                        ],
                                      ),
                              ),
                              const SizedBox(height: 18),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Flexible(
                                    child: Text(
                                      l10n.alreadyHaveAnAccount,
                                      style: const TextStyle(
                                        color: _mutedInk,
                                        fontSize: 14.5,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                  GestureDetector(
                                    onTap: () =>
                                        Navigator.pushNamed(context, '/login'),
                                    child: const Padding(
                                      padding: EdgeInsets.only(left: 2),
                                      child: Text(
                                        ' Login',
                                        style: TextStyle(
                                          color: _brandDeep,
                                          fontSize: 15,
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
          ],
        ),
      ),
    );
  }

  Widget _buildHeroCard(AppLocalizations l10n) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF083A64), Color(0xFF0F6A86)],
        ),
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            color: _brandDeep.withValues(alpha: 0.22),
            blurRadius: 28,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            top: -26,
            right: -18,
            child: Container(
              width: 112,
              height: 112,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.08),
              ),
            ),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: const Text(
                        'SeaGuard Access',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      l10n.continueCreatingYourAccount,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                        height: 1.08,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      _heroSubtitle(context),
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.86),
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              Container(
                width: 88,
                height: 88,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Colors.white.withValues(alpha: 0.18),
                      const Color(0xFF062945).withValues(alpha: 0.28),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(26),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.22),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF041F36).withValues(alpha: 0.2),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF062945).withValues(alpha: 0.22),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  padding: const EdgeInsets.all(8),
                  child: ColorFiltered(
                    colorFilter: const ColorFilter.mode(
                      Colors.white,
                      BlendMode.srcIn,
                    ),
                    child: Image.asset(
                      'assets/image.png',
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => const Icon(
                        Icons.sailing_rounded,
                        color: Colors.white,
                        size: 38,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFieldLabel(String text) {
    return Text(
      text,
      style: const TextStyle(
        color: _ink,
        fontSize: 14.5,
        fontWeight: FontWeight.w700,
      ),
    );
  }

  Widget _buildInfoCard(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF5FBFD),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _cardBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: _brandSoft,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.mark_email_read_outlined,
              size: 17,
              color: _brand,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: _mutedInk,
                fontSize: 13.2,
                fontWeight: FontWeight.w600,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDivider(String label) {
    return Row(
      children: [
        const Expanded(
          child: Divider(color: _cardBorder, thickness: 1),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            label,
            style: const TextStyle(
              color: _mutedInk,
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const Expanded(
          child: Divider(color: _cardBorder, thickness: 1),
        ),
      ],
    );
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
}
