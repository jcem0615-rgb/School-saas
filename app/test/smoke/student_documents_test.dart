import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logicclass/core/constants/user_roles.dart';
import 'package:logicclass/demo/demo_overrides.dart';
import 'package:logicclass/demo/demo_store.dart';
import 'package:logicclass/features/documents/domain/entities/student_document.dart';
import 'package:logicclass/features/documents/presentation/controllers/documents_controller.dart';
import 'package:logicclass/features/documents/presentation/screens/student_documents_screen.dart';

/// The student folder, end to end on the demo repositories.
///
/// The folder is half of a pair: `documentReleases` says a document left
/// the office, and this says what the document was. The tests that matter
/// most here are the ones about that join and about withdrawal, because
/// those are the two properties a school is actually answerable for.
void main() {
  /// A small real PDF, so what is filed is a file rather than a string.
  final somePdf = Uint8List.fromList(utf8.encode('%PDF-1.4\nnot a real document\n'));

  Future<ProviderContainer> signedInAs(UserRole role) async {
    final container = ProviderContainer(overrides: demoOverrides());
    addTearDown(container.dispose);
    container.read(demoAuthRepositoryProvider).signInAs(
          DemoStore.demoAccounts.firstWhere((a) => a.role == role),
        );
    // Sign-in has to settle before the controller is read: the demo
    // repositories watch authStateProvider, so the emission rebuilds the
    // autoDispose controller underneath a caller that read it too early.
    await Future<void>.delayed(const Duration(milliseconds: 100));
    final sub = container.listen(documentsActionControllerProvider, (_, __) {});
    addTearDown(sub.close);
    return container;
  }

  group('filing', () {
    test('a scanned document lands in the student folder', () async {
      final container = await signedInAs(UserRole.registrar);
      final store = container.read(demoStoreProvider);
      final before = store.studentDocuments.value.length;

      final ok = await container
          .read(documentsActionControllerProvider.notifier)
          .fileScannedDocument(
            studentId: 'stu_002',
            studentName: 'Miguel Torres',
            kind: DocumentKind.form137Received,
            title: 'Form 137 - Bacoor NHS',
            fileName: 'f137.pdf',
            bytes: somePdf,
            contentType: 'application/pdf',
            note: 'Received by courier.',
          );

      expect(ok, isTrue);
      expect(store.studentDocuments.value, hasLength(before + 1));

      final filed = store.studentDocuments.value.first;
      expect(filed.studentId, 'stu_002');
      expect(filed.kind, DocumentKind.form137Received);
      expect(filed.title, 'Form 137 - Bacoor NHS');
      expect(filed.note, 'Received by courier.');
      expect(filed.origin, DocumentOrigin.received);
      expect(filed.sizeBytes, somePdf.lengthInBytes);
      // Stamped from the signed-in user, never from the form: an entry
      // naming somebody else as the filer puts a colleague's name on a
      // decision they did not make.
      expect(filed.filedByName, isNotEmpty);
      expect(filed.url, startsWith('data:application/pdf'),
          reason: 'demo mode never touches a bucket');
    });

    test('a file Storage would refuse never gets uploaded', () async {
      final container = await signedInAs(UserRole.registrar);
      final store = container.read(demoStoreProvider);
      final before = store.studentDocuments.value.length;

      final ok = await container
          .read(documentsActionControllerProvider.notifier)
          .fileScannedDocument(
            studentId: 'stu_002',
            studentName: 'Miguel Torres',
            kind: DocumentKind.other,
            fileName: 'records.zip',
            bytes: somePdf,
            contentType: 'application/zip',
          );

      expect(ok, isFalse);
      expect(store.studentDocuments.value, hasLength(before));
    });

    test('a copy of an issued document is pinned to its release', () async {
      // The join that makes the append-only release log reproducible:
      // without it the school can say a TOR left the office in March and
      // cannot show what was on it.
      final container = await signedInAs(UserRole.registrar);
      final store = container.read(demoStoreProvider);

      final ok = await container
          .read(documentsActionControllerProvider.notifier)
          .fileIssuedCopy(
            studentId: 'stu_002',
            studentName: 'Miguel Torres',
            releaseId: 'rel_001',
            title: 'Transcript of Records - TOR-S-2026-000002-20260312',
            fileName: 'tor.pdf',
            bytes: somePdf,
          );

      expect(ok, isTrue);
      final copy = store.studentDocuments.value.first;
      expect(copy.origin, DocumentOrigin.issued);
      expect(copy.kind, DocumentKind.issuedCopy);
      expect(copy.releaseId, 'rel_001');
      expect(copy.isIssuedCopy, isTrue);
    });

    test('the seeded folder already shows the pair', () async {
      // Andrea's released Form 137 and the copy of it. A demo that seeded
      // only the log would show half the feature.
      final container = await signedInAs(UserRole.registrar);
      final store = container.read(demoStoreProvider);

      final release = store.documentReleases.value.firstWhere((r) => r.id == 'rel_001');
      final copy = store.studentDocuments.value
          .firstWhere((d) => d.releaseId == 'rel_001');

      expect(copy.studentId, release.studentId);
      expect(copy.origin, DocumentOrigin.issued);
    });
  });

  group('withdrawing', () {
    test('archives rather than removes, and keeps the reason', () async {
      final container = await signedInAs(UserRole.registrar);
      final store = container.read(demoStoreProvider);
      final before = store.studentDocuments.value.length;

      final ok = await container
          .read(documentsActionControllerProvider.notifier)
          .archiveDocument(
            documentId: 'doc_002',
            reason: 'Superseded by the corrected PSA copy.',
          );

      expect(ok, isTrue);
      // Still there. A folder that can be emptied answers nothing.
      expect(store.studentDocuments.value, hasLength(before));

      final withdrawn =
          store.studentDocuments.value.firstWhere((d) => d.id == 'doc_002');
      expect(withdrawn.isArchived, isTrue);
      expect(withdrawn.archiveReason, 'Superseded by the corrected PSA copy.');
      expect(withdrawn.archivedByName, isNotEmpty);
      expect(withdrawn.url, isNotEmpty, reason: 'the file itself is not dropped');
    });

    test('an empty reason is refused', () async {
      final container = await signedInAs(UserRole.registrar);
      final store = container.read(demoStoreProvider);

      final ok = await container
          .read(documentsActionControllerProvider.notifier)
          .archiveDocument(documentId: 'doc_002', reason: '   ');

      expect(ok, isFalse);
      expect(
        store.studentDocuments.value.firstWhere((d) => d.id == 'doc_002').isArchived,
        isFalse,
      );
    });

    test('a document that is not there is said so, not silently ignored', () async {
      final container = await signedInAs(UserRole.registrar);
      final ok = await container
          .read(documentsActionControllerProvider.notifier)
          .archiveDocument(documentId: 'doc_nonexistent', reason: 'Filed in error.');

      expect(ok, isFalse);
    });
  });

  group('the folder summary', () {
    test('counts what is on file, not what was', () async {
      final container = await signedInAs(UserRole.registrar);
      final sub = container.listen(studentDocumentsProvider('stu_001'), (_, __) {});
      addTearDown(sub.close);
      await Future<void>.delayed(const Duration(milliseconds: 200));

      final summary = container.read(folderSummaryProvider('stu_001'));
      // Juan is seeded with a birth certificate on file and a withdrawn
      // good-moral certificate.
      expect(summary.onFile, 1);
      expect(summary.archived, 1);
      expect(summary.holds(DocumentKind.birthCertificate), isTrue);
      expect(summary.holds(DocumentKind.goodMoral), isFalse,
          reason: 'a withdrawn paper is not one the school holds');
    });
  });

  group('the screen', () {
    /// Everything runs inside [WidgetTester.runAsync]: the demo
    /// repositories await real delays to feel like a network, and a
    /// widget test's clock is fake, so awaiting one outside runAsync is a
    /// test that hangs rather than one that fails.
    Future<ProviderContainer> pump(
      WidgetTester tester, {
      required UserRole role,
      required String studentId,
      required String studentName,
      bool readOnly = false,
    }) async {
      late ProviderContainer container;
      await tester.runAsync(() async {
        container = await signedInAs(role);
      });
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: StudentDocumentsScreen(
              studentId: studentId,
              studentName: studentName,
              readOnly: readOnly,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return container;
    }

    testWidgets('the registrar can file, the family cannot', (tester) async {
      await pump(
        tester,
        role: UserRole.registrar,
        studentId: 'stu_001',
        studentName: 'Juan Dela Cruz',
      );
      expect(find.text('File a document'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await pump(
        tester,
        role: UserRole.parent,
        studentId: 'stu_001',
        studentName: 'Juan Dela Cruz',
        readOnly: true,
      );
      expect(find.text('File a document'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('withdrawn papers are hidden until asked for', (tester) async {
      // They are history. A folder that opens on everything it ever held
      // buries what it holds now, which is the question being asked nine
      // times out of ten.
      await pump(
        tester,
        role: UserRole.registrar,
        studentId: 'stu_001',
        studentName: 'Juan Dela Cruz',
      );

      expect(find.text('PSA Birth Certificate'), findsOneWidget);
      expect(find.text('Good Moral - Bacoor Elementary'), findsNothing);

      await tester.tap(find.text('Show 1 withdrawn'));
      await tester.pumpAndSettle();

      expect(find.text('Good Moral - Bacoor Elementary'), findsOneWidget);
      expect(find.textContaining('Superseded by the signed copy'), findsOneWidget);
    });

    testWidgets('an empty folder says so rather than showing nothing',
        (tester) async {
      await pump(
        tester,
        role: UserRole.registrar,
        studentId: 'stu_with_no_papers',
        studentName: 'Nobody At All',
      );

      expect(find.text('Nothing on file yet'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
