import '../../../../core/errors/app_exceptions.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/errors/result.dart';
import '../../../qr_attendance/domain/entities/attendance_record.dart'
    show AttendanceStatus;
import '../../domain/entities/class_session.dart';
import '../../domain/repositories/class_session_repository.dart';
import '../datasources/class_session_remote_datasource.dart';

class ClassSessionRepositoryImpl implements ClassSessionRepository {
  final ClassSessionRemoteDataSource _remote;

  /// Today, as the school's calendar has it.
  ///
  /// Taken from the device rather than the server, and that is a real
  /// limitation worth naming: a phone whose clock or timezone is wrong
  /// asks for the wrong day's sessions and sees none. It cannot *write*
  /// the wrong day -- the callables derive the date key from the
  /// school's own timezone, server-side -- so the failure is a list that
  /// looks empty, not a register filed under Tuesday.
  final DateTime Function() _now;

  ClassSessionRepositoryImpl(this._remote, {DateTime Function()? now})
      : _now = now ?? DateTime.now;

  String get _todayKey {
    final now = _now();
    final month = now.month.toString().padLeft(2, '0');
    final day = now.day.toString().padLeft(2, '0');
    return '${now.year}-$month-$day';
  }

  @override
  Stream<List<ClassSession>> watchTodaysSessions() =>
      _remote.watchSessionsOn(_todayKey);

  @override
  Stream<ClassSession?> watchSession(String sessionId) =>
      _remote.watchSession(sessionId);

  @override
  Stream<List<SubjectAttendanceMark>> watchRoll(String sessionId) =>
      _remote.watchRoll(sessionId);

  @override
  Stream<List<SubjectAttendanceMark>> watchStudentMarks(String studentId) =>
      _remote.watchStudentMarks(studentId);

  @override
  Future<Result<String>> openSession(String scheduleBlockId) async {
    try {
      return Success(await _remote.openSession(scheduleBlockId));
    } on ServerException catch (e) {
      return Error(ServerFailure(e.message));
    } catch (_) {
      return const Error(UnknownFailure());
    }
  }

  @override
  Future<Result<void>> closeSession(String sessionId) =>
      _run(() => _remote.closeSession(sessionId));

  @override
  Future<Result<void>> mark({
    required String sessionId,
    required String studentId,
    required AttendanceStatus status,
  }) =>
      _run(() => _remote.mark(
            sessionId: sessionId,
            studentId: studentId,
            status: status.value,
          ));

  Future<Result<void>> _run(Future<void> Function() action) async {
    try {
      await action();
      return const Success(null);
    } on ServerException catch (e) {
      // The message is carried through rather than flattened, because
      // these are the ones worth reading: "that class is not timetabled
      // today", "this register is from an earlier day".
      return Error(ServerFailure(e.message));
    } catch (_) {
      return const Error(UnknownFailure());
    }
  }
}
