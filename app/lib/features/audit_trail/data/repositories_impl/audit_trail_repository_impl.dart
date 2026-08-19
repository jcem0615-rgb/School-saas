import '../../domain/entities/audit_log_entry.dart';
import '../../domain/repositories/audit_trail_repository.dart';
import '../datasources/audit_trail_remote_datasource.dart';

class AuditTrailRepositoryImpl implements AuditTrailRepository {
  final AuditTrailRemoteDataSource _remote;
  const AuditTrailRepositoryImpl(this._remote);

  @override
  Stream<List<AuditLogEntry>> watchAuditLog({
    String? moduleFilter,
    DateTime? startDate,
    DateTime? endDate,
    String? userIdFilter,
    int limit = 100,
  }) {
    return _remote.watchAuditLog(
      moduleFilter: moduleFilter,
      startDate: startDate,
      endDate: endDate,
      userIdFilter: userIdFilter,
      limit: limit,
    );
  }
}
