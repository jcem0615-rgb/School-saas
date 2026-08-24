import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../auth/presentation/controllers/auth_controller.dart' show authStateProvider, firestoreProvider;
import '../../data/datasources/profile_remote_datasource.dart';
import '../../data/repositories_impl/profile_repository_impl.dart';
import '../../domain/repositories/profile_repository.dart';
import '../../domain/usecases/update_profile_usecase.dart';

final profileRemoteDataSourceProvider = Provider<ProfileRemoteDataSource>((ref) {
  final user = ref.watch(authStateProvider).valueOrNull;
  if (user == null || user.schoolId == null) {
    throw StateError('ProfileRemoteDataSource requires a signed-in, school-scoped user.');
  }
  return ProfileRemoteDataSource(
    firestore: ref.watch(firestoreProvider),
    schoolId: user.schoolId!,
    uid: user.uid,
  );
});

final profileRepositoryProvider = Provider<ProfileRepository>((ref) {
  return ProfileRepositoryImpl(ref.watch(profileRemoteDataSourceProvider));
});

class ProfileActionController extends StateNotifier<AsyncValue<void>> {
  // `mounted` guards below: these action controllers are autoDispose, and
  // the repositories they depend on rebuild whenever authStateProvider
  // emits. If that lands while a write is in flight the notifier is gone
  // by the time the result returns, and assigning `state` then throws
  // "used after dispose" -- which surfaces as an action that silently does
  // nothing even though the write succeeded.
  final UpdateProfileUseCase _updateProfile;
  ProfileActionController(this._updateProfile) : super(const AsyncData(null));

  Future<bool> updateProfile({String? phone, String? photoUrl}) async {
    if (mounted) state = const AsyncLoading();
    final result = await _updateProfile(phone: phone, photoUrl: photoUrl);
    if (result.isSuccess) {
      if (mounted) state = const AsyncData(null);
      return true;
    }
    if (mounted) state = AsyncError(result.failureOrNull?.message ?? 'Failed to update profile.', StackTrace.current);
    return false;
  }
}

final profileActionControllerProvider =
    StateNotifierProvider.autoDispose<ProfileActionController, AsyncValue<void>>((ref) {
  return ProfileActionController(UpdateProfileUseCase(ref.watch(profileRepositoryProvider)));
});
