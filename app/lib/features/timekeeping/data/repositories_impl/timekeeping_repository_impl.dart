import '../../../../core/errors/failures.dart';
import '../../../../core/errors/result.dart';
import '../../../qr_attendance/domain/entities/attendance_record.dart';
import '../../domain/entities/leave_request.dart';
import '../../domain/repositories/timekeeping_repository.dart';
import '../datasources/timekeeping_remote_datasource.dart';

class TimekeepingRepositoryImpl implements TimekeepingRepository {
  final TimekeepingRemoteDataSource _remote;
  const TimekeepingRepositoryImpl(this._remote);

  @override
  Stream<List<LeaveRequest>> watchMyLeave() => _remote.watchMyLeave();

  @override
  Stream<List<LeaveRequest>> watchAllLeave() => _remote.watchAllLeave();

  @override
  Stream<List<LeaveRequest>> watchLeaveFor(String employeeUid) =>
      _remote.watchLeaveFor(employeeUid);

  @override
  Stream<List<AttendanceRecord>> watchAttendanceFor({
    required String employeeUid,
    required String fromDate,
    required String toDate,
  }) =>
      _remote.watchAttendanceFor(
        employeeUid: employeeUid,
        fromDate: fromDate,
        toDate: toDate,
      );

  @override
  Future<Result<void>> fileLeave({
    required LeaveType type,
    required String fromDate,
    required String toDate,
    required int days,
    required String reason,
  }) =>
      _run(() => _remote.fileLeave(
            type: type,
            fromDate: fromDate,
            toDate: toDate,
            days: days,
            reason: reason,
          ));

  @override
  Future<Result<void>> cancelLeave(String requestId) =>
      _run(() => _remote.cancelLeave(requestId));

  @override
  Future<Result<void>> decideLeave({
    required String requestId,
    required bool approved,
    String? remarks,
  }) =>
      _run(() => _remote.decideLeave(
            requestId: requestId,
            approved: approved,
            remarks: remarks,
          ));

  Future<Result<void>> _run(Future<void> Function() action) async {
    try {
      await action();
      return const Success(null);
    } catch (_) {
      return const Error(UnknownFailure());
    }
  }
}
