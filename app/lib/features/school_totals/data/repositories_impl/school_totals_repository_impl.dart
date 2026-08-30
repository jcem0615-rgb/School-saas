import '../../../../core/errors/app_exceptions.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/errors/result.dart';
import '../../domain/entities/school_totals.dart';
import '../../domain/repositories/school_totals_repository.dart';
import '../datasources/school_totals_remote_datasource.dart';

class SchoolTotalsRepositoryImpl implements SchoolTotalsRepository {
  final SchoolTotalsRemoteDataSource _remote;
  const SchoolTotalsRepositoryImpl(this._remote);

  @override
  Future<Result<SchoolTotals>> fetch() async {
    try {
      return Success(await _remote.fetch());
    } on ServerException catch (e) {
      return Error(ServerFailure(e.message));
    } catch (_) {
      return const Error(UnknownFailure());
    }
  }
}
