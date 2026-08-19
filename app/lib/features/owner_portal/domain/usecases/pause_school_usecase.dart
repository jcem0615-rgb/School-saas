import '../../../../core/errors/failures.dart';
import '../../../../core/errors/result.dart';
import '../repositories/owner_repository.dart';

class PauseSchoolUseCase {
  final OwnerRepository _repository;
  const PauseSchoolUseCase(this._repository);

  Future<Result<void>> call({required String schoolId, required String reason}) {
    if (reason.trim().isEmpty) {
      return Future.value(
        const Error(ValidationFailure('A reason is required when pausing a school.')),
      );
    }
    return _repository.pauseSchool(schoolId: schoolId, reason: reason.trim());
  }
}
