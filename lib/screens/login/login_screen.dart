import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../Admin/terms_conditions_page.dart';
import '../../services/auth_service.dart';
import '../../l10n/app_localizations.dart';
import '../../utils/responsive.dart';
import '../profile/terms_and_condition_page.dart';
import 'otp_verification_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  static final RegExp _emailRegex = RegExp(r'^[\w\.-]+@[\w\.-]+\.\w+$');

  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  late final Listenable _formListenable = Listenable.merge([
    emailController,
    passwordController,
  ]);
  bool rememberPassword = false;
  bool obscurePassword = true;

  @override
  void initState() {
    super.initState();
    _loadRememberedCredentials();
  }

  Future<void> _loadRememberedCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    final savedEmail = prefs.getString('saved_email');
    final savedPassword = prefs.getString('saved_password');
    final savedRemember = prefs.getBool('remember_password') ?? false;

    if (savedRemember && savedEmail != null && savedPassword != null) {
      if (!mounted) return;
      emailController.text = savedEmail;
      passwordController.text = savedPassword;
      setState(() => rememberPassword = true);
    }
  }

  Future<void> _saveRememberedCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    if (rememberPassword) {
      await prefs.setString('saved_email', emailController.text.trim());
      await prefs.setString('saved_password', passwordController.text.trim());
      await prefs.setBool('remember_password', true);
    } else {
      await prefs.remove('saved_email');
      await prefs.remove('saved_password');
      await prefs.setBool('remember_password', false);
    }
  }

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  void _showMessage(String msg, {bool success = false, String? title}) {
    if (!context.mounted) return;
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
        duration: Duration(seconds: success ? 2 : 4),
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
                    if (title != null && title.trim().isNotEmpty) ...[
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
                    ],
                    Text(
                      msg,
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

  String _friendlyAuthError(FirebaseAuthException e) =>
      _friendlyAuthCode(e.code, message: e.message);

  String _friendlyAuthCode(String code, {String? message}) {
    switch (code) {
      case 'wrong-password':
      case 'invalid-credential':
      case 'invalid-login-credentials':
        return 'Incorrect email, mobile number, or password.';
      case 'user-not-found':
        return 'No account found with those login details.';
      case 'invalid-email':
        return 'Please enter a valid email.';
      case 'missing-password':
        return 'Please enter your password.';
      case 'user-disabled':
        return 'This account has been disabled.';
      case 'too-many-requests':
        return 'Too many attempts. Please try again later.';
      case 'network-request-failed':
        return 'Network error. Check your connection and try again.';
      case 'email-not-verified':
        return 'Please verify your email. We just sent a new verification link.';
      default:
        final raw = (message ?? '').toLowerCase();
        if (raw.contains('credential') || raw.contains('password')) {
          return 'Login failed. Check your email, mobile number, and password.';
        }
        return 'Login failed. Please try again.';
    }
  }

  bool _shouldReverifyPhoneLogin(String code) {
    const credentialErrors = {
      'wrong-password',
      'invalid-credential',
      'invalid-login-credentials',
      'user-not-found',
      'invalid-email',
      'missing-password',
      'email-not-verified',
      'user-disabled',
      'too-many-requests',
      'network-request-failed',
    };
    return !credentialErrors.contains(code);
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

  Future<bool> _requireVerified(User user) async {
    final hasPhone = (user.phoneNumber ?? '').trim().isNotEmpty;
    final isEmailVerified = user.emailVerified;

    if (isEmailVerified || hasPhone) return true;

    try {
      await user.sendEmailVerification();
    } catch (_) {}

    await FirebaseAuth.instance.signOut();
    if (mounted) {
      _showMessage('Please verify your email (we just sent a link) or sign in with a verified mobile number.');
    }
    return false;
  }

  Future<void> _routeAfterLogin(
    User user, {
    String? fallbackRole,
  }) async {
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
      _showMessage('Your account is deactivated. Please contact an administrator.');
      return;
    }

    if (_isPcgRole(
          derivedRole,
          (userData['roleLabel'] ?? userData['role_label'] ?? '').toString(),
        ) &&
        !_isPcgApproved(userData)) {
      await FirebaseAuth.instance.signOut();
      _showMessage(_pcgApprovalMessage(_pcgApprovalStatus(userData)));
      return;
    }

    final isAdmin = _isAdminRole(derivedRole);
    final continueRoute = isAdmin ? '/adminDashboard' : '/dashboard';

    if (!acceptedTerms) {
      Navigator.pushReplacement(
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
      );
      return;
    }

    Navigator.pushReplacementNamed(context, continueRoute);
  }

  InputDecoration _inputDecoration(
    String hint, {
    IconData? prefixIcon,
  }) {
    final border = OutlineInputBorder(
      borderSide: const BorderSide(color: Color(0xFFD7DFEA)),
      borderRadius: BorderRadius.circular(16),
    );

    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(
        color: Color(0xFF98A6B7),
        fontWeight: FontWeight.w500,
      ),
      prefixIcon: prefixIcon == null
          ? null
          : Icon(prefixIcon, color: const Color(0xFF65758B), size: 21),
      filled: true,
      fillColor: Colors.white,
      enabledBorder: border,
      focusedBorder: border.copyWith(
        borderSide: const BorderSide(color: Color(0xFF20228B), width: 1.4),
      ),
      errorBorder: border.copyWith(
        borderSide: const BorderSide(color: Color(0xFFDC4C2F), width: 1.2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
    );
  }

  bool get isLoginEnabled {
    final identifier = emailController.text.trim();
    final password = passwordController.text.trim();
    final isEmail = _emailRegex.hasMatch(identifier);
    final isPhone = _isPhoneInput(identifier);
    if (isEmail) return password.isNotEmpty;
    if (isPhone) return identifier.isNotEmpty;
    return false;
  }

  String _normalizePhone(String input) {
    final cleaned = input.replaceAll(RegExp(r'[\s-]'), '');
    if (cleaned.startsWith('+639') && cleaned.length == 13) return cleaned;
    if (cleaned.startsWith('09') && cleaned.length == 11) {
      return '+63${cleaned.substring(1)}';
    }
    if (cleaned.startsWith('9') && cleaned.length == 10) return '+63$cleaned';
    if (cleaned.startsWith('639') && cleaned.length == 12) return '+$cleaned';
    return cleaned;
  }

  bool _isPhoneInput(String input) {
    final normalized = _normalizePhone(input);
    return RegExp(r'^\+639\d{9}$').hasMatch(normalized);
  }

  String _pseudoEmailForPhone(String normalizedPhone) {
    final digitsOnly = normalizedPhone.replaceAll(RegExp(r'[^0-9]'), '');
    return 'phone_$digitsOnly@seaguard.local';
  }

  Set<String> _phoneCandidates(String normalizedPhone) {
    final cleaned = normalizedPhone.replaceAll(RegExp(r'\s+|-'), '');
    final variants = <String>{cleaned};

    if (cleaned.startsWith('+63') && cleaned.length > 3) {
      variants.add('0${cleaned.substring(3)}');
    }
    if (cleaned.startsWith('09')) {
      variants.add('+63${cleaned.substring(1)}');
    }
    if (cleaned.startsWith('9') && cleaned.length == 10) {
      variants.add('+63$cleaned');
      variants.add('0$cleaned');
    }

    return variants;
  }

  Future<Map<String, dynamic>> _findAccountByPhone(String normalizedPhone) async {
    var email = '';
    var exists = false;
    Map<String, dynamic>? userData;
    final candidates = _phoneCandidates(normalizedPhone).toList();
    const fields = [
      'contact_number',
      'phone',
      'mobile',
      'phoneNumber',
      'contactNumber',
      'username',
    ];

    for (final field in fields) {
      try {
        final snap = await FirebaseFirestore.instance
            .collection('users')
            .where(field, whereIn: candidates)
            .limit(1)
            .get();
        if (snap.docs.isNotEmpty) {
          exists = true;
          userData = snap.docs.first.data();
          break;
        }
      } catch (e, st) {
        debugPrint('Phone lookup failed for $field: $e');
        debugPrintStack(stackTrace: st);
      }
    }

    if (userData != null) {
      final docEmail = userData['email']?.toString().trim();
      if (docEmail != null && docEmail.isNotEmpty) {
        email = docEmail;
      } else {
        final username = userData['username']?.toString().trim();
        if (username != null && username.contains('@')) {
          email = username;
        }
      }
    }

    return {'email': email, 'exists': exists};
  }

  Future<void> _handleLogin() async {
    try {
      FocusScope.of(context).unfocus();
      debugPrint('Attempting login for ${emailController.text}');
      await _saveRememberedCredentials();
      if (!mounted) return;

      final identifier = emailController.text.trim();
      final password = passwordController.text.trim();

      final isPhone = _isPhoneInput(identifier);
      final isEmail = _emailRegex.hasMatch(identifier);

      String? loginIdentifier;
      bool attemptedPhoneLogin = false;
      String? formattedPhoneForOtp;
      String? pseudoEmailForPhone;

      if (isPhone) {
        final formatted = _normalizePhone(identifier);
        final lookup = await _findAccountByPhone(formatted);
        final emailForPhone = lookup['email']?.toString().trim() ?? '';
        final exists = lookup['exists'] == true;
        final pseudoEmail = _pseudoEmailForPhone(formatted);
        attemptedPhoneLogin = true;
        formattedPhoneForOtp = formatted;
        pseudoEmailForPhone = pseudoEmail;

        if (!mounted) return;

        if (!exists) {
          _showMessage('No account found for that mobile number. Please sign up first.');
          return;
        }

        if (emailForPhone.isNotEmpty) {
          if (password.isEmpty) {
            _showMessage('Enter your password to sign in with the email linked to this number.');
            return;
          }
          loginIdentifier = emailForPhone;
        } else {
          final methods = await FirebaseAuth.instance.fetchSignInMethodsForEmail(pseudoEmail);
          final hasPassword = methods.contains('password');

          if (hasPassword) {
            if (password.isEmpty) {
              _showMessage('Enter your password to sign in with this number.');
              return;
            }
            loginIdentifier = pseudoEmail;
          } else {
            if (password.isEmpty) {
              _showMessage('Enter a password so we can link it to your verified number after OTP.');
              return;
            }
            _showMessage('We will send an SMS code to finish signing you in.');
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => OTPVerificationScreen(
                  phoneNumber: formatted,
                  userData: const {},
                  loginMode: true,
                  linkEmail: pseudoEmail,
                  linkPassword: password,
                ),
              ),
            );
            return;
          }
        }
      }

      loginIdentifier ??= identifier;

      if (!isEmail && loginIdentifier == identifier) {
        _showMessage('Please enter a valid email or mobile number.');
        return;
      }

      final result = await AuthService.login(loginIdentifier, password);

      if (!mounted) return;

      if (result['error'] != null) {
        final code = (result['error'] ?? '').toString();
        final msg = result['message']?.toString();
        final friendly = _friendlyAuthCode(code, message: msg);

        if (attemptedPhoneLogin &&
            formattedPhoneForOtp != null &&
            _shouldReverifyPhoneLogin(code)) {
          _showMessage(
            'We need to re-verify this number via OTP to complete sign-in.',
          );
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => OTPVerificationScreen(
                phoneNumber: formattedPhoneForOtp!,
                userData: const {},
                loginMode: true,
                linkEmail: loginIdentifier ?? pseudoEmailForPhone,
                linkPassword: password,
              ),
            ),
          );
          return;
        }

        _showMessage(friendly);
        return;
      }

      final user = result['user'] as User;
      final role = (result['role'] ?? '').toString();

      debugPrint('Login successful. Role: $role');

      final verifiedOk = await _requireVerified(user);
      if (!verifiedOk) return;
      _showMessage(
        'Signed in successfully.',
        success: true,
        title: 'Welcome back',
      );
      await _routeAfterLogin(user, fallbackRole: role);
    } catch (e, st) {
      debugPrint('Login error: $e');
      debugPrintStack(stackTrace: st);
      String msg = 'Login failed';
      if (e is FirebaseAuthException) {
        msg = _friendlyAuthError(e);
      } else {
        msg = e.toString();
      }
      _showMessage(msg);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    const brand = Color(0xFF20228B);
    const ink = Color(0xFF0E3764);
    const muted = Color(0xFF65758B);
    final buttonStyle = ElevatedButton.styleFrom(
      backgroundColor: brand,
      disabledBackgroundColor: brand.withValues(alpha: 0.34),
      foregroundColor: Colors.white,
      disabledForegroundColor: Colors.white.withValues(alpha: 0.78),
      minimumSize: const Size(double.infinity, 54),
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(17)),
      textStyle: const TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w800,
      ),
    );

    Widget fieldLabel(String label) {
      return Align(
        alignment: Alignment.centerLeft,
        child: Text(
          label,
          style: const TextStyle(
            color: Color(0xFF344054),
            fontSize: 13.2,
            fontWeight: FontWeight.w800,
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFD),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final pagePadding = Responsive.pagePadding(context);
            final topPadding = constraints.maxHeight > 760 ? 54.0 : 32.0;

            return SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: EdgeInsets.fromLTRB(pagePadding, topPadding, pagePadding, 28),
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: Responsive.maxContentWidth(context, maxWidth: 420),
                  ),
                  child: Column(
                    children: [
                      Container(
                        width: 112,
                        height: 112,
                        padding: const EdgeInsets.all(15),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          border: Border.all(color: const Color(0xFFE1E9F2)),
                          boxShadow: [
                            BoxShadow(
                              color: ink.withValues(alpha: 0.08),
                              blurRadius: 24,
                              offset: const Offset(0, 12),
                            ),
                          ],
                        ),
                        child: Image.asset('assets/image.png'),
                      ),
                      const SizedBox(height: 14),
                      const Text(
                        'Sea Guard',
                        style: TextStyle(
                          color: ink,
                          fontSize: 30,
                          fontWeight: FontWeight.w900,
                          height: 1,
                        ),
                      ),
                      const SizedBox(height: 7),
                      const Text(
                        'Sign in to continue',
                        style: TextStyle(
                          color: muted,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 34),
                      fieldLabel(l10n.emailOrMobileNumber),
                      const SizedBox(height: 7),
                      TextField(
                        controller: emailController,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        decoration: _inputDecoration(
                          l10n.enterYourEmailOrNumber,
                          prefixIcon: Icons.person_outline_rounded,
                        ),
                      ),
                      const SizedBox(height: 14),
                      fieldLabel(l10n.password),
                      const SizedBox(height: 7),
                      TextField(
                        controller: passwordController,
                        obscureText: obscurePassword,
                        textInputAction: TextInputAction.done,
                        decoration:
                            _inputDecoration(
                              l10n.enterYourPassword,
                              prefixIcon: Icons.lock_outline_rounded,
                            ).copyWith(
                              suffixIcon: IconButton(
                                icon: Icon(
                                  obscurePassword
                                      ? Icons.visibility_off_rounded
                                      : Icons.visibility_rounded,
                                  color: const Color(0xFF4F5D6F),
                                ),
                                onPressed: () => setState(
                                  () => obscurePassword = !obscurePassword,
                                ),
                              ),
                            ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          SizedBox(
                            width: 32,
                            height: 32,
                            child: Checkbox(
                              value: rememberPassword,
                              activeColor: brand,
                              visualDensity: VisualDensity.compact,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(5),
                              ),
                              onChanged: (val) => setState(
                                () => rememberPassword = val ?? false,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            l10n.rememberPassword,
                            style: const TextStyle(
                              color: Color(0xFF344054),
                              fontSize: 14.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 22),
                      AnimatedBuilder(
                        animation: _formListenable,
                        builder: (context, child) {
                          return ElevatedButton(
                            onPressed: isLoginEnabled ? _handleLogin : null,
                            style: buttonStyle,
                            child: child ?? const SizedBox.shrink(),
                          );
                        },
                        child: Text(l10n.logIn),
                      ),
                      const SizedBox(height: 18),
                      TextButton(
                        onPressed: () => Navigator.pushNamed(context, '/register'),
                        style: TextButton.styleFrom(
                          foregroundColor: const Color(0xFF6E56A8),
                          textStyle: const TextStyle(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        child: Text(l10n.dontHaveAnAccountSignup),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
