import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:logicclass/core/constants/user_roles.dart';
import 'package:logicclass/core/theme/app_theme.dart';
import 'package:logicclass/demo/demo_overrides.dart';
import 'package:logicclass/demo/demo_store.dart';
import 'package:logicclass/features/admissions/domain/entities/applicant.dart';
import 'package:logicclass/features/admissions/presentation/controllers/admissions_controller.dart';
import 'package:logicclass/features/admissions/presentation/screens/admissions_screen.dart';

/// The admissions pipeline, driven the way an office would.
///
/// The domain tests cover the funnel arithmetic and the legal moves.
/// What is worth driving here is the part a unit test cannot see: that
/// the office is shown who to ring, that a family cannot be jumped
/// forward through stages, and that enrolling twice produces one student
/// rather than twins.
void main() {
  Future<(ProviderContainer, DemoStore)> pumpScreen(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final container = ProviderContainer(overrides: demoOverrides());
    addTearDown(container.dispose);
    container.read(demoAuthRepositoryProvider).signInAs(
          DemoStore.demoAccounts.firstWhere((a) => a.role == UserRole.registrar),
        );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(theme: AppTheme.light(), home: const AdmissionsScreen()),
      ),
    );
    await tester.pumpAndSettle();
    return (container, container.read(demoStoreProvider));
  }

  testWidgets('the pipeline opens on the funnel and who to ring', (tester) async {
    await pumpScreen(tester);

    expect(tester.takeException(), isNull);
    // The number the office acts on. A screen that opened on the list
    // would bury it.
    expect(find.textContaining('to ring back'), findsOneWidget);
    expect(find.textContaining('enrol'), findsWidgets);
  });

  testWidgets('the two endings are counted apart', (tester) async {
    await pumpScreen(tester);
    // "We turned them down" and "they went elsewhere" are different
    // problems and only one of them is the school's doing.
    expect(find.textContaining('not accepted'), findsOneWidget);
    expect(find.textContaining('went elsewhere'), findsOneWidget);
  });

  testWidgets('a family cannot be jumped forward through the stages',
      (tester) async {
    final (container, store) = await pumpScreen(tester);
    final atInquiry =
        store.applicants.value.firstWhere((a) => a.stage == AdmissionStage.inquiry);

    final jumped = await tester.runAsync(
      () => container.read(admissionsRepositoryProvider).advanceApplicant(
            applicantId: atInquiry.id,
            stage: AdmissionStage.offered,
          ),
    );

    expect(jumped, isA<Object>());
    expect(
      store.applicants.value.firstWhere((a) => a.id == atInquiry.id).stage,
      AdmissionStage.inquiry,
      reason: 'a pipeline whose stages can be set freely stops meaning anything',
    );
  });

  testWidgets('enrolling creates a student, and only ever one', (tester) async {
    final (container, store) = await pumpScreen(tester);
    final reserved =
        store.applicants.value.firstWhere((a) => a.stage == AdmissionStage.reserved);
    final studentsBefore = store.students.value.length;

    final repository = container.read(admissionsRepositoryProvider);
    final first = await tester.runAsync(
      () => repository.enrolApplicant(
        applicantId: reserved.id,
        section: 'Grade 7 - Sampaguita',
        birthDate: DateTime(2013, 4, 2),
      ),
    );
    expect(first, isNotNull);
    expect(store.students.value.length, studentsBefore + 1);

    final enrolled = store.applicants.value.firstWhere((a) => a.id == reserved.id);
    expect(enrolled.stage, AdmissionStage.enrolled);
    expect(enrolled.hasEnrolled, isTrue);

    // The reservation follows them. Money the school has taken and the
    // cashier cannot see is money the family gets asked for twice.
    final student = store.students.value.firstWhere((s) => s.id == enrolled.studentId);
    expect(student.balance, -reserved.reservationFeePaid);
    expect(student.section, 'Grade 7 - Sampaguita');

    // The second press, on a slow connection or a screen left open.
    await tester.runAsync(
      () => repository.enrolApplicant(
        applicantId: reserved.id,
        section: 'Grade 7 - Sampaguita',
        birthDate: DateTime(2013, 4, 2),
      ),
    );
    expect(store.students.value.length, studentsBefore + 1,
        reason: 'one child, one student record, however many times it is pressed');
  });

  testWidgets('an enquiry taken down gets a reference to read back', (tester) async {
    final (container, store) = await pumpScreen(tester);
    final before = store.applicants.value.length;

    final saved = await tester.runAsync(
      () => container.read(admissionsRepositoryProvider).saveApplicant(
            firstName: 'Ana',
            lastName: 'Lim',
            educationLevel: store.applicants.value.first.educationLevel,
            gradeLevel: 'Grade 7',
            guardianName: 'Cecilia Lim',
            guardianPhone: '09181234567',
            source: 'Walk-in',
          ),
    );

    expect(saved, isNotNull);
    expect(store.applicants.value.length, before + 1);
    // Its clock starts now, so a brand new enquiry is not on the
    // follow-up list the moment it is taken.
    final fresh = store.applicants.value.first;
    expect(fresh.stage, AdmissionStage.inquiry);
    expect(fresh.daysInStage(DateTime.now()), 0);
  });
}
