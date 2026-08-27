import '../../../../core/errors/result.dart';
import '../../../faculty_portal/domain/entities/grade.dart';
import '../../../payments/domain/entities/assessment.dart';
import '../../../payments/domain/entities/payment.dart';
import '../../../qr_attendance/domain/entities/attendance_record.dart';
import '../../../registrar_portal/domain/entities/student_summary.dart';
import '../entities/report_kind.dart';
import '../entities/report_period.dart';

/// Everything one report needed, fetched once.
///
/// A report is a snapshot somebody exports and mails, not a live view --
/// so this is a one-shot read rather than the streams the rest of the app
/// is built on. A table that reshuffles under the reader while they are
/// reading a column down is worse than one that is a minute old.
class ReportData {
  final List<StudentSummary> students;
  final List<Payment> payments;
  final List<Assessment> assessments;
  final List<AttendanceRecord> attendance;
  final List<Grade> grades;

  /// Collections that came back at their read limit, and so may be
  /// missing rows.
  ///
  /// Surfaced rather than swallowed. A report quietly built from the
  /// first five thousand of six thousand scans is not slightly wrong, it
  /// is wrong in a way that looks exactly like being right.
  final Set<String> truncated;

  const ReportData({
    this.students = const [],
    this.payments = const [],
    this.assessments = const [],
    this.attendance = const [],
    this.grades = const [],
    this.truncated = const {},
  });
}

abstract class ReportsRepository {
  Future<Result<ReportData>> fetch({
    required ReportKind kind,
    required ReportPeriod period,
  });
}
