import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../utils/responsive.dart';
import '../profile/terms_and_condition_page.dart';

class GoogleRoleSelectionScreen extends StatefulWidget {
  final User user;
  final Map<String, dynamic>? existingData;

  const GoogleRoleSelectionScreen({
    super.key,
    required this.user,
    this.existingData,
  });

  @override
  State<GoogleRoleSelectionScreen> createState() =>
      _GoogleRoleSelectionScreenState();
}

class _GoogleRoleSelectionScreenState extends State<GoogleRoleSelectionScreen> {
  String? _selectedRole = 'user';
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _selectedRole = 'user';
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Map<String, String> _splitName(String fullName) {
    final cleaned = fullName.trim();
    if (cleaned.isEmpty) return {'first': '', 'last': ''};
    final parts = cleaned
        .split(RegExp(r'\s+'))
        .where((p) => p.trim().isNotEmpty)
        .toList();
    final first = parts.isNotEmpty ? parts.first : '';
    final last = parts.length > 1 ? parts.sublist(1).join(' ') : '';
    return {'first': first, 'last': last};
  }

  bool _isPcgRole(Map<String, dynamic> data) {
    final combined =
        '${data['role'] ?? ''} ${data['roleLabel'] ?? data['role_label'] ?? ''}'
            .toLowerCase();
    return combined.contains('pcg') ||
        combined.contains('coast guard') ||
        combined.contains('sub-admin') ||
        combined.contains('sub admin') ||
        combined.contains('subadmin');
  }

  Future<User?> _requireVerifiedEmail(User user) async {
    await user.reload();
    final refreshedUser = FirebaseAuth.instance.currentUser ?? user;
    if (refreshedUser.emailVerified) return refreshedUser;

    _showMessage('Please verify your email before choosing a role.');
    await FirebaseAuth.instance.signOut();
    if (mounted) {
      Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false);
    }
    return null;
  }

  Future<void> _returnToLogin() async {
    try {
      await FirebaseAuth.instance.signOut();
    } catch (_) {}
    if (mounted) {
      Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false);
    }
  }

  Future<void> _continue() async {
    if (_selectedRole == null) {
      _showMessage('Please choose an account type to continue.');
      return;
    }
    setState(() => _isSaving = true);

    try {
      final user = widget.user;
      await user.reload();
      final refreshedUser = FirebaseAuth.instance.currentUser ?? user;
      final verifiedUser = await _requireVerifiedEmail(refreshedUser);
      if (verifiedUser == null || !mounted) return;

      final fullName = (user.displayName ?? '').trim();
      final nameParts = _splitName(fullName);
      const roleLabel = 'Community Member';

      final docRef = FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid);
      final snapshot = await docRef.get();
      final existing =
          snapshot.data() ?? widget.existingData ?? const <String, dynamic>{};
      if (_isPcgRole(existing)) {
        await _returnToLogin();
        if (!mounted) return;
        _showMessage(
          'PCG accounts are created by the web PCG admin. Please sign in from Login.',
        );
        return;
      }

      final updates = <String, dynamic>{
        'email': (user.email ?? '').trim(),
        'name': fullName,
        'fullName': fullName,
        'firstName': nameParts['first'],
        'lastName': nameParts['last'],
        'first_name': nameParts['first'],
        'last_name': nameParts['last'],
        'provider': 'google',
        'providerLabel': 'google',
        'provider_id': 'google',
        'role': 'user',
        'roleLabel': roleLabel,
        'email_verified': verifiedUser.emailVerified,
        'email_confirmation_required': !verifiedUser.emailVerified,
        'authPhotoUrl': user.photoURL,
        'profileImageUrl': user.photoURL,
        'photo_url': user.photoURL,
        'updated_at': FieldValue.serverTimestamp(),
      };

      if (!snapshot.exists) {
        updates['created_at'] = FieldValue.serverTimestamp();
      }

      await docRef.set(updates, SetOptions(merge: true));
      final mergedData = <String, dynamic>{...existing, ...updates};

      await docRef.set({
        'email_verified': verifiedUser.emailVerified,
        'email_confirmation_required': !verifiedUser.emailVerified,
        'email_verified_at': verifiedUser.emailVerified
            ? FieldValue.serverTimestamp()
            : null,
        'updated_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      final accepted = (mergedData['acceptedTerms'] == true) ||
          (mergedData['termsAcceptedAt'] != null);

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
      _showMessage('Unable to continue: $e');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Widget _roleCard({
    required String value,
    required String title,
    required String subtitle,
    required IconData icon,
  }) {
    final isSelected = _selectedRole == value;
    return InkWell(
      onTap: _isSaving ? null : () => setState(() => _selectedRole = value),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected ? Colors.indigo.shade50 : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? Colors.indigo : Colors.grey.shade300,
            width: 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: Colors.indigo.withOpacity(0.1),
              foregroundColor: Colors.indigo.shade700,
              child: Icon(icon),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(color: Colors.grey.shade700),
                  ),
                ],
              ),
            ),
            Radio<String>(
              value: value,
              groupValue: _selectedRole,
              activeColor: Colors.indigo,
              onChanged: _isSaving
                  ? null
                  : (val) => setState(() => _selectedRole = val),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final padding = Responsive.pagePadding(context);
    final vertical = Responsive.verticalSpace(context);
    final maxWidth = Responsive.maxContentWidth(context, maxWidth: 520);

    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      appBar: AppBar(
        title: const Text('Choose your role'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0.5,
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: SingleChildScrollView(
              padding: EdgeInsets.all(padding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 6),
                  Text(
                    'Continue with Google',
                    style: TextStyle(
                      color: Colors.grey.shade700,
                      fontSize: 14,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Center(
                    child: Text(
                      widget.user.email ?? '',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  SizedBox(height: vertical),
                  _roleCard(
                    value: 'user',
                    title: 'Community Member',
                    subtitle:
                        'Access community updates, reports, and marine tools.',
                    icon: Icons.groups_rounded,
                  ),
                  SizedBox(height: vertical),
                  ElevatedButton(
                    onPressed: _isSaving ? null : _continue,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.indigo[900],
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(50),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _isSaving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Colors.white,
                              ),
                            ),
                          )
                        : const Text('Continue'),
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
