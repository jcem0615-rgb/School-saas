import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../auth/presentation/controllers/auth_controller.dart' show authStateProvider, firestoreProvider;
import '../../../registrar_portal/domain/entities/student_summary.dart';
import '../../data/datasources/parent_remote_datasource.dart';
import '../../data/repositories_impl/parent_repository_impl.dart';
import '../../domain/repositories/parent_repository.dart';
import '../../domain/usecases/watch_children_usecase.dart';

final parentRemoteDataSourceProvider = Provider<ParentRemoteDataSource>((ref) {
  final user = ref.watch(authStateProvider).valueOrNull;
  if (user == null || user.schoolId == null) {
    throw StateError('ParentRemoteDataSource requires a signed-in, school-scoped user.');
  }
  return ParentRemoteDataSource(firestore: ref.watch(firestoreProvider), schoolId: user.schoolId!);
});

final parentRepositoryProvider = Provider<ParentRepository>((ref) {
  return ParentRepositoryImpl(ref.watch(parentRemoteDataSourceProvider));
});

/// Re-derives automatically if the parent's linkedStudentIds ever changes
/// (e.g. the Registrar links another child) since it watches
/// authStateProvider rather than capturing the list once.
final myChildrenProvider = StreamProvider.autoDispose<List<StudentSummary>>((ref) {
  final linkedIds = ref.watch(authStateProvider).valueOrNull?.linkedStudentIds ?? const [];
  return WatchChildrenUseCase(ref.watch(parentRepositoryProvider))(linkedIds);
});
