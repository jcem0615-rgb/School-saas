import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/result.dart';

import '../../../auth/presentation/controllers/auth_controller.dart'
    show authStateProvider, firestoreProvider;
import '../../data/datasources/director_remote_datasource.dart';
import '../../data/repositories_impl/director_repository_impl.dart';
import '../../domain/entities/announcement.dart';
import '../../domain/entities/approval_request.dart';
import '../../domain/entities/director_dashboard_summary.dart';
import '../../domain/entities/expense.dart';
import '../../domain/entities/meeting.dart';
import '../../domain/repositories/director_repository.dart';
import '../../domain/usecases/announcement_usecases.dart';
import '../../domain/usecases/approval_usecases.dart';
import '../../domain/usecases/expense_usecases.dart';
import '../../domain/usecases/meeting_usecases.dart';
import '../../domain/usecases/watch_dashboard_summary_usecase.dart';

/// Rebuilt whenever the signed-in user changes, since every write this
/// data source performs stamps the *current* user's uid/name/role onto
/// the document. Throws if watched before a Director-role user is signed
/// in -- callers only ever reach Director Portal screens after the router
/// guard has already confirmed that, so this should never fire in practice.
final directorRemoteDataSourceProvider = Provider<DirectorRemoteDataSource>((ref) {
  final user = ref.watch(authStateProvider).valueOrNull;
  if (user == null || user.schoolId == null) {
    throw StateError('DirectorRemoteDataSource requires a signed-in, school-scoped user.');
  }
  return DirectorRemoteDataSource(
    firestore: ref.watch(firestoreProvider),
    actingUser: ActingUser(
      uid: user.uid,
      schoolId: user.schoolId!,
      name: user.fullName,
      role: user.role.value,
    ),
  );
});

final directorRepositoryProvider = Provider<DirectorRepository>((ref) {
  return DirectorRepositoryImpl(ref.watch(directorRemoteDataSourceProvider));
});

final dashboardSummaryProvider = FutureProvider.autoDispose<DirectorDashboardSummary>((ref) async {
  final result = await GetDashboardSummaryUseCase(ref.watch(directorRepositoryProvider))();
  return switch (result) {
    Success(:final value) => value,
    Error(:final failure) => throw failure,
  };
});

final announcementsStreamProvider = StreamProvider.autoDispose<List<Announcement>>((ref) {
  return WatchAnnouncementsUseCase(ref.watch(directorRepositoryProvider))();
});

final meetingsStreamProvider = StreamProvider.autoDispose<List<Meeting>>((ref) {
  return WatchMeetingsUseCase(ref.watch(directorRepositoryProvider))();
});

final approvalsStreamProvider =
    StreamProvider.autoDispose.family<List<ApprovalRequest>, ApprovalStatus?>((ref, statusFilter) {
  return WatchApprovalsUseCase(ref.watch(directorRepositoryProvider))(statusFilter: statusFilter);
});

/// A user's own filed requests, regardless of status -- backs Faculty's
/// "My Material Requests" screen (and any future module reusing this same
/// generic approvals inbox for self-filed requests).
final myApprovalsStreamProvider = StreamProvider.autoDispose<List<ApprovalRequest>>((ref) {
  final uid = ref.watch(authStateProvider).valueOrNull?.uid;
  if (uid == null) return const Stream.empty();
  return WatchApprovalsUseCase(ref.watch(directorRepositoryProvider))(requestedByUid: uid);
});

final expensesStreamProvider = StreamProvider.autoDispose<List<Expense>>((ref) {
  return WatchExpensesUseCase(ref.watch(directorRepositoryProvider))();
});

/// Drives every write action across the Director Portal's four CRUD
/// screens. Kept as one controller (rather than one per screen) since none
/// of these actions run concurrently from the user's perspective -- only
/// one dialog/form is open at a time -- and it keeps the DI wiring small.
class DirectorActionController extends StateNotifier<AsyncValue<void>> {
  // `mounted` guards below: these action controllers are autoDispose, and
  // the repositories they depend on rebuild whenever authStateProvider
  // emits. If that lands while a write is in flight the notifier is gone
  // by the time the result returns, and assigning `state` then throws
  // "used after dispose" -- which surfaces as an action that silently does
  // nothing even though the write succeeded.
  final CreateAnnouncementUseCase _createAnnouncement;
  final UpdateAnnouncementUseCase _updateAnnouncement;
  final DeleteAnnouncementUseCase _deleteAnnouncement;
  final CreateMeetingUseCase _createMeeting;
  final UpdateMeetingUseCase _updateMeeting;
  final CancelMeetingUseCase _cancelMeeting;
  final DeleteMeetingUseCase _deleteMeeting;
  final CreateApprovalRequestUseCase _createApprovalRequest;
  final DecideApprovalUseCase _decideApproval;
  final CreateExpenseUseCase _createExpense;
  final UpdateExpenseUseCase _updateExpense;
  final DeleteExpenseUseCase _deleteExpense;

  DirectorActionController({
    required CreateAnnouncementUseCase createAnnouncement,
    required UpdateAnnouncementUseCase updateAnnouncement,
    required DeleteAnnouncementUseCase deleteAnnouncement,
    required CreateMeetingUseCase createMeeting,
    required UpdateMeetingUseCase updateMeeting,
    required CancelMeetingUseCase cancelMeeting,
    required DeleteMeetingUseCase deleteMeeting,
    required CreateApprovalRequestUseCase createApprovalRequest,
    required DecideApprovalUseCase decideApproval,
    required CreateExpenseUseCase createExpense,
    required UpdateExpenseUseCase updateExpense,
    required DeleteExpenseUseCase deleteExpense,
  })  : _createAnnouncement = createAnnouncement,
        _updateAnnouncement = updateAnnouncement,
        _deleteAnnouncement = deleteAnnouncement,
        _createMeeting = createMeeting,
        _updateMeeting = updateMeeting,
        _cancelMeeting = cancelMeeting,
        _deleteMeeting = deleteMeeting,
        _createApprovalRequest = createApprovalRequest,
        _decideApproval = decideApproval,
        _createExpense = createExpense,
        _updateExpense = updateExpense,
        _deleteExpense = deleteExpense,
        super(const AsyncData(null));

  Future<bool> createAnnouncement({
    required String title,
    required String body,
    required AnnouncementAudience audience,
    bool pinned = false,
  }) => _run(() => _createAnnouncement(title: title, body: body, audience: audience, pinned: pinned));

  Future<bool> updateAnnouncement({
    required String announcementId,
    required String title,
    required String body,
    required AnnouncementAudience audience,
    bool pinned = false,
  }) => _run(() => _updateAnnouncement(
        announcementId: announcementId,
        title: title,
        body: body,
        audience: audience,
        pinned: pinned,
      ));

  Future<bool> deleteAnnouncement(String announcementId) =>
      _run(() => _deleteAnnouncement(announcementId));

  Future<bool> createMeeting({
    required String title,
    String? description,
    required DateTime startTime,
    required DateTime endTime,
    String? location,
    required List<String> attendeeRoles,
  }) => _run(() => _createMeeting(
        title: title,
        description: description,
        startTime: startTime,
        endTime: endTime,
        location: location,
        attendeeRoles: attendeeRoles,
      ));

  Future<bool> updateMeeting({
    required String meetingId,
    required String title,
    String? description,
    required DateTime startTime,
    required DateTime endTime,
    String? location,
    required List<String> attendeeRoles,
  }) => _run(() => _updateMeeting(
        meetingId: meetingId,
        title: title,
        description: description,
        startTime: startTime,
        endTime: endTime,
        location: location,
        attendeeRoles: attendeeRoles,
      ));

  Future<bool> cancelMeeting(String meetingId) => _run(() => _cancelMeeting(meetingId));

  Future<bool> deleteMeeting(String meetingId) => _run(() => _deleteMeeting(meetingId));

  Future<bool> createApprovalRequest({
    required String type,
    required String title,
    String? description,
    Map<String, dynamic> details = const {},
  }) => _run(() => _createApprovalRequest(type: type, title: title, description: description, details: details));

  Future<bool> decideApproval({required String approvalId, required bool approve, String? remarks}) =>
      _run(() => _decideApproval(approvalId: approvalId, approve: approve, remarks: remarks));

  Future<bool> createExpense({
    required String category,
    required String description,
    required double amount,
    required DateTime date,
    String? receiptUrl,
  }) => _run(() => _createExpense(
        category: category,
        description: description,
        amount: amount,
        date: date,
        receiptUrl: receiptUrl,
      ));

  Future<bool> updateExpense({
    required String expenseId,
    required String category,
    required String description,
    required double amount,
    required DateTime date,
    String? receiptUrl,
  }) => _run(() => _updateExpense(
        expenseId: expenseId,
        category: category,
        description: description,
        amount: amount,
        date: date,
        receiptUrl: receiptUrl,
      ));

  Future<bool> deleteExpense(String expenseId) => _run(() => _deleteExpense(expenseId));

  Future<bool> _run(Future<dynamic> Function() action) async {
    if (mounted) state = const AsyncLoading();
    final result = await action();
    return switch (result) {
      Success() => _succeed(),
      Error(:final failure) => _fail(failure.message),
      _ => _succeed(),
    };
  }

  bool _succeed() {
    if (mounted) state = const AsyncData(null);
    return true;
  }

  bool _fail(String message) {
    if (mounted) state = AsyncError(message, StackTrace.current);
    return false;
  }
}

final directorActionControllerProvider =
    StateNotifierProvider.autoDispose<DirectorActionController, AsyncValue<void>>((ref) {
  final repo = ref.watch(directorRepositoryProvider);
  return DirectorActionController(
    createAnnouncement: CreateAnnouncementUseCase(repo),
    updateAnnouncement: UpdateAnnouncementUseCase(repo),
    deleteAnnouncement: DeleteAnnouncementUseCase(repo),
    createMeeting: CreateMeetingUseCase(repo),
    updateMeeting: UpdateMeetingUseCase(repo),
    cancelMeeting: CancelMeetingUseCase(repo),
    deleteMeeting: DeleteMeetingUseCase(repo),
    createApprovalRequest: CreateApprovalRequestUseCase(repo),
    decideApproval: DecideApprovalUseCase(repo),
    createExpense: CreateExpenseUseCase(repo),
    updateExpense: UpdateExpenseUseCase(repo),
    deleteExpense: DeleteExpenseUseCase(repo),
  );
});
