import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:logicclass/core/constants/user_roles.dart';
import 'package:logicclass/demo/demo_overrides.dart';
import 'package:logicclass/demo/demo_store.dart';
import 'package:logicclass/features/faculty_portal/domain/entities/grade.dart';
import 'package:logicclass/features/faculty_portal/domain/entities/grading_scheme.dart';
import 'package:logicclass/features/faculty_portal/presentation/controllers/faculty_controller.dart';

/// Repairing marks filed under a term no screen queries.
///
/// The write paths are fixed -- the submission dialog is a dropdown and
/// the import canonicalises its column -- but marks typed before that are
/// still on file under "Q1", saved and confirmed and invisible. This is
/// the repair for those, and the two things that matter about it are that
/// it reports before it writes and that it refuses to double-count.
void main() {
  Grade mark({
    required String id,
    String term = 'Q1',
    String studentId = 'stu_001',
    double score = 18,
    String? assessmentId,
  }) =>
      Grade(
        id: id,
        studentId: studentId,
        studentName: 'Miguel Torres',
        subject: 'Mathematics',
        section: 'Grade 10 - Rizal',
        term: term,
        assessmentId: assessmentId,
        component: GradingComponent.writtenWork,
        score: score,
        maxScore: 20,
        submittedByName: 'Maria Santos',
        submittedAt: DateTime(2026, 8, 1),
      );

  ProviderContainer signedInAsAdmin(List<Grade> marks) {
    final container = ProviderContainer(overrides: demoOverrides());
    addTearDown(container.dispose);
    container.read(demoAuthRepositoryProvider).signInAs(
          DemoStore.demoAccounts.firstWhere((a) => a.role == UserRole.admin),
        );
    container.read(demoStoreProvider).grades.add(marks);
    return container;
  }

  FacultyActionController actions(ProviderContainer c) =>
      c.read(facultyActionControllerProvider.notifier);

  test('a dry run says what it would do and changes nothing', () async {
    final container = signedInAsAdmin([mark(id: 'g1'), mark(id: 'g2', term: 'q2')]);

    final report = await actions(container).repairGradeTerms(apply: false);

    expect(report, isNotNull);
    expect(report!.applied, isFalse);
    expect(report.moved, 2);
    expect(
      report.moves.map((m) => '${m.from}->${m.to}'),
      containsAll(['Q1->1st Quarter', 'q2->2nd Quarter']),
    );
    // The whole point of a dry run.
    final after = container.read(demoStoreProvider).grades.value;
    expect(after.map((g) => g.term), containsAll(['Q1', 'q2']));
  });

  test('applying moves them, and the class record can finally see them', () async {
    final container = signedInAsAdmin([mark(id: 'g1')]);

    final report = await actions(container).repairGradeTerms(apply: true);

    expect(report!.applied, isTrue);
    expect(report.moved, 1);
    expect(
      container.read(demoStoreProvider).grades.value.single.term,
      '1st Quarter',
    );
  });

  test('a term nobody recognises is left exactly as it is', () async {
    // A school running "Prelim" keeps it. Rewriting it to a quarter would
    // be this software deciding how a school divides its year.
    final container = signedInAsAdmin([mark(id: 'g1', term: 'Prelim')]);

    final report = await actions(container).repairGradeTerms(apply: true);

    expect(report!.moved, 0);
    expect(container.read(demoStoreProvider).grades.value.single.term, 'Prelim');
  });

  test('it refuses to move a mark onto its own twin', () async {
    // The same quiz entered through both screens. Moving the first turns
    // 18/20 into 36/40 -- a wrong grade produced by the repair itself.
    final container = signedInAsAdmin([
      mark(id: 'loose_q1'),
      mark(id: 'loose_canonical', term: '1st Quarter'),
    ]);

    final report = await actions(container).repairGradeTerms(apply: true);

    expect(report!.moved, 0);
    expect(report.skipped, hasLength(1));
    expect(report.skipped.single.reason, contains('twice'));
    expect(
      container.read(demoStoreProvider).grades.value
          .firstWhere((g) => g.id == 'loose_q1')
          .term,
      'Q1',
      reason: 'left for a person to decide which of the two is real',
    );
  });

  test('but a mark that only looks similar still moves', () async {
    // Same student and component, different score: two real pieces of
    // work, and the second belongs beside the first.
    final container = signedInAsAdmin([
      mark(id: 'g1', score: 15),
      mark(id: 'g2', term: '1st Quarter', score: 18),
    ]);

    final report = await actions(container).repairGradeTerms(apply: true);

    expect(report!.moved, 1);
    expect(report.skipped, isEmpty);
  });

  test('marks tied to a piece of work move without a twin check', () async {
    // They cannot collide: a mark lives at {assessment}_{student}, so one
    // assessment and one student is one document.
    final container = signedInAsAdmin([
      mark(id: 'as_1_stu_001', assessmentId: 'as_1'),
      mark(id: 'as_2_stu_001', assessmentId: 'as_2'),
    ]);

    final report = await actions(container).repairGradeTerms(apply: true);

    expect(report!.moved, 2);
    expect(report.skipped, isEmpty);
  });

  test('nothing to do is said plainly rather than reported as a repair', () async {
    final container = signedInAsAdmin([mark(id: 'g1', term: '1st Quarter')]);

    final report = await actions(container).repairGradeTerms(apply: false);

    expect(report!.hasWork, isFalse);
    expect(report.moved, 0);
  });
}
