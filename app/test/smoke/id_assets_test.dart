import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:logicclass/core/storage/upload_repository.dart';
import 'package:logicclass/core/theme/app_theme.dart';
import 'package:logicclass/demo/demo_overrides.dart';
import 'package:logicclass/demo/demo_store.dart';
import 'package:logicclass/features/admin_portal/presentation/controllers/admin_controller.dart';
import 'package:logicclass/features/qr_attendance/presentation/screens/e_id_screen.dart';
import 'package:logicclass/features/registrar_portal/presentation/controllers/registrar_controller.dart';

/// A photo and a signature are the two things that make an ID card an ID
/// card rather than a printed name. Both are uploaded somewhere other than
/// where they are used, so these tests follow them the whole way.
void main() {
  late ProviderContainer container;

  ProviderContainer signedInAs(String email) {
    final c = ProviderContainer(overrides: demoOverrides());
    addTearDown(c.dispose);
    c.read(demoAuthRepositoryProvider).signInAs(
          DemoStore.demoAccounts.firstWhere((a) => a.email == email),
        );
    return c;
  }

  group('student photo', () {
    setUp(() => container = signedInAs('registrar@demo.ph'));

    test('lands on the student record', () async {
      final store = container.read(demoStoreProvider);
      final student = store.students.value.first;
      expect(student.photoUrl, isNull, reason: 'the demo starts with no photos');

      final ok = await container
          .read(registrarActionControllerProvider.notifier)
          .setStudentPhoto(studentId: student.id, photoUrl: 'https://example.test/face.png');

      expect(ok, isTrue);
      final after = store.students.value.firstWhere((s) => s.id == student.id);
      expect(after.photoUrl, 'https://example.test/face.png');
    });

    test('setting a photo changes nothing else on the record', () async {
      final store = container.read(demoStoreProvider);
      final before = store.students.value.first;

      await container
          .read(registrarActionControllerProvider.notifier)
          .setStudentPhoto(studentId: before.id, photoUrl: 'https://example.test/face.png');

      final after = store.students.value.firstWhere((s) => s.id == before.id);
      expect(after.gradeLevel, before.gradeLevel);
      expect(after.section, before.section);
      expect(after.balance, before.balance);
      expect(after.status, before.status);
      expect(after.birthDate, before.birthDate);
    });

    test('an empty url is refused before it reaches the record', () async {
      final store = container.read(demoStoreProvider);
      final student = store.students.value.first;

      final ok = await container
          .read(registrarActionControllerProvider.notifier)
          .setStudentPhoto(studentId: student.id, photoUrl: '   ');

      expect(ok, isFalse);
      final after = store.students.value.firstWhere((s) => s.id == student.id);
      expect(after.photoUrl, isNull);
    });

    test('the uploader offers a student-photo folder of its own', () {
      // Not filed under branding or coursework: storage.rules scopes on
      // the folder, and a student's face is not a school asset.
      expect(UploadFolder.studentPhotos.folder, 'student-photos');
    });
  });

  group('signatures', () {
    setUp(() => container = signedInAs('admin@demo.ph'));

    test('the demo school ships with both, so a card shows what one looks like', () {
      final branding = container.read(demoStoreProvider).branding.value;
      expect(branding.hasPrincipalSignature, isTrue);
      expect(branding.hasDirectorSignature, isTrue);
    });

    test('uploading one leaves the other alone', () async {
      final store = container.read(demoStoreProvider);
      final directorBefore = store.branding.value.directorSignatureUrl;

      await container.read(adminActionControllerProvider.notifier).updateBranding(
            principalSignatureUrl: 'https://example.test/new-principal.png',
          );

      final after = store.branding.value;
      expect(after.principalSignatureUrl, 'https://example.test/new-principal.png');
      expect(after.directorSignatureUrl, directorBefore,
          reason: 'saving one signatory must not clear the other');
    });

    test('saving the names does not wipe the signatures', () async {
      // The Save button sends only the text fields. A non-merging write
      // would silently strip both scans off every future ID card.
      final store = container.read(demoStoreProvider);
      final before = store.branding.value.principalSignatureUrl;

      await container.read(adminActionControllerProvider.notifier).updateBranding(
            principalName: 'Ramon Salazar Jr.',
            directorName: 'Corazon Buenaventura',
            schoolYear: '2030-2031',
          );

      final after = store.branding.value;
      expect(after.principalName, 'Ramon Salazar Jr.');
      expect(after.principalSignatureUrl, before);
      expect(after.hasDirectorSignature, isTrue);
    });
  });

  group('the ID card', () {
    testWidgets('renders for a student without throwing, signatures and all',
        (tester) async {
      tester.view.physicalSize = const Size(390 * 3, 844 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      final c = signedInAs('student@demo.ph');
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: MaterialApp(theme: AppTheme.light(), home: const EIdScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      // Both signatory lines are on the card, whether or not the images
      // resolve in a test binding.
      expect(find.text('PRINCIPAL'), findsWidgets);
      expect(find.text('DIRECTOR'), findsWidgets);
      expect(find.text('Ramon Salazar'), findsWidgets);
    });
  });
}
