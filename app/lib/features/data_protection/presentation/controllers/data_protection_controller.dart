import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/result.dart';
import '../../../auth/presentation/controllers/auth_controller.dart'
    show authStateProvider, firestoreProvider;
import '../../data/datasources/data_protection_remote_datasource.dart';
import '../../data/repositories_impl/data_protection_repository_impl.dart';
import '../../domain/entities/privacy_notice.dart';
import '../../domain/repositories/data_protection_repository.dart';
import '../../domain/usecases/data_protection_usecases.dart';

final dataProtectionRemoteDataSourceProvider = Provider<DataProtectionRemoteDataSource>((ref) {
  final user = ref.watch(authStateProvider).valueOrNull;
  if (user == null || user.schoolId == null) {
    throw StateError('DataProtectionRemoteDataSource requires a signed-in, school-scoped user.');
  }
  return DataProtectionRemoteDataSource(
    firestore: ref.watch(firestoreProvider),
    schoolId: user.schoolId!,
    uid: user.uid,
  );
});

final dataProtectionRepositoryProvider = Provider<DataProtectionRepository>((ref) {
  return DataProtectionRepositoryImpl(ref.watch(dataProtectionRemoteDataSourceProvider));
});

/// Whether this person still owes an acknowledgement of the current
/// notice.
///
/// A version comparison rather than a null check, so that rewriting the
/// notice asks everybody again instead of recording the people who
/// agreed to the old wording as having agreed to the new.
final needsPrivacyAcknowledgementProvider = Provider<bool>((ref) {
  final user = ref.watch(authStateProvider).valueOrNull;
  if (user == null) return false;
  return (user.privacyNoticeVersion ?? 0) < PrivacyNotice.version;
});

class DataProtectionActionController extends StateNotifier<AsyncValue<void>> {
  final AcknowledgePrivacyNoticeUseCase _acknowledge;

  DataProtectionActionController({
    required AcknowledgePrivacyNoticeUseCase acknowledge,
  })  : _acknowledge = acknowledge,
        super(const AsyncData(null));

  Future<bool> acknowledge() async {
    if (mounted) state = const AsyncLoading();
    return _boolFrom(await _acknowledge(PrivacyNotice.version));
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

final dataProtectionActionControllerProvider = StateNotifierProvider.autoDispose<
    DataProtectionActionController, AsyncValue<void>>((ref) {
  return DataProtectionActionController(
    acknowledge: AcknowledgePrivacyNoticeUseCase(ref.watch(dataProtectionRepositoryProvider)),
  );
});
