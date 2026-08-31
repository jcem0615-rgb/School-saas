import 'package:flutter_test/flutter_test.dart';

import 'package:logicclass/core/constants/education_level.dart';
import 'package:logicclass/features/faculty_portal/domain/entities/grading_scheme.dart';
import 'package:logicclass/features/faculty_portal/domain/entities/quarterly_grade.dart';
import 'package:logicclass/features/registrar_portal/domain/entities/promotion.dart';
import 'package:logicclass/features/registrar_portal/domain/entities/student_summary.dart';

/// Deciding who moves up a year.
///
/// The least reversible thing this system does. A promotion written
/// wrongly puts a child in a class they cannot follow; a retention
/// written wrongly holds one back for a year. Nothing here decides
/// anything on its own -- these produce a recommendation a registrar
/// reads and can change -- but a recommendation that is quietly wrong is
/// the one that gets accepted without being read.
void main() {
  StudentSummary student({
    String id = 'stu_1',
    String gradeLevel = 'Grade 9',
    EducationLevel level = EducationLevel.highSchool,
  }) =>
      StudentSummary(
        id: id,
        studentNumber: '2026-00001',
        firstName: 'Miguel',
        lastName: 'Torres',
        educationLevel: level,
        gradeLevel: gradeLevel,
        section: '$gradeLevel - Rizal',
        status: StudentStatus.enrolled,
        balance: 0,
        enrollmentDate: DateTime(2026, 6, 1),
      );

  QuarterlyGrade mark(String subject, String term, int grade) => QuarterlyGrade(
        subject: subject,
        term: term,
        weights: const GradingScheme(weights: GradingScheme.depEdBasicEducationDefaults)
            .weightsFor(subject),
        components: const [],
        initialGrade: grade.toDouble(),
        finalGrade: grade,
        hasWork: true,
      );

  List<QuarterlyGrade> year(Map<String, int> bySubject) => [
        for (final entry in bySubject.entries)
          for (final term in ['1st Quarter', '2nd Quarter', '3rd Quarter', '4th Quarter'])
            mark(entry.key, term, entry.value),
      ];

  PromotionCandidate recommend(
    Map<String, int> grades, {
    StudentSummary? who,
    Set<EducationLevel> divisions = const {EducationLevel.highSchool},
  }) =>
      recommendPromotion(
        student: who ?? student(),
        yearsGrades: year(grades),
        divisionsInUse: divisions,
      );

  group('reading the next year out of what the school typed', () {
    test('the ordinary case', () {
      expect(nextGradeLevel('Grade 9'), 'Grade 10');
      expect(nextGradeLevel('Grade 1'), 'Grade 2');
    });

    test('an ordinal moves with its number', () {
      // "2st Year" is what a naive increment produces, and it would go
      // on every class list in the school.
      expect(nextGradeLevel('1st Year'), '2nd Year');
      expect(nextGradeLevel('2nd Year'), '3rd Year');
      expect(nextGradeLevel('3rd Year'), '4th Year');
    });

    test('whatever else the school wrote is kept', () {
      expect(nextGradeLevel('Yr 7 (SPED)'), 'Yr 8 (SPED)');
    });

    test('refuses rather than guesses when there is no single number', () {
      // A guess here puts a child in the wrong year and nobody finds out
      // until June. The screen turns a null into a question.
      expect(nextGradeLevel('Kinder'), isNull);
      expect(nextGradeLevel('Grade 11 - STEM 2'), isNull);
      expect(nextGradeLevel(''), isNull);
    });
  });

  group('the recommendation', () {
    test('every subject passed is a promotion', () {
      final candidate = recommend({'Mathematics': 88, 'Science': 91, 'English': 85});
      expect(candidate.recommended, PromotionOutcome.promoted);
      expect(candidate.generalAverage, 88);
      expect(candidate.nextGradeLevel, 'Grade 10');
      expect(candidate.failedSubjects, isEmpty);
    });

    test('one or two failures is remedial work, not a promotion', () {
      final candidate = recommend({'Mathematics': 72, 'Science': 91, 'English': 85});
      expect(candidate.recommended, PromotionOutcome.conditional);
      expect(candidate.failedSubjects, ['Mathematics']);
      // The outcome exists so that leaving the row alone cannot promote
      // a student who has not sat the remedial classes yet.
      expect(candidate.recommended.advances, isFalse);
    });

    test('three failures is a retention', () {
      final candidate = recommend({
        'Mathematics': 72,
        'Science': 70,
        'English': 74,
        'Filipino': 88,
      });
      expect(candidate.recommended, PromotionOutcome.retained);
      expect(candidate.failedSubjects, ['English', 'Mathematics', 'Science']);
    });

    test('74 fails and 75 passes, per subject', () {
      expect(recommend({'Mathematics': 75, 'Science': 90}).failedSubjects, isEmpty);
      expect(recommend({'Mathematics': 74, 'Science': 90}).failedSubjects, ['Mathematics']);
    });

    test('a good average does not rescue a failed subject', () {
      // The rule is per subject, not on the average. A child with a 95
      // in five subjects and a 60 in one has a subject to make up.
      final candidate = recommend({
        'Mathematics': 60,
        'Science': 95,
        'English': 95,
        'Filipino': 95,
      });
      expect(candidate.generalAverage, greaterThan(85));
      expect(candidate.recommended, PromotionOutcome.conditional);
    });

    test('a student with nothing on file is held, not promoted', () {
      // Promoting off no evidence would move a child up a year on the
      // strength of a teacher not having entered anything.
      final candidate = recommend(const {});
      expect(candidate.recommended, PromotionOutcome.held);
      expect(candidate.generalAverage, isNull);
      expect(candidate.reason, contains('No grades on file'));
    });

    test('a subject the teacher never graded is not a failed subject', () {
      final candidate = recommendPromotion(
        student: student(),
        yearsGrades: [
          ...year({'Mathematics': 88}),
          QuarterlyGrade(
            subject: 'MAPEH',
            term: '1st Quarter',
            weights: const SubjectWeights(
              label: 'MAPEH',
              writtenWork: 20,
              performanceTask: 60,
              quarterlyAssessment: 20,
            ),
            components: const [],
            initialGrade: 0,
            finalGrade: 0,
            hasWork: false,
          ),
        ],
        divisionsInUse: const {EducationLevel.highSchool},
      );
      expect(candidate.failedSubjects, isEmpty);
      expect(candidate.finalGradeBySubject.keys, ['Mathematics']);
    });

    test('the year grade is the mean of the quarters that have marks', () {
      final candidate = recommendPromotion(
        student: student(),
        yearsGrades: [
          mark('Mathematics', '1st Quarter', 80),
          mark('Mathematics', '2nd Quarter', 90),
          // The fourth quarter has not happened. Averaging over three is
          // right; averaging over four with a zero is not.
          mark('Mathematics', '3rd Quarter', 85),
        ],
        divisionsInUse: const {EducationLevel.highSchool},
      );
      expect(candidate.finalGradeBySubject['Mathematics'], 85);
    });
  });

  group('graduating, which depends on what the school runs', () {
    test('Grade 10 graduates when the school has no Senior High', () {
      final candidate = recommend(
        {'Mathematics': 88},
        who: student(gradeLevel: 'Grade 10'),
        divisions: const {EducationLevel.elementary, EducationLevel.highSchool},
      );
      expect(candidate.recommended, PromotionOutcome.graduated);
    });

    test('Grade 10 moves up when the same school runs Senior High', () {
      final candidate = recommend(
        {'Mathematics': 88},
        who: student(gradeLevel: 'Grade 10'),
        divisions: const {EducationLevel.highSchool, EducationLevel.seniorHigh},
      );
      expect(candidate.recommended, PromotionOutcome.promoted);
      expect(candidate.nextGradeLevel, 'Grade 11');
    });

    test('Grade 6 moves up when the school runs a Junior High', () {
      final candidate = recommend(
        {'Mathematics': 88},
        who: student(gradeLevel: 'Grade 6', level: EducationLevel.elementary),
        divisions: const {EducationLevel.elementary, EducationLevel.highSchool},
      );
      expect(candidate.recommended, PromotionOutcome.promoted);
      expect(candidate.nextGradeLevel, 'Grade 7');
    });

    test('Grade 12 graduates even from a school with a college', () {
      // A Senior High graduate applies to college; they are not rolled
      // into it.
      final candidate = recommend(
        {'Mathematics': 88},
        who: student(gradeLevel: 'Grade 12', level: EducationLevel.seniorHigh),
        divisions: const {EducationLevel.seniorHigh, EducationLevel.college},
      );
      expect(candidate.recommended, PromotionOutcome.graduated);
    });

    test('a failed subject in the exit year is still remedial, not a diploma', () {
      final candidate = recommend(
        {'Mathematics': 60, 'Science': 90},
        who: student(gradeLevel: 'Grade 10'),
        divisions: const {EducationLevel.highSchool},
      );
      expect(candidate.recommended, PromotionOutcome.conditional);
    });
  });

  group('the section name carried forward', () {
    test('swaps the year inside it', () {
      expect(
        nextSectionName(
          section: 'Grade 9 - Rizal',
          fromGradeLevel: 'Grade 9',
          toGradeLevel: 'Grade 10',
        ),
        'Grade 10 - Rizal',
      );
    });

    test('leaves the rest of the name alone', () {
      expect(
        nextSectionName(
          section: 'Grade 9 - St. Therese (AM)',
          fromGradeLevel: 'Grade 9',
          toGradeLevel: 'Grade 10',
        ),
        'Grade 10 - St. Therese (AM)',
      );
    });

    test('refuses when the year is not in the name', () {
      // Guessing would produce a section that does not exist and put a
      // whole class in it. The field is left empty and typed instead.
      expect(
        nextSectionName(
          section: 'Sampaguita',
          fromGradeLevel: 'Grade 9',
          toGradeLevel: 'Grade 10',
        ),
        isNull,
      );
    });
  });

  group('which school year it is', () {
    test('June onwards is the year that just opened', () {
      expect(currentSchoolYear(DateTime(2026, 6, 15)), '2026-2027');
      expect(currentSchoolYear(DateTime(2026, 12, 1)), '2026-2027');
    });

    test('before June is still the year that opened last June', () {
      // Backwards here would default the rollover screen to a year that
      // has not happened yet.
      expect(currentSchoolYear(DateTime(2027, 3, 20)), '2026-2027');
      expect(currentSchoolYear(DateTime(2027, 5, 31)), '2026-2027');
    });
  });

  group('the summary a registrar reports', () {
    test('counts every outcome, and they add up', () {
      final summary = RolloverSummary.of([
        PromotionOutcome.promoted,
        PromotionOutcome.promoted,
        PromotionOutcome.retained,
        PromotionOutcome.graduated,
        PromotionOutcome.conditional,
        PromotionOutcome.held,
      ]);
      expect(summary.promoted, 2);
      expect(summary.retained, 1);
      expect(summary.graduated, 1);
      expect(summary.conditional, 1);
      expect(summary.held, 1);
      expect(summary.total, 6);
    });
  });

  test('"no decision" is not something a rollover writes down', () {
    // A promotion record marks a student as done for the year and is
    // what a re-run skips on, so writing one for somebody nobody has
    // decided about would lock them out of the rollover for good. The
    // registrar who runs this before the last marks are in has to be
    // able to come back for them.
    const held = PromotionDecision(
      studentId: 'stu_1',
      studentName: 'Miguel Torres',
      recommended: PromotionOutcome.held,
      outcome: PromotionOutcome.held,
      fromGradeLevel: 'Grade 9',
      fromSection: 'Grade 9 - Rizal',
      toGradeLevel: '',
      toSection: '',
      generalAverage: null,
      failedSubjects: [],
    );
    expect(held.outcome.advances, isFalse);
    expect(held.recommended, PromotionOutcome.held);
  });

  test('a decision that departs from the recommendation says so', () {
    // The record keeps both, so an override is visible afterwards
    // rather than looking like what the marks said all along.
    const decision = PromotionDecision(
      studentId: 'stu_1',
      studentName: 'Miguel Torres',
      recommended: PromotionOutcome.retained,
      outcome: PromotionOutcome.conditional,
      fromGradeLevel: 'Grade 9',
      fromSection: 'Grade 9 - Rizal',
      toGradeLevel: '',
      toSection: '',
      generalAverage: 74,
      failedSubjects: ['Mathematics', 'Science', 'English'],
    );
    expect(decision.departsFromRecommendation, isTrue);
  });
}
