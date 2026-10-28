import 'dart:developer';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AuthService {
  static final FirebaseAuth auth = FirebaseAuth.instance;
  static final FirebaseFirestore firestore = FirebaseFirestore.instance;

  static Future<User?> signUp(
    String email,
    String password, {
    Map<String, dynamic>? extraData,
  }) async {
    try {
      final cred = await auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      await cred.user!.sendEmailVerification();

      if (extraData != null) {
        await firestore.collection('users').doc(cred.user!.uid).set({
          'email': email,
          'role': extraData['role'] ?? 'user',
          ...extraData..remove('role'),
          'email_verified': false,
          'created_at': FieldValue.serverTimestamp(),
        });
      }

      log(" Verification email sent to $email");
      return cred.user;
    } catch (e) {
      log(' Signup failed: ${e.toString()}');
      return null;
    }
  }

  static Future<Map<String, dynamic>> login(
    String email,
    String password,
  ) async {
    try {
      final userCred = await auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      final user = userCred.user;
      await user!.reload();

      final refreshedUser = auth.currentUser;
      final lowerEmail = (refreshedUser?.email ?? email).toLowerCase();
      final hasPhoneProvider =
          refreshedUser?.providerData.any((p) => p.providerId == 'phone') ?? false;
      final isPseudoPhoneEmail =
          lowerEmail.startsWith('phone_') || lowerEmail.endsWith('@seaguard.local');
      final shouldEnforceEmailVerification = !hasPhoneProvider && !isPseudoPhoneEmail;

      if (shouldEnforceEmailVerification && !(refreshedUser?.emailVerified ?? false)) {
        try {
          await refreshedUser?.sendEmailVerification();
          log("Email not verified. Verification email resent.");
        } catch (e) {
          log("Email verification send failed: $e");
        }
        await auth.signOut();
        return {
          'error': 'email-not-verified',
          'message': 'Email not verified. We sent a new verification link.',
        };
      }

      final userDoc = await firestore.collection('users').doc(user.uid).get();
      final role = userDoc.data()?['role'] ?? 'user';

      log(" Login successful for $email (role: $role)");
      return {'user': refreshedUser, 'role': role};
    } on FirebaseAuthException catch (e) {
      log(' Login failed: ${e.code} ${e.message}');
      return {'error': e.code, 'message': e.message};
    } catch (e) {
      log(' Login failed: ${e.toString()}');
      return {'error': 'unknown', 'message': e.toString()};
    }
  }

  static Future<User?> signInWithGoogle() async {
    try {
      final GoogleSignIn googleSignIn = GoogleSignIn.standard();
      await googleSignIn.signOut();

      final googleUser = await googleSignIn.signIn();
      if (googleUser == null) return null;

      final googleAuth = await googleUser.authentication;

      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final userCredential = await auth.signInWithCredential(credential);
      final user = userCredential.user;
      if (user == null) return null;

      await user.reload();
      final refreshedUser = auth.currentUser ?? user;

      if (!refreshedUser.emailVerified) {
        try {
          await refreshedUser.sendEmailVerification();
        } catch (e) {
          log(" Google email verification send failed: $e");
        }
        await googleSignIn.signOut();
        await auth.signOut();
        log(" Google Sign-In blocked until email verification for ${refreshedUser.email}");
        return null;
      }

      final doc = firestore.collection('users').doc(refreshedUser.uid);
      if (!(await doc.get()).exists) {
        await doc.set({
          'email': refreshedUser.email,
          'name': refreshedUser.displayName,
          'photo_url': refreshedUser.photoURL,
          'provider': 'google',
          'role': 'user',
          'roleLabel': 'Community Member',
          'email_verified': refreshedUser.emailVerified,
          'created_at': FieldValue.serverTimestamp(),
        });
      }

      log(" Google Sign-In successful for ${refreshedUser.email}");
      return refreshedUser;
    } catch (e, stackTrace) {
      log(" Google Sign-In error: ${e.toString()}", stackTrace: stackTrace);
      return null;
    }
  }

  static Future<void> logout() async {
    try {
      await GoogleSignIn().signOut();
      await auth.signOut();
      log(" User logged out");
    } catch (e) {
      log(" Logout failed: ${e.toString()}");
    }
  }

  static Future<void> sendOTP({
    required String phoneNumber,
    required void Function(String verificationId) codeSent,
    required void Function(FirebaseAuthException e) verificationFailed,
    required void Function(PhoneAuthCredential credential)
    verificationCompleted,
    required void Function(String verificationId) codeAutoRetrievalTimeout,
  }) async {
    try {
      await auth.verifyPhoneNumber(
        phoneNumber: phoneNumber,
        timeout: const Duration(seconds: 60),
        verificationCompleted: verificationCompleted,
        verificationFailed: verificationFailed,
        codeSent: (verificationId, resendToken) {
          log(" Code sent to $phoneNumber");
          codeSent(verificationId);
        },
        codeAutoRetrievalTimeout: (verificationId) {
          log(" Auto-retrieval timeout for $phoneNumber");
          codeAutoRetrievalTimeout(verificationId);
        },
      );
    } catch (e) {
      log(" Failed to send OTP: ${e.toString()}");
    }
  }

  static Future<User?> verifyOTP(String verificationId, String smsCode) async {
    try {
      final credential = PhoneAuthProvider.credential(
        verificationId: verificationId,
        smsCode: smsCode,
      );

      final userCred = await auth.signInWithCredential(credential);
      final user = userCred.user;

      log(" Phone number verified for UID: ${user?.uid}");
      return user;
    } catch (e) {
      log(" OTP Verification failed: ${e.toString()}");
      return null;
    }
  }

  static Future tempCreateAccount(userData, userData2) async {}
}
