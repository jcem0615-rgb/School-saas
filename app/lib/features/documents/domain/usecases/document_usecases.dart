import '../../../../core/errors/failures.dart';
import '../../../../core/errors/result.dart';
import '../entities/student_document.dart';
import '../repositories/documents_repository.dart';

class WatchStudentDocumentsUseCase {
  final DocumentsRepository _repository;
  const WatchStudentDocumentsUseCase(this._repository);

  Stream<List<StudentDocument>> call(String studentId) =>
      _repository.watchStudentDocuments(studentId);
}

/// Files a paper in a student's folder.
///
/// The checks are all about the row being worth keeping. A folder entry
/// with no file behind it, or one pointing at a file nobody can open, is
/// worse than an empty folder: it says the school holds a document it
/// does not hold, and somebody will rely on that at enrolment time.
class FileStudentDocumentUseCase {
  final DocumentsRepository _repository;
  const FileStudentDocumentUseCase(this._repository);

  Future<Result<void>> call({
    required String studentId,
    required String studentName,
    required DocumentKind kind,
    required String fileName,
    required String url,
    required String contentType,
    required int sizeBytes,
    String title = '',
    DocumentOrigin origin = DocumentOrigin.received,
    String? note,
    String? releaseId,
  }) {
    if (studentId.trim().isEmpty) {
      return Future.value(const Error(ValidationFailure('Missing student.')));
    }
    if (fileName.trim().isEmpty || url.trim().isEmpty) {
      return Future.value(
        const Error(ValidationFailure('Attach the scanned document first.')),
      );
    }
    // A zero-byte upload is a failed one that reported success. Filing it
    // would put a row in the folder whose file opens to nothing.
    if (sizeBytes <= 0) {
      return Future.value(
        const Error(ValidationFailure('That file is empty. Scan it again.')),
      );
    }
    if (!isFilableContentType(contentType)) {
      return Future.value(const Error(
        ValidationFailure('Only PDFs and photos can go in a student folder.'),
      ));
    }
    // A copy of a release has to say which release, or the two halves of
    // the record cannot be put back together.
    if (origin == DocumentOrigin.issued && (releaseId?.trim().isEmpty ?? true)) {
      return Future.value(const Error(
        ValidationFailure('An issued copy must name the release it came from.'),
      ));
    }
    if (origin == DocumentOrigin.received && kind == DocumentKind.issuedCopy) {
      return Future.value(const Error(
        ValidationFailure('A copy of an issued document is filed by releasing it.'),
      ));
    }

    // A blank title is not worth refusing somebody over -- the kind
    // already says what the paper is, so that becomes the title.
    final named = title.trim().isEmpty ? kind.displayLabel : title.trim();

    return _repository.fileDocument(
      studentId: studentId,
      studentName: studentName,
      kind: kind,
      origin: origin,
      title: named,
      fileName: fileName.trim(),
      url: url.trim(),
      contentType: contentType.trim().toLowerCase(),
      sizeBytes: sizeBytes,
      note: note?.trim().isEmpty ?? true ? null : note!.trim(),
      releaseId: releaseId?.trim().isEmpty ?? true ? null : releaseId!.trim(),
    );
  }
}

/// Withdraws a paper, with the reason recorded.
///
/// The reason is required and that is the whole point of the use case. An
/// archive with no reason is a delete with extra steps: six months later
/// nobody can say whether the birth certificate was superseded by a
/// corrected one or removed because somebody filed it under the wrong
/// child.
class ArchiveStudentDocumentUseCase {
  final DocumentsRepository _repository;
  const ArchiveStudentDocumentUseCase(this._repository);

  /// Short enough that "wrong student" passes and long enough that a
  /// stabbed keyboard does not.
  static const minimumReasonLength = 4;

  Future<Result<void>> call({
    required String documentId,
    required String reason,
  }) {
    if (documentId.trim().isEmpty) {
      return Future.value(const Error(ValidationFailure('Missing document.')));
    }
    final why = reason.trim();
    if (why.length < minimumReasonLength) {
      return Future.value(const Error(
        ValidationFailure('Say why it is being withdrawn.'),
      ));
    }
    return _repository.archiveDocument(documentId: documentId, reason: why);
  }
}
