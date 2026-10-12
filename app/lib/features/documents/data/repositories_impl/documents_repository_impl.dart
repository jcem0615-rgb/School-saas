import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/errors/result.dart';
import '../../domain/entities/student_document.dart';
import '../../domain/repositories/documents_repository.dart';
import '../datasources/documents_remote_datasource.dart';

class DocumentsRepositoryImpl implements DocumentsRepository {
  final DocumentsRemoteDataSource _remote;
  const DocumentsRepositoryImpl(this._remote);

  @override
  Stream<List<StudentDocument>> watchStudentDocuments(String studentId) =>
      _remote.watchStudentDocuments(studentId);

  @override
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
  }) async {
    try {
      await _remote.fileDocument(
        studentId: studentId,
        studentName: studentName,
        kind: kind,
        origin: origin,
        title: title,
        fileName: fileName,
        url: url,
        contentType: contentType,
        sizeBytes: sizeBytes,
        note: note,
        releaseId: releaseId,
      );
      return const Success(null);
    } on FirebaseException catch (e) {
      // The two refusals a registrar can actually hit: a division they do
      // not cover, and a role that may read a folder but not add to one.
      // Saying which is the difference between a fixable message and
      // "something went wrong".
      if (e.code == 'permission-denied') {
        return const Error(PermissionFailure(
          'This account cannot file documents for that student. Filing is for '
          'the Registrar and Admin, within their own division.',
        ));
      }
      return Error(ServerFailure(e.message ?? 'The document could not be filed.'));
    } catch (_) {
      return const Error(UnknownFailure('The document could not be filed.'));
    }
  }

  @override
  Future<Result<void>> archiveDocument({
    required String documentId,
    required String reason,
  }) async {
    try {
      await _remote.archiveDocument(documentId: documentId, reason: reason);
      return const Success(null);
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        return const Error(PermissionFailure(
          'This account cannot withdraw a document from a folder.',
        ));
      }
      if (e.code == 'not-found') {
        // Somebody else archived it while this screen was open, or it
        // never existed. Either way the folder on screen is stale.
        return const Error(ServerFailure(
          'That document is no longer in the folder.',
        ));
      }
      return Error(ServerFailure(e.message ?? 'The document could not be withdrawn.'));
    } catch (_) {
      return const Error(UnknownFailure('The document could not be withdrawn.'));
    }
  }
}
