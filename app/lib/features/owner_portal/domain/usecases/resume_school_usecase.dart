import '../../../../core/errors/result.dart';
import '../repositories/owner_repository.dart';

class ResumeSchoolUseCase {
  final OwnerRepository _repository;
  const ResumeSchoolUseCase(this._repository);

  Future<Result<void>> call({required String schoolId}) =>
      _repository.resumeSchool(schoolId: schoolId);
}
