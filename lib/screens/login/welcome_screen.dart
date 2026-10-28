import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  bool _hasNavigated = false;

  @override
  void initState() {
    super.initState();

    _checkSessionAndNavigate();
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

  void _navigateToLogin({bool immediate = false}) {
    final action = () {
      if (!mounted || _hasNavigated) return;
      _hasNavigated = true;
      Navigator.pushReplacementNamed(context, '/login');
    };

    if (immediate) {
      action();
    } else {
      Future.delayed(const Duration(seconds: 3), action);
    }
  }

  void _navigateToRole(String role) {
    if (!mounted || _hasNavigated) return;
    _hasNavigated = true;
    final isAdmin = _isAdminRole(role);
    Navigator.pushReplacementNamed(
      context,
      isAdmin ? '/adminDashboard' : '/dashboard',
    );
  }

  Future<void> _checkSessionAndNavigate() async {
    final user = FirebaseAuth.instance.currentUser;

    if (user != null) {
      try {
        final snap =
            await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
        final data = snap.data() ?? {};
        final isActive = data['active'];

        if (isActive == false) {
          await FirebaseAuth.instance.signOut();
          _navigateToLogin(immediate: true);
          return;
        }

        final role = (data['role'] ?? '').toString();
        final roleLabel = (data['roleLabel'] ?? data['role_label'] ?? '').toString();
        if (_isPcgRole(role, roleLabel) && !_isPcgApproved(data)) {
          await FirebaseAuth.instance.signOut();
          _navigateToLogin(immediate: true);
          return;
        }
        _navigateToRole(role);
        return;
      } catch (_) {
        // If we can't fetch role, default to user dashboard to keep flow smooth.
        _navigateToRole('');
        return;
      }
    }

    _navigateToLogin();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Image.asset('assets/image.png', height: 200),
        ),
      ),
    );
  }
}
