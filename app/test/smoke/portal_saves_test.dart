import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:school_saas/core/constants/education_level.dart';
import 'package:school_saas/core/constants/user_roles.dart';
import 'package:school_saas/demo/demo_overrides.dart';
import 'package:school_saas/demo/demo_store.dart';
import 'package:school_saas/features/admin_portal/presentation/controllers/admin_controller.dart';
import 'package:school_saas/features/director_portal/domain/entities/announcement.dart';
import 'package:school_saas/features/director_portal/presentation/controllers/director_controller.dart';
import 'package:school_saas/features/faculty_portal/domain/entities/coursework_item.dart';
import 'package:school_saas/features/faculty_portal/presentation/controllers/faculty_controller.dart';
import 'package:school_saas/features/guidance_portal/domain/entities/guidance_record.dart';
import 'package:school_saas/features/guidance_portal/presentation/controllers/guidance_controller.dart';
import 'package:school_saas/features/registrar_portal/presentation/controllers/registrar_controller.dart';
import 'package:school_saas/features/staff_portal/presentation/controllers/staff_controller.dart';

/// portal_actions_test proves every primary button opens its form. This
/// proves the form can still be *submitted* -- which is a different
/// failure and the one that a new required field causes.
///
/// Adding `delivery`, `educationLevel` and `birthDate` as required
/// arguments cannot silently break a caller (the analyzer would catch a
/// missing one), but it can silently break a *user*: a save that now
/// fails validation for a reason the form never mentions looks exactly
/// like a dead button. So each case here submits a record the way the
/// form does and asserts it actually landed in the store.
void main() {
  /// One signed-in container per case. The demo repositories re-subscribe
  /// on the auth emission, so the controller has to be read after that
  /// lands or the notifier is disposed mid-write.
  Future<ProviderContainer> signedInAs(UserRole role) async {
    final container = ProviderContainer(overrides: demoOverrides());
    addTearDown(container.dispose);
    container.read(demoAuthRepositoryProvider).signInAs(
          DemoStore.demoAccounts.firstWhere((a) => a.role == role),
        );
    await Future<void>.delayed(const Duration(milliseconds: 100));
    return container;
  }

  test('Director · an announcement saves', () async {
    final container = await signedInAs(UserRole.director);
    final sub = container.listen(directorActionControllerProvider, (_, __) {});
    addTearDown(sub.close);
    final store = container.read(demoStoreProvider);
    final before = store.announcements.value.length;

    final ok = await container.read(directorActionControllerProvider.notifier).createAnnouncement(
          title: 'Faculty meeting Friday',
          body: 'All faculty, 4pm, AVR.',
          audience: AnnouncementAudience.everyone,
        );

    expect(ok, isTrue);
    expect(store.announcements.value.length, before + 1);
  });

  test('Director · an expense saves', () async {
    final container = await signedInAs(UserRole.director);
    final sub = container.listen(directorActionControllerProvider, (_, __) {});
    addTearDown(sub.close);
    final store = container.read(demoStoreProvider);
    final before = store.expenses.value.length;

    final ok = await container.read(directorActionControllerProvider.notifier).createExpense(
          category: 'Supplies',
          description: 'Chalk and markers',
          amount: 1250,
          date: DateTime.now(),
        );

    expect(ok, isTrue);
    expect(store.expenses.value.length, before + 1);
  });

  test('Admin · a teacher assignment saves', () async {
    final container = await signedInAs(UserRole.admin);
    final sub = container.listen(adminActionControllerProvider, (_, __) {});
    addTearDown(sub.close);
    final store = container.read(demoStoreProvider);
    final before = store.assignments.value.length;

    final ok = await container.read(adminActionControllerProvider.notifier).createTeacherAssignment(
          teacherId: 'u_faculty',
          teacherName: 'Maria Santos',
          subject: 'Filipino',
          section: 'Grade 10 - Rizal',
          schoolYear: '2026-2027',
        );

    expect(ok, isTrue);
    expect(store.assignments.value.length, before + 1);
  });

  test('Admin · a college program saves', () async {
    final container = await signedInAs(UserRole.admin);
    final sub = container.listen(adminActionControllerProvider, (_, __) {});
    addTearDown(sub.close);
    final store = container.read(demoStoreProvider);
    final before = store.programs.value.length;

    final ok = await container.read(adminActionControllerProvider.notifier).createProgram(
          name: 'BS Nursing',
          code: 'BSN',
          department: 'College of Health Sciences',
          educationLevel: EducationLevel.college,
        );

    expect(ok, isTrue);
    expect(store.programs.value.length, before + 1);
  });

  test('Admin · a Senior High strand saves', () async {
    final container = await signedInAs(UserRole.admin);
    final sub = container.listen(adminActionControllerProvider, (_, __) {});
    addTearDown(sub.close);
    final store = container.read(demoStoreProvider);

    final ok = await container.read(adminActionControllerProvider.notifier).createProgram(
          name: 'Home Economics',
          code: 'TVL-HE',
          department: 'Technical-Vocational-Livelihood',
          educationLevel: EducationLevel.seniorHigh,
        );

    expect(ok, isTrue);
    final saved = store.programs.value.firstWhere((p) => p.code == 'TVL-HE');
    expect(saved.educationLevel, EducationLevel.seniorHigh,
        reason: 'the division has to survive the round trip, or the strand '
            'shows up in the college dropdown');
  });

  test('Faculty · face-to-face coursework saves without a file', () async {
    final container = await signedInAs(UserRole.faculty);
    final sub = container.listen(facultyActionControllerProvider, (_, __) {});
    addTearDown(sub.close);
    final store = container.read(demoStoreProvider);
    final before = store.coursework.value.length;

    final ok = await container.read(facultyActionControllerProvider.notifier).createCourseworkItem(
          type: CourseworkType.lesson,
          delivery: CourseworkDelivery.faceToFace,
          title: 'Board work: factoring',
          description: 'Solve at the board.',
          subject: 'Mathematics',
          section: 'Grade 10 - Rizal',
        );

    expect(ok, isTrue, reason: 'the common case must not have gained a requirement');
    expect(store.coursework.value.length, before + 1);
  });

  test('Faculty · a grade saves', () async {
    final container = await signedInAs(UserRole.faculty);
    final sub = container.listen(facultyActionControllerProvider, (_, __) {});
    addTearDown(sub.close);

    final ok = await container.read(facultyActionControllerProvider.notifier).submitGrade(
          studentId: 'stu_001',
          studentName: 'Miguel Torres',
          subject: 'Mathematics',
          section: 'Grade 10 - Rizal',
          term: 'Q2',
          score: 88,
          maxScore: 100,
        );

    expect(ok, isTrue);
  });

  test('Registrar · a student registers with a birthday', () async {
    final container = await signedInAs(UserRole.registrar);
    final sub = container.listen(registrarActionControllerProvider, (_, __) {});
    addTearDown(sub.close);
    final store = container.read(demoStoreProvider);
    final before = store.students.value.length;

    final outcome =
        await container.read(registrarActionControllerProvider.notifier).registerStudent(
              firstName: 'Ana',
              lastName: 'Reyes',
              educationLevel: EducationLevel.elementary,
              gradeLevel: 'Grade 5',
              section: 'Grade 5 - Ilang-Ilang',
              birthDate: DateTime(2015, 4, 2),
            );

    expect(outcome, isNotNull, reason: 'registration is the registrar portal');
    expect(store.students.value.length, before + 1);
  });

  test('Registrar · a Senior High student registers with a strand', () async {
    final container = await signedInAs(UserRole.registrar);
    final sub = container.listen(registrarActionControllerProvider, (_, __) {});
    addTearDown(sub.close);
    final store = container.read(demoStoreProvider);

    final outcome =
        await container.read(registrarActionControllerProvider.notifier).registerStudent(
              firstName: 'Ben',
              lastName: 'Cruz',
              educationLevel: EducationLevel.seniorHigh,
              gradeLevel: 'Grade 12',
              section: 'ABM 12-B',
              birthDate: DateTime(2008, 1, 20),
              programId: 'shs_abm',
            );

    expect(outcome, isNotNull);
    final saved = store.students.value.firstWhere((s) => s.id == outcome!.studentId);
    expect(saved.educationLevel, EducationLevel.seniorHigh);
    expect(saved.programId, 'shs_abm');
  });

  test('Guidance · a record saves', () async {
    final container = await signedInAs(UserRole.guidance);
    final sub = container.listen(guidanceActionControllerProvider, (_, __) {});
    addTearDown(sub.close);
    final store = container.read(demoStoreProvider);
    final before = store.guidanceRecords.value.length;

    final ok = await container.read(guidanceActionControllerProvider.notifier).createGuidanceRecord(
          section: 'Grade 10 - Rizal',
          category: GuidanceCategory.academic,
          notes: 'Section-wide orientation on study habits.',
        );

    expect(ok, isTrue);
    expect(store.guidanceRecords.value.length, before + 1);
  });

  test('Guidance · a summons saves', () async {
    final container = await signedInAs(UserRole.guidance);
    final sub = container.listen(guidanceActionControllerProvider, (_, __) {});
    addTearDown(sub.close);
    final store = container.read(demoStoreProvider);
    final before = store.summonses.value.length;

    final ok = await container.read(guidanceActionControllerProvider.notifier).createSummons(
          studentId: 'stu_001',
          studentName: 'Miguel Torres',
          reason: 'Repeated tardiness',
          scheduledDate: DateTime.now().add(const Duration(days: 2)),
        );

    expect(ok, isTrue);
    expect(store.summonses.value.length, before + 1);
  });

  test('Staff · a checklist item saves', () async {
    final container = await signedInAs(UserRole.staff);
    final sub = container.listen(staffActionControllerProvider, (_, __) {});
    addTearDown(sub.close);
    final store = container.read(demoStoreProvider);
    final before = store.checklist.value.length;

    final ok = await container.read(staffActionControllerProvider.notifier).addChecklistItem(
          task: 'Restock the canteen fridge',
          date: DateTime.now().toIso8601String().substring(0, 10),
        );

    expect(ok, isTrue);
    expect(store.checklist.value.length, before + 1);
  });

  test('Staff · a daily report saves', () async {
    final container = await signedInAs(UserRole.staff);
    final sub = container.listen(staffActionControllerProvider, (_, __) {});
    addTearDown(sub.close);
    final store = container.read(demoStoreProvider);
    final before = store.dailyReports.value.length;

    final ok = await container.read(staffActionControllerProvider.notifier).submitDailyReport(
          date: DateTime.now().toIso8601String().substring(0, 10),
          content: 'Canteen restocked, two tables repaired.',
        );

    expect(ok, isTrue);
    expect(store.dailyReports.value.length, before + 1);
  });
}
