import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/result.dart';
import '../../../../core/storage/upload_providers.dart';
import '../../../../core/storage/upload_repository.dart';
import '../../../auth/presentation/controllers/auth_controller.dart'
    show authStateProvider, firestoreProvider;
import '../../data/datasources/documents_remote_datasource.dart';
import '../../data/repositories_impl/documents_repository_impl.dart';
import '../../domain/entities/student_document.dart';
import '../../domain/repositories/documents_repository.dart';
import '../../domain/usecases/document_usecases.dart';

final documentsRemoteDataSourceProvider = Provider<DocumentsRemoteDataSource>((ref) {
  final user = ref.watch(authStateProvider).valueOrNull;
  if (user == null || user.schoolId == null) {
    throw StateError('DocumentsRemoteDataSource requires a signed-in, school-scoped user.');
  }
  return DocumentsRemoteDataSource(
    firestore: ref.watch(firestoreProvider),
    actingUser: ActingFiler(
      uid: user.uid,
      schoolId: user.schoolId!,
      name: user.fullName,
    ),
  );
});

final documentsRepositoryProvider = Provider<DocumentsRepository>((ref) {
  return DocumentsRepositoryImpl(ref.watch(documentsRemoteDataSourceProvider));
});

/// One student's folder.
///
/// Family-scoped so the registrar's screen and a parent's own view can be
/// open at once without one evicting the other.
final studentDocumentsProvider =
    StreamProvider.autoDispose.family<List<StudentDocument>, String>((ref, studentId) {
  return WatchStudentDocumentsUseCase(ref.watch(documentsRepositoryProvider))(studentId);
});

/// What the folder holds, for the line above the list.
final folderSummaryProvider =
    Provider.autoDispose.family<FolderSummary, String>((ref, studentId) {
  final documents = ref.watch(studentDocumentsProvider(studentId)).valueOrNull ??
      const <StudentDocument>[];
  return FolderSummary.of(documents);
});

final documentsActionControllerProvider =
    StateNotifierProvider.autoDispose<DocumentsActionController, AsyncValue<void>>((ref) {
  final repo = ref.watch(documentsRepositoryProvider);
  return DocumentsActionController(
    uploads: ref.watch(uploadRepositoryProvider),
    fileDocument: FileStudentDocumentUseCase(repo),
    archiveDocument: ArchiveStudentDocumentUseCase(repo),
  );
});

class DocumentsActionController extends StateNotifier<AsyncValue<void>> {
  final UploadRepository _uploads;
  final FileStudentDocumentUseCase _fileDocument;
  final ArchiveStudentDocumentUseCase _archiveDocument;

  DocumentsActionController({
    required UploadRepository uploads,
    required FileStudentDocumentUseCase fileDocument,
    required ArchiveStudentDocumentUseCase archiveDocument,
  })  : _uploads = uploads,
        _fileDocument = fileDocument,
        _archiveDocument = archiveDocument,
        super(const AsyncData(null));

  /// Uploads the scan, then records it.
  ///
  /// Two steps, and the order matters: an upload that succeeds and a
  /// write that fails leaves an orphaned file in the bucket, which costs
  /// a few kilobytes. The other order leaves a folder row pointing at
  /// nothing, which is a school believing it holds a document it does
  /// not hold.
  Future<bool> fileScannedDocument({
    required String studentId,
    required String studentName,
    required DocumentKind kind,
    required String fileName,
    required Uint8List bytes,
    required String contentType,
    String title = '',
    String? note,
  }) async {
    if (mounted) state = const AsyncLoading();

    // Refused before the bytes go over the wire. storage.rules would
    // reject it anyway, as a permission error that reads like the user's
    // fault rather than the file's.
    if (!isFilableContentType(contentType)) {
      if (mounted) {
        state = AsyncError(
          'Only PDFs and photos can go in a student folder.',
          StackTrace.current,
        );
      }
      return false;
    }

    final uploaded = await _uploads.upload(
      folder: UploadFolder.studentDocuments,
      fileName: fileName,
      bytes: bytes,
      contentType: contentType,
    );
    if (uploaded case Error(:final failure)) {
      if (mounted) state = AsyncError(failure.message, StackTrace.current);
      return false;
    }
    final file = (uploaded as Success<UploadedFile>).value;

    return _settle(await _fileDocument(
      studentId: studentId,
      studentName: studentName,
      kind: kind,
      title: title,
      fileName: file.fileName,
      url: file.url,
      contentType: contentType,
      sizeBytes: file.sizeBytes,
      note: note,
    ));
  }

  /// Files a copy of a document this school just issued.
  ///
  /// Called by the release screen with the PDF it has already built, so
  /// the copy on file is the same bytes that came out of the printer
  /// rather than a second render that could differ.
  Future<bool> fileIssuedCopy({
    required String studentId,
    required String studentName,
    required String releaseId,
    required String title,
    required String fileName,
    required Uint8List bytes,
  }) async {
    if (mounted) state = const AsyncLoading();
    final uploaded = await _uploads.upload(
      folder: UploadFolder.studentDocuments,
      fileName: fileName,
      bytes: bytes,
      contentType: 'application/pdf',
    );
    if (uploaded case Error(:final failure)) {
      if (mounted) state = AsyncError(failure.message, StackTrace.current);
      return false;
    }
    final file = (uploaded as Success<UploadedFile>).value;

    return _settle(await _fileDocument(
      studentId: studentId,
      studentName: studentName,
      kind: DocumentKind.issuedCopy,
      origin: DocumentOrigin.issued,
      releaseId: releaseId,
      title: title,
      fileName: file.fileName,
      url: file.url,
      contentType: 'application/pdf',
      sizeBytes: file.sizeBytes,
    ));
  }

  Future<bool> archiveDocument({
    required String documentId,
    required String reason,
  }) async {
    if (mounted) state = const AsyncLoading();
    return _settle(await _archiveDocument(documentId: documentId, reason: reason));
  }

  bool _settle(Result<void> result) => switch (result) {
        Success() => () {
            if (mounted) state = const AsyncData(null);
            return true;
          }(),
        Error(:final failure) => () {
            if (mounted) state = AsyncError(failure.message, StackTrace.current);
            return false;
          }(),
      };
}
