import 'package:flutter_test/flutter_test.dart';

import 'package:logicclass/core/constants/education_level.dart';
import 'package:logicclass/features/faculty_portal/domain/entities/grade.dart';
import 'package:logicclass/features/payments/domain/entities/assessment.dart';
import 'package:logicclass/features/payments/domain/entities/fee_structure.dart';
import 'package:logicclass/features/payments/domain/entities/payment.dart';
import 'package:logicclass/features/qr_attendance/domain/entities/attendance_record.dart';
import 'package:logicclass/features/registrar_portal/domain/entities/student_summary.dart';
import 'package:logicclass/features/reports/domain/entities/report_period.dart';
import 'package:logicclass/features/reports/domain/entities/report_table.dart';
import 'package:logicclass/features/reports/domain/usecases/attendance_report.dart';
import 'package:logicclass/features/reports/domain/usecases/collections_report.dart';
import 'package:logicclass/features/reports/domain/usecases/enrollment_report.dart';
import 'package:logicclass/features/reports/domain/usecases/grade_distribution_report.dart';

/// The builders are pure functions over lists, which is the point: the
/// arithmetic a school will quote to a division office is checkable here
/// without a database in the loop.

StudentSummary student({
  required String id,
  EducationLevel level = EducationLevel.highSchool,
  String gradeLevel = 'Grade 10',
  String section = 'Rizal',
  StudentStatus status = StudentStatus.enrolled,
  double balance = 0,
}) =>
    StudentSummary(
      id: id,
      studentNumber: id,
      firstName: 'First',
      lastName: id,
      educationLevel: level,
      gradeLevel: gradeLevel,
      section: section,
      status: status,
      balance: balance,
      enrollmentDate: DateTime(2026, 6, 1),
    );

Payment payment({
  required String studentId,
  required double amount,
  required DateTime on,
  String? refundOf,
  PaymentStatus status = PaymentStatus.completed,
}) =>
    Payment(
      id: 'pay_$studentId$amount${on.millisecondsSinceEpoch}',
      studentId: studentId,
      amount: amount,
      method: PaymentMethod.cash,
      receiptNumber: 'OR-1',
      collectedByName: 'Cashier',
      purpose: PaymentPurpose.tuition,
      status: status,
      createdAt: on,
      refundOf: refundOf,
    );

Assessment assessment({
  required String studentId,
  required double amount,
  required DateTime on,
  DateTime? voidedAt,
}) =>
    Assessment(
      id: 'a_$studentId${on.millisecondsSinceEpoch}',
      studentId: studentId,
      studentName: studentId,
      schoolYear: '2026-2027',
      items: [FeeItem(label: 'Tuition', amount: amount, category: FeeCategory.tuition)],
      assessedByName: 'Registrar',
      assessedAt: on,
      voidedAt: voidedAt,
    );

AttendanceRecord attendance({
  required String personId,
  required String date,
  AttendanceStatus status = AttendanceStatus.present,
  AttendanceSubjectType subjectType = AttendanceSubjectType.student,
}) =>
    AttendanceRecord(
      id: 'att_$personId$date${status.value}',
      personId: personId,
      personRole: 'student',
      subjectType: subjectType,
      date: date,
      timestampIn: DateTime.parse('${date}T07:30:00'),
      status: status,
    );

Grade grade({
  required String studentId,
  required double score,
  String subject = 'Mathematics',
  String section = 'Rizal',
  String term = '1st Quarter',
  double maxScore = 100,
  DateTime? on,
}) =>
    Grade(
      id: 'g_$studentId$subject$score$term',
      studentId: studentId,
      studentName: studentId,
      subject: subject,
      section: section,
      term: term,
      score: score,
      maxScore: maxScore,
      submittedByName: 'Teacher',
      submittedAt: on ?? DateTime(2026, 8, 10),
    );

String cell(ReportTable table, String rowStartsWith, String column) {
  final index = table.headers.indexOf(column);
  expect(index, isNot(-1), reason: 'no column "$column" in ${table.headers}');
  final row = table.rows.firstWhere(
    (r) => r.cells.first == rowStartsWith,
    orElse: () => throw StateError('no row "$rowStartsWith" in '
        '${table.rows.map((r) => r.cells.first).toList()}'),
  );
  return row.cells[index];
}

void main() {
  final period = ReportPeriod(DateTime(2026, 8, 1), DateTime(2026, 8, 31));

  group('ReportPeriod', () {
    // The half-open convention would drop the last day, and nobody would
    // notice until the totals were compared against a bank statement.
    test('includes the whole of the last day', () {
      expect(period.contains(DateTime(2026, 8, 31, 23, 59)), isTrue);
      expect(period.contains(DateTime(2026, 9, 1)), isFalse);
    });

    test('a school year asked for in January is the one that began last June', () {
      final year = ReportPeriod.schoolYearOf(DateTime(2027, 1, 15));
      expect(year.start, DateTime(2026, 6, 1));
      expect(year.end.year, 2027);
      expect(year.end.month, 3);
    });

    test('counts both ends of the range as days', () {
      expect(ReportPeriod(DateTime(2026, 8, 1), DateTime(2026, 8, 1)).dayCount, 1);
      expect(period.dayCount, 31);
    });
  });

  group('EnrollmentReport', () {
    test('counts every status, not just the survivors', () {
      final table = EnrollmentReport.build([
        student(id: 's1'),
        student(id: 's2'),
        student(id: 's3', status: StudentStatus.transferredOut),
        student(id: 's4', level: EducationLevel.elementary, gradeLevel: 'Grade 4', section: 'Sampaguita'),
      ]);

      expect(cell(table, 'Junior High School', 'Enrolled'), '2');
      expect(cell(table, 'Junior High School', 'Transferred Out'), '1');
      expect(cell(table, 'Junior High School', 'Total'), '3');
      expect(cell(table, 'All divisions', 'Total'), '4');
    });

    test('counts a section once however many students are in it', () {
      final table = EnrollmentReport.build([
        student(id: 's1', section: 'Rizal'),
        student(id: 's2', section: 'Rizal'),
        student(id: 's3', section: 'Bonifacio'),
      ]);
      expect(cell(table, 'Junior High School', 'Sections'), '2');
    });

    test('says the head count is taken today', () {
      final table = EnrollmentReport.build([student(id: 's1')]);
      expect(table.note, contains('as it stands today'));
    });
  });

  group('CollectionsReport', () {
    ReportTable build({
      List<StudentSummary>? students,
      List<Payment>? payments,
      List<Assessment>? assessments,
    }) =>
        CollectionsReport.build(
          period: period,
          students: students ?? [student(id: 's1', balance: 8500)],
          payments: payments ?? const [],
          assessments: assessments ?? const [],
        );

    test('a refund reduces what was collected', () {
      final table = build(payments: [
        payment(studentId: 's1', amount: 5000, on: DateTime(2026, 8, 5)),
        payment(
          studentId: 's1',
          amount: -2000,
          on: DateTime(2026, 8, 6),
          refundOf: 'pay_original',
        ),
      ]);
      expect(cell(table, 'Junior High School', 'Collected'), '₱3,000.00');
    });

    test('a payment outside the period is not counted', () {
      final table = build(payments: [
        payment(studentId: 's1', amount: 5000, on: DateTime(2026, 7, 31)),
      ]);
      expect(cell(table, 'Junior High School', 'Collected'), '₱0.00');
    });

    // One family's overpayment must not quietly settle another family's
    // arrears -- receivables would come out short and nobody chasing it.
    test('a credit balance is excluded from receivables and disclosed', () {
      final table = build(students: [
        student(id: 's1', balance: 8500),
        student(id: 's2', balance: -1500),
      ]);
      expect(cell(table, 'Junior High School', 'Outstanding'), '₱8,500.00');
      expect(cell(table, 'Junior High School', 'Owing'), '1');
      expect(table.note, contains('Credit balances totalling ₱1,500.00'));
    });

    test('a voided assessment charges nothing', () {
      final table = build(assessments: [
        assessment(studentId: 's1', amount: 17000, on: DateTime(2026, 8, 2)),
        assessment(
          studentId: 's1',
          amount: 5000,
          on: DateTime(2026, 8, 3),
          voidedAt: DateTime(2026, 8, 9),
        ),
      ]);
      expect(cell(table, 'Junior High School', 'Assessed'), '₱17,000.00');
    });

    test('the ratio is left blank rather than dividing by nothing', () {
      final table = build(assessments: const []);
      expect(cell(table, 'Junior High School', 'Collected / Assessed'), '-');
    });

    test('says outright that outstanding is not a period figure', () {
      expect(build().note, contains('as it stands today'));
    });
  });

  group('AttendanceReport', () {
    ReportTable build(List<AttendanceRecord> records, {List<StudentSummary>? students}) =>
        AttendanceReport.build(
          period: period,
          students: students ?? [student(id: 's1'), student(id: 's2')],
          records: records,
        );

    test('a late student counts as having come to school', () {
      final table = build([
        attendance(personId: 's1', date: '2026-08-03'),
        attendance(personId: 's2', date: '2026-08-03', status: AttendanceStatus.late),
      ]);
      expect(cell(table, 'Junior High School', 'Rate'), '100.0%');
      expect(cell(table, 'Junior High School', 'Late'), '1');
    });

    // An outbreak is not a discipline problem, and the rate must not
    // report it as one.
    test('an excused absence sits outside the rate entirely', () {
      final table = build([
        attendance(personId: 's1', date: '2026-08-03'),
        attendance(personId: 's2', date: '2026-08-03', status: AttendanceStatus.excused),
      ]);
      expect(cell(table, 'Junior High School', 'Rate'), '100.0%');
      expect(cell(table, 'Junior High School', 'Excused'), '1');
    });

    test('an absence pulls the rate down', () {
      final table = build([
        attendance(personId: 's1', date: '2026-08-03'),
        attendance(personId: 's2', date: '2026-08-03', status: AttendanceStatus.absent),
      ]);
      expect(cell(table, 'Junior High School', 'Rate'), '50.0%');
    });

    test('records outside the period and staff scans are left out', () {
      final table = build([
        attendance(personId: 's1', date: '2026-07-30'),
        attendance(
          personId: 's1',
          date: '2026-08-03',
          subjectType: AttendanceSubjectType.employee,
        ),
        attendance(personId: 's2', date: '2026-08-04'),
      ]);
      expect(cell(table, 'Junior High School', 'Records'), '1');
      expect(cell(table, 'Junior High School', 'Days'), '1');
    });

    // A rate computed over an unknown fraction of the scans is not a rate.
    test('scans against invisible students are reported, not dropped quietly', () {
      final table = build([
        attendance(personId: 's1', date: '2026-08-03'),
        attendance(personId: 'ghost', date: '2026-08-03'),
      ]);
      expect(table.note, contains('1 record is excluded'));
    });
  });

  group('GradeDistributionReport', () {
    ReportTable build(List<Grade> grades, {String? term}) =>
        GradeDistributionReport.build(period: period, grades: grades, term: term);

    test('bands marks on the DepEd descriptors', () {
      final table = build([
        grade(studentId: 's1', score: 92, on: DateTime(2026, 8, 3)),
        grade(studentId: 's2', score: 86, on: DateTime(2026, 8, 3)),
        grade(studentId: 's3', score: 81, on: DateTime(2026, 8, 3)),
        grade(studentId: 's4', score: 75, on: DateTime(2026, 8, 3)),
        grade(studentId: 's5', score: 74, on: DateTime(2026, 8, 3)),
      ]);
      expect(cell(table, 'Mathematics', 'O (90+)'), '1');
      expect(cell(table, 'Mathematics', 'VS (85-89)'), '1');
      expect(cell(table, 'Mathematics', 'S (80-84)'), '1');
      expect(cell(table, 'Mathematics', 'FS (75-79)'), '1');
      expect(cell(table, 'Mathematics', 'DNME (below 75)'), '1');
      expect(cell(table, 'Mathematics', 'At or above 75'), '80.0%');
    });

    // 75 is the passing mark, so it belongs above the line, not below.
    test('exactly 75 passes', () {
      final table = build([grade(studentId: 's1', score: 75, on: DateTime(2026, 8, 3))]);
      expect(cell(table, 'Mathematics', 'DNME (below 75)'), '0');
      expect(cell(table, 'Mathematics', 'At or above 75'), '100.0%');
    });

    test('scores are banded on percentage, not raw marks', () {
      final table = build([
        grade(studentId: 's1', score: 19, maxScore: 20, on: DateTime(2026, 8, 3)),
      ]);
      expect(cell(table, 'Mathematics', 'O (90+)'), '1');
      expect(cell(table, 'Mathematics', 'Average %'), '95.0');
    });

    test('a mark out of zero is skipped rather than banded', () {
      final table = build([
        grade(studentId: 's1', score: 0, maxScore: 0, on: DateTime(2026, 8, 3)),
        grade(studentId: 's2', score: 90, on: DateTime(2026, 8, 3)),
      ]);
      expect(cell(table, 'Mathematics', 'Marks'), '1');
    });

    test('offers the terms that were actually used', () {
      final table = build([
        grade(studentId: 's1', score: 90, term: '1st Quarter', on: DateTime(2026, 8, 3)),
        grade(studentId: 's2', score: 80, term: '2nd Quarter', on: DateTime(2026, 8, 4)),
      ]);
      expect(table.filterLabel, 'Term');
      expect(table.filterOptions, ['1st Quarter', '2nd Quarter']);
      expect(table.note, contains('Marks from 2 terms'));
    });

    test('filtering to a term keeps the other terms on offer', () {
      final table = build([
        grade(studentId: 's1', score: 90, term: '1st Quarter', on: DateTime(2026, 8, 3)),
        grade(studentId: 's2', score: 80, term: '2nd Quarter', on: DateTime(2026, 8, 4)),
      ], term: '1st Quarter');
      expect(cell(table, 'Mathematics', 'Marks'), '1');
      expect(
        table.filterOptions,
        ['1st Quarter', '2nd Quarter'],
        reason: 'a filter that removes its own alternatives is a one-way door',
      );
    });

    test('splits the same subject taught to two sections', () {
      final table = build([
        grade(studentId: 's1', score: 90, section: 'Rizal', on: DateTime(2026, 8, 3)),
        grade(studentId: 's2', score: 70, section: 'Bonifacio', on: DateTime(2026, 8, 3)),
      ]);
      expect(table.rows.where((r) => !r.isTotal).length, 2);
      expect(cell(table, 'All subjects', 'Marks'), '2');
    });
  });
}
