import '../entities/invoice.dart';
import '../repositories/owner_repository.dart';

class WatchInvoicesUseCase {
  final OwnerRepository _repository;
  const WatchInvoicesUseCase(this._repository);

  Stream<List<Invoice>> call(String schoolId) => _repository.watchInvoices(schoolId);
}
