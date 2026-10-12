import '../../../../core/errors/result.dart';
import '../entities/student_document.dart';

/// The student's folder.
///
/// Reads are a stream because two people work this folder at once: a
/// registrar filing what a family just handed in while the adviser is
/// looking at the same student.
abstract class DocumentsRepository {
  /// Everything in one student's folder, newest first, archived rows
  /// included.
  ///
  /// Archived rows come back rather than being filtered server-side
  /// because "what used to be in here" is a question the office asks, and
  /// a query that could not answer it would need a second query that can.
  /// The screen hides them by default.
  Stream<List<StudentDocument>> watchStudentDocuments(String studentId);

  /// Records a paper that has already been uploaded.
  ///
  /// Uploading and recording are two steps on purpose -- the same split
  /// `setStudentPhoto` makes. The upload can succeed and the write fail,
  /// and a caller that conflated them would report a document filed that
  /// no record points at.
  Future<Result<void>> fileDocument({
    required String studentId,
    required String studentName,
    required DocumentKind kind,
    required DocumentOrigin origin,
    required String title,
    required String fileName,
    required String url,
    required String contentType,
    required int sizeBytes,
    String? note,
    String? releaseId,
  });

  /// Withdraws a paper from the folder, with the reason on the record.
  ///
  /// Never a delete. See [StudentDocument.archivedAt].
  Future<Result<void>> archiveDocument({
    required String documentId,
    required String reason,
  });
}
