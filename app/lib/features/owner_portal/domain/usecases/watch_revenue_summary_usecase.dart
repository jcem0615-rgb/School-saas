import '../entities/revenue_summary.dart';
import '../repositories/owner_repository.dart';

class WatchRevenueSummaryUseCase {
  final OwnerRepository _repository;
  const WatchRevenueSummaryUseCase(this._repository);

  Stream<RevenueSummary> call() => _repository.watchRevenueSummary();
}
