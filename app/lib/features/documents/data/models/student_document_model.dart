import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/entities/student_document.dart';

class StudentDocumentModel extends StudentDocument {
  const StudentDocumentModel({
    required super.id,
    required super.studentId,
    required super.studentName,
    required super.kind,
    required super.origin,
    required super.title,
    required super.fileName,
    required super.url,
    required super.contentType,
    required super.sizeBytes,
    required super.filedByName,
    required super.filedAt,
    super.note,
    super.releaseId,
    super.archivedAt,
    super.archivedByName,
    super.archiveReason,
  });

  factory StudentDocumentModel.fromFirestore(String id, Map<String, dynamic> data) {
    final kind = DocumentKind.fromString(data['kind'] as String? ?? '');
    return StudentDocumentModel(
      id: id,
      studentId: data['studentId'] as String? ?? '',
      studentName: data['studentName'] as String? ?? '',
      kind: kind,
      origin: DocumentOrigin.fromString(data['origin'] as String? ?? ''),
      // A row written before the field existed, or one saved with an
      // empty title, still has to say what it is on the list.
      title: (data['title'] as String?)?.trim().isNotEmpty == true
          ? (data['title'] as String).trim()
          : kind.displayLabel,
      fileName: data['fileName'] as String? ?? '',
      url: data['url'] as String? ?? '',
      contentType: data['contentType'] as String? ?? 'application/octet-stream',
      sizeBytes: (data['sizeBytes'] as num?)?.toInt() ?? 0,
      filedByName: data['filedByName'] as String? ?? 'Unknown',
      // Written from the server clock, so it is null in the local echo of
      // a document that has not round-tripped yet.
      filedAt: (data['filedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      note: data['note'] as String?,
      releaseId: data['releaseId'] as String?,
      archivedAt: (data['archivedAt'] as Timestamp?)?.toDate(),
      archivedByName: data['archivedByName'] as String?,
      archiveReason: data['archiveReason'] as String?,
    );
  }
}
