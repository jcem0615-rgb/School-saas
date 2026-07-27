import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/result.dart';
import '../../../auth/presentation/controllers/auth_controller.dart' show authStateProvider, firestoreProvider;
import '../../data/datasources/guidance_remote_datasource.dart';
import '../../data/repositories_impl/guidance_repository_impl.dart';
import '../../domain/entities/guidance_record.dart';
import '../../domain/entities/summons.dart';
import '../../domain/repositories/guidance_repository.dart';
import '../../domain/usecases/guidance_record_usecases.dart';
import '../../domain/usecases/summons_usecases.dart';

final guidanceRemoteDataSourceProvider = Provider<GuidanceRemoteDataSource>((ref) {
  final user = ref.watch(authStateProvider).valueOrNull;
  if (user == null || user.schoolId == null) {
    throw StateError('GuidanceRemoteDataSource requires a signed-in, school-scoped user.');
  }
  return GuidanceRemoteDataSource(
    firestore: ref.watch(firestoreProvider),
    actingUser: ActingGuidance(uid: user.uid, schoolId: user.schoolId!, name: user.fullName),
  );
});

final guidanceRepositoryProvider = Provider<GuidanceRepository>((ref) {
  return GuidanceRepositoryImpl(ref.watch(guidanceRemoteDataSourceProvider));
});

final guidanceRecordsProvider =
    StreamProvider.autoDispose.family<List<GuidanceRecord>, String>((ref, studentId) {
  return WatchGuidanceRecordsUseCase(ref.watch(guidanceRepositoryProvider))(studentId);
});

final summonsStreamProvider = StreamProvider.autoDispose<List<Summons>>((ref) {
  return WatchSummonsUseCase(ref.watch(guidanceRepositoryProvider))();
});

class GuidanceActionController extends StateNotifier<AsyncValue<void>> {
  final CreateGuidanceRecordUseCase _createGuidanceRecord;
  final CreateSummonsUseCase _createSummons;
  final UpdateSummonsStatusUseCase _updateSummonsStatus;

  GuidanceActionController({
    required CreateGuidanceRecordUseCase createGuidanceRecord,
    required CreateSummonsUseCase createSummons,
    required UpdateSummonsStatusUseCase updateSummonsStatus,
  })  : _createGuidanceRecord = createGuidanceRecord,
        _createSummons = createSummons,
        _updateSummonsStatus = updateSummonsStatus,
        super(const AsyncData(null));

  Future<bool> createGuidanceRecord({
    required String studentId,
    required String studentName,
    required GuidanceCategory category,
    required String notes,
  }) => _run(() => _createGuidanceRecord(
        studentId: studentId,
        studentName: studentName,
        category: category,
        notes: notes,
      ));

  Future<bool> createSummons({
    required String studentId,
    required String studentName,
    required String reason,
    required DateTime scheduledDate,
  }) => _run(() => _createSummons(
        studentId: studentId,
        studentName: studentName,
        reason: reason,
        scheduledDate: scheduledDate,
      ));

  Future<bool> updateSummonsStatus({required String summonsId, required SummonsStatus status}) =>
      _run(() => _updateSummonsStatus(summonsId: summonsId, status: status));

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

final guidanceActionControllerProvider =
    StateNotifierProvider.autoDispose<GuidanceActionController, AsyncValue<void>>((ref) {
  final repo = ref.watch(guidanceRepositoryProvider);
  return GuidanceActionController(
    createGuidanceRecord: CreateGuidanceRecordUseCase(repo),
    createSummons: CreateSummonsUseCase(repo),
    updateSummonsStatus: UpdateSummonsStatusUseCase(repo),
  );
});
