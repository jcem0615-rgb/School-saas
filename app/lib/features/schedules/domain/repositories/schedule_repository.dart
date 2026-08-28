import '../../../../core/errors/result.dart';
import '../entities/schedule_block.dart';

abstract class ScheduleRepository {
  /// Every block for the school year, newest first by day and time.
  ///
  /// The whole timetable, not a filtered slice. A school's week is a few
  /// hundred blocks at most, every view of it is a different cut of the
  /// same data (by section, by teacher, by room), and conflict detection
  /// needs to see all of it anyway -- so it is fetched once and filtered
  /// in the client rather than re-queried per view.
  Stream<List<ScheduleBlock>> watchSchedule(String schoolYear);

  Future<Result<String>> saveScheduleBlock({
    String? blockId,
    required String subject,
    required String section,
    required String teacherId,
    required String teacherName,
    String? room,
    required int dayOfWeek,
    required int startMinute,
    required int endMinute,
    required String schoolYear,
    String? term,
  });

  Future<Result<void>> deleteScheduleBlock(String blockId);
}
