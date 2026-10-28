import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../utils/responsive.dart';

class EmailVerificationScreen extends StatefulWidget {
  final User user;
  final bool createdNewUser;
  final bool autoContinueWhenVerified;

  const EmailVerificationScreen({
    super.key,
    required this.user,
    this.createdNewUser = false,
    this.autoContinueWhenVerified = true,
  });

  @override
  State<EmailVerificationScreen> createState() =>
      _EmailVerificationScreenState();
}

class _EmailVerificationScreenState extends State<EmailVerificationScreen>
    with WidgetsBindingObserver {
  static const Duration _autoCheckInterval = Duration(seconds: 3);

  bool _isChecking = false;
  bool _isResending = false;
  bool _hasCompletedVerification = false;
  bool _isRefreshingVerification = false;
  bool _isVerified = false;
  Timer? _verificationPoller;
  Timer? _resendCooldownTimer;
  int _resendCooldownSeconds = 0;

  @override
  void initState() {
    super.initState();
    _isVerified = widget.user.emailVerified;
    WidgetsBinding.instance.addObserver(this);
    _startVerificationWatcher();
  }

  Future<User?> _refreshUser() async {
    try {
      await widget.user.reload();
    } catch (_) {}
    return FirebaseAuth.instance.currentUser;
  }

  void _startVerificationWatcher() {
    _verificationPoller?.cancel();
    if (!widget.autoContinueWhenVerified && _isVerified) return;

    _scheduleVerificationCheck();
    _verificationPoller = Timer.periodic(_autoCheckInterval, (_) {
      _scheduleVerificationCheck();
    });
  }

  void _scheduleVerificationCheck({
    bool showPendingMessage = false,
    bool indicateProgress = false,
  }) {
    unawaited(
      _checkVerificationStatus(
        showPendingMessage: showPendingMessage,
        indicateProgress: indicateProgress,
      ),
    );
  }

  Future<void> _checkVerificationStatus({
    bool showPendingMessage = false,
    bool indicateProgress = false,
    bool completeWhenVerified = false,
  }) async {
    if (_isRefreshingVerification || _hasCompletedVerification || !mounted) {
      return;
    }

    _isRefreshingVerification = true;
    if (indicateProgress) {
      setState(() => _isChecking = true);
    }
    try {
      final refreshed = await _refreshUser();
      if (!mounted || _hasCompletedVerification) return;

      final verified = refreshed?.emailVerified ?? false;
      if (verified) {
        _verificationPoller?.cancel();
        if (widget.autoContinueWhenVerified || completeWhenVerified) {
          _hasCompletedVerification = true;
          Navigator.pop(context, true);
          return;
        }
        if (!_isVerified) {
          setState(() => _isVerified = true);
        }
        return;
      }

      if (showPendingMessage) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Email not verified yet. Please tap the link we sent.',
            ),
          ),
        );
      }
    } finally {
      _isRefreshingVerification = false;
      if (indicateProgress && mounted && !_hasCompletedVerification) {
        setState(() => _isChecking = false);
      }
    }
  }

  Future<void> _checkIfVerified() async {
    if (_isVerified && !widget.autoContinueWhenVerified) {
      Navigator.pop(context, true);
      return;
    }

    await _checkVerificationStatus(
      showPendingMessage: true,
      indicateProgress: true,
      completeWhenVerified: true,
    );
  }

  Future<void> _resendEmail() async {
    if (_isResending || _isVerified || _resendCooldownSeconds > 0) return;
    setState(() => _isResending = true);
    try {
      await widget.user.sendEmailVerification();
      if (mounted) {
        _startResendCooldown(60);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Verification email sent again.')),
        );
      }
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      if (e.code == 'too-many-requests') {
        _startResendCooldown(300);
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_friendlyResendError(e))),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unable to resend verification: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isResending = false);
    }
  }

  String _friendlyResendError(FirebaseAuthException e) {
    switch (e.code) {
      case 'too-many-requests':
        return 'Too many verification email requests. Use the latest email link, or try resending again later.';
      case 'user-disabled':
        return 'This account has been disabled. Please contact an administrator.';
      case 'network-request-failed':
        return 'Network error. Check your connection and try again.';
      default:
        return e.message ?? 'Unable to resend verification right now.';
    }
  }

  void _startResendCooldown(int seconds) {
    _resendCooldownTimer?.cancel();
    setState(() => _resendCooldownSeconds = seconds);
    _resendCooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_resendCooldownSeconds <= 1) {
        timer.cancel();
        setState(() => _resendCooldownSeconds = 0);
        return;
      }
      setState(() => _resendCooldownSeconds--);
    });
  }

  String _resendButtonText() {
    if (_resendCooldownSeconds <= 0) return 'Resend verification';
    final minutes = _resendCooldownSeconds ~/ 60;
    final seconds = _resendCooldownSeconds % 60;
    if (minutes <= 0) return 'Resend in ${seconds}s';
    return 'Resend in ${minutes}m ${seconds.toString().padLeft(2, '0')}s';
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _verificationPoller?.cancel();
    _resendCooldownTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _scheduleVerificationCheck();
    }
  }

  @override
  Widget build(BuildContext context) {
    final email = widget.user.email ?? '';
    final padding = Responsive.pagePadding(context);
    final vertical = Responsive.verticalSpace(context);
    final maxWidth = Responsive.maxContentWidth(context, maxWidth: 420);
    final manualMode = !widget.autoContinueWhenVerified;

    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: Padding(
              padding: EdgeInsets.all(padding),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.mark_email_read,
                    size: 64,
                    color: Colors.indigo,
                  ),
                  SizedBox(height: vertical / 2),
                  const Text(
                    'Verify your email',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _isVerified
                        ? 'This email is verified'
                        : 'We sent a verification link to',
                    style: TextStyle(color: Colors.grey[700]),
                  ),
                  Text(
                    email,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    manualMode
                        ? (_isVerified
                            ? 'Tap Continue to finish setting up your account.'
                            : 'Verify this email first, then return here and tap the button below.')
                        : 'This screen will continue automatically once your email is verified.',
                    style: TextStyle(color: Colors.grey[700]),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: vertical),
                  ElevatedButton(
                    onPressed: _isChecking ? null : _checkIfVerified,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.indigo[900],
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(48),
                    ),
                    child: _isChecking
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(
                            _isVerified && manualMode
                                ? 'Continue'
                                : 'I verified my email',
                          ),
                  ),
                  const SizedBox(height: 8),
                  if (!_isVerified)
                    OutlinedButton(
                      onPressed:
                          (_isResending || _resendCooldownSeconds > 0)
                              ? null
                              : _resendEmail,
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                        side: BorderSide(color: Colors.indigo.shade900),
                        foregroundColor: Colors.indigo[900],
                      ),
                      child: _isResending
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(_resendButtonText()),
                    ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Cancel'),
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
