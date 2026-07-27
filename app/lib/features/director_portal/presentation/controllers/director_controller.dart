import 'package:flutter_riverpod/flutter_riverpod.dart';

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
  final CreateAnnouncementUseCase _createAnnouncement;
  final CreateMeetingUseCase _createMeeting;
  final CancelMeetingUseCase _cancelMeeting;
  final CreateApprovalRequestUseCase _createApprovalRequest;
  final DecideApprovalUseCase _decideApproval;
  final CreateExpenseUseCase _createExpense;

  DirectorActionController({
    required CreateAnnouncementUseCase createAnnouncement,
    required CreateMeetingUseCase createMeeting,
    required CancelMeetingUseCase cancelMeeting,
    required CreateApprovalRequestUseCase createApprovalRequest,
    required DecideApprovalUseCase decideApproval,
    required CreateExpenseUseCase createExpense,
  })  : _createAnnouncement = createAnnouncement,
        _createMeeting = createMeeting,
        _cancelMeeting = cancelMeeting,
        _createApprovalRequest = createApprovalRequest,
        _decideApproval = decideApproval,
        _createExpense = createExpense,
        super(const AsyncData(null));

  Future<bool> createAnnouncement({
    required String title,
    required String body,
    required AnnouncementAudience audience,
    bool pinned = false,
  }) => _run(() => _createAnnouncement(title: title, body: body, audience: audience, pinned: pinned));

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

  Future<bool> cancelMeeting(String meetingId) => _run(() => _cancelMeeting(meetingId));

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

  Future<bool> _run(Future<dynamic> Function() action) async {
    state = const AsyncLoading();
    final result = await action();
    return switch (result) {
      Success() => _succeed(),
      Error(:final failure) => _fail(failure.message),
      _ => _succeed(),
    };
  }

  bool _succeed() {
    state = const AsyncData(null);
    return true;
  }

  bool _fail(String message) {
    state = AsyncError(message, StackTrace.current);
    return false;
  }
}

final directorActionControllerProvider =
    StateNotifierProvider.autoDispose<DirectorActionController, AsyncValue<void>>((ref) {
  final repo = ref.watch(directorRepositoryProvider);
  return DirectorActionController(
    createAnnouncement: CreateAnnouncementUseCase(repo),
    createMeeting: CreateMeetingUseCase(repo),
    cancelMeeting: CancelMeetingUseCase(repo),
    createApprovalRequest: CreateApprovalRequestUseCase(repo),
    decideApproval: DecideApprovalUseCase(repo),
    createExpense: CreateExpenseUseCase(repo),
  );
});
