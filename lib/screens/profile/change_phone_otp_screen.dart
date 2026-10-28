import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class ChangePhoneOtpScreen extends StatefulWidget {
  final String verificationId;
  final String displayPhone;
  final String normalizedPhone;

  const ChangePhoneOtpScreen({
    super.key,
    required this.verificationId,
    required this.displayPhone,
    required this.normalizedPhone,
  });

  @override
  State<ChangePhoneOtpScreen> createState() => _ChangePhoneOtpScreenState();
}

class _ChangePhoneOtpScreenState extends State<ChangePhoneOtpScreen> {
  final TextEditingController _otpController = TextEditingController();
  bool _isVerifying = false;

  Future<void> _verify() async {
    final smsCode = _otpController.text.trim();
    if (smsCode.length != 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter the 6-digit code.')),
      );
      return;
    }

    setState(() => _isVerifying = true);

    try {
      final credential = PhoneAuthProvider.credential(
        verificationId: widget.verificationId,
        smsCode: smsCode,
      );

      final auth = FirebaseAuth.instance;
      await auth.currentUser?.updatePhoneNumber(credential);

      final uid = auth.currentUser?.uid;
      if (uid != null) {
        await FirebaseFirestore.instance.collection('users').doc(uid).update({
          'contact_number': widget.normalizedPhone,
          'username': widget.displayPhone,
        });
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Phone number verified successfully.')),
      );
      Navigator.pop(context);
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message ?? 'Invalid code. Please try again.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Verification failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _isVerifying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Verify New Number'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0.5,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Enter the 6-digit code sent to ${widget.displayPhone}',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _otpController,
              keyboardType: TextInputType.number,
              maxLength: 6,
              decoration: const InputDecoration(
                hintText: '6-digit code',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _isVerifying ? null : _verify,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1A2530),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: Text(
                _isVerifying ? 'Verifying...' : 'Verify',
                style: const TextStyle(
                    fontWeight: FontWeight.bold, color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
