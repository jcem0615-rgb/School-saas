import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/result.dart';
import '../../../auth/presentation/controllers/auth_controller.dart'
    show authStateProvider, firestoreProvider;
import '../../data/datasources/data_protection_remote_datasource.dart';
import '../../data/repositories_impl/data_protection_repository_impl.dart';
import '../../domain/entities/data_request.dart';
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
    userName: user.fullName,
  );
});

final dataProtectionRepositoryProvider = Provider<DataProtectionRepository>((ref) {
  return DataProtectionRepositoryImpl(ref.watch(dataProtectionRemoteDataSourceProvider));
});

/// The office's queue.
final dataRequestsProvider = StreamProvider.autoDispose<List<DataRequest>>((ref) {
  return WatchDataRequestsUseCase(ref.watch(dataProtectionRepositoryProvider))();
});

/// What one person has asked for, on their own profile.
final myDataRequestsProvider = StreamProvider.autoDispose<List<DataRequest>>((ref) {
  final uid = ref.watch(authStateProvider).valueOrNull?.uid;
  if (uid == null) return const Stream.empty();
  return WatchMyDataRequestsUseCase(ref.watch(dataProtectionRepositoryProvider))(uid);
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
  final RaiseDataRequestUseCase _raise;
  final CloseDataRequestUseCase _close;
  final AcknowledgePrivacyNoticeUseCase _acknowledge;

  DataProtectionActionController({
    required RaiseDataRequestUseCase raise,
    required CloseDataRequestUseCase close,
    required AcknowledgePrivacyNoticeUseCase acknowledge,
  })  : _raise = raise,
        _close = close,
        _acknowledge = acknowledge,
        super(const AsyncData(null));

  Future<bool> raise({
    required DataRequestKind kind,
    required String details,
    String? studentId,
    String? studentName,
  }) async {
    if (mounted) state = const AsyncLoading();
    return _boolFrom(await _raise(
      kind: kind,
      details: details,
      studentId: studentId,
      studentName: studentName,
    ));
  }

  Future<bool> close({
    required String requestId,
    required DataRequestStatus status,
    required String outcome,
  }) async {
    if (mounted) state = const AsyncLoading();
    return _boolFrom(await _close(requestId: requestId, status: status, outcome: outcome));
  }

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
  final repository = ref.watch(dataProtectionRepositoryProvider);
  return DataProtectionActionController(
    raise: RaiseDataRequestUseCase(repository),
    close: CloseDataRequestUseCase(repository),
    acknowledge: AcknowledgePrivacyNoticeUseCase(repository),
  );
});
