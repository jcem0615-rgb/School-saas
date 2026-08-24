import '../../../../core/errors/result.dart';
import '../entities/guidance_record.dart';
import '../entities/summons.dart';

abstract class GuidanceRepository {
  Stream<List<GuidanceRecord>> watchGuidanceRecords(String studentId);
  /// Section-level guidance notes -- those not tied to one student.
  Stream<List<GuidanceRecord>> watchSectionRecords(String section);

  Future<Result<void>> createGuidanceRecord({
    String? studentId,
    String? studentName,
    required String section,
    required GuidanceCategory category,
    required String notes,
  });

  Future<Result<void>> updateGuidanceRecord({
    required String recordId,
    required GuidanceCategory category,
    required String notes,
  });

  /// Soft delete throughout -- firestore.rules denies hard delete.
  Future<Result<void>> deleteGuidanceRecord(String recordId);

  Stream<List<Summons>> watchSummons();
  Future<Result<void>> createSummons({
    required String studentId,
    required String studentName,
    required String reason,
    required DateTime scheduledDate,
  });
  Future<Result<void>> updateSummonsStatus({required String summonsId, required SummonsStatus status});
  Future<Result<void>> updateSummons({
    required String summonsId,
    required String reason,
    required DateTime scheduledDate,
  });
  Future<Result<void>> deleteSummons(String summonsId);
}
