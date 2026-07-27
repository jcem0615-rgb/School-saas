import '../../../../core/errors/failures.dart';
import '../../../../core/errors/result.dart';
import '../../../../core/utils/validators.dart';
import '../entities/guidance_record.dart';
import '../repositories/guidance_repository.dart';

class WatchGuidanceRecordsUseCase {
  final GuidanceRepository _repository;
  const WatchGuidanceRecordsUseCase(this._repository);

  Stream<List<GuidanceRecord>> call(String studentId) => _repository.watchGuidanceRecords(studentId);
}

class CreateGuidanceRecordUseCase {
  final GuidanceRepository _repository;
  const CreateGuidanceRecordUseCase(this._repository);

  Future<Result<void>> call({
    required String studentId,
    required String studentName,
    required GuidanceCategory category,
    required String notes,
  }) {
    if (studentId.trim().isEmpty) {
      return Future.value(const Error(ValidationFailure('A student must be specified.')));
    }
    final notesError = Validators.required(notes, fieldName: 'Notes');
    if (notesError != null) return Future.value(Error(ValidationFailure(notesError)));

    return _repository.createGuidanceRecord(
      studentId: studentId.trim(),
      studentName: studentName.trim(),
      category: category,
      notes: notes.trim(),
    );
  }
}
