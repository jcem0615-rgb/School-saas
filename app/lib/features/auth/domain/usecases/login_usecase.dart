import '../../../../core/errors/failures.dart';
import '../../../../core/errors/result.dart';
import '../../../../core/utils/validators.dart';
import '../entities/app_user.dart';
import '../repositories/auth_repository.dart';

/// Encapsulates the login flow, including client-side validation that
/// should never even reach the network. Kept as a single-purpose class
/// (rather than a method on a giant AuthService) so it can be unit tested
/// in isolation and composed/mocked independently in the controller test.
class LoginUseCase {
  final AuthRepository _repository;
  const LoginUseCase(this._repository);

  Future<Result<AppUser>> call({
    required String email,
    required String password,
  }) async {
    final emailError = Validators.email(email);
    if (emailError != null) return Error(ValidationFailure(emailError));

    if (password.isEmpty) {
      return const Error(ValidationFailure('Password is required.'));
    }

    return _repository.login(email: email.trim(), password: password);
  }
}
