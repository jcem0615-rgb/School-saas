import '../../../../core/errors/failures.dart';
import '../../../../core/errors/result.dart';
import '../../../../core/utils/validators.dart';
import '../entities/summons.dart';
import '../repositories/guidance_repository.dart';

class WatchSummonsUseCase {
  final GuidanceRepository _repository;
  const WatchSummonsUseCase(this._repository);

  Stream<List<Summons>> call() => _repository.watchSummons();
}

class CreateSummonsUseCase {
  final GuidanceRepository _repository;
  const CreateSummonsUseCase(this._repository);

  Future<Result<void>> call({
    required String studentId,
    required String studentName,
    required String reason,
    required DateTime scheduledDate,
  }) {
    if (studentId.trim().isEmpty) {
      return Future.value(const Error(ValidationFailure('A student must be specified.')));
    }
    final reasonError = Validators.required(reason, fieldName: 'Reason');
    if (reasonError != null) return Future.value(Error(ValidationFailure(reasonError)));

    return _repository.createSummons(
      studentId: studentId.trim(),
      studentName: studentName.trim(),
      reason: reason.trim(),
      scheduledDate: scheduledDate,
    );
  }
}

class UpdateSummonsStatusUseCase {
  final GuidanceRepository _repository;
  const UpdateSummonsStatusUseCase(this._repository);

  Future<Result<void>> call({required String summonsId, required SummonsStatus status}) =>
      _repository.updateSummonsStatus(summonsId: summonsId, status: status);
}

class UpdateSummonsUseCase {
  final GuidanceRepository _repository;
  const UpdateSummonsUseCase(this._repository);

  Future<Result<void>> call({
    required String summonsId,
    required String reason,
    required DateTime scheduledDate,
  }) {
    if (summonsId.trim().isEmpty) {
      return Future.value(const Error(ValidationFailure('Missing summons.')));
    }
    final reasonError = Validators.required(reason, fieldName: 'Reason');
    if (reasonError != null) return Future.value(Error(ValidationFailure(reasonError)));

    return _repository.updateSummons(
      summonsId: summonsId,
      reason: reason.trim(),
      scheduledDate: scheduledDate,
    );
  }
}

class DeleteSummonsUseCase {
  final GuidanceRepository _repository;
  const DeleteSummonsUseCase(this._repository);

  Future<Result<void>> call(String summonsId) {
    if (summonsId.trim().isEmpty) {
      return Future.value(const Error(ValidationFailure('Missing summons.')));
    }
    return _repository.deleteSummons(summonsId);
  }
}
