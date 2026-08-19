import '../../../../core/errors/failures.dart';
import '../../../../core/errors/result.dart';
import '../../domain/entities/announcement.dart';
import '../../domain/entities/approval_request.dart';
import '../../domain/entities/director_dashboard_summary.dart';
import '../../domain/entities/expense.dart';
import '../../domain/entities/meeting.dart';
import '../../domain/repositories/director_repository.dart';
import '../datasources/director_remote_datasource.dart';

class DirectorRepositoryImpl implements DirectorRepository {
  final DirectorRemoteDataSource _remote;
  const DirectorRepositoryImpl(this._remote);

  Future<Result<T>> _guard<T>(Future<T> Function() action) async {
    try {
      return Success(await action());
    } catch (_) {
      return const Error(UnknownFailure());
    }
  }

  @override
  Future<Result<DirectorDashboardSummary>> getDashboardSummary() {
    return _guard(() async {
      final agg = await _remote.fetchDashboardAggregates();
      return DirectorDashboardSummary(
        todayAttendancePresentCount: (agg['todayAttendancePresentCount'] ?? 0).toInt(),
        todayAttendanceTotalCount: (agg['todayAttendanceTotalCount'] ?? 0).toInt(),
        todayPaymentsTotal: (agg['todayPaymentsTotal'] ?? 0).toDouble(),
        pendingApprovalsCount: (agg['pendingApprovalsCount'] ?? 0).toInt(),
        upcomingMeetingsCount: (agg['upcomingMeetingsCount'] ?? 0).toInt(),
      );
    });
  }

  @override
  Stream<List<Announcement>> watchAnnouncements() => _remote.watchAnnouncements();

  @override
  Future<Result<void>> createAnnouncement({
    required String title,
    required String body,
    required AnnouncementAudience audience,
    required bool pinned,
  }) {
    return _guard(() => _remote.createAnnouncement(
          title: title,
          body: body,
          audienceAll: audience.all,
          audienceRoles: audience.roles,
          pinned: pinned,
        ));
  }

  @override
  Stream<List<Meeting>> watchMeetings() => _remote.watchMeetings();

  @override
  Future<Result<void>> createMeeting({
    required String title,
    String? description,
    required DateTime startTime,
    required DateTime endTime,
    String? location,
    required List<String> attendeeRoles,
  }) {
    return _guard(() => _remote.createMeeting(
          title: title,
          description: description,
          startTime: startTime,
          endTime: endTime,
          location: location,
          attendeeRoles: attendeeRoles,
        ));
  }

  @override
  Future<Result<void>> cancelMeeting(String meetingId) {
    return _guard(() => _remote.cancelMeeting(meetingId));
  }

  @override
  Stream<List<ApprovalRequest>> watchApprovals({ApprovalStatus? statusFilter, String? requestedByUid}) {
    return _remote.watchApprovals(statusFilter: statusFilter?.value, requestedByUid: requestedByUid);
  }

  @override
  Future<Result<void>> createApprovalRequest({
    required String type,
    required String title,
    String? description,
    Map<String, dynamic> details = const {},
  }) {
    return _guard(() => _remote.createApprovalRequest(
          type: type,
          title: title,
          description: description,
          details: details,
        ));
  }

  @override
  Future<Result<void>> decideApproval({
    required String approvalId,
    required bool approve,
    String? remarks,
  }) {
    return _guard(() => _remote.decideApproval(approvalId: approvalId, approve: approve, remarks: remarks));
  }

  @override
  Stream<List<Expense>> watchExpenses() => _remote.watchExpenses();

  @override
  Future<Result<void>> createExpense({
    required String category,
    required String description,
    required double amount,
    required DateTime date,
    String? receiptUrl,
  }) {
    return _guard(() => _remote.createExpense(
          category: category,
          description: description,
          amount: amount,
          date: date,
          receiptUrl: receiptUrl,
        ));
  }
}
