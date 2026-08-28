import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../auth/presentation/controllers/auth_controller.dart'
    show authStateProvider, firestoreProvider, firebaseFunctionsProvider;
import '../../data/repositories_impl/system_check_repository_impl.dart';
import '../../domain/entities/system_check.dart';
import '../../domain/repositories/system_check_repository.dart';

final systemCheckRepositoryProvider = Provider<SystemCheckRepository>((ref) {
  final user = ref.watch(authStateProvider).valueOrNull;
  if (user == null || user.schoolId == null) {
    throw StateError('The system check needs a signed-in, school-scoped user.');
  }
  return SystemCheckRepositoryImpl(
    firestore: ref.watch(firestoreProvider),
    functions: ref.watch(firebaseFunctionsProvider),
    storage: FirebaseStorage.instance,
    auth: FirebaseAuth.instance,
    schoolId: user.schoolId!,
  );
});

/// The last report, or null before anything has been run.
///
/// Deliberately not run on open. The probes call twelve functions and
/// write to Storage; that is a thing somebody asks for, not something a
/// screen does to a live deployment because it was navigated to.
class SystemCheckController extends StateNotifier<AsyncValue<SystemCheckReport?>> {
  final SystemCheckRepository _repository;

  SystemCheckController(this._repository) : super(const AsyncData(null));

  Future<void> run() async {
    if (mounted) state = const AsyncLoading();
    try {
      final report = await _repository.run();
      if (mounted) state = AsyncData(report);
    } catch (e, stack) {
      if (mounted) state = AsyncError(e, stack);
    }
  }
}

final systemCheckControllerProvider =
    StateNotifierProvider.autoDispose<SystemCheckController, AsyncValue<SystemCheckReport?>>(
        (ref) {
  // read, not watch, and that distinction is the whole difference
  // between this screen working and this screen doing nothing.
  //
  // The claims check calls getIdTokenResult(force: true) on purpose --
  // stale claims are one of the faults it exists to find. That refresh
  // makes authStateProvider emit, which rebuilds the repository, which
  // with a watch here would dispose this controller and construct a new
  // one in AsyncData(null). The report would be discarded a moment
  // after it was produced, and the screen would sit back at "Run the
  // checks" as though nothing had happened -- which is exactly what it
  // did the first time it was run against a real deployment.
  return SystemCheckController(ref.read(systemCheckRepositoryProvider));
});
