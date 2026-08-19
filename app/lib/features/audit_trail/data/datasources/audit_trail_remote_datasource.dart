import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../../core/constants/firestore_paths.dart';
import '../models/audit_log_entry_model.dart';

class AuditTrailRemoteDataSource {
  final FirebaseFirestore _firestore;
  final String _schoolId;

  const AuditTrailRemoteDataSource({required FirebaseFirestore firestore, required String schoolId})
      : _firestore = firestore,
        _schoolId = schoolId;

  Stream<List<AuditLogEntryModel>> watchAuditLog({
    String? moduleFilter,
    DateTime? startDate,
    DateTime? endDate,
    String? userIdFilter,
    int limit = 100,
  }) {
    Query<Map<String, dynamic>> query = _firestore.collection(FirestorePaths.auditLog(_schoolId));

    if (moduleFilter != null) {
      query = query.where('module', isEqualTo: moduleFilter);
    }
    if (userIdFilter != null) {
      query = query.where('userId', isEqualTo: userIdFilter);
    }
    if (startDate != null) {
      query = query.where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(startDate));
    }
    if (endDate != null) {
      query = query.where('timestamp', isLessThanOrEqualTo: Timestamp.fromDate(endDate));
    }

    return query
        .orderBy('timestamp', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) => snap.docs.map((d) => AuditLogEntryModel.fromFirestore(d.id, d.data())).toList());
  }
}
