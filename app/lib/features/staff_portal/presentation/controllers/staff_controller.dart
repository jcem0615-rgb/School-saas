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
  final AddChecklistItemUseCase _addChecklistItem;
  final ToggleChecklistItemUseCase _toggleChecklistItem;
  final SubmitDailyReportUseCase _submitDailyReport;

  StaffActionController({
    required AddChecklistItemUseCase addChecklistItem,
    required ToggleChecklistItemUseCase toggleChecklistItem,
    required SubmitDailyReportUseCase submitDailyReport,
  })  : _addChecklistItem = addChecklistItem,
        _toggleChecklistItem = toggleChecklistItem,
        _submitDailyReport = submitDailyReport,
        super(const AsyncData(null));

  Future<bool> addChecklistItem({required String task, required String date}) =>
      _run(() => _addChecklistItem(task: task, date: date));

  Future<bool> toggleChecklistItem({required String itemId, required bool completed}) =>
      _run(() => _toggleChecklistItem(itemId: itemId, completed: completed));

  Future<bool> submitDailyReport({required String date, required String content}) =>
      _run(() => _submitDailyReport(date: date, content: content));

  Future<bool> _run(Future<dynamic> Function() action) async {
    state = const AsyncLoading();
    final result = await action();
    if (result case Success()) {
      state = const AsyncData(null);
      return true;
    } else if (result case Error(:final failure)) {
      state = AsyncError(failure.message, StackTrace.current);
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
    submitDailyReport: SubmitDailyReportUseCase(repo),
  );
});
