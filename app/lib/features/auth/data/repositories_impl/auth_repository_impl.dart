import '../../../../core/errors/app_exceptions.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/errors/result.dart';
import '../../domain/entities/app_user.dart';
import '../../domain/repositories/auth_repository.dart';
import '../datasources/auth_remote_datasource.dart';

/// Translates data-source exceptions into typed [Failure]s. This is the
/// only layer allowed to catch [AuthException]/[ServerException]/etc --
/// everything above it works purely with [Result].
class AuthRepositoryImpl implements AuthRepository {
  final AuthRemoteDataSource _remote;
  const AuthRepositoryImpl(this._remote);

  @override
  Stream<AppUser?> watchAuthState() => _remote.watchAuthState();

  @override
  Future<Result<AppUser>> login({required String email, required String password}) async {
    try {
      final user = await _remote.login(email: email, password: password);
      return Success(user);
    } on AuthException catch (e) {
      return Error(AuthFailure(e.code, e.message));
    } on NotFoundException catch (e) {
      return Error(ServerFailure(e.message));
    } catch (_) {
      return const Error(UnknownFailure());
    }
  }

  @override
  Future<Result<void>> logout() async {
    try {
      await _remote.logout();
      return const Success(null);
    } catch (_) {
      return const Error(UnknownFailure('Failed to sign out. Please try again.'));
    }
  }

  @override
  Future<Result<void>> sendPasswordResetEmail(String email) async {
    try {
      await _remote.sendPasswordResetEmail(email);
      return const Success(null);
    } on AuthException catch (e) {
      return Error(AuthFailure(e.code, e.message));
    } catch (_) {
      return const Error(UnknownFailure());
    }
  }

  @override
  Future<Result<void>> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    try {
      await _remote.changePassword(currentPassword: currentPassword, newPassword: newPassword);
      return const Success(null);
    } on AuthException catch (e) {
      return Error(AuthFailure(e.code, e.message));
    } catch (_) {
      return const Error(UnknownFailure());
    }
  }

  @override
  Future<Result<void>> clearForcePasswordChangeFlag() async {
    try {
      await _remote.clearForcePasswordChangeFlag();
      return const Success(null);
    } on ServerException catch (e) {
      return Error(ServerFailure(e.message));
    } catch (_) {
      return const Error(UnknownFailure());
    }
  }

  @override
  Future<Result<AppUser>> getCurrentUserProfile() async {
    try {
      final user = await _remote.getCurrentUserProfile();
      return Success(user);
    } on AuthException catch (e) {
      return Error(AuthFailure(e.code, e.message));
    } on NotFoundException catch (e) {
      return Error(ServerFailure(e.message));
    } catch (_) {
      return const Error(UnknownFailure());
    }
  }
}
