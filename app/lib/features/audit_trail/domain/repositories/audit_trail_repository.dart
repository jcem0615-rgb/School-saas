import '../entities/audit_log_entry.dart';

abstract class AuditTrailRepository {
  /// Search/filter is done via Firestore query composition in the data
  /// layer (module + date range are indexed fields); free-text search
  /// across userName/remarks is filtered client-side over the fetched
  /// page, since Firestore doesn't support substring search natively.
  /// Full-text search backed by a search index is a Reports-module
  /// concern if this becomes a real need at scale.
  Stream<List<AuditLogEntry>> watchAuditLog({
    String? moduleFilter,
    DateTime? startDate,
    DateTime? endDate,
    String? userIdFilter,
    int limit,
  });
}
