import '../../../../core/errors/app_exceptions.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/errors/result.dart';
import '../../domain/repositories/data_protection_repository.dart';
import '../datasources/data_protection_remote_datasource.dart';

class DataProtectionRepositoryImpl implements DataProtectionRepository {
  final DataProtectionRemoteDataSource _remote;
  const DataProtectionRepositoryImpl(this._remote);

  @override
  Future<Result<void>> acknowledgePrivacyNotice(int version) async {
    try {
      await _remote.acknowledgePrivacyNotice(version);
      return const Success(null);
    } on ServerException catch (e) {
      return Error(ServerFailure(e.message));
    } catch (_) {
      return const Error(UnknownFailure('That could not be recorded.'));
    }
  }
}
