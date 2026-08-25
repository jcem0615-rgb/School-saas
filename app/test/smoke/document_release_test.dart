import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:logicclass/core/constants/user_roles.dart';
import 'package:logicclass/core/storage/pdf_image.dart';
import 'package:logicclass/demo/demo_overrides.dart';
import 'package:logicclass/demo/demo_store.dart';
import 'package:logicclass/features/admin_portal/domain/entities/school_branding.dart';
import 'package:logicclass/features/registrar_portal/domain/entities/document_release.dart';
import 'package:logicclass/features/registrar_portal/presentation/controllers/registrar_controller.dart';
import 'package:logicclass/features/registrar_portal/presentation/documents/academic_record_pdf.dart';

/// Two things have to hold for a release log to be worth keeping: it has
/// to record what actually happened, and it has to record it every time.
/// These check the write, what it refuses, and that the document it
/// prints alongside is a real PDF rather than an empty file.
void main() {
  Future<ProviderContainer> signedInRegistrar() async {
    final container = ProviderContainer(overrides: demoOverrides());
    addTearDown(container.dispose);
    container.read(demoAuthRepositoryProvider).signInAs(
          DemoStore.demoAccounts.firstWhere((a) => a.role == UserRole.registrar),
        );
    // Sign-in has to settle before the controller is read: the demo
    // repositories watch authStateProvider, so the emission rebuilds the
    // autoDispose controller underneath a caller that read it too early.
    await Future<void>.delayed(const Duration(milliseconds: 100));
    final sub = container.listen(registrarActionControllerProvider, (_, __) {});
    addTearDown(sub.close);
    return container;
  }

  test('releasing a document writes it to the history', () async {
    final container = await signedInRegistrar();
    final store = container.read(demoStoreProvider);
    final before = store.documentReleases.value.length;

    final ok = await container
        .read(registrarActionControllerProvider.notifier)
        .recordDocumentRelease(
          studentId: 'stu_001',
          studentName: 'Miguel Torres',
          document: SchoolDocument.transcriptOfRecords,
          copies: 2,
          purpose: 'College application',
          releasedToName: 'Elena Torres',
          releasedToRelation: 'Mother',
        );

    expect(ok, isTrue);
    expect(store.documentReleases.value, hasLength(before + 1));

    final logged = store.documentReleases.value.first;
    expect(logged.studentId, 'stu_001');
    expect(logged.document, SchoolDocument.transcriptOfRecords);
    expect(logged.copies, 2);
    expect(logged.purpose, 'College application');
    expect(logged.receivedByLabel, 'Elena Torres (Mother)');
    // Stamped from the signed-in user, never from the form: a log entry
    // naming somebody else as the releaser would be worse than no log.
    expect(logged.releasedByName, isNotEmpty);
  });

  test('a release with no purpose or no recipient is refused', () async {
    final container = await signedInRegistrar();
    final store = container.read(demoStoreProvider);
    final before = store.documentReleases.value.length;
    final controller = container.read(registrarActionControllerProvider.notifier);

    expect(
      await controller.recordDocumentRelease(
        studentId: 'stu_001',
        studentName: 'Miguel Torres',
        document: SchoolDocument.form137,
        copies: 1,
        purpose: '   ',
        releasedToName: 'Elena Torres',
      ),
      isFalse,
      reason: 'a release with no stated purpose answers nothing',
    );

    expect(
      await controller.recordDocumentRelease(
        studentId: 'stu_001',
        studentName: 'Miguel Torres',
        document: SchoolDocument.form137,
        copies: 1,
        purpose: 'Transfer',
        releasedToName: '  ',
      ),
      isFalse,
      reason: 'a release with nobody named answers nothing either',
    );

    expect(store.documentReleases.value, hasLength(before));
  });

  test('an implausible number of copies is refused', () async {
    final container = await signedInRegistrar();
    final controller = container.read(registrarActionControllerProvider.notifier);

    for (final copies in [0, -1, 300]) {
      expect(
        await controller.recordDocumentRelease(
          studentId: 'stu_001',
          studentName: 'Miguel Torres',
          document: SchoolDocument.form137,
          copies: copies,
          purpose: 'Transfer',
          releasedToName: 'Elena Torres',
        ),
        isFalse,
        reason: 'copies=$copies should be refused',
      );
    }
  });

  test('the history is per student, newest first', () async {
    final container = await signedInRegistrar();
    final controller = container.read(registrarActionControllerProvider.notifier);

    await controller.recordDocumentRelease(
      studentId: 'stu_001',
      studentName: 'Miguel Torres',
      document: SchoolDocument.form137,
      copies: 1,
      purpose: 'First',
      releasedToName: 'Elena Torres',
    );
    await controller.recordDocumentRelease(
      studentId: 'stu_001',
      studentName: 'Miguel Torres',
      document: SchoolDocument.transcriptOfRecords,
      copies: 1,
      purpose: 'Second',
      releasedToName: 'Elena Torres',
    );

    final mine = await container
        .read(documentReleasesStreamProvider('stu_001').future);
    expect(mine.map((r) => r.purpose).take(2), ['Second', 'First']);
    expect(mine.every((r) => r.studentId == 'stu_001'), isTrue);

    // The seeded release belongs to another student and must not appear
    // on this one's record.
    expect(mine.any((r) => r.id == 'rel_001'), isFalse);
  });

  test('the transcript renders as a real PDF carrying the student', () async {
    final container = await signedInRegistrar();
    final store = container.read(demoStoreProvider);
    final student = store.students.value.firstWhere((s) => s.id == 'stu_001');
    final grades = store.grades.value.where((g) => g.studentId == 'stu_001').toList();
    expect(grades, isNotEmpty, reason: 'seed precondition: this student has marks');

    final bytes = await AcademicRecordPdf.build(
      document: SchoolDocument.transcriptOfRecords,
      student: student,
      // Deliberately unbranded: a school that has not uploaded a logo or
      // a signature must still get a printable document, because the
      // registrar is standing at a counter when they find out.
      branding: SchoolBranding.empty,
      grades: grades,
      registrarName: 'Rosario Aguilar',
      purpose: 'College application',
      releasedToName: 'Elena Torres',
    );

    expect(bytes.length, greaterThan(1000));
    expect(
      String.fromCharCodes(bytes.take(5)),
      '%PDF-',
      reason: 'the bytes handed to the printer must be a PDF',
    );
  });

  test('a student with no marks still produces a document', () async {
    final container = await signedInRegistrar();
    final store = container.read(demoStoreProvider);
    final student = store.students.value.first;

    final bytes = await AcademicRecordPdf.build(
      document: SchoolDocument.form137,
      student: student,
      branding: SchoolBranding.empty,
      grades: const [],
      registrarName: 'Rosario Aguilar',
    );

    // Refusing to print would leave the office with nothing to hand
    // over; the sheet says the record is empty instead.
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
  });

  test('an uploaded signature loads from a data URI as well as a URL', () async {
    // The bug this pins: networkImage cannot fetch a data: URI, and it
    // fails silently by design here so that a missing logo never stops a
    // document printing. The result was a transcript and an ID card with
    // the signature line blank and no indication why -- in demo mode
    // always, and in a real deployment for anything uploaded before the
    // bucket is wired up.
    final store = ProviderContainer(overrides: demoOverrides()).read(demoStoreProvider);
    final url = store.branding.value.principalSignatureUrl;
    expect(url, isNotNull, reason: 'seed precondition: a signature is on file');
    expect(url, startsWith('data:'), reason: 'demo uploads are data URIs');

    expect(await pdfImage(url!), isNotNull);
    expect(await pdfImage(''), isNull);
    expect(await pdfImage('data:image/png;base64,not-base64-at-all'), isNull);
    // A URL that cannot be fetched degrades to nothing rather than
    // throwing out of the print.
    expect(await pdfImage('https://127.0.0.1:1/nope.png'), isNull);
  });

  test('the control number identifies the document, student and day', () {
    final container = ProviderContainer(overrides: demoOverrides());
    addTearDown(container.dispose);
    final student = container.read(demoStoreProvider).students.value.first;

    final control = AcademicRecordPdf.controlNumber(
      document: SchoolDocument.form137,
      student: student,
      on: DateTime(2026, 3, 7),
    );

    expect(control, 'F137-${student.studentNumber}-20260307');
  });
}
