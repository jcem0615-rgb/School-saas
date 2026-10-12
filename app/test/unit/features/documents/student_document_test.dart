import 'package:flutter_test/flutter_test.dart';
import 'package:logicclass/core/errors/failures.dart';
import 'package:logicclass/core/errors/result.dart';
import 'package:logicclass/features/documents/domain/entities/student_document.dart';
import 'package:logicclass/features/documents/domain/repositories/documents_repository.dart';
import 'package:logicclass/features/documents/domain/usecases/document_usecases.dart';

/// Records what the repository was asked to do, so the tests can check
/// what the use case passed on rather than only whether it refused.
class _SpyRepository implements DocumentsRepository {
  final List<Map<String, Object?>> filed = [];
  final List<Map<String, Object?>> archived = [];

  @override
  Stream<List<StudentDocument>> watchStudentDocuments(String studentId) =>
      const Stream.empty();

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
    filed.add({
      'studentId': studentId,
      'kind': kind,
      'origin': origin,
      'title': title,
      'fileName': fileName,
      'url': url,
      'contentType': contentType,
      'sizeBytes': sizeBytes,
      'note': note,
      'releaseId': releaseId,
    });
    return const Success(null);
  }

  @override
  Future<Result<void>> archiveDocument({
    required String documentId,
    required String reason,
  }) async {
    archived.add({'documentId': documentId, 'reason': reason});
    return const Success(null);
  }
}

StudentDocument _doc({
  String id = 'doc_1',
  DocumentKind kind = DocumentKind.birthCertificate,
  int sizeBytes = 2048,
  bool archived = false,
}) =>
    StudentDocument(
      id: id,
      studentId: 'stu_001',
      studentName: 'Juan Dela Cruz',
      kind: kind,
      origin: DocumentOrigin.received,
      title: kind.displayLabel,
      fileName: 'scan.pdf',
      url: 'https://example.test/scan.pdf',
      contentType: 'application/pdf',
      sizeBytes: sizeBytes,
      filedByName: 'Rosario Aguilar',
      filedAt: DateTime(2026, 3, 2),
      archivedAt: archived ? DateTime(2026, 4, 1) : null,
      archivedByName: archived ? 'Rosario Aguilar' : null,
      archiveReason: archived ? 'Superseded.' : null,
    );

void main() {
  group('what may go in a folder', () {
    test('PDFs and photos, and nothing else', () {
      // The same pair storage.rules accepts. Checked here too so an
      // unsupported file is refused with a sentence rather than coming
      // back as a permission error that reads like the user's fault.
      expect(isFilableContentType('application/pdf'), isTrue);
      expect(isFilableContentType('image/jpeg'), isTrue);
      expect(isFilableContentType('IMAGE/PNG'), isTrue);
      expect(isFilableContentType('application/zip'), isFalse);
      expect(isFilableContentType('text/html'), isFalse);
      expect(isFilableContentType(''), isFalse);
    });

    test('a copy of an issued document cannot be chosen by hand', () {
      // It is written by the release flow and carries a releaseId. One
      // filed by hand would be a copy of a release that never happened.
      expect(DocumentKind.fileable, isNot(contains(DocumentKind.issuedCopy)));
      expect(DocumentKind.fileable, contains(DocumentKind.birthCertificate));
    });

    test('an unknown kind reads as Other rather than throwing', () {
      // A folder that refuses to open because one row has a kind this
      // build has not heard of is worse than a row labelled "Other".
      expect(DocumentKind.fromString('form_137_received'),
          DocumentKind.form137Received);
      expect(DocumentKind.fromString('something_from_the_future'),
          DocumentKind.other);
      expect(DocumentOrigin.fromString('issued'), DocumentOrigin.issued);
      expect(DocumentOrigin.fromString(''), DocumentOrigin.received);
    });
  });

  group('filing', () {
    test('passes a scanned document through', () async {
      final repo = _SpyRepository();
      final result = await FileStudentDocumentUseCase(repo)(
        studentId: 'stu_001',
        studentName: 'Juan Dela Cruz',
        kind: DocumentKind.birthCertificate,
        fileName: '  psa.pdf ',
        url: ' https://example.test/psa.pdf ',
        contentType: 'application/pdf',
        sizeBytes: 2048,
        note: '  Original sighted. ',
      );

      expect(result.isSuccess, isTrue);
      expect(repo.filed, hasLength(1));
      expect(repo.filed.single['fileName'], 'psa.pdf');
      expect(repo.filed.single['url'], 'https://example.test/psa.pdf');
      expect(repo.filed.single['note'], 'Original sighted.');
      expect(repo.filed.single['origin'], DocumentOrigin.received);
    });

    test('a blank title becomes the kind, rather than being refused', () async {
      // The kind already says what the paper is. Refusing somebody over a
      // title would be making them type a word the row already knows.
      final repo = _SpyRepository();
      await FileStudentDocumentUseCase(repo)(
        studentId: 'stu_001',
        studentName: 'Juan Dela Cruz',
        kind: DocumentKind.goodMoral,
        title: '   ',
        fileName: 'gm.pdf',
        url: 'https://example.test/gm.pdf',
        contentType: 'application/pdf',
        sizeBytes: 100,
      );

      expect(repo.filed.single['title'], DocumentKind.goodMoral.displayLabel);
    });

    test('a blank note is stored as nothing, not as an empty string', () async {
      final repo = _SpyRepository();
      await FileStudentDocumentUseCase(repo)(
        studentId: 'stu_001',
        studentName: 'Juan Dela Cruz',
        kind: DocumentKind.goodMoral,
        fileName: 'gm.pdf',
        url: 'https://example.test/gm.pdf',
        contentType: 'application/pdf',
        sizeBytes: 100,
        note: '   ',
      );

      expect(repo.filed.single['note'], isNull);
    });

    test('a row with no file behind it is refused', () async {
      // Worse than an empty folder: it says the school holds a document
      // it does not hold, and somebody will rely on that at enrolment.
      final repo = _SpyRepository();
      for (final broken in [
        {'fileName': '', 'url': 'https://example.test/x.pdf', 'size': 10},
        {'fileName': 'x.pdf', 'url': '   ', 'size': 10},
      ]) {
        final result = await FileStudentDocumentUseCase(repo)(
          studentId: 'stu_001',
          studentName: 'Juan Dela Cruz',
          kind: DocumentKind.other,
          fileName: broken['fileName']! as String,
          url: broken['url']! as String,
          contentType: 'application/pdf',
          sizeBytes: broken['size']! as int,
        );
        expect(result.failureOrNull, isA<ValidationFailure>());
      }
      expect(repo.filed, isEmpty);
    });

    test('a zero-byte file is refused', () async {
      // A failed upload that reported success. Filing it would put a row
      // in the folder whose file opens to nothing.
      final repo = _SpyRepository();
      final result = await FileStudentDocumentUseCase(repo)(
        studentId: 'stu_001',
        studentName: 'Juan Dela Cruz',
        kind: DocumentKind.other,
        fileName: 'empty.pdf',
        url: 'https://example.test/empty.pdf',
        contentType: 'application/pdf',
        sizeBytes: 0,
      );

      expect(result.failureOrNull, isA<ValidationFailure>());
      expect(repo.filed, isEmpty);
    });

    test('a file type Storage would reject never leaves the device', () async {
      final repo = _SpyRepository();
      final result = await FileStudentDocumentUseCase(repo)(
        studentId: 'stu_001',
        studentName: 'Juan Dela Cruz',
        kind: DocumentKind.other,
        fileName: 'records.zip',
        url: 'https://example.test/records.zip',
        contentType: 'application/zip',
        sizeBytes: 4096,
      );

      expect(result.failureOrNull, isA<ValidationFailure>());
      expect(repo.filed, isEmpty);
    });

    test('an issued copy must name the release it came from', () async {
      // The join that makes the append-only release log mean something.
      // Without it the folder and the log are two lists nobody can put
      // back together.
      final repo = _SpyRepository();
      final orphan = await FileStudentDocumentUseCase(repo)(
        studentId: 'stu_001',
        studentName: 'Juan Dela Cruz',
        kind: DocumentKind.issuedCopy,
        origin: DocumentOrigin.issued,
        fileName: 'tor.pdf',
        url: 'https://example.test/tor.pdf',
        contentType: 'application/pdf',
        sizeBytes: 2048,
      );
      expect(orphan.failureOrNull, isA<ValidationFailure>());

      final pinned = await FileStudentDocumentUseCase(repo)(
        studentId: 'stu_001',
        studentName: 'Juan Dela Cruz',
        kind: DocumentKind.issuedCopy,
        origin: DocumentOrigin.issued,
        releaseId: 'rel_001',
        fileName: 'tor.pdf',
        url: 'https://example.test/tor.pdf',
        contentType: 'application/pdf',
        sizeBytes: 2048,
      );
      expect(pinned.isSuccess, isTrue);
      expect(repo.filed.single['releaseId'], 'rel_001');
    });

    test('a received document cannot claim to be an issued copy', () async {
      final repo = _SpyRepository();
      final result = await FileStudentDocumentUseCase(repo)(
        studentId: 'stu_001',
        studentName: 'Juan Dela Cruz',
        kind: DocumentKind.issuedCopy,
        fileName: 'tor.pdf',
        url: 'https://example.test/tor.pdf',
        contentType: 'application/pdf',
        sizeBytes: 2048,
      );

      expect(result.failureOrNull, isA<ValidationFailure>());
      expect(repo.filed, isEmpty);
    });
  });

  group('withdrawing', () {
    test('needs a reason', () async {
      // An archive with no reason is a delete with extra steps: six
      // months later nobody can say whether the paper was superseded or
      // filed under the wrong child.
      final repo = _SpyRepository();
      for (final reason in ['', '   ', 'x', 'ab']) {
        final result =
            await ArchiveStudentDocumentUseCase(repo)(documentId: 'doc_1', reason: reason);
        expect(result.failureOrNull, isA<ValidationFailure>(),
            reason: 'reason "$reason" should be refused');
      }
      expect(repo.archived, isEmpty);
    });

    test('records the reason, trimmed', () async {
      final repo = _SpyRepository();
      final result = await ArchiveStudentDocumentUseCase(repo)(
        documentId: 'doc_1',
        reason: '  Superseded by the corrected PSA copy.  ',
      );

      expect(result.isSuccess, isTrue);
      expect(repo.archived.single['reason'], 'Superseded by the corrected PSA copy.');
    });
  });

  group('what the folder says about itself', () {
    test('counts only what is still in it', () {
      // An archived Form 137 is not a Form 137 the school holds, and a
      // summary that said otherwise would answer "do we have it yet"
      // wrongly -- which is the whole question.
      final summary = FolderSummary.of([
        _doc(id: 'a', kind: DocumentKind.birthCertificate),
        _doc(id: 'b', kind: DocumentKind.form137Received, archived: true),
        _doc(id: 'c', kind: DocumentKind.goodMoral),
      ]);

      expect(summary.onFile, 2);
      expect(summary.archived, 1);
      expect(summary.holds(DocumentKind.birthCertificate), isTrue);
      expect(summary.holds(DocumentKind.form137Received), isFalse);
      expect(summary.isEmpty, isFalse);
    });

    test('an empty folder says so', () {
      final summary = FolderSummary.of(const []);
      expect(summary.isEmpty, isTrue);
      expect(summary.archived, 0);
    });
  });

  group('the row on the list', () {
    test('sizes read as a person would say them', () {
      // The point is "is this the scan or the thumbnail", not the byte
      // count.
      expect(_doc(sizeBytes: 512).sizeLabel, '512 B');
      expect(_doc(sizeBytes: 2048).sizeLabel, '2 KB');
      expect(_doc(sizeBytes: 1024 * 1024 + 512 * 1024).sizeLabel, '1.5 MB');
    });

    test('archiving keeps everything else about the row', () {
      // Which student, which file and when it was filed are what make it
      // evidence. Withdrawing a paper does not rewrite any of that.
      final before = _doc();
      final after = before.archived(
        at: DateTime(2026, 5, 4),
        byName: 'Rosario Aguilar',
        reason: 'Superseded.',
      );

      expect(after.isArchived, isTrue);
      expect(after.archiveReason, 'Superseded.');
      expect(after.id, before.id);
      expect(after.studentId, before.studentId);
      expect(after.url, before.url);
      expect(after.filedAt, before.filedAt);
      expect(before.isArchived, isFalse, reason: 'the original is untouched');
    });
  });
}
