import '../entities/audit_log_entry.dart';
import '../repositories/audit_trail_repository.dart';

class WatchAuditLogUseCase {
  final AuditTrailRepository _repository;
  const WatchAuditLogUseCase(this._repository);

  Stream<List<AuditLogEntry>> call({
    String? moduleFilter,
    DateTime? startDate,
    DateTime? endDate,
    String? userIdFilter,
    int limit = 100,
  }) =>
      _repository.watchAuditLog(
        moduleFilter: moduleFilter,
        startDate: startDate,
        endDate: endDate,
        userIdFilter: userIdFilter,
        limit: limit,
      );
}
