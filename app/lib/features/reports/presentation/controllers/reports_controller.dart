import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/result.dart';
import '../../../auth/presentation/controllers/auth_controller.dart'
    show authStateProvider, firestoreProvider;
import '../../data/datasources/reports_remote_datasource.dart';
import '../../data/repositories_impl/reports_repository_impl.dart';
import '../../domain/entities/report_kind.dart';
import '../../domain/entities/report_period.dart';
import '../../domain/entities/report_table.dart';
import '../../domain/repositories/reports_repository.dart';
import '../../domain/usecases/build_report_usecase.dart';

final reportsRemoteDataSourceProvider = Provider<ReportsRemoteDataSource>((ref) {
  final user = ref.watch(authStateProvider).valueOrNull;
  if (user == null || user.schoolId == null) {
    throw StateError('ReportsRemoteDataSource requires a signed-in, school-scoped user.');
  }
  return ReportsRemoteDataSource(
    firestore: ref.watch(firestoreProvider),
    schoolId: user.schoolId!,
  );
});

final reportsRepositoryProvider = Provider<ReportsRepository>((ref) {
  return ReportsRepositoryImpl(ref.watch(reportsRemoteDataSourceProvider));
});

/// What the screen is asking for.
///
/// A value class rather than three separate providers, because a report
/// is one request: changing the kind and the period should produce one
/// fetch, not two, and separate providers would race each other into a
/// half-applied query.
class ReportRequest {
  final ReportKind kind;
  final ReportPeriod period;

  /// Grade distribution only. Null means every term pooled, which the
  /// report says plainly rather than implying a single-term figure.
  final String? term;

  ReportRequest({required this.kind, required this.period, this.term});

  ReportRequest copyWith({ReportKind? kind, ReportPeriod? period, Object? term = _unset}) =>
      ReportRequest(
        kind: kind ?? this.kind,
        period: period ?? this.period,
        term: term == _unset ? this.term : term as String?,
      );

  static const _unset = Object();
}

/// The screen's current request. Not autoDispose: coming back from the
/// print preview should not reset the date range somebody just set.
final reportRequestProvider = StateProvider<ReportRequest>((ref) {
  return ReportRequest(
    kind: ReportKind.enrollment,
    period: ReportPeriod.schoolYearOf(DateTime.now()),
  );
});

/// The finished table for the current request.
///
/// A FutureProvider rather than a stream: a report is a snapshot somebody
/// reads down a column of, and one that reshuffles underneath them is
/// worse than one that is a minute old. Pulling to refresh is the way to
/// get a newer one.
final reportTableProvider = FutureProvider.autoDispose<ReportTable>((ref) async {
  final request = ref.watch(reportRequestProvider);
  final result = await BuildReportUseCase(ref.watch(reportsRepositoryProvider))(
    kind: request.kind,
    period: request.period,
    term: request.term,
  );
  return switch (result) {
    Success(:final value) => value,
    Error(:final failure) => throw failure.message,
  };
});
