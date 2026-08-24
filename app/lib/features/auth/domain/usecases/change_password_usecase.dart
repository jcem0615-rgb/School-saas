import '../../../../core/errors/failures.dart';
import '../../../../core/errors/result.dart';
import '../../../../core/utils/validators.dart';
import '../repositories/auth_repository.dart';

/// Used both for the voluntary "change my password" flow (Settings) and
/// the mandatory force-change flow after first login / admin reset --
/// the validation and repository call are identical either way, only the
/// screen and post-success navigation differ.
class ChangePasswordUseCase {
  final AuthRepository _repository;
  const ChangePasswordUseCase(this._repository);

  Future<Result<void>> call({
    required String currentPassword,
    required String newPassword,
    required String confirmPassword,
  }) async {
    final pwError = Validators.password(newPassword);
    if (pwError != null) return Error(ValidationFailure(pwError));

    final confirmError = Validators.confirmPassword(confirmPassword, newPassword);
    if (confirmError != null) return Error(ValidationFailure(confirmError));

    if (newPassword == currentPassword) {
      return const Error(
        ValidationFailure('New password must be different from the current password.'),
      );
    }

    final result = await _repository.changePassword(
      currentPassword: currentPassword,
      newPassword: newPassword,
    );

    if (result.isError) return result;

    // Clear the forced-change flag server-side only after the password
    // update itself has actually succeeded.
    return _repository.clearForcePasswordChangeFlag();
  }
}
