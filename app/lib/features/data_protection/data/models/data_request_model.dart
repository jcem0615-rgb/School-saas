import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/entities/data_request.dart';

class DataRequestModel extends DataRequest {
  const DataRequestModel({
    required super.id,
    required super.requestedByUid,
    required super.requestedByName,
    required super.kind,
    required super.details,
    required super.requestedAt,
    super.studentId,
    super.studentName,
    super.status,
    super.handledByName,
    super.handledAt,
    super.outcome,
  });

  factory DataRequestModel.fromFirestore(String id, Map<String, dynamic> data) {
    return DataRequestModel(
      id: id,
      requestedByUid: data['requestedByUid'] as String? ?? '',
      requestedByName: data['requestedByName'] as String? ?? 'Unknown',
      kind: DataRequestKind.fromString(data['kind'] as String? ?? 'access'),
      details: data['details'] as String? ?? '',
      // The write stamps this from the server clock, so it is null in
      // the local echo of a document that has not round-tripped yet.
      requestedAt: (data['requestedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      studentId: data['studentId'] as String?,
      studentName: data['studentName'] as String?,
      status: DataRequestStatus.fromString(data['status'] as String? ?? 'open'),
      handledByName: data['handledByName'] as String?,
      handledAt: (data['handledAt'] as Timestamp?)?.toDate(),
      outcome: data['outcome'] as String?,
    );
  }
}
