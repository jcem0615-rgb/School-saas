import 'package:flutter_test/flutter_test.dart';

import 'package:logicclass/features/faculty_portal/domain/entities/grade.dart';
import 'package:logicclass/features/faculty_portal/domain/entities/grading_scheme.dart';
import 'package:logicclass/features/faculty_portal/domain/entities/quarterly_grade.dart';

/// Turning raw scores into the number that goes on a Form 138.
///
/// Every case here has a child behind it. A grade that is wrong low is a
/// child held back a year; one that is wrong high is a school issuing a
/// credential it cannot stand behind. The arithmetic is DepEd's and is
/// not in dispute -- what this file is really testing is the handful of
/// judgement calls around the edges of it.
void main() {
  Grade score(
    double raw,
    double max, {
    GradingComponent component = GradingComponent.writtenWork,
    String subject = 'Science',
  }) =>
      Grade(
        id: 'g',
        studentId: 'stu1',
        studentName: 'Bea Torres',
        subject: subject,
        section: 'Grade 10 - Rizal',
        term: '1st Quarter',
        component: component,
        score: raw,
        maxScore: max,
        submittedByName: 'Maria Santos',
        submittedAt: DateTime(2026, 8, 1),
      );

  const scheme = GradingScheme(
    weights: GradingScheme.depEdBasicEducationDefaults,
    confirmedBySchool: true,
  );

  QuarterlyGrade compute(List<Grade> grades, {String subject = 'Science'}) =>
      computeQuarterlyGrade(
        subject: subject,
        term: '1st Quarter',
        grades: grades,
        scheme: scheme,
      );

  group('the weights that apply', () {
    test('Science and Mathematics are 40/40/20', () {
      final weights = scheme.weightsFor('Science');
      expect(weights.writtenWork, 40);
      expect(weights.performanceTask, 40);
      expect(weights.quarterlyAssessment, 20);
    });

    test('English falls in the languages group', () {
      expect(scheme.weightsFor('English').performanceTask, 50);
    });

    test('matching ignores case', () {
      expect(scheme.weightsFor('mathematics').writtenWork, 40);
    });

    test('a subject in no group gets the fallback, and it is labelled', () {
      final weights = scheme.weightsFor('Robotics');
      expect(weights.label, 'Other subjects');
      expect(weights.balances, isTrue);
    });

    test('every default grouping adds up to a hundred', () {
      // The one misconfiguration that produces plausible-looking wrong
      // grades for a whole year rather than an obvious error.
      for (final group in GradingScheme.depEdBasicEducationDefaults) {
        expect(group.balances, isTrue, reason: '${group.label} does not total 100');
      }
    });
  });

  group('the arithmetic', () {
    test('one component, all of it', () {
      // 142 of 165 is 86.06%. With only written work recorded, the whole
      // grade is that component rescaled to the weight available.
      final grade = compute([score(142, 165)]);
      expect(grade.componentFor(GradingComponent.writtenWork).percentageScore, 86.06);
      expect(grade.initialGrade, 86.06);
    });

    test('three components, weighted', () {
      final grade = compute([
        score(80, 100),
        score(90, 100, component: GradingComponent.performanceTask),
        score(70, 100, component: GradingComponent.quarterlyAssessment),
      ]);
      // 80*.4 + 90*.4 + 70*.2 = 32 + 36 + 14 = 82
      expect(grade.initialGrade, 82);
      expect(grade.hasWork, isTrue);
      expect(grade.missingComponents, isEmpty);
    });

    test('several pieces in one component are summed, not averaged', () {
      // A 10-point quiz and a 90-point test are not equal halves of the
      // component, and averaging their percentages would make the quiz
      // worth as much as the test.
      final grade = compute([score(5, 10), score(90, 90)]);
      expect(grade.componentFor(GradingComponent.writtenWork).raw, 95);
      expect(grade.componentFor(GradingComponent.writtenWork).possible, 100);
      expect(grade.initialGrade, 95);
    });
  });

  group('a component nobody has graded yet', () {
    test('is not counted as zero', () {
      // The failure that matters. In week two no quarterly assessment has
      // been given; counting it as zero at 20 per cent caps every child
      // in the school at 80 until the exam, and a teacher looking at that
      // concludes the system is broken.
      final grade = compute([
        score(90, 100),
        score(90, 100, component: GradingComponent.performanceTask),
      ]);
      expect(grade.initialGrade, 90);
    });

    test('is named, so nobody mistakes a partial grade for a final one', () {
      final grade = compute([score(90, 100)]);
      expect(grade.missingComponents, [
        GradingComponent.performanceTask,
        GradingComponent.quarterlyAssessment,
      ]);
    });

    test('a subject with nothing at all has no grade rather than a zero', () {
      final grade = compute(const []);
      expect(grade.hasWork, isFalse);
      expect(grade.initialGrade, 0);
    });
  });

  group('what a teacher actually does', () {
    test('work worth zero points does not enter the denominator', () {
      // Recording attendance at an activity, not an assessment. Counting
      // it would leave the denominator wrong.
      final grade = compute([score(90, 100), score(0, 0)]);
      expect(grade.componentFor(GradingComponent.writtenWork).possible, 100);
      expect(grade.initialGrade, 90);
    });

    test('bonus marks are kept rather than clamped', () {
      // Schools give them. Capping silently would erase a teacher's
      // decision; a component over 100 is visible and explicable.
      final grade = compute([score(105, 100)]);
      expect(grade.componentFor(GradingComponent.writtenWork).percentageScore, 105);
    });

    test('a component the teacher started but nobody scored in', () {
      final grade = compute([score(0, 50)]);
      expect(grade.componentFor(GradingComponent.writtenWork).hasWork, isTrue);
      expect(grade.initialGrade, 0);
    });
  });

  group('transmutation', () {
    const table = [
      TransmutationBand(from: 0, to: 3.99, transmuted: 60),
      TransmutationBand(from: 4, to: 19.99, transmuted: 61),
      TransmutationBand(from: 20, to: 39.99, transmuted: 70),
      TransmutationBand(from: 40, to: 79.99, transmuted: 85),
      TransmutationBand(from: 80, to: 100, transmuted: 95),
    ];

    test('reads the band the initial grade falls in', () {
      expect(transmute(50, table), 85);
      expect(transmute(0, table), 60);
      expect(transmute(100, table), 95);
    });

    test('a boundary belongs to the band that names it', () {
      expect(transmute(40, table), 85);
      expect(transmute(39.99, table), 70);
    });

    test('no table means the school does not transmute', () {
      // A real configuration, not a missing one. Inventing a table would
      // silently change every grade the school issues.
      expect(transmute(86.4, const []), 86);
      expect(transmute(86.5, const []), 87);
    });

    test('a value past the end of the table clamps rather than falling to zero', () {
      // A table that does not reach 100 is a misconfiguration. Turning a
      // perfect paper into a zero because of it is the worst possible way
      // to discover that.
      const short = [TransmutationBand(from: 0, to: 90, transmuted: 80)];
      expect(transmute(95, short), 80);
      expect(transmute(-5, short), 80);
    });
  });

  group('what it means in words', () {
    test('the descriptors, and where the line is', () {
      expect(gradeDescriptor(90), 'Outstanding');
      expect(gradeDescriptor(85), 'Very Satisfactory');
      expect(gradeDescriptor(80), 'Satisfactory');
      expect(gradeDescriptor(75), 'Fairly Satisfactory');
      expect(gradeDescriptor(74), 'Did Not Meet Expectations');
    });

    test('75 passes and 74 does not', () {
      expect(isPassing(75), isTrue);
      expect(isPassing(74), isFalse);
    });
  });

  group('the general average', () {
    QuarterlyGrade graded(String subject, int finalGrade, {bool hasWork = true}) =>
        QuarterlyGrade(
          subject: subject,
          term: '1st Quarter',
          weights: scheme.weightsFor(subject),
          components: const [],
          initialGrade: finalGrade.toDouble(),
          finalGrade: finalGrade,
          hasWork: hasWork,
        );

    test('is the mean of the final grades', () {
      expect(generalAverage([graded('Science', 90), graded('English', 85)]), 88);
    });

    test('leaves out a subject nobody has graded', () {
      // The number parents look at first. Dragging it down with a subject
      // the teacher has not started makes it wrong until the day the
      // quarter closes.
      expect(
        generalAverage([
          graded('Science', 90),
          graded('English', 0, hasWork: false),
        ]),
        90,
      );
    });

    test('is nothing at all when no subject has been graded', () {
      expect(generalAverage([graded('Science', 0, hasWork: false)]), isNull);
    });
  });
}
