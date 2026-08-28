import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/result.dart';
import '../../../admin_portal/presentation/controllers/admin_controller.dart' show brandingProvider;
import '../../../auth/presentation/controllers/auth_controller.dart'
    show authStateProvider, firestoreProvider, firebaseFunctionsProvider;
import '../../data/datasources/schedule_remote_datasource.dart';
import '../../data/repositories_impl/schedule_repository_impl.dart';
import '../../domain/entities/schedule_block.dart';
import '../../domain/repositories/schedule_repository.dart';
import '../../domain/usecases/schedule_usecases.dart';

final scheduleRemoteDataSourceProvider = Provider<ScheduleRemoteDataSource>((ref) {
  final user = ref.watch(authStateProvider).valueOrNull;
  if (user == null || user.schoolId == null) {
    throw StateError('ScheduleRemoteDataSource requires a signed-in, school-scoped user.');
  }
  return ScheduleRemoteDataSource(
    firestore: ref.watch(firestoreProvider),
    functions: ref.watch(firebaseFunctionsProvider),
    schoolId: user.schoolId!,
  );
});

final scheduleRepositoryProvider = Provider<ScheduleRepository>((ref) {
  return ScheduleRepositoryImpl(ref.watch(scheduleRemoteDataSourceProvider));
});

/// Which year's timetable is on screen.
///
/// Defaults to the school's own current year from branding rather than
/// to a guess from today's date, so every screen agrees with what is
/// printed on the ID cards and the transcripts.
final scheduleYearProvider = StateProvider<String>((ref) {
  final branding = ref.watch(brandingProvider).valueOrNull?.schoolYear?.trim();
  if (branding != null && branding.isNotEmpty) return branding;
  final now = DateTime.now();
  final start = now.month >= 6 ? now.year : now.year - 1;
  return '$start-${start + 1}';
});

/// The whole week. Not autoDispose: three screens read it, the editor
/// needs it for the clash check, and it is a few hundred documents that
/// change a handful of times a term.
final scheduleProvider = StreamProvider<List<ScheduleBlock>>((ref) {
  return WatchScheduleUseCase(ref.watch(scheduleRepositoryProvider))(
    ref.watch(scheduleYearProvider),
  );
});

/// One section's week.
final sectionScheduleProvider =
    Provider.autoDispose.family<List<ScheduleBlock>, String>((ref, section) {
  final all = ref.watch(scheduleProvider).valueOrNull ?? const <ScheduleBlock>[];
  final wanted = section.trim().toLowerCase();
  return all.where((b) => b.section.trim().toLowerCase() == wanted).toList();
});

/// One teacher's week.
final teacherScheduleProvider =
    Provider.autoDispose.family<List<ScheduleBlock>, String>((ref, teacherId) {
  final all = ref.watch(scheduleProvider).valueOrNull ?? const <ScheduleBlock>[];
  return all.where((b) => b.teacherId == teacherId).toList();
});

class ScheduleActionController extends StateNotifier<AsyncValue<void>> {
  final SaveScheduleBlockUseCase _save;
  final DeleteScheduleBlockUseCase _delete;

  ScheduleActionController({
    required SaveScheduleBlockUseCase save,
    required DeleteScheduleBlockUseCase delete,
  })  : _save = save,
        _delete = delete,
        super(const AsyncData(null));

  Future<bool> save({
    String? blockId,
    required String subject,
    required String section,
    required String teacherId,
    required String teacherName,
    String? room,
    required int dayOfWeek,
    required int startMinute,
    required int endMinute,
    required String schoolYear,
    String? term,
    Iterable<ScheduleBlock> existing = const [],
  }) async {
    if (mounted) state = const AsyncLoading();
    final result = await _save(
      blockId: blockId,
      subject: subject,
      section: section,
      teacherId: teacherId,
      teacherName: teacherName,
      room: room,
      dayOfWeek: dayOfWeek,
      startMinute: startMinute,
      endMinute: endMinute,
      schoolYear: schoolYear,
      term: term,
      existing: existing,
    );
    return _boolFrom(result);
  }

  Future<bool> delete(String blockId) async {
    if (mounted) state = const AsyncLoading();
    return _boolFrom(await _delete(blockId));
  }

  bool _boolFrom(Result<Object?> result) {
    return switch (result) {
      Success() => () {
          if (mounted) state = const AsyncData(null);
          return true;
        }(),
      Error(:final failure) => () {
          if (mounted) state = AsyncError(failure.message, StackTrace.current);
          return false;
        }(),
    };
  }
}

final scheduleActionControllerProvider =
    StateNotifierProvider.autoDispose<ScheduleActionController, AsyncValue<void>>((ref) {
  final repository = ref.watch(scheduleRepositoryProvider);
  return ScheduleActionController(
    save: SaveScheduleBlockUseCase(repository),
    delete: DeleteScheduleBlockUseCase(repository),
  );
});
