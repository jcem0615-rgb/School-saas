import 'package:intl/intl.dart';

import '../../../director_portal/domain/entities/approval_request.dart';
import '../../../payments/domain/entities/assessment.dart';
import '../../../payments/domain/entities/clearance.dart';
import '../../../payments/domain/entities/payment.dart';
import '../../../registrar_portal/domain/entities/student_summary.dart';
import '../entities/report_table.dart';

final _peso = NumberFormat.currency(locale: 'en_PH', symbol: '₱');
final _dayFormat = DateFormat('d MMM y');

/// Who may sit the examination.
///
/// The permit is the lever a private school actually uses to collect: the
/// cashier signs a slip and the proctor turns away anybody without one.
/// Before this the cashier worked from a printed balance list and a
/// memory of who had been given more time, which is why the promissory
/// note in the demo data is titled "Second Quarter exam permit" -- the
/// workflow existed in the school and not in the app.
///
/// Nothing is stored. A permit written down on Monday lies on Friday:
/// the family pays on Wednesday and the record still says they owe. This
/// is computed from the plan, the payments and the approved notes each
/// time it is asked for, so a payment taken at the window clears the
/// student before they have walked back to the classroom.
class ExamPermitsReport {
  const ExamPermitsReport._();

  static ReportTable build({
    required List<StudentSummary> students,
    required List<Payment> payments,
    required List<Assessment> assessments,
    required List<ApprovalRequest> approvals,
    DateTime? asOf,
  }) {
    final today = asOf ?? DateTime.now();

    final assessmentsByStudent = <String, List<Assessment>>{};
    for (final assessment in assessments) {
      (assessmentsByStudent[assessment.studentId] ??= []).add(assessment);
    }
    final paidByStudent = <String, double>{};
    for (final payment in payments) {
      paidByStudent[payment.studentId] =
          (paidByStudent[payment.studentId] ?? 0) + payment.amount;
    }
    final notesByStudent = promissoryCoversByStudent(approvals);

    final rows = <ReportRow>[];
    var blocked = 0;
    var onNote = 0;
    var shortfallTotal = 0.0;

    // Sorted blocked-first, then by how much: the cashier works down this
    // list and the people who need talking to are the reason it is open.
    final assessed = <_Row>[];
    for (final student in students) {
      final theirs = assessmentsByStudent[student.id] ?? const <Assessment>[];
      if (theirs.isEmpty) continue;

      final clearance = clearanceFor(
        schedule: Assessment.combinedSchedule(theirs),
        paid: paidByStudent[student.id] ?? 0,
        asOf: today,
        notes: notesByStudent[student.id] ?? const [],
      );
      assessed.add(_Row(student, clearance));

      if (clearance.outcome == ClearanceOutcome.blocked) {
        blocked++;
        shortfallTotal += clearance.shortfall;
      } else if (clearance.outcome == ClearanceOutcome.clearedByNote) {
        onNote++;
      }
    }

    assessed.sort((a, b) {
      final rank = _rank(a.clearance.outcome).compareTo(_rank(b.clearance.outcome));
      if (rank != 0) return rank;
      return b.clearance.shortfall.compareTo(a.clearance.shortfall);
    });

    for (final row in assessed) {
      rows.add(ReportRow([
        row.student.fullName,
        row.student.studentNumber,
        row.student.classLabel,
        _verdict(row.clearance),
        row.clearance.overdue <= 0 ? '--' : _peso.format(row.clearance.overdue),
        row.clearance.shortfall <= 0 ? '--' : _peso.format(row.clearance.shortfall),
        _basis(row.clearance),
      ]));
    }

    return ReportTable(
      title: 'Exam Permits',
      subtitle: 'Cleared as at ${_dayFormat.format(today)}',
      columns: const [
        ReportColumn('Student'),
        ReportColumn('Student No.'),
        ReportColumn('Class'),
        ReportColumn('Permit'),
        ReportColumn('Overdue', numeric: true),
        ReportColumn('Short by', numeric: true),
        ReportColumn('Basis'),
      ],
      rows: rows,
      headline: [
        ReportStat(
          label: 'Not permitted',
          value: '$blocked',
          caption: blocked == 0
              ? 'Everybody assessed is cleared'
              : 'short by ${_peso.format(shortfallTotal)} in total',
        ),
        ReportStat(
          label: 'Cleared',
          value: '${assessed.length - blocked}',
          caption: onNote == 0 ? 'of ${assessed.length} assessed' : '$onNote on a '
              'promissory note',
        ),
      ],
      note: 'Computed now, from the payment plan and the approved promissory '
          'notes, rather than stored -- a permit issued on Monday would still '
          'say a family owes after they paid on Wednesday. A note that has '
          'passed its settle-by date no longer clears anybody. Students with '
          'no assessment do not appear: there is nothing they can be behind on.',
    );
  }

  static int _rank(ClearanceOutcome outcome) => switch (outcome) {
        ClearanceOutcome.blocked => 0,
        ClearanceOutcome.clearedByNote => 1,
        ClearanceOutcome.cleared => 2,
      };

  static String _verdict(Clearance clearance) => switch (clearance.outcome) {
        ClearanceOutcome.cleared => 'Permitted',
        ClearanceOutcome.clearedByNote => 'Permitted (note)',
        ClearanceOutcome.blocked => 'NOT PERMITTED',
      };

  static String _basis(Clearance clearance) => switch (clearance.outcome) {
        ClearanceOutcome.cleared => 'Account current',
        ClearanceOutcome.clearedByNote => clearance.note?.settleBy == null
            ? 'Promissory note (no date)'
            : 'Note, settle by ${_dayFormat.format(clearance.note!.settleBy!)}',
        ClearanceOutcome.blocked => clearance.note == null
            ? 'No note on file'
            : 'Note covers only part',
      };
}

/// Reads the approvals queue into the value type the clearance rule takes.
///
/// A promissory note is stored as a generic [ApprovalRequest] with
/// `type: 'promissory_note'`, so this is the one place that knows the
/// shape of its `details` map. Keeping it here rather than inside the
/// rule is what lets the rule stay arithmetic.
///
/// Only approved notes count. A pending one is a request the school has
/// not answered, and clearing a student on the strength of having *asked*
/// would make the approval step decorative.
Map<String, List<PromissoryCover>> promissoryCoversByStudent(
  Iterable<ApprovalRequest> approvals,
) {
  final byStudent = <String, List<PromissoryCover>>{};
  for (final approval in approvals) {
    if (approval.type != 'promissory_note') continue;
    if (approval.status != ApprovalStatus.approved) continue;

    final studentId = approval.details['studentId'] as String?;
    if (studentId == null || studentId.isEmpty) continue;

    final amount = (approval.details['amount'] as num?)?.toDouble() ?? 0;
    if (amount <= 0) continue;

    // A note written before the settle-by field existed carries none.
    // Treated as open-ended rather than expired: the school approved
    // something, and refusing to honour it because the record is old
    // would turn away a student over a schema change.
    final settleBy = DateTime.tryParse(approval.details['settleBy'] as String? ?? '');

    (byStudent[studentId] ??= []).add(PromissoryCover(
      amount: amount,
      settleBy: settleBy,
      reference: approval.title,
    ));
  }
  return byStudent;
}

class _Row {
  final StudentSummary student;
  final Clearance clearance;
  const _Row(this.student, this.clearance);
}
