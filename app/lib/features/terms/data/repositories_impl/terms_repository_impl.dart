import '../../../../core/errors/app_exceptions.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/errors/result.dart';
import '../../domain/repositories/terms_repository.dart';
import '../datasources/terms_remote_datasource.dart';

class TermsRepositoryImpl implements TermsRepository {
  final TermsRemoteDataSource _remote;
  const TermsRepositoryImpl(this._remote);

  @override
  Future<Result<void>> acceptTerms(int version) async {
    try {
      await _remote.acceptTerms(version);
      return const Success(null);
    } on ServerException catch (e) {
      return Error(ServerFailure(e.message));
    } catch (_) {
      return const Error(UnknownFailure());
    }
  }
}
