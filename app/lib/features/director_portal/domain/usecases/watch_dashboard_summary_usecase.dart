import '../../../../core/errors/result.dart';
import '../entities/director_dashboard_summary.dart';
import '../repositories/director_repository.dart';

class GetDashboardSummaryUseCase {
  final DirectorRepository _repository;
  const GetDashboardSummaryUseCase(this._repository);

  Future<Result<DirectorDashboardSummary>> call() => _repository.getDashboardSummary();
}
