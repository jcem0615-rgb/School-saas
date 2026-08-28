import '../../../../core/errors/app_exceptions.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/errors/result.dart';
import '../../domain/entities/schedule_block.dart';
import '../../domain/repositories/schedule_repository.dart';
import '../datasources/schedule_remote_datasource.dart';

class ScheduleRepositoryImpl implements ScheduleRepository {
  final ScheduleRemoteDataSource _remote;
  const ScheduleRepositoryImpl(this._remote);

  @override
  Stream<List<ScheduleBlock>> watchSchedule(String schoolYear) =>
      _remote.watchSchedule(schoolYear);

  @override
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
  }) async {
    try {
      return Success(await _remote.saveScheduleBlock(
        blockId: blockId,
        subject: subject,
        section: section,
        teacherId: teacherId,
        teacherName: teacherName,
        room: room,
        dayOfWeek: dayOfWeek,
        startMinute: startMinute,
        endMinute: endMinute,
        schoolYear: schoolYear,
        term: term,
      ));
    } on ServerException catch (e) {
      return Error(ServerFailure(e.message));
    } catch (_) {
      return const Error(UnknownFailure('The class could not be saved.'));
    }
  }

  @override
  Future<Result<void>> deleteScheduleBlock(String blockId) async {
    try {
      await _remote.deleteScheduleBlock(blockId);
      return const Success(null);
    } on ServerException catch (e) {
      return Error(ServerFailure(e.message));
    } catch (_) {
      return const Error(UnknownFailure('The class could not be removed.'));
    }
  }
}
