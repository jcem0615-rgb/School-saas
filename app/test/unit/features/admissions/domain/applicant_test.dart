import 'package:flutter_test/flutter_test.dart';

import 'package:logicclass/core/constants/education_level.dart';
import 'package:logicclass/features/admissions/domain/entities/applicant.dart';

/// The pipeline a private school's year is won or lost in.
///
/// What is being tested here is mostly not arithmetic. It is that the
/// stages cannot be set to whatever somebody expects, that a family who
/// went elsewhere is counted apart from one the school turned down, and
/// that the list of people to ring this morning is actually the people
/// nobody has rung.
void main() {
  Applicant applicant({
    String id = 'app_1',
    AdmissionStage stage = AdmissionStage.inquiry,
    DateTime? stageChangedAt,
    String? studentId,
    double? examScore,
    double? examMaxScore,
  }) =>
      Applicant(
        id: id,
        referenceNumber: 'A-0001',
        firstName: 'Bea',
        lastName: 'Torres',
        educationLevel: EducationLevel.highSchool,
        gradeLevel: 'Grade 7',
        guardianName: 'Rosario Torres',
        guardianPhone: '09171234567',
        stage: stage,
        inquiredAt: DateTime(2026, 1, 10),
        stageChangedAt: stageChangedAt ?? DateTime(2026, 1, 10),
        examScore: examScore,
        examMaxScore: examMaxScore,
        studentId: studentId,
      );

  group('where an applicant may be moved to', () {
    test('forward one step, back one step, or out', () {
      final next = nextStagesFrom(AdmissionStage.examScheduled);
      expect(next, contains(AdmissionStage.examTaken));
      expect(next, contains(AdmissionStage.applied));
      expect(next, contains(AdmissionStage.declined));
      expect(next, contains(AdmissionStage.withdrawn));
    });

    test('never several steps forward at once', () {
      // A pipeline whose stages can be set freely stops meaning
      // anything: somebody marks a family as offered because that is the
      // outcome they expect, and the funnel then reports offers the
      // school never made.
      expect(nextStagesFrom(AdmissionStage.inquiry), isNot(contains(AdmissionStage.offered)));
      expect(nextStagesFrom(AdmissionStage.inquiry), isNot(contains(AdmissionStage.enrolled)));
    });

    test('the first stage has nowhere to go back to', () {
      expect(nextStagesFrom(AdmissionStage.inquiry), [
        AdmissionStage.applied,
        AdmissionStage.declined,
        AdmissionStage.withdrawn,
      ]);
    });

    test('a family who came back starts again rather than resuming', () {
      expect(nextStagesFrom(AdmissionStage.withdrawn), [AdmissionStage.inquiry]);
      expect(nextStagesFrom(AdmissionStage.declined), [AdmissionStage.inquiry]);
    });

    test('nothing moves out of enrolled', () {
      // There is a student record behind it. Moving out would leave a
      // child enrolled in the school and an applicant record saying they
      // withdrew.
      expect(nextStagesFrom(AdmissionStage.enrolled), isEmpty);
    });
  });

  group('the entrance exam', () {
    test('is a percentage of what it was out of', () {
      final sat = applicant(examScore: 68, examMaxScore: 80);
      expect(sat.examPercentage, 85.0);
    });

    test('is nothing at all until it is sat', () {
      // Not zero. A child who has not taken the test has not failed it,
      // and a list sorted by score would put them below everybody who
      // did badly.
      expect(applicant().examPercentage, isNull);
      expect(applicant(examScore: 40).examPercentage, isNull);
    });

    test('an exam out of nothing is not a score', () {
      expect(applicant(examScore: 40, examMaxScore: 0).examPercentage, isNull);
    });
  });

  group('who to ring this morning', () {
    final today = DateTime(2026, 2, 20);

    test('open applicants nobody has moved in a week, longest wait first', () {
      final list = applicantsNeedingFollowUp(
        [
          applicant(id: 'a', stageChangedAt: DateTime(2026, 2, 1)),
          applicant(id: 'b', stageChangedAt: DateTime(2026, 2, 12)),
          applicant(id: 'c', stageChangedAt: DateTime(2026, 2, 19)),
        ],
        asOf: today,
      );
      expect(list.map((a) => a.id), ['a', 'b']);
    });

    test('leaves out the ones who are finished, however long ago', () {
      // An enrolled family is not waiting for a phone call, and a list
      // that says they are is a list the office stops reading.
      final list = applicantsNeedingFollowUp(
        [
          applicant(
              id: 'enrolled',
              stage: AdmissionStage.enrolled,
              studentId: 'stu_1',
              stageChangedAt: DateTime(2025, 8, 1)),
          applicant(
              id: 'gone',
              stage: AdmissionStage.withdrawn,
              stageChangedAt: DateTime(2025, 8, 1)),
          applicant(id: 'waiting', stageChangedAt: DateTime(2026, 2, 1)),
        ],
        asOf: today,
      );
      expect(list.map((a) => a.id), ['waiting']);
    });

    test('counts days in the stage, not days since the enquiry', () {
      // A family being actively worked through the stages is not going
      // cold, however long ago they first rang.
      final busy = applicant(
        stage: AdmissionStage.offered,
        stageChangedAt: DateTime(2026, 2, 19),
      );
      expect(busy.daysInStage(today), 1);
      expect(applicantsNeedingFollowUp([busy], asOf: today), isEmpty);
    });
  });

  group('the funnel', () {
    final applicants = [
      applicant(id: '1'),
      applicant(id: '2'),
      applicant(id: '3', stage: AdmissionStage.applied),
      applicant(id: '4', stage: AdmissionStage.offered),
      applicant(id: '5', stage: AdmissionStage.enrolled, studentId: 'stu_5'),
      applicant(id: '6', stage: AdmissionStage.enrolled, studentId: 'stu_6'),
      applicant(id: '7', stage: AdmissionStage.declined),
      applicant(id: '8', stage: AdmissionStage.withdrawn),
    ];

    test('counts who is where right now', () {
      final funnel = AdmissionFunnel.of(applicants);
      expect(funnel.nowIn[AdmissionStage.inquiry], 2);
      expect(funnel.nowIn[AdmissionStage.enrolled], 2);
      expect(funnel.total, 8);
    });

    test('counts who has got at least this far', () {
      // Both numbers are needed. Forty families are at the enquiry stage
      // today; four hundred passed through it this year, and a report
      // giving only the first looks like a school with no pipeline at
      // all by June.
      final funnel = AdmissionFunnel.of(applicants);
      // Everybody still on the pipeline: the two at enquiry, the one who
      // applied, the one offered, and the two enrolled. The declined and
      // the withdrawn are not on it -- see the comment on the factory.
      expect(funnel.reached[AdmissionStage.inquiry], 6);
      expect(funnel.reached[AdmissionStage.offered], 3);
      expect(funnel.reached[AdmissionStage.enrolled], 2);
    });

    test('keeps "we said no" apart from "they went elsewhere"', () {
      // Different problems, and only one of them is the school's doing.
      final funnel = AdmissionFunnel.of(applicants);
      expect(funnel.declined, 1);
      expect(funnel.withdrawn, 1);
      expect(funnel.open, 4);
    });

    test('converts enrolments against everybody who ever enquired', () {
      expect(AdmissionFunnel.of(applicants).conversionRate, 25.0);
    });

    test('a stage nobody has reached has no rate, rather than zero', () {
      // 0% for a stage nobody has got to yet is a report that reads as a
      // disaster when nothing has happened at all.
      final early = AdmissionFunnel.of([applicant(id: '1')]);
      expect(early.rateBetween(AdmissionStage.offered, AdmissionStage.enrolled), isNull);
      expect(early.conversionRate, 0.0);
    });

    test('an empty year has no conversion rate at all', () {
      expect(AdmissionFunnel.of(const []).conversionRate, isNull);
    });
  });

  test('an applicant with a student behind them has enrolled', () {
    expect(applicant(stage: AdmissionStage.enrolled, studentId: 'stu_1').hasEnrolled, isTrue);
    expect(applicant().hasEnrolled, isFalse);
  });
}
