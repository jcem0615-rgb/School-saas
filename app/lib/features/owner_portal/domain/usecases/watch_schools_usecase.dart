import '../entities/school_summary.dart';
import '../repositories/owner_repository.dart';

class WatchSchoolsUseCase {
  final OwnerRepository _repository;
  const WatchSchoolsUseCase(this._repository);

  Stream<List<SchoolSummary>> call() => _repository.watchSchools();
}
