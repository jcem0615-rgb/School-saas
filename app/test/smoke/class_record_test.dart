import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:logicclass/core/theme/app_theme.dart';
import 'package:logicclass/demo/demo_overrides.dart';
import 'package:logicclass/demo/demo_store.dart';
import 'package:logicclass/features/faculty_portal/domain/entities/class_assessment.dart';
import 'package:logicclass/features/faculty_portal/domain/entities/grading_scheme.dart';
import 'package:logicclass/features/faculty_portal/presentation/controllers/faculty_controller.dart';
import 'package:logicclass/features/faculty_portal/presentation/screens/class_record_screen.dart';

/// The class record: what a teacher types into, and what it computes.
///
/// Two things are being pinned. The first is the defect: a mark used to
/// be posted and never replaced, and the quarterly arithmetic sums the
/// scores *and the maximums* inside a component — so 80 out of 10,
/// corrected to 8 out of 10, left the child on 88 out of 20 with nothing
/// on any screen saying so.
///
/// The second is the feature: the teacher enters scores against a piece
/// of work and the quarterly grade follows from the percentages the
/// class is graded on, without anybody computing anything by hand.
void main() {
  const query = GradeQuery(
    subject: 'Mathematics',
    section: 'Grade 10 - Rizal',
    term: '2nd Quarter',
  );

  Future<ProviderContainer> teacherContainer() async {
    final container = ProviderContainer(overrides: demoOverrides());
    container.read(demoAuthRepositoryProvider).signInAs(
          DemoStore.demoAccounts.firstWhere((a) => a.email == 'faculty@demo.ph'),
        );
    return container;
  }

  FacultyActionController actions(ProviderContainer container) {
    container.listen(facultyActionControllerProvider, (_, __) {});
    return container.read(facultyActionControllerProvider.notifier);
  }

  /// The assembled record, once every stream behind it has emitted.
  ///
  /// `classRecordProvider` is deliberately null until the roster, the
  /// marks, the pieces of work and the scheme have all arrived -- a
  /// record built from a roster that loaded and marks that did not shows
  /// a class of ungraded children, which looks exactly like a class
  /// nobody has marked. So the test waits for it rather than reading
  /// through the gap.
  Future<ClassRecord> record(ProviderContainer container) async {
    container.listen(classRecordProvider(query), (_, __) {});
    // Pumped before reading, not only while it is null. The demo store's
    // subjects emit synchronously but Riverpod rebuilds on a microtask,
    // so a read straight after a write returns the value from before it
    // -- which reads as "the change did nothing" rather than as a test
    // that looked too early.
    for (var attempt = 0; attempt < 50; attempt++) {
      await Future<void>.delayed(Duration.zero);
      final value = container.read(classRecordProvider(query));
      if (value != null && attempt >= 4) return value;
    }
    fail('the class record never assembled');
  }

  group('what the record shows', () {
    test('a column per piece of work, and a row per student', () async {
      final container = await teacherContainer();
      addTearDown(container.dispose);

      final r = await record(container);
      expect(r.assessments.map((a) => a.title), [
        'Quiz 1 - Quadratics',
        'Group problem set',
        'Long test - Functions',
        'Board work',
      ]);
      // The three students actually enrolled in the section. The roster
      // drives the rows, not the marks: a teacher needs to see who has
      // *not* been marked, which a marks-only list can never show.
      expect(r.rows, hasLength(3));
    });

    test('the grade follows from the percentages, with nothing typed by hand',
        () async {
      // Written work 40, performance tasks 40, quarterly 20 — the
      // school's confirmed scheme for Mathematics. Andrea has 56/60 of
      // written work and 77/80 of performance tasks, and no exam yet.
      final container = await teacherContainer();
      addTearDown(container.dispose);

      final andrea = (await record(container))
          .rows
          .firstWhere((r) => r.student.fullName.contains('Andrea'));
      final ww = andrea.grade.componentFor(GradingComponent.writtenWork);
      final pt = andrea.grade.componentFor(GradingComponent.performanceTask);

      expect(ww.raw, 56);
      expect(ww.possible, 60);
      expect(pt.raw, 77);
      expect(pt.possible, 80);
      expect(ww.percentageScore, closeTo(93.33, 0.01));
      expect(pt.percentageScore, closeTo(96.25, 0.01));

      // Weighted over the eighty per cent that has actually been given
      // out, not over a hundred with the unsat exam counted as zero.
      expect(andrea.grade.availableWeight, 80);
      expect(
        andrea.grade.initialGrade,
        closeTo((93.33 * 40 + 96.25 * 40) / 80, 0.05),
      );
      expect(andrea.grade.hasWork, isTrue);
    });

    test('a blank is not a zero', () async {
      // Paolo did not sit the long test. The piece of work drops out of
      // both his score and the total it is over; counting it as nothing
      // would mark him as having failed something he was absent from.
      final container = await teacherContainer();
      addTearDown(container.dispose);

      final r = await record(container);
      final longTest =
          r.assessments.firstWhere((a) => a.title == 'Long test - Functions');
      final paolo =
          r.rows.firstWhere((row) => row.student.fullName.contains('Paolo'));

      expect(paolo.marks.containsKey(longTest.id), isFalse);
      // 12 out of 20 only, not 12 out of 60.
      final ww = paolo.grade.componentFor(GradingComponent.writtenWork);
      expect(ww.raw, 12);
      expect(ww.possible, 20);
    });

    test('says which percentages produced the number, and whose they are',
        () async {
      final container = await teacherContainer();
      addTearDown(container.dispose);

      final r = await record(container);
      expect(r.weights.isOverride, isFalse);
      expect(r.weights.provenance, contains('School scheme'));
      expect(r.weights.weights.balances, isTrue);
    });

    test('shows its working rather than only the answer', () async {
      final container = await teacherContainer();
      addTearDown(container.dispose);

      final andrea = (await record(container))
          .rows
          .firstWhere((r) => r.student.fullName.contains('Andrea'));
      final working = andrea.grade.workingOut.join('\n');

      expect(working, contains('Written Work'));
      expect(working, contains('x 40%'));
      expect(working, contains('Initial grade'));
      expect(working, contains('Final grade'));
      // And says why the total is over eighty rather than a hundred.
      expect(working, contains('80% of the grade has been given out'));
    });
  });

  group('typing marks in', () {
    test('a corrected score replaces the wrong one', () async {
      // The regression, in one test. Entering 80 out of 20 is refused;
      // entering 18 after 8 leaves one mark of 18, not two summing to
      // 26 out of 40.
      final container = await teacherContainer();
      addTearDown(container.dispose);
      final store = container.read(demoStoreProvider);
      final quiz = (await record(container))
          .assessments
          .firstWhere((a) => a.title == 'Quiz 1 - Quadratics');

      Future<void> mark(double score) => actions(container).saveAssessmentScores(
            assessmentId: quiz.id,
            scores: [
              ScoreEntry(
                studentId: 'stu_001',
                studentName: 'Miguel Torres',
                score: score,
              ),
            ],
          );

      await mark(8);
      await mark(18);

      final his = store.grades.value
          .where((g) => g.assessmentId == quiz.id && g.studentId == 'stu_001')
          .toList();
      expect(his, hasLength(1));
      expect(his.single.score, 18);
      expect(his.single.maxScore, 20);
    });

    test('a score above the total is refused, and nothing is written', () async {
      final container = await teacherContainer();
      addTearDown(container.dispose);
      final store = container.read(demoStoreProvider);
      final quiz = (await record(container))
          .assessments
          .firstWhere((a) => a.title == 'Quiz 1 - Quadratics');
      final before = store.grades.value.length;

      final result = await actions(container).saveAssessmentScores(
        assessmentId: quiz.id,
        scores: [
          const ScoreEntry(
            studentId: 'stu_001',
            studentName: 'Miguel Torres',
            score: 200,
          ),
        ],
      );
      expect(result, isNull);
      expect(store.grades.value, hasLength(before));
    });

    test('a score that is not a number is refused', () async {
      // `double.tryParse('NaN')` returns NaN for one word typed into the
      // box, and every guard here was a comparison, all of which are
      // false for NaN.
      final container = await teacherContainer();
      addTearDown(container.dispose);
      final quiz = (await record(container))
          .assessments
          .firstWhere((a) => a.title == 'Quiz 1 - Quadratics');

      expect(
        await actions(container).saveAssessmentScores(
          assessmentId: quiz.id,
          scores: [
            const ScoreEntry(
              studentId: 'stu_001',
              studentName: 'Miguel Torres',
              score: double.nan,
            ),
          ],
        ),
        isNull,
      );
    });

    test('clearing a mark leaves the work out rather than scoring nothing',
        () async {
      final container = await teacherContainer();
      addTearDown(container.dispose);
      final quiz = (await record(container))
          .assessments
          .firstWhere((a) => a.title == 'Quiz 1 - Quadratics');

      final result = await actions(container).saveAssessmentScores(
        assessmentId: quiz.id,
        scores: [
          const ScoreEntry(studentId: 'stu_001', studentName: 'Miguel Torres'),
        ],
      );
      expect(result?.cleared, 1);

      final miguel = (await record(container))
          .rows
          .firstWhere((r) => r.student.id == 'stu_001');
      expect(miguel.marks.containsKey(quiz.id), isFalse);
      // Still has the long test, so written work is out of 40 now.
      expect(miguel.grade.componentFor(GradingComponent.writtenWork).possible, 40);
    });
  });

  group('the percentages the teacher sets', () {
    test('replace the school scheme, and every grade follows', () async {
      final container = await teacherContainer();
      addTearDown(container.dispose);
      final before = (await record(container))
          .rows
          .firstWhere((r) => r.student.fullName.contains('Andrea'))
          .grade
          .initialGrade;

      final ok = await actions(container).setClassWeights(
        subject: query.subject,
        section: query.section,
        weights: const SubjectWeights(
          label: 'Set for this class',
          writtenWork: 20,
          performanceTask: 60,
          quarterlyAssessment: 20,
        ),
      );
      expect(ok, isTrue);

      final after = await record(container);
      expect(after.weights.isOverride, isTrue);
      expect(after.weights.weights.performanceTask, 60);
      expect(after.weights.provenance, contains('Set for this class'));
      // Andrea is stronger on performance tasks, so weighting them
      // higher moves her up. The point is that it moved at all without
      // anybody re-entering a mark.
      final now = after.rows
          .firstWhere((r) => r.student.fullName.contains('Andrea'))
          .grade
          .initialGrade;
      expect(now, isNot(closeTo(before, 0.001)));
      expect(now, greaterThan(before));
    });

    test('are refused unless the three add up to a hundred', () async {
      // The one misconfiguration that does not announce itself: the
      // grades stay plausible and are wrong for the whole class.
      final container = await teacherContainer();
      addTearDown(container.dispose);

      final ok = await actions(container).setClassWeights(
        subject: query.subject,
        section: query.section,
        weights: const SubjectWeights(
          label: 'Set for this class',
          writtenWork: 30,
          performanceTask: 50,
          quarterlyAssessment: 30,
        ),
      );
      expect(ok, isFalse);
      expect((await record(container)).weights.isOverride, isFalse);
    });

    test('can be handed back to the school scheme', () async {
      final container = await teacherContainer();
      addTearDown(container.dispose);

      await actions(container).setClassWeights(
        subject: query.subject,
        section: query.section,
        weights: const SubjectWeights(
          label: 'Set for this class',
          writtenWork: 20,
          performanceTask: 60,
          quarterlyAssessment: 20,
        ),
      );
      expect((await record(container)).weights.isOverride, isTrue);

      await actions(container).setClassWeights(
        subject: query.subject,
        section: query.section,
      );
      expect((await record(container)).weights.isOverride, isFalse);
    });
  });

  group('adding a piece of work', () {
    test('needs a name and a total that is a number above zero', () async {
      final container = await teacherContainer();
      addTearDown(container.dispose);

      Future<Object?> save({String title = 'Seatwork 2', double maxScore = 15}) =>
          actions(container).saveClassAssessment(
            subject: query.subject,
            section: query.section,
            term: query.term!,
            title: title,
            component: GradingComponent.writtenWork,
            maxScore: maxScore,
          );

      expect(await save(title: '   '), isNull);
      expect(await save(maxScore: 0), isNull);
      expect(await save(maxScore: double.nan), isNull);
      expect(await save(), isNotNull);
      expect((await record(container)).assessments, hasLength(5));
    });

    test('lowering the total names the marks that no longer fit', () async {
      // Either number could be the right one, and only the teacher knows
      // which. Clamping would change a mark without saying so.
      final container = await teacherContainer();
      addTearDown(container.dispose);
      final longTest = (await record(container))
          .assessments
          .firstWhere((a) => a.title == 'Long test - Functions');

      final result = await actions(container).saveClassAssessment(
        assessmentId: longTest.id,
        subject: query.subject,
        section: query.section,
        term: query.term!,
        title: longTest.title,
        component: longTest.component,
        maxScore: 30,
      );
      expect(result, isNotNull);
      expect(result!.marksOverMax, contains('Andrea Villanueva'));
    });
  });

  group('a mark entered in Grade Submission', () {
    test('lands in the quarter the class record is looking at', () async {
      // The bug this pins: Grade Submission shipped a free-text term box
      // defaulting to "Q1" while the class record's dropdown offered
      // "1st Quarter". Every query on `term` is an equality match, so
      // the mark was saved, confirmed, and invisible.
      final container = await teacherContainer();
      addTearDown(container.dispose);

      final student = (await record(container)).rows.first.student;
      final ok = await actions(container).submitGrade(
        studentId: student.id,
        studentName: student.fullName,
        subject: query.subject,
        section: query.section,
        term: query.term!,
        score: 17,
        maxScore: 20,
        component: GradingComponent.writtenWork,
      );
      expect(ok, isTrue);

      final after = await record(container);
      final theirs = after.rows.firstWhere((r) => r.student.id == student.id);
      expect(
        theirs.grade.componentFor(GradingComponent.writtenWork).possible,
        greaterThanOrEqualTo(20),
        reason: 'a mark posted into this quarter has to reach this record',
      );
    });

    test('filed under a term nothing queries would be invisible', () async {
      // The other half, and the reason the dialog is a dropdown now: a
      // mark in "Q1" does not reach a record open on "1st Quarter". This
      // asserts the gap is real rather than assuming it.
      final container = await teacherContainer();
      addTearDown(container.dispose);

      final student = (await record(container)).rows.first.student;
      final before = (await record(container))
          .rows
          .firstWhere((r) => r.student.id == student.id)
          .grade
          .componentFor(GradingComponent.writtenWork)
          .possible;

      await actions(container).submitGrade(
        studentId: student.id,
        studentName: student.fullName,
        subject: query.subject,
        section: query.section,
        term: 'Q2', // not one of the names any screen offers
        score: 17,
        maxScore: 20,
        component: GradingComponent.writtenWork,
      );

      final after = (await record(container))
          .rows
          .firstWhere((r) => r.student.id == student.id)
          .grade
          .componentFor(GradingComponent.writtenWork)
          .possible;
      expect(after, before,
          reason: 'which is exactly why nothing in the app lets a teacher '
              'type a term by hand any more');
    });
  });

  group('deleting a piece of work', () {
    test('takes its marks with it, and says how many', () async {
      // The marks are the reason this is not a simple delete. Removing
      // the column and leaving them behind would keep them summing into
      // the component total: the class still graded on a quiz that is no
      // longer on any screen.
      final container = await teacherContainer();
      addTearDown(container.dispose);

      final before = await record(container);
      final quiz = before.assessments.firstWhere((a) => a.title == 'Quiz 1 - Quadratics');
      final marked =
          before.rows.where((r) => r.marks.containsKey(quiz.id)).length;
      expect(marked, greaterThan(0), reason: 'the fixture needs marks to lose');

      final removed = await actions(container).deleteClassAssessment(quiz.id);
      expect(removed, marked);

      final after = await record(container);
      expect(after.assessments.map((a) => a.title), isNot(contains('Quiz 1 - Quadratics')));
      expect(
        after.rows.every((r) => !r.marks.containsKey(quiz.id)),
        isTrue,
        reason: 'a mark whose piece of work is gone would still be summed',
      );
    });

    test('changes the grades it should, and only those', () async {
      final container = await teacherContainer();
      addTearDown(container.dispose);

      final before = await record(container);
      final quiz = before.assessments.firstWhere((a) => a.title == 'Quiz 1 - Quadratics');
      final marked = before.rows.firstWhere((r) => r.marks.containsKey(quiz.id));
      final untouched =
          before.rows.where((r) => !r.marks.containsKey(quiz.id)).firstOrNull;

      await actions(container).deleteClassAssessment(quiz.id);
      final after = await record(container);

      final markedAfter =
          after.rows.firstWhere((r) => r.student.id == marked.student.id);
      expect(markedAfter.grade.componentFor(GradingComponent.writtenWork).possible,
          lessThan(marked.grade.componentFor(GradingComponent.writtenWork).possible),
          reason: 'the deleted total should no longer be in the denominator');

      if (untouched != null) {
        final same = after.rows.firstWhere((r) => r.student.id == untouched.student.id);
        expect(same.grade.finalGrade, untouched.grade.finalGrade,
            reason: 'a student who was never marked on it should not move');
      }
    });

    test('a piece of work that is already gone is refused', () async {
      final container = await teacherContainer();
      addTearDown(container.dispose);
      expect(await actions(container).deleteClassAssessment('as_nope'), isNull);
    });
  });

  group('the screen', () {
    testWidgets('opens a class and shows the working', (tester) async {
      tester.view.physicalSize = const Size(430 * 3, 2600 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      final container = await teacherContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const ClassRecordScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, 'Mathematics');
      await tester.enterText(find.byType(TextField).at(1), 'Grade 10 - Rizal');
      await tester.pumpAndSettle();

      // The quarter the seeded marks are in.
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('2nd Quarter').last);
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Open'));
      await tester.pumpAndSettle();

      expect(find.text('Quiz 1 - Quadratics'), findsWidgets);
      expect(find.text('Andrea Villanueva'), findsOneWidget);
      // The percentages in force, named on the screen rather than
      // implied.
      expect(find.textContaining('WW 40%'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('shows the class even before any work has been given out',
        (tester) async {
      // A quarter with no pieces of work used to collapse the whole
      // screen to one sentence, and the roster went with it: a teacher
      // opening their own class saw nobody in it. The columns are what
      // is empty, not the class.
      tester.view.physicalSize = const Size(430 * 3, 3000 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      final container = await teacherContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(theme: AppTheme.light(), home: const ClassRecordScreen()),
        ),
      );
      await tester.pumpAndSettle();

      // English, 1st Quarter: a real class with nothing set in it yet.
      await tester.enterText(find.byType(TextField).first, 'English');
      await tester.enterText(find.byType(TextField).at(1), 'Grade 10 - Rizal');
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('1st Quarter').last);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Open'));
      await tester.pumpAndSettle();

      // It says there is no work yet...
      expect(find.textContaining('Nothing has been given out'), findsOneWidget);
      // ...and the class is still on the screen, counted and listed.
      expect(find.textContaining('The class ·'), findsOneWidget);
      expect(find.text('Andrea Villanueva'), findsOneWidget);
      expect(find.textContaining('waiting on their first mark'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('opening a student shows the whole grade, missing parts included',
        (tester) async {
      // "Why did this child get 89?" has to be answerable on this screen
      // or the teacher goes back to a spreadsheet. Every component, every
      // piece of work inside it, the arithmetic, and -- the part that was
      // missing -- the component with nothing in it that is the reason
      // the grade is not final.
      tester.view.physicalSize = const Size(430 * 3, 4200 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      final container = await teacherContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(theme: AppTheme.light(), home: const ClassRecordScreen()),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, 'Mathematics');
      await tester.enterText(find.byType(TextField).at(1), 'Grade 10 - Rizal');
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('2nd Quarter').last);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Andrea Villanueva'));
      await tester.pumpAndSettle();

      // All three components named, not only the two with marks in them.
      expect(find.text('Written Work'), findsWidgets);
      expect(find.text('Performance Tasks'), findsWidgets);
      expect(find.text('Quarterly Assessment'), findsWidgets);

      // The empty one says what it is waiting for rather than being absent.
      expect(find.textContaining('nothing recorded'), findsWidgets);

      // The pieces of work inside a component, with this student's marks.
      expect(find.text('Long test - Functions'), findsWidgets);

      // And the arithmetic, ending in the verdict rather than a bare number.
      expect(find.textContaining('Initial grade'), findsOneWidget);
      expect(find.textContaining('Final grade: INC'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
