import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb_auth;

import '../../../../core/constants/firestore_paths.dart';
import '../../../../core/errors/app_exceptions.dart';
import '../models/app_user_model.dart';

/// The only file in the app allowed to talk to `firebase_auth` directly
/// for authentication concerns. Everything above this layer works with
/// [AppUserModel] / [AppUser], never with `firebase_auth`'s `User` type.
class AuthRemoteDataSource {
  final fb_auth.FirebaseAuth _auth;
  final FirebaseFirestore _firestore;
  final FirebaseFunctions _functions;

  const AuthRemoteDataSource({
    required fb_auth.FirebaseAuth auth,
    required FirebaseFirestore firestore,
    required FirebaseFunctions functions,
  })  : _auth = auth,
        _firestore = firestore,
        _functions = functions;

  /// Emits a fully-hydrated [AppUserModel] (or null) any time Firebase
  /// Auth's sign-in state changes. `idTokenChanges` (not `authStateChanges`)
  /// is used so that custom-claim updates -- e.g. an admin approving the
  /// account or clearing mustChangePassword -- also trigger a re-fetch
  /// without requiring the user to sign out and back in.
  Stream<AppUserModel?> watchAuthState() {
    return _auth.idTokenChanges().asyncMap((user) async {
      if (user == null) return null;
      return _hydrateUser(user);
    });
  }

  Future<AppUserModel> login({required String email, required String password}) async {
    try {
      final credential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      final user = credential.user;
      if (user == null) {
        throw const AuthException('unknown', 'Sign-in returned no user.');
      }
      return _hydrateUser(user);
    } on fb_auth.FirebaseAuthException catch (e) {
      throw AuthException(e.code, _mapAuthErrorMessage(e.code));
    }
  }

  Future<void> logout() async {
    await _auth.signOut();
  }

  Future<void> sendPasswordResetEmail(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email);
    } on fb_auth.FirebaseAuthException catch (e) {
      throw AuthException(e.code, _mapAuthErrorMessage(e.code));
    }
  }

  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final user = _auth.currentUser;
    if (user == null || user.email == null) {
      throw const AuthException('no-current-user', 'No signed-in user found.');
    }
    try {
      // Firebase Auth requires a recent sign-in for sensitive operations
      // like password changes; re-authenticate explicitly rather than
      // surfacing a confusing 'requires-recent-login' error to the user.
      final credential = fb_auth.EmailAuthProvider.credential(
        email: user.email!,
        password: currentPassword,
      );
      await user.reauthenticateWithCredential(credential);
      await user.updatePassword(newPassword);
    } on fb_auth.FirebaseAuthException catch (e) {
      throw AuthException(e.code, _mapAuthErrorMessage(e.code));
    }
  }

  /// Clearing `mustChangePassword` touches both a custom claim and the
  /// Firestore profile doc, and must be tamper-proof -- so it goes through
  /// a callable Cloud Function running with Admin privileges rather than a
  /// direct client Firestore write.
  Future<void> clearForcePasswordChangeFlag() async {
    try {
      final callable = _functions.httpsCallable('clearForcePasswordChangeFlag');
      await callable.call();
      // Force a token refresh so the cleared claim is reflected locally
      // without requiring the user to sign out and back in.
      await _auth.currentUser?.getIdToken(true);
    } on FirebaseFunctionsException catch (e) {
      throw ServerException(e.message ?? 'Failed to update password change status.');
    }
  }

  Future<AppUserModel> getCurrentUserProfile() async {
    final user = _auth.currentUser;
    if (user == null) {
      throw const AuthException('no-current-user', 'No signed-in user found.');
    }
    return _hydrateUser(user);
  }

  Future<AppUserModel> _hydrateUser(fb_auth.User user) async {
    // Force-refresh so we never read stale claims right after a role
    // change or after clearForcePasswordChangeFlag ran.
    final tokenResult = await user.getIdTokenResult(true);
    final claims = tokenResult.claims ?? {};

    final role = claims['role'] as String?;
    if (role == null) {
      throw const AuthException(
        'no-role-claim',
        'Your account has not been fully provisioned yet. Please contact your school administrator.',
      );
    }
    final schoolId = claims['schoolId'] as String?; // null for Owner
    final mustChangePassword = claims['mustChangePassword'] as bool? ?? false;

    // Owner profile lives outside any school; everyone else's lives under
    // schools/{schoolId}/users/{uid}.
    final docPath = schoolId != null
        ? FirestorePaths.userDoc(schoolId, user.uid)
        : FirestorePaths.ownerProfileDoc(user.uid);

    final snapshot = await _firestore.doc(docPath).get();
    if (!snapshot.exists) {
      throw NotFoundException('User profile not found for uid ${user.uid}.');
    }

    return AppUserModel.fromFirestore(
      uid: user.uid,
      data: snapshot.data()!,
      schoolIdFromClaims: schoolId,
      roleFromClaims: role,
      mustChangePasswordFromClaims: mustChangePassword,
    );
  }

  String _mapAuthErrorMessage(String code) {
    return switch (code) {
      'invalid-credential' || 'wrong-password' || 'user-not-found' =>
        'Incorrect email or password.',
      'user-disabled' => 'This account has been disabled. Contact your school administrator.',
      'too-many-requests' => 'Too many attempts. Please wait a moment and try again.',
      'network-request-failed' => 'Network error. Check your connection and try again.',
      'requires-recent-login' => 'Please sign in again before changing your password.',
      'weak-password' => 'Password is too weak.',
      _ => 'Authentication failed. Please try again.',
    };
  }
}
