import '../../../../core/errors/failures.dart';
import '../../../../core/errors/result.dart';
import '../../domain/entities/guidance_record.dart';
import '../../domain/entities/summons.dart';
import '../../domain/repositories/guidance_repository.dart';
import '../datasources/guidance_remote_datasource.dart';

class GuidanceRepositoryImpl implements GuidanceRepository {
  final GuidanceRemoteDataSource _remote;
  const GuidanceRepositoryImpl(this._remote);

  Future<Result<void>> _guard(Future<void> Function() action) async {
    try {
      await action();
      return const Success(null);
    } catch (_) {
      return const Error(UnknownFailure());
    }
  }

  @override
  Stream<List<GuidanceRecord>> watchGuidanceRecords(String studentId) =>
      _remote.watchGuidanceRecords(studentId);

  @override
  Future<Result<void>> createGuidanceRecord({
    required String studentId,
    required String studentName,
    required GuidanceCategory category,
    required String notes,
  }) {
    return _guard(() => _remote.createGuidanceRecord(
          studentId: studentId,
          studentName: studentName,
          category: category.value,
          notes: notes,
        ));
  }

  @override
  Stream<List<Summons>> watchSummons() => _remote.watchSummons();

  @override
  Future<Result<void>> createSummons({
    required String studentId,
    required String studentName,
    required String reason,
    required DateTime scheduledDate,
  }) {
    return _guard(() => _remote.createSummons(
          studentId: studentId,
          studentName: studentName,
          reason: reason,
          scheduledDate: scheduledDate,
        ));
  }

  @override
  Future<Result<void>> updateSummonsStatus({required String summonsId, required SummonsStatus status}) {
    return _guard(() => _remote.updateSummonsStatus(summonsId: summonsId, status: status.value));
  }
}
