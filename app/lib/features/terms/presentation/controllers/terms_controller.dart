import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/result.dart';
import '../../../auth/presentation/controllers/auth_controller.dart'
    show authStateProvider, firestoreProvider;
import '../../data/datasources/terms_remote_datasource.dart';
import '../../data/repositories_impl/terms_repository_impl.dart';
import '../../domain/entities/terms_of_service.dart';
import '../../domain/repositories/terms_repository.dart';

final termsRemoteDataSourceProvider = Provider<TermsRemoteDataSource>((ref) {
  final user = ref.watch(authStateProvider).valueOrNull;
  if (user == null || user.schoolId == null) {
    throw StateError('Accepting terms requires a signed-in, school-scoped user.');
  }
  return TermsRemoteDataSource(
    firestore: ref.watch(firestoreProvider),
    schoolId: user.schoolId!,
    uid: user.uid,
  );
});

final termsRepositoryProvider = Provider<TermsRepository>((ref) {
  return TermsRepositoryImpl(ref.watch(termsRemoteDataSourceProvider));
});

/// Whether this account still owes an acceptance of the current version.
///
/// Same shape as needsPrivacyAcknowledgementProvider: an account that
/// accepted version 1 is asked again once version 2 exists, and an
/// account that has never accepted anything reads as 0.
final needsTermsAcceptanceProvider = Provider<bool>((ref) {
  final user = ref.watch(authStateProvider).valueOrNull;
  if (user == null) return false;
  return (user.termsVersion ?? 0) < TermsOfService.version;
});

class TermsController extends StateNotifier<AsyncValue<void>> {
  final TermsRepository _repository;
  TermsController(this._repository) : super(const AsyncData(null));

  Future<bool> accept() async {
    state = const AsyncLoading();
    final result = await _repository.acceptTerms(TermsOfService.version);
    return switch (result) {
      Success() => () {
          state = const AsyncData(null);
          return true;
        }(),
      Error(:final failure) => () {
          state = AsyncError(failure.message, StackTrace.current);
          return false;
        }(),
    };
  }
}

final termsControllerProvider =
    StateNotifierProvider<TermsController, AsyncValue<void>>((ref) {
  return TermsController(ref.watch(termsRepositoryProvider));
});
