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
    String? studentId,
    String? studentName,
    required String section,
    required GuidanceCategory category,
    required String notes,
  }) {
    // A note is filed against a section; naming a student within it is
    // optional, which is what allows section-wide notes ("whole class
    // briefed on the new tardiness policy") to be recorded at all.
    final sectionError = Validators.required(section, fieldName: 'Section');
    if (sectionError != null) return Future.value(Error(ValidationFailure(sectionError)));

    final notesError = Validators.required(notes, fieldName: 'Notes');
    if (notesError != null) return Future.value(Error(ValidationFailure(notesError)));

    // Blank is normalised to null rather than stored as '': an empty
    // string would read as a note pointing at a student that does not
    // exist, and firestore.rules keys its scoping on studentId being
    // absent, not empty.
    final trimmedId = studentId?.trim();
    final trimmedName = studentName?.trim();

    return _repository.createGuidanceRecord(
      studentId: (trimmedId == null || trimmedId.isEmpty) ? null : trimmedId,
      studentName: (trimmedName == null || trimmedName.isEmpty) ? null : trimmedName,
      section: section.trim(),
      category: category,
      notes: notes.trim(),
    );
  }
}

class UpdateGuidanceRecordUseCase {
  final GuidanceRepository _repository;
  const UpdateGuidanceRecordUseCase(this._repository);

  Future<Result<void>> call({
    required String recordId,
    required GuidanceCategory category,
    required String notes,
  }) {
    if (recordId.trim().isEmpty) {
      return Future.value(const Error(ValidationFailure('Missing record.')));
    }
    final notesError = Validators.required(notes, fieldName: 'Notes');
    if (notesError != null) return Future.value(Error(ValidationFailure(notesError)));

    return _repository.updateGuidanceRecord(
      recordId: recordId,
      category: category,
      notes: notes.trim(),
    );
  }
}

class DeleteGuidanceRecordUseCase {
  final GuidanceRepository _repository;
  const DeleteGuidanceRecordUseCase(this._repository);

  Future<Result<void>> call(String recordId) {
    if (recordId.trim().isEmpty) {
      return Future.value(const Error(ValidationFailure('Missing record.')));
    }
    return _repository.deleteGuidanceRecord(recordId);
  }
}
