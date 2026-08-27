import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/errors/result.dart';
import '../../domain/entities/report_kind.dart';
import '../../domain/entities/report_period.dart';
import '../../domain/repositories/reports_repository.dart';
import '../datasources/reports_remote_datasource.dart';

class ReportsRepositoryImpl implements ReportsRepository {
  final ReportsRemoteDataSource _remote;
  const ReportsRepositoryImpl(this._remote);

  @override
  Future<Result<ReportData>> fetch({
    required ReportKind kind,
    required ReportPeriod period,
  }) async {
    try {
      return Success(await _remote.fetch(kind: kind, period: period));
    } on FirebaseException catch (e) {
      // A report reads several collections at once, so a denial here is
      // almost always a role that may read one of them and not another.
      // Saying which is the difference between a fixable message and
      // "something went wrong".
      if (e.code == 'permission-denied') {
        return const Error(PermissionFailure(
          'This account cannot read everything this report needs. Reports are '
          'a Director and Admin surface.',
        ));
      }
      if (e.code == 'failed-precondition') {
        return Error(ServerFailure(
          'The database is missing an index this report needs. '
          '${e.message ?? ''}'.trim(),
        ));
      }
      return Error(ServerFailure(e.message ?? 'The report could not be built.'));
    } catch (_) {
      return const Error(UnknownFailure('The report could not be built.'));
    }
  }
}
