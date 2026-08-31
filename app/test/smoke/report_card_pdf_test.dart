import 'package:flutter_test/flutter_test.dart';

import 'package:logicclass/features/admin_portal/domain/entities/school_branding.dart';
import 'package:logicclass/features/faculty_portal/domain/entities/grade.dart';
import 'package:logicclass/features/faculty_portal/domain/entities/grading_scheme.dart';
import 'package:logicclass/features/faculty_portal/domain/entities/quarterly_grade.dart';
import 'package:logicclass/features/faculty_portal/presentation/documents/report_card_pdf.dart';

/// The report card renders, and refuses to render off an unconfirmed
/// scheme.
///
/// The refusal is the half worth testing. The weights this document is
/// computed from are seeded with the DepEd groupings -- transcribed from
/// a public order, not this software's assertion about anybody's grades
/// -- and a card printed on a school's letterhead off defaults nobody
/// there has checked would turn that transcription into the school's
/// claim about its own children.
void main() {
  Grade mark(
    String subject,
    String term,
    GradingComponent component,
    double score,
    double max,
  ) =>
      Grade(
        id: '$subject-$term-${component.value}',
        studentId: 'stu_1',
        studentName: 'Miguel Torres',
        subject: subject,
        section: 'Grade 10 - Rizal',
        term: term,
        component: component,
        score: score,
        maxScore: max,
        submittedByName: 'Maria Santos',
        submittedAt: DateTime(2026, 8, 1),
      );

  Map<String, List<QuarterlyGrade>> record(GradingScheme scheme) {
    const terms = ['1st Quarter', '2nd Quarter'];
    final marks = [
      for (final term in terms) ...[
        mark('Mathematics', term, GradingComponent.writtenWork, 34, 40),
        mark('Mathematics', term, GradingComponent.performanceTask, 88, 100),
        mark('Mathematics', term, GradingComponent.quarterlyAssessment, 42, 50),
        mark('Science', term, GradingComponent.writtenWork, 21, 25),
        mark('Science', term, GradingComponent.performanceTask, 92, 100),
      ],
      // A subject started this year and not yet graded at all. Its row
      // has to print blank rather than a column of noughts.
      mark('MAPEH', '1st Quarter', GradingComponent.writtenWork, 0, 0),
    ];

    return {
      for (final subject in {for (final m in marks) m.subject})
        subject: [
          for (final term in terms)
            computeQuarterlyGrade(
              subject: subject,
              term: term,
              grades: marks.where((m) => m.subject == subject && m.term == term),
              scheme: scheme,
            ),
        ],
    };
  }

  const branding = SchoolBranding(
    schoolName: 'Demo Academy of Bulacan',
    addressLine: 'Malolos, Bulacan',
    principalName: 'Elena Reyes',
    schoolYear: '2026-2027',
  );

  test('a confirmed scheme prints a report card', () async {
    const scheme = GradingScheme(
      weights: GradingScheme.depEdBasicEducationDefaults,
      confirmedBySchool: true,
      confirmedByName: 'Grace Mendoza',
    );

    final bytes = await ReportCardPdf.build(
      studentName: 'Miguel Torres',
      studentNumber: '2026-00001',
      classLabel: 'Grade 10 - Rizal',
      schoolYear: '2026-2027',
      terms: const ['1st Quarter', '2nd Quarter'],
      bySubject: record(scheme),
      scheme: scheme,
      branding: branding,
      preparedByName: 'Maria Santos',
      on: DateTime(2026, 8, 31),
    );

    expect(bytes.length, greaterThan(1000));
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
  });

  test('an unconfirmed scheme refuses, and says what to do about it', () async {
    const scheme = GradingScheme(weights: GradingScheme.depEdBasicEducationDefaults);

    expect(
      () => ReportCardPdf.build(
        studentName: 'Miguel Torres',
        studentNumber: '2026-00001',
        classLabel: 'Grade 10 - Rizal',
        schoolYear: '2026-2027',
        terms: const ['1st Quarter'],
        bySubject: record(scheme),
        scheme: scheme,
        branding: branding,
        preparedByName: 'Maria Santos',
      ),
      throwsA(isA<StateError>().having(
        (e) => e.message,
        'message',
        contains('Grading Scheme screen'),
      )),
    );
  });

  test('a student with no marks at all still prints', () async {
    // The card a school issues for a transferee who arrived last week.
    // Nothing to show is not a reason to fail to produce the document.
    const scheme = GradingScheme(
      weights: GradingScheme.depEdBasicEducationDefaults,
      confirmedBySchool: true,
    );

    final bytes = await ReportCardPdf.build(
      studentName: 'Ana Cruz',
      studentNumber: '2026-00099',
      classLabel: 'Grade 10 - Rizal',
      schoolYear: '2026-2027',
      terms: const [],
      bySubject: const {},
      scheme: scheme,
      branding: branding,
      preparedByName: 'Maria Santos',
    );

    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
  });

  test('the file name is safe to write to a disk', () {
    expect(ReportCardPdf.fileName('Miguel  Torres Jr.'), 'report-card-miguel-torres-jr-.pdf');
  });
}
