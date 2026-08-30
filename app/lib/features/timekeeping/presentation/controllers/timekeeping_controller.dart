import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/result.dart';
import '../../../auth/presentation/controllers/auth_controller.dart'
    show authStateProvider, firestoreProvider;
import '../../../qr_attendance/domain/entities/attendance_record.dart';
import '../../data/datasources/timekeeping_remote_datasource.dart';
import '../../data/repositories_impl/timekeeping_repository_impl.dart';
import '../../domain/entities/leave_request.dart';
import '../../domain/entities/timesheet.dart';
import '../../domain/repositories/timekeeping_repository.dart';

final timekeepingRepositoryProvider = Provider<TimekeepingRepository>((ref) {
  final user = ref.watch(authStateProvider).valueOrNull;
  if (user == null || user.schoolId == null) {
    throw StateError('Timekeeping requires a signed-in, school-scoped user.');
  }
  return TimekeepingRepositoryImpl(
    TimekeepingRemoteDataSource(
      firestore: ref.watch(firestoreProvider),
      actingUser: ActingEmployee(
        uid: user.uid,
        schoolId: user.schoolId!,
        name: user.fullName,
        role: user.role.value,
      ),
    ),
  );
});

/// The signed-in employee's own requests.
final myLeaveProvider = StreamProvider.autoDispose<List<LeaveRequest>>((ref) {
  return ref.watch(timekeepingRepositoryProvider).watchMyLeave();
});

/// Everyone's, for the office.
final allLeaveProvider = StreamProvider.autoDispose<List<LeaveRequest>>((ref) {
  return ref.watch(timekeepingRepositoryProvider).watchAllLeave();
});

/// What is still waiting on somebody. Derived rather than queried, so
/// the queue and the history come from one subscription.
final pendingLeaveProvider = Provider.autoDispose<List<LeaveRequest>>((ref) {
  final all = ref.watch(allLeaveProvider).valueOrNull ?? const [];
  return all.where((r) => r.isPending).toList();
});

/// Which employee and which month a timesheet is being read for.
class TimesheetQuery {
  final String employeeUid;
  final String employeeName;

  /// Any date inside the month being read.
  final DateTime month;

  const TimesheetQuery({
    required this.employeeUid,
    required this.employeeName,
    required this.month,
  });

  DateTime get from => DateTime(month.year, month.month, 1);

  /// Day zero of the next month is the last day of this one, which is
  /// how February and the thirty-one-day months are handled without a
  /// table of month lengths or a leap-year rule.
  DateTime get to => DateTime(month.year, month.month + 1, 0);

  @override
  bool operator ==(Object other) =>
      other is TimesheetQuery &&
      other.employeeUid == employeeUid &&
      other.month.year == month.year &&
      other.month.month == month.month;

  @override
  int get hashCode => Object.hash(employeeUid, month.year, month.month);
}

final _timesheetAttendanceProvider = StreamProvider.autoDispose
    .family<List<AttendanceRecord>, TimesheetQuery>((ref, query) {
  return ref.watch(timekeepingRepositoryProvider).watchAttendanceFor(
        employeeUid: query.employeeUid,
        fromDate: dateKeyOf(query.from),
        toDate: dateKeyOf(query.to),
      );
});

final _timesheetLeaveProvider = StreamProvider.autoDispose
    .family<List<LeaveRequest>, TimesheetQuery>((ref, query) {
  return ref
      .watch(timekeepingRepositoryProvider)
      .watchLeaveFor(query.employeeUid);
});

/// The month, assembled.
///
/// Null while either half is still loading, so the screen shows a
/// spinner rather than a sheet that says everybody was absent all month
/// because the scans have not arrived yet. That is not a cosmetic
/// distinction: an incomplete timesheet looks exactly like a damning one.
final timesheetProvider =
    Provider.autoDispose.family<Timesheet?, TimesheetQuery>((ref, query) {
  final records = ref.watch(_timesheetAttendanceProvider(query)).valueOrNull;
  final leaves = ref.watch(_timesheetLeaveProvider(query)).valueOrNull;
  if (records == null || leaves == null) return null;

  return buildTimesheet(
    employeeUid: query.employeeUid,
    employeeName: query.employeeName,
    from: query.from,
    to: query.to,
    records: records,
    leaves: leaves,
  );
});

/// Filing, cancelling and deciding.
class TimekeepingActionController extends StateNotifier<AsyncValue<void>> {
  /// A getter rather than an instance: the repository rebuilds whenever
  /// `authStateProvider` emits, and a controller holding the instance
  /// would be torn down mid-write.
  final TimekeepingRepository Function() _repository;

  TimekeepingActionController(this._repository)
      : super(const AsyncValue.data(null));

  Future<bool> fileLeave({
    required LeaveType type,
    required DateTime from,
    required DateTime to,
    required String reason,
  }) =>
      _run(() => _repository().fileLeave(
            type: type,
            fromDate: dateKeyOf(from),
            toDate: dateKeyOf(to),
            // Counted once, here, and stored -- so a request keeps the
            // number it was approved on even if the school later
            // redefines its working week.
            days: workingDaysBetween(from, to),
            reason: reason.trim(),
          ));

  Future<bool> cancelLeave(String requestId) =>
      _run(() => _repository().cancelLeave(requestId));

  Future<bool> decideLeave({
    required String requestId,
    required bool approved,
    String? remarks,
  }) =>
      _run(() => _repository().decideLeave(
            requestId: requestId,
            approved: approved,
            remarks: remarks,
          ));

  Future<bool> _run(Future<Result<void>> Function() action) async {
    _set(const AsyncValue.loading());
    final result = await action();
    switch (result) {
      case Success():
        _set(const AsyncValue.data(null));
        return true;
      case Error(:final failure):
        _set(AsyncValue.error(failure.message, StackTrace.current));
        return false;
    }
  }

  void _set(AsyncValue<void> next) {
    if (mounted) state = next;
  }
}

final timekeepingActionControllerProvider =
    StateNotifierProvider<TimekeepingActionController, AsyncValue<void>>((ref) {
  return TimekeepingActionController(() => ref.read(timekeepingRepositoryProvider));
});
