import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/result.dart';
import '../../../auth/presentation/controllers/auth_controller.dart'
    show authStateProvider, firestoreProvider;
import '../../data/datasources/school_totals_remote_datasource.dart';
import '../../data/repositories_impl/school_totals_repository_impl.dart';
import '../../domain/entities/school_totals.dart';
import '../../domain/repositories/school_totals_repository.dart';

final schoolTotalsRemoteDataSourceProvider =
    Provider<SchoolTotalsRemoteDataSource>((ref) {
  final user = ref.watch(authStateProvider).valueOrNull;
  if (user == null || user.schoolId == null) {
    throw StateError('SchoolTotals requires a signed-in, school-scoped user.');
  }
  return SchoolTotalsRemoteDataSource(
    firestore: ref.watch(firestoreProvider),
    schoolId: user.schoolId!,
    uid: user.uid,
    role: user.role,
  );
});

final schoolTotalsRepositoryProvider = Provider<SchoolTotalsRepository>((ref) {
  return SchoolTotalsRepositoryImpl(ref.watch(schoolTotalsRemoteDataSourceProvider));
});

/// The figures for the card.
///
/// A FutureProvider, so it reads once when a dashboard opens and again
/// only when something asks -- `ref.invalidate` on a pull-to-refresh. The
/// alternative, a stream, would re-run four aggregation queries on every
/// write anywhere in the school, to move a number nobody is watching
/// change.
final schoolTotalsProvider = FutureProvider.autoDispose<SchoolTotals>((ref) async {
  final result = await ref.watch(schoolTotalsRepositoryProvider).fetch();
  return switch (result) {
    Success(:final value) => value,
    Error(:final failure) => throw failure.message,
  };
});
