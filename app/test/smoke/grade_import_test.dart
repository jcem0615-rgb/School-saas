import 'package:flutter_test/flutter_test.dart';

import 'package:logicclass/core/constants/education_level.dart';
import 'package:logicclass/core/data_transfer/csv.dart' show ImportIssue;
import 'package:logicclass/features/faculty_portal/domain/entities/grade.dart';
import 'package:logicclass/features/faculty_portal/presentation/import/grade_import.dart';
import 'package:logicclass/features/registrar_portal/domain/entities/student_summary.dart';

/// A grade import writes to a student's permanent record, and the thing
/// that can go quietly wrong is attribution: a mark landing on the wrong
/// student because two of them share a name, or a term being posted
/// twice. Most of these tests are about that.
void main() {
  StudentSummary student({
    required String id,
    required String number,
    required String first,
    required String last,
    String? middle,
  }) =>
      StudentSummary(
        id: id,
        studentNumber: number,
        firstName: first,
        lastName: last,
        middleName: middle,
        educationLevel: EducationLevel.highSchool,
        gradeLevel: 'Grade 10',
        section: 'Grade 10 - Rizal',
        status: StudentStatus.enrolled,
        balance: 0,
        enrollmentDate: DateTime(2025, 6, 1),
      );

  final roster = [
    student(id: 'stu_1', number: '2025-00001', first: 'Maria', last: 'Santos', middle: 'Cruz'),
    student(id: 'stu_2', number: '2025-00002', first: 'Miguel', last: 'Torres'),
  ];

  List<String> row({
    String name = 'Maria Santos',
    String term = 'Q1',
    String score = '88',
    String maxScore = '100',
    String remarks = '',
  }) =>
      [name, term, score, maxScore, remarks];

  Object? parse(
    List<String> r, {
    List<StudentSummary>? students,
    List<Grade> existing = const [],
    Set<String>? seen,
  }) =>
      GradeImport.parseRow(
        row: r,
        rowNumber: 2,
        roster: students ?? roster,
        existing: existing,
        seen: seen ?? <String>{},
      );

  Grade posted({required String studentId, required String term}) => Grade(
        id: 'gr_1',
        studentId: studentId,
        studentName: 'Maria Santos',
        subject: 'Mathematics',
        section: 'Grade 10 - Rizal',
        term: term,
        score: 80,
        maxScore: 100,
        submittedByName: 'Maria Santos',
        submittedAt: DateTime(2026, 1, 1),
      );

  group('a good row', () {
    test('becomes a mark against the right student', () {
      final g = parse(row()) as GradeImportRow;
      expect(g.studentId, 'stu_1');
      expect(g.studentName, 'Maria Santos');
      expect(g.term, 'Q1');
      expect(g.score, 88);
      expect(g.maxScore, 100);
    });

    test('matches a student by their number', () {
      final g = parse(row(name: '2025-00002')) as GradeImportRow;
      expect(g.studentId, 'stu_2');
    });

    test('matches a class list sorted surname-first', () {
      final g = parse(row(name: 'Santos, Maria')) as GradeImportRow;
      expect(g.studentId, 'stu_1');
    });

    test('matches a name carrying the middle name', () {
      final g = parse(row(name: 'Maria Cruz Santos')) as GradeImportRow;
      expect(g.studentId, 'stu_1');
    });

    test('tolerates the double space a copied name carries', () {
      final g = parse(row(name: 'Maria  Santos')) as GradeImportRow;
      expect(g.studentId, 'stu_1');
    });

    test('takes a blank max score as a mark out of 100', () {
      final g = parse(row(maxScore: '')) as GradeImportRow;
      expect(g.maxScore, GradeImport.defaultMaxScore);
    });

    test('keeps a remark, and drops an empty one', () {
      expect((parse(row(remarks: 'Improved')) as GradeImportRow).remarks, 'Improved');
      expect((parse(row(remarks: '  ')) as GradeImportRow).remarks, isNull);
    });
  });

  group('refuses', () {
    test('a student who is not in this section', () {
      final issue = parse(row(name: 'Andrea Villanueva')) as ImportIssue;
      expect(issue.message, contains('not in this section'));
    });

    test('a name two students in the class share', () {
      // The failure this exists for: silently posting somebody else's
      // mark onto a permanent record.
      final twins = [
        student(id: 'stu_a', number: '2025-00010', first: 'Juan', last: 'Reyes'),
        student(id: 'stu_b', number: '2025-00011', first: 'Juan', last: 'Reyes'),
      ];
      final issue = parse(row(name: 'Juan Reyes'), students: twins) as ImportIssue;
      expect(issue.message, contains('More than one student'));
      expect(issue.message, contains('2025-00010'));
      expect(issue.message, contains('2025-00011'));
    });

    test('a missing term', () {
      expect(parse(row(term: '')), isA<ImportIssue>());
    });

    test('a score above the max score', () {
      // Almost always the two columns filled in the wrong order, and it
      // would enter the average as a mark over 100%.
      final issue = parse(row(score: '100', maxScore: '40')) as ImportIssue;
      expect(issue.message, contains('higher than the max score'));
    });

    test('a negative score and a zero max score', () {
      expect(parse(row(score: '-5')), isA<ImportIssue>());
      expect(parse(row(maxScore: '0')), isA<ImportIssue>());
    });

    test('an unreadable score', () {
      expect(parse(row(score: 'absent')), isA<ImportIssue>());
    });

    test('a term the student already has a mark for', () {
      // submitGrade writes a new document every time, so a re-run would
      // leave two marks for one term and no way to tell which was meant.
      final issue = parse(
        row(),
        existing: [posted(studentId: 'stu_1', term: 'Q1')],
      ) as ImportIssue;
      expect(issue.message, contains('already has a Q1 mark'));
    });

    test('the same student twice for one term in one file', () {
      final seen = <String>{};
      expect(parse(row(), seen: seen), isA<GradeImportRow>());
      final issue = parse(row(), seen: seen) as ImportIssue;
      expect(issue.message, contains('appears twice'));
    });

    test('nothing when the same student appears for two different terms', () {
      final seen = <String>{};
      expect(parse(row(term: 'Q1'), seen: seen), isA<GradeImportRow>());
      expect(parse(row(term: 'Q2'), seen: seen), isA<GradeImportRow>());
    });
  });
}
