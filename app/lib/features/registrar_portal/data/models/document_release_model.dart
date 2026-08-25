import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/entities/document_release.dart';

class DocumentReleaseModel extends DocumentRelease {
  const DocumentReleaseModel({
    required super.id,
    required super.studentId,
    required super.studentName,
    required super.document,
    required super.copies,
    required super.purpose,
    required super.releasedToName,
    required super.releasedByName,
    required super.releasedAt,
    super.releasedToRelation,
    super.remarks,
  });

  factory DocumentReleaseModel.fromFirestore(String id, Map<String, dynamic> data) {
    return DocumentReleaseModel(
      id: id,
      studentId: data['studentId'] as String? ?? '',
      studentName: data['studentName'] as String? ?? '',
      document: SchoolDocument.fromString(data['document'] as String? ?? ''),
      // One, not zero, for a record written before copies was a field.
      // A release of nothing is not a thing that happened.
      copies: (data['copies'] as num?)?.toInt() ?? 1,
      purpose: data['purpose'] as String? ?? '',
      releasedToName: data['releasedToName'] as String? ?? '',
      releasedToRelation: data['releasedToRelation'] as String?,
      releasedByName: data['releasedByName'] as String? ?? 'Unknown',
      // The write sets this from the server clock, so it is null in the
      // local echo of a document that has not round-tripped yet.
      releasedAt: (data['releasedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      remarks: data['remarks'] as String?,
    );
  }
}
