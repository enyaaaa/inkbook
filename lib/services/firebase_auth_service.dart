import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import 'auth_service.dart';

/// [AuthService] backed by Firebase Authentication: email/password and
/// Google. Firebase keeps the session, so people stay signed in across
/// launches until they sign out.
class FirebaseAuthService implements AuthService {
  FirebaseAuthService({FirebaseAuth? auth})
      : _auth = auth ?? FirebaseAuth.instance;

  final FirebaseAuth _auth;

  static AuthUser? _map(User? user) => user == null
      ? null
      : AuthUser(
          uid: user.uid,
          email: user.email,
          displayName: user.displayName,
        );

  @override
  AuthUser? get currentUser => _map(_auth.currentUser);

  @override
  Stream<AuthUser?> get userChanges => _auth.authStateChanges().map(_map);

  @override
  Future<void> signInWithGoogle() => _guard(() => kIsWeb
      ? _auth.signInWithPopup(GoogleAuthProvider())
      : _auth.signInWithProvider(GoogleAuthProvider()));

  @override
  Future<void> createAccount({
    required String email,
    required String password,
  }) =>
      _guard(() => _auth.createUserWithEmailAndPassword(
            email: email.trim(),
            password: password,
          ));

  @override
  Future<void> signIn({required String email, required String password}) =>
      _guard(() => _auth.signInWithEmailAndPassword(
            email: email.trim(),
            password: password,
          ));

  @override
  Future<void> sendPasswordReset(String email) =>
      _guard(() => _auth.sendPasswordResetEmail(email: email.trim()));

  @override
  Future<void> signOut() => _auth.signOut();

  Future<T> _guard<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on FirebaseAuthException catch (e) {
      throw AuthFailure(_message(e));
    }
  }

  static String _message(FirebaseAuthException e) {
    switch (e.code) {
      case 'invalid-email':
        return 'That email address does not look right.';
      case 'email-already-in-use':
        return 'That email already has an account - sign in instead.';
      case 'account-exists-with-different-credential':
        return 'That email already has an account with a password - sign '
            'in with your email instead.';
      case 'weak-password':
        return 'Use a password with at least 6 characters.';
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        return 'Email or password is incorrect.';
      case 'user-disabled':
        return 'This account has been disabled.';
      case 'too-many-requests':
        return 'Too many attempts. Wait a moment and try again.';
      case 'popup-closed-by-user':
      case 'cancelled-popup-request':
      case 'web-context-canceled':
        return 'Sign-in was cancelled.';
      case 'popup-blocked':
        return 'Your browser blocked the sign-in window - allow pop-ups '
            'for this site and try again.';
      case 'network-request-failed':
        return 'No connection. Check your internet and try again.';
      case 'operation-not-allowed':
        return 'This sign-in method is not enabled in the Firebase console.';
      default:
        return e.message ?? 'Something went wrong (${e.code}).';
    }
  }
}
