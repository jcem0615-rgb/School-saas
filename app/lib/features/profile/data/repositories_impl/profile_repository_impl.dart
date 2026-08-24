import '../../../../core/errors/failures.dart';
import '../../../../core/errors/result.dart';
import '../../domain/repositories/profile_repository.dart';
import '../datasources/profile_remote_datasource.dart';

class ProfileRepositoryImpl implements ProfileRepository {
  final ProfileRemoteDataSource _remote;
  const ProfileRepositoryImpl(this._remote);

  @override
  Future<Result<void>> updateProfile({String? phone, String? photoUrl}) async {
    try {
      await _remote.updateProfile(phone: phone, photoUrl: photoUrl);
      return const Success(null);
    } catch (_) {
      return const Error(UnknownFailure());
    }
  }
}
