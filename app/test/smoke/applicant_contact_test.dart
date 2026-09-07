import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:logicclass/core/constants/education_level.dart';
import 'package:logicclass/core/errors/result.dart';
import 'package:logicclass/core/theme/app_theme.dart';
import 'package:logicclass/demo/demo_overrides.dart';
import 'package:logicclass/demo/demo_store.dart';
import 'package:logicclass/features/admissions/domain/entities/applicant.dart';
import 'package:logicclass/features/admissions/domain/repositories/admissions_repository.dart';
import 'package:logicclass/features/admissions/presentation/controllers/admissions_controller.dart';
import 'package:logicclass/features/admissions/presentation/screens/applicant_detail_screen.dart';

/// Contact details through the admissions pipeline.
///
/// Two problems, and the second was one the student-record work created.
///
/// The guardian's mobile number was mandatory and unchecked, so "0"
/// satisfied it — and the only reason the field is mandatory at all is
/// that somebody can be rung back. The guardian's email was not checked
/// either, which mattered more than it looks: at enrolment it is copied
/// onto the student record, so admissions was the back door around the
/// validation on the student form and the student import.
///
/// And the applicant had no email or phone of their own. Once the student
/// record grew those two fields, admissions became the one path that
/// collected contact details for weeks and then wrote a student with
/// neither — a student who could not be given a portal account at all,
/// because the Registrar screen refuses to create one against an address
/// nobody wrote down.
void main() {
  Future<ProviderContainer> registrarContainer() async {
    final container = ProviderContainer(overrides: demoOverrides());
    container.read(demoAuthRepositoryProvider).signInAs(
          DemoStore.demoAccounts.firstWhere((a) => a.email == 'registrar@demo.ph'),
        );
    return container;
  }

  Future<SavedApplicant?> save(
    ProviderContainer container, {
    String guardianPhone = '09171234567',
    String? guardianEmail,
    String? email,
    String? phone,
  }) {
    return container.read(admissionsActionControllerProvider.notifier).saveApplicant(
          firstName: 'Bea',
          lastName: 'Marquez',
          educationLevel: EducationLevel.highSchool,
          gradeLevel: 'Grade 7',
          guardianName: 'Alma Marquez',
          guardianPhone: guardianPhone,
          guardianEmail: guardianEmail,
          email: email,
          phone: phone,
        );
  }

  group('what an enquiry will accept', () {
    test('a number that could never be rung is refused', () async {
      // The field was mandatory and unchecked, so "0" passed. A row with
      // "0" in it is exactly the row the mandatory check exists to
      // refuse, wearing a disguise.
      final container = await registrarContainer();
      addTearDown(container.dispose);

      for (final bad in ['0', '12', 'asdf', 'n/a']) {
        expect(await save(container, guardianPhone: bad), isNull, reason: bad);
      }
    });

    test('every shape a Philippine number is written in is accepted', () async {
      final container = await registrarContainer();
      addTearDown(container.dispose);

      for (final shape in ['09171234567', '+639171234567', '0917 123 4567']) {
        expect(await save(container, guardianPhone: shape), isNotNull, reason: shape);
      }
    });

    test('a guardian address that would reach a student record is refused', () async {
      // Admissions was the back door around the student form's checks.
      final container = await registrarContainer();
      addTearDown(container.dispose);

      expect(await save(container, guardianEmail: 'alma@gmailcom'), isNull);
      expect(await save(container, guardianEmail: 'alma@gmail.com'), isNotNull);
    });

    test('the applicant\'s own details are optional, and checked when given',
        () async {
      // A Grade 1 applicant has neither, which is why they are optional.
      final container = await registrarContainer();
      addTearDown(container.dispose);

      expect(await save(container), isNotNull);
      expect(await save(container, email: 'bea@gmailcom'), isNull);
      expect(await save(container, phone: '12'), isNull);
      expect(
        await save(container, email: 'bea@student.demo.ph', phone: '0918 555 0100'),
        isNotNull,
      );
    });
  });

  group('what enrolment carries across', () {
    test('the family\'s contact details land on the student record', () async {
      // The regression. Lian Reyes is the seeded Senior High applicant,
      // old enough to have her own email and number — and the school has
      // been holding both since the enquiry.
      final container = await registrarContainer();
      addTearDown(container.dispose);
      final store = container.read(demoStoreProvider);

      final lian = store.applicants.value.firstWhere((a) => a.id == 'app_003');
      expect(lian.email, 'lian.reyes@student.demo.ph');
      expect(lian.phone, '0918 555 0134');

      final repo = container.read(admissionsRepositoryProvider);
      // Straight to reserved, then enrolled: the pipeline itself is
      // covered elsewhere, and this test is about what survives the move.
      for (final stage in [
        AdmissionStage.examScheduled,
        AdmissionStage.examTaken,
        AdmissionStage.offered,
        AdmissionStage.reserved,
      ]) {
        await repo.advanceApplicant(
          applicantId: 'app_003',
          stage: stage,
          examScheduledFor: DateTime.now(),
          examScore: 88,
          examMaxScore: 100,
          reservationFee: 2000,
        );
      }

      final enrolled = await repo.enrolApplicant(
        applicantId: 'app_003',
        section: 'STEM 11-A',
        birthDate: DateTime(2009, 5, 2),
      );
      expect(enrolled, isA<Success<EnrolledApplicant>>());

      final student = store.students.value
          .firstWhere((s) => s.id == (enrolled as Success<EnrolledApplicant>).value.studentId);
      expect(student.email, 'lian.reyes@student.demo.ph');
      expect(student.phone, '0918 555 0134');
      expect(student.guardianContacts.single.email, 'nestor.reyes@gmail.com');

      // And the point of carrying them: this student can now be given a
      // portal account without the office going to find an address.
      expect(student.canProvisionAccount, isTrue);
    });

    test('an applicant who gave neither enrols as reachable by nobody', () async {
      // A Grade 7 enquiry. The record must read as "none on file" rather
      // than looking contactable, which is what the provisioning gate and
      // the roster screens both check.
      final container = await registrarContainer();
      addTearDown(container.dispose);
      final store = container.read(demoStoreProvider);
      final repo = container.read(admissionsRepositoryProvider);

      final bea = store.applicants.value.firstWhere((a) => a.id == 'app_001');
      expect(bea.email, isNull);

      for (final stage in [
        AdmissionStage.applied,
        AdmissionStage.examScheduled,
        AdmissionStage.examTaken,
        AdmissionStage.offered,
        AdmissionStage.reserved,
      ]) {
        await repo.advanceApplicant(
          applicantId: 'app_001',
          stage: stage,
          examScheduledFor: DateTime.now(),
          examScore: 75,
          examMaxScore: 100,
          reservationFee: 1000,
        );
      }
      final enrolled = await repo.enrolApplicant(
        applicantId: 'app_001',
        section: 'Grade 7 - Mabini',
        birthDate: DateTime(2013, 4, 11),
      );

      final student = store.students.value
          .firstWhere((s) => s.id == (enrolled as Success<EnrolledApplicant>).value.studentId);
      expect(student.email, isNull);
      expect(student.phone, isNull);
      expect(student.canProvisionAccount, isFalse);
      // The guardian is still the way to reach this family.
      expect(student.reachablePhone, isNotNull);
    });
  });

  group('the enquiry screen', () {
    testWidgets('asks for the applicant\'s own email and mobile', (tester) async {
      tester.view.physicalSize = const Size(390 * 3, 2000 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      final container = await registrarContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const ApplicantDetailScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('The applicant themselves'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      expect(find.text('Their email (optional)'), findsOneWidget);
      expect(find.text('Their mobile number (optional)'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
