import '../../../../core/errors/failures.dart';
import '../../../../core/errors/result.dart';
import '../../../../core/utils/validators.dart';
import '../repositories/auth_repository.dart';

class ForgotPasswordUseCase {
  final AuthRepository _repository;
  const ForgotPasswordUseCase(this._repository);

  Future<Result<void>> call(String email) async {
    final emailError = Validators.email(email);
    if (emailError != null) return Error(ValidationFailure(emailError));
    return _repository.sendPasswordResetEmail(email.trim());
  }
}
