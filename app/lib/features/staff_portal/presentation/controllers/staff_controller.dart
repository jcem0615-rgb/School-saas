import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/result.dart';
import '../../../auth/presentation/controllers/auth_controller.dart' show authStateProvider, firestoreProvider;
import '../../data/datasources/staff_remote_datasource.dart';
import '../../data/repositories_impl/staff_repository_impl.dart';
import '../../domain/entities/checklist_item.dart';
import '../../domain/entities/daily_report.dart';
import '../../domain/repositories/staff_repository.dart';
import '../../domain/usecases/checklist_usecases.dart';
import '../../domain/usecases/daily_report_usecases.dart';

final staffRemoteDataSourceProvider = Provider<StaffRemoteDataSource>((ref) {
  final user = ref.watch(authStateProvider).valueOrNull;
  if (user == null || user.schoolId == null) {
    throw StateError('StaffRemoteDataSource requires a signed-in, school-scoped user.');
  }
  return StaffRemoteDataSource(
    firestore: ref.watch(firestoreProvider),
    actingUser: ActingStaff(uid: user.uid, schoolId: user.schoolId!, name: user.fullName),
  );
});

final staffRepositoryProvider = Provider<StaffRepository>((ref) {
  return StaffRepositoryImpl(ref.watch(staffRemoteDataSourceProvider));
});

final myChecklistProvider = StreamProvider.autoDispose.family<List<ChecklistItem>, String>((ref, date) {
  return WatchMyChecklistUseCase(ref.watch(staffRepositoryProvider))(date);
});

final myDailyReportsProvider = StreamProvider.autoDispose<List<DailyReport>>((ref) {
  return WatchMyDailyReportsUseCase(ref.watch(staffRepositoryProvider))();
});

class StaffActionController extends StateNotifier<AsyncValue<void>> {
  // `mounted` guards below: these action controllers are autoDispose, and
  // the repositories they depend on rebuild whenever authStateProvider
  // emits. If that lands while a write is in flight the notifier is gone
  // by the time the result returns, and assigning `state` then throws
  // "used after dispose" -- which surfaces as an action that silently does
  // nothing even though the write succeeded.
  final AddChecklistItemUseCase _addChecklistItem;
  final ToggleChecklistItemUseCase _toggleChecklistItem;
  final UpdateChecklistItemUseCase _updateChecklistItem;
  final DeleteChecklistItemUseCase _deleteChecklistItem;
  final SubmitDailyReportUseCase _submitDailyReport;

  StaffActionController({
    required AddChecklistItemUseCase addChecklistItem,
    required ToggleChecklistItemUseCase toggleChecklistItem,
    required UpdateChecklistItemUseCase updateChecklistItem,
    required DeleteChecklistItemUseCase deleteChecklistItem,
    required SubmitDailyReportUseCase submitDailyReport,
  })  : _addChecklistItem = addChecklistItem,
        _toggleChecklistItem = toggleChecklistItem,
        _updateChecklistItem = updateChecklistItem,
        _deleteChecklistItem = deleteChecklistItem,
        _submitDailyReport = submitDailyReport,
        super(const AsyncData(null));

  Future<bool> addChecklistItem({required String task, required String date}) =>
      _run(() => _addChecklistItem(task: task, date: date));

  Future<bool> toggleChecklistItem({required String itemId, required bool completed}) =>
      _run(() => _toggleChecklistItem(itemId: itemId, completed: completed));

  Future<bool> updateChecklistItem({required String itemId, required String task}) =>
      _run(() => _updateChecklistItem(itemId: itemId, task: task));

  Future<bool> deleteChecklistItem(String itemId) => _run(() => _deleteChecklistItem(itemId));

  /// Note there is no edit/delete for daily reports: firestore.rules makes
  /// dailyReports immutable, so corrections are filed as a new entry.
  Future<bool> submitDailyReport({required String date, required String content}) =>
      _run(() => _submitDailyReport(date: date, content: content));

  Future<bool> _run(Future<dynamic> Function() action) async {
    if (mounted) state = const AsyncLoading();
    final result = await action();
    if (result case Success()) {
      if (mounted) state = const AsyncData(null);
      return true;
    } else if (result case Error(:final failure)) {
      if (mounted) state = AsyncError(failure.message, StackTrace.current);
    }
    return false;
  }
}

final staffActionControllerProvider =
    StateNotifierProvider.autoDispose<StaffActionController, AsyncValue<void>>((ref) {
  final repo = ref.watch(staffRepositoryProvider);
  return StaffActionController(
    addChecklistItem: AddChecklistItemUseCase(repo),
    toggleChecklistItem: ToggleChecklistItemUseCase(repo),
    updateChecklistItem: UpdateChecklistItemUseCase(repo),
    deleteChecklistItem: DeleteChecklistItemUseCase(repo),
    submitDailyReport: SubmitDailyReportUseCase(repo),
  );
});
