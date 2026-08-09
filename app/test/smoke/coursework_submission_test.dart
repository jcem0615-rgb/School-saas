import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:school_saas/core/constants/user_roles.dart';
import 'package:school_saas/demo/demo_overrides.dart';
import 'package:school_saas/demo/demo_store.dart';
import 'package:school_saas/features/faculty_portal/domain/entities/coursework_item.dart';
import 'package:school_saas/features/faculty_portal/domain/entities/coursework_submission.dart';
import 'package:school_saas/features/faculty_portal/presentation/controllers/faculty_controller.dart';
import 'package:school_saas/features/student_portal/presentation/controllers/student_controller.dart';

/// Handing work in is the only write a student account makes anywhere in
/// this app. Everything else they touch is read-only, so this path
/// carries more weight than its size suggests.
void main() {
  Future<ProviderContainer> signedInAs(UserRole role) async {
    final container = ProviderContainer(overrides: demoOverrides());
    addTearDown(container.dispose);
    container.read(demoAuthRepositoryProvider).signInAs(
          DemoStore.demoAccounts.firstWhere((a) => a.role == role),
        );
    await Future<void>.delayed(const Duration(milliseconds: 100));
    return container;
  }

  CourseworkItem itemFrom(ProviderContainer c, String id) =>
      c.read(demoStoreProvider).coursework.value.firstWhere((i) => i.id == id);

  test('a student can hand in an assignment', () async {
    final container = await signedInAs(UserRole.student);
    final sub = container.listen(studentActionControllerProvider, (_, __) {});
    addTearDown(sub.close);
    final store = container.read(demoStoreProvider);
    // cw_003 is the Second Quarter Exam -- gradable, and nobody has
    // handed it in in the seed.
    final item = itemFrom(container, 'cw_003');
    final before = store.courseworkSubmissions.value.length;

    final ok = await container.read(studentActionControllerProvider.notifier).submitCoursework(
          item: item,
          studentId: 'stu_001',
          studentName: 'Miguel Torres',
          section: 'Grade 10 - Rizal',
          answer: 'My answers to the second quarter exam.',
        );

    expect(ok, isTrue);
    expect(store.courseworkSubmissions.value.length, before + 1);
    final saved = store.courseworkSubmissions.value.firstWhere((s) => s.courseworkId == 'cw_003');
    expect(saved.answer, 'My answers to the second quarter exam.');
    expect(saved.studentId, 'stu_001');
    expect(saved.wasRevised, isFalse, reason: 'a first submission has not been revised');
  });

  test('a file alone is enough to hand in', () async {
    // Plenty of work is a photo of a worksheet with nothing typed. A
    // required text box would have students typing "see attached".
    final container = await signedInAs(UserRole.student);
    final sub = container.listen(studentActionControllerProvider, (_, __) {});
    addTearDown(sub.close);

    final ok = await container.read(studentActionControllerProvider.notifier).submitCoursework(
          item: itemFrom(container, 'cw_003'),
          studentId: 'stu_001',
          studentName: 'Miguel Torres',
          section: 'Grade 10 - Rizal',
          answer: '',
          attachmentUrl: 'https://example.org/answers.pdf',
          attachmentName: 'answers.pdf',
        );

    expect(ok, isTrue);
  });

  test('an empty submission is refused', () async {
    // Recording this as handed in is worse than refusing it: the student
    // walks away believing they are finished and the teacher sees a blank.
    final container = await signedInAs(UserRole.student);
    final sub = container.listen(studentActionControllerProvider, (_, __) {});
    addTearDown(sub.close);
    final store = container.read(demoStoreProvider);
    final before = store.courseworkSubmissions.value.length;

    final ok = await container.read(studentActionControllerProvider.notifier).submitCoursework(
          item: itemFrom(container, 'cw_003'),
          studentId: 'stu_001',
          studentName: 'Miguel Torres',
          section: 'Grade 10 - Rizal',
          answer: '   ',
        );

    expect(ok, isFalse);
    expect(store.courseworkSubmissions.value.length, before);
  });

  test('a lesson cannot be handed in', () async {
    // cw_005 is a Lesson: material to read, not work to do.
    final container = await signedInAs(UserRole.student);
    final sub = container.listen(studentActionControllerProvider, (_, __) {});
    addTearDown(sub.close);

    final lesson = itemFrom(container, 'cw_005');
    expect(lesson.acceptsSubmissions, isFalse, reason: 'seed precondition');

    final ok = await container.read(studentActionControllerProvider.notifier).submitCoursework(
          item: lesson,
          studentId: 'stu_001',
          studentName: 'Miguel Torres',
          section: 'Grade 10 - Rizal',
          answer: 'Read it.',
        );

    expect(ok, isFalse);
  });

  test('handing in twice replaces the answer rather than duplicating it', () async {
    final container = await signedInAs(UserRole.student);
    final sub = container.listen(studentActionControllerProvider, (_, __) {});
    addTearDown(sub.close);
    final store = container.read(demoStoreProvider);
    final item = itemFrom(container, 'cw_003');

    final notifier = container.read(studentActionControllerProvider.notifier);
    await notifier.submitCoursework(
      item: item,
      studentId: 'stu_001',
      studentName: 'Miguel Torres',
      section: 'Grade 10 - Rizal',
      answer: 'First attempt.',
    );
    final afterFirst =
        store.courseworkSubmissions.value.where((s) => s.courseworkId == 'cw_003').toList();
    expect(afterFirst, hasLength(1));

    await notifier.submitCoursework(
      submissionId: afterFirst.single.id,
      item: item,
      studentId: 'stu_001',
      studentName: 'Miguel Torres',
      section: 'Grade 10 - Rizal',
      answer: 'Second attempt, corrected.',
    );

    final afterSecond =
        store.courseworkSubmissions.value.where((s) => s.courseworkId == 'cw_003').toList();
    expect(afterSecond, hasLength(1), reason: 'a teacher must not get two answers to mark');
    expect(afterSecond.single.answer, 'Second attempt, corrected.');
    expect(afterSecond.single.wasRevised, isTrue);
    expect(
      afterSecond.single.submittedAt,
      afterFirst.single.submittedAt,
      reason: 'the original hand-in time survives a revision, or lateness could be edited away',
    );
  });

  test('the teacher sees what was handed in', () async {
    final container = await signedInAs(UserRole.faculty);
    final submissions = await container.read(submissionsForProvider('cw_001').future);

    expect(submissions, hasLength(1));
    expect(submissions.single.studentName, 'Miguel Torres');
    expect(submissions.single.hasAttachment, isTrue);
  });

  group('lateness', () {
    // Derived from the item at read time rather than stored, so a client
    // never gets to assert it and a moved due date re-evaluates honestly.
    final item = CourseworkItem(
      id: 'cw_x',
      type: CourseworkType.assignment,
      title: 'T',
      description: '',
      subject: 'Math',
      section: 'A',
      teacherId: 't',
      teacherName: 'T',
      published: true,
      createdAt: DateTime(2026, 1, 1),
      dueDate: DateTime(2026, 6, 1, 17),
    );

    CourseworkSubmission at(DateTime when) => CourseworkSubmission(
          id: 's',
          courseworkId: 'cw_x',
          courseworkTitle: 'T',
          studentId: 'stu',
          studentName: 'S',
          section: 'A',
          userId: 'u',
          answer: 'a',
          submittedAt: when,
        );

    test('before the deadline is not late', () {
      expect(at(DateTime(2026, 6, 1, 16, 59)).isLateFor(item), isFalse);
    });

    test('after the deadline is late', () {
      expect(at(DateTime(2026, 6, 1, 17, 1)).isLateFor(item), isTrue);
    });

    test('coursework with no deadline is never late', () {
      final noDue = CourseworkItem(
        id: 'cw_y',
        type: CourseworkType.project,
        title: 'T',
        description: '',
        subject: 'Math',
        section: 'A',
        teacherId: 't',
        teacherName: 'T',
        published: true,
        createdAt: DateTime(2026, 1, 1),
      );
      expect(at(DateTime(2030, 1, 1)).isLateFor(noDue), isFalse);
    });
  });
}
