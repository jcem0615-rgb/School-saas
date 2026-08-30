import '../../../../core/errors/result.dart';
import '../../../qr_attendance/domain/entities/attendance_record.dart';
import '../entities/leave_request.dart';

abstract class TimekeepingRepository {
  /// The signed-in employee's own requests, newest first.
  Stream<List<LeaveRequest>> watchMyLeave();

  /// Everything the office has to decide or has decided. Admin-tier only
  /// -- the rules refuse this read to anybody else, so the screens that
  /// use it are behind the same roles.
  Stream<List<LeaveRequest>> watchAllLeave();

  /// One employee's requests, for their timesheet.
  Stream<List<LeaveRequest>> watchLeaveFor(String employeeUid);

  /// One employee's scans across a period, inclusive.
  Stream<List<AttendanceRecord>> watchAttendanceFor({
    required String employeeUid,
    required String fromDate,
    required String toDate,
  });

  Future<Result<void>> fileLeave({
    required LeaveType type,
    required String fromDate,
    required String toDate,
    required int days,
    required String reason,
  });

  /// Withdrawing a request that has not been decided yet.
  Future<Result<void>> cancelLeave(String requestId);

  /// Approving or declining. The rules pin the decider to the caller, so
  /// the name beside a decision is the account that made it.
  Future<Result<void>> decideLeave({
    required String requestId,
    required bool approved,
    String? remarks,
  });
}
