import '../../../../core/errors/result.dart';
import '../entities/guidance_record.dart';
import '../entities/summons.dart';

abstract class GuidanceRepository {
  Stream<List<GuidanceRecord>> watchGuidanceRecords(String studentId);
  Future<Result<void>> createGuidanceRecord({
    required String studentId,
    required String studentName,
    required GuidanceCategory category,
    required String notes,
  });

  Stream<List<Summons>> watchSummons();
  Future<Result<void>> createSummons({
    required String studentId,
    required String studentName,
    required String reason,
    required DateTime scheduledDate,
  });
  Future<Result<void>> updateSummonsStatus({required String summonsId, required SummonsStatus status});
}
