import '../../../../core/errors/result.dart';
import '../entities/announcement.dart';
import '../entities/approval_request.dart';
import '../entities/director_dashboard_summary.dart';
import '../entities/expense.dart';
import '../entities/meeting.dart';

abstract class DirectorRepository {
  Future<Result<DirectorDashboardSummary>> getDashboardSummary();

  Stream<List<Announcement>> watchAnnouncements();
  Future<Result<void>> createAnnouncement({
    required String title,
    required String body,
    required AnnouncementAudience audience,
    required bool pinned,
  });
  Future<Result<void>> updateAnnouncement({
    required String announcementId,
    required String title,
    required String body,
    required AnnouncementAudience audience,
    required bool pinned,
  });

  /// Flips `isDeleted` rather than removing the document. Every collection
  /// in firestore.rules sets `allow delete: if false`, so this is the only
  /// delete path there is -- the record stays recoverable and its audit
  /// history stays intact. Applies to every `delete*` method below.
  Future<Result<void>> deleteAnnouncement(String announcementId);

  Stream<List<Meeting>> watchMeetings();
  Future<Result<void>> createMeeting({
    required String title,
    String? description,
    required DateTime startTime,
    required DateTime endTime,
    String? location,
    required List<String> attendeeRoles,
  });
  Future<Result<void>> updateMeeting({
    required String meetingId,
    required String title,
    String? description,
    required DateTime startTime,
    required DateTime endTime,
    String? location,
    required List<String> attendeeRoles,
  });

  /// Cancelling keeps the meeting listed with a cancelled badge so
  /// attendees can see it was called off; deleting removes it from the
  /// list. Both are soft operations -- neither destroys the document.
  Future<Result<void>> cancelMeeting(String meetingId);
  Future<Result<void>> deleteMeeting(String meetingId);

  /// [requestedByUid] lets a caller see only their own filed requests
  /// (e.g. Faculty's "My Material Requests") -- omit it for the
  /// Director/Admin decision inbox, which shows everyone's.
  Stream<List<ApprovalRequest>> watchApprovals({ApprovalStatus? statusFilter, String? requestedByUid});

  /// Files a new request into the generic approvals inbox. Any active
  /// tenant member may call this (see firestore.rules -- the
  /// `requestedByRole == claims().role` check prevents impersonating a
  /// different role); only Director/Admin can later decide it. Faculty's
  /// "Material Requests" feature (Faculty Portal module) is this same
  /// mechanism with `type: 'material_request'`.
  Future<Result<void>> createApprovalRequest({
    required String type,
    required String title,
    String? description,
    Map<String, dynamic> details = const {},
  });

  Future<Result<void>> decideApproval({
    required String approvalId,
    required bool approve,
    String? remarks,
  });

  Stream<List<Expense>> watchExpenses();
  Future<Result<void>> createExpense({
    required String category,
    required String description,
    required double amount,
    required DateTime date,
    String? receiptUrl,
  });
  Future<Result<void>> updateExpense({
    required String expenseId,
    required String category,
    required String description,
    required double amount,
    required DateTime date,
    String? receiptUrl,
  });
  Future<Result<void>> deleteExpense(String expenseId);
}
