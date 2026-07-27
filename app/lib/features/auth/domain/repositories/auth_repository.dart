import '../../../../core/errors/result.dart';
import '../entities/app_user.dart';

/// Contract the data layer must fulfil. Usecases and Riverpod controllers
/// depend only on this interface, never on the Firebase implementation --
/// this is what makes the domain layer testable without a Firebase emulator.
abstract class AuthRepository {
  /// Emits the current [AppUser] whenever Firebase Auth state changes,
  /// or `null` when signed out. Emits a fresh profile fetch on every
  /// change so role/status/mustChangePassword are always current.
  Stream<AppUser?> watchAuthState();

  Future<Result<AppUser>> login({
    required String email,
    required String password,
  });

  Future<Result<void>> logout();

  Future<Result<void>> sendPasswordResetEmail(String email);

  /// Changes the password for the currently signed-in user. Requires
  /// re-authentication with [currentPassword] first, since Firebase Auth
  /// rejects sensitive updates on a stale session.
  Future<Result<void>> changePassword({
    required String currentPassword,
    required String newPassword,
  });

  /// Called after a successful forced password change to clear the
  /// `mustChangePassword` flag server-side (both the Firestore doc and
  /// the custom claim). Must go through a Cloud Function -- the client
  /// cannot be trusted to clear its own security flag directly.
  Future<Result<void>> clearForcePasswordChangeFlag();

  Future<Result<AppUser>> getCurrentUserProfile();
}
