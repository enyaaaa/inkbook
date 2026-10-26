import 'dart:async';

/// The signed-in person, as far as the app cares.
class AuthUser {
  const AuthUser({required this.uid, this.email, this.displayName});

  final String uid;
  final String? email;

  /// From Google sign-in; used to pre-fill the profile set-up form.
  final String? displayName;
}

/// A sign-in failure with a message fit to show the user.
class AuthFailure implements Exception {
  const AuthFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Sign-in, expressed as an interface so the app runs with or without
/// Firebase (see [LocalAuthService] and `FirebaseAuthService`).
///
/// There are no guest sessions: everyone signs in or creates an account
/// before they reach their sketchbooks.
abstract class AuthService {
  AuthUser? get currentUser;

  /// Emits the current user straight away (null if signed out), then again
  /// whenever someone signs in or out.
  Stream<AuthUser?> get userChanges;

  Future<void> signInWithGoogle();

  Future<void> createAccount({required String email, required String password});

  Future<void> signIn({required String email, required String password});

  Future<void> sendPasswordReset(String email);

  Future<void> signOut();
}

/// Offline stand-in used when Firebase is not configured for the platform:
/// one permanent local user, no real accounts.
class LocalAuthService implements AuthService {
  static const AuthUser _local = AuthUser(uid: 'u-me');

  @override
  AuthUser? get currentUser => _local;

  @override
  Stream<AuthUser?> get userChanges => Stream<AuthUser?>.value(_local);

  static const AuthFailure _unsupported =
      AuthFailure('Accounts need the Firebase backend, which is not set up.');

  @override
  Future<void> signInWithGoogle() async => throw _unsupported;

  @override
  Future<void> createAccount({
    required String email,
    required String password,
  }) async =>
      throw _unsupported;

  @override
  Future<void> signIn({
    required String email,
    required String password,
  }) async =>
      throw _unsupported;

  @override
  Future<void> sendPasswordReset(String email) async => throw _unsupported;

  @override
  Future<void> signOut() async {}
}
