import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../../core/constants/firestore_paths.dart';
import '../../../faculty_portal/data/models/grade_model.dart';
import '../../../payments/data/models/fee_models.dart';
import '../../../payments/domain/entities/receipt_booklet.dart';
import '../../../director_portal/data/models/approval_request_model.dart';
import '../../../payments/data/models/payment_model.dart';
import '../../../qr_attendance/data/models/attendance_record_model.dart';
import '../../../registrar_portal/data/models/student_summary_model.dart';
import '../../domain/entities/report_kind.dart';
import '../../domain/entities/report_period.dart';
import '../../domain/repositories/reports_repository.dart';

/// Reads the rows a report is computed from.
///
/// Rows, not aggregates. Firestore's count() and sum() answer "how many"
/// and "how much" but cannot group, and every report here is a group-by:
/// enrolment *by division*, attendance *by section*, marks *by subject*.
/// So the documents come back and the domain layer does the grouping,
/// which is also what makes those builders pure functions worth testing.
///
/// That trade has a ceiling, and [_limit] is where it sits. A school with
/// more scans in a term than this needs server-side aggregation -- a
/// scheduled function writing rollup documents -- rather than a bigger
/// number here. What matters until then is that hitting the ceiling is
/// reported instead of hidden.
class ReportsRemoteDataSource {
  final FirebaseFirestore _firestore;
  final String _schoolId;

  static const int _limit = 5000;

  ReportsRemoteDataSource({
    required FirebaseFirestore firestore,
    required String schoolId,
  })  : _firestore = firestore,
        _schoolId = schoolId;

  Future<ReportData> fetch({required ReportKind kind, required ReportPeriod period}) async {
    final startStamp = Timestamp.fromDate(period.start);
    final endStamp = Timestamp.fromDate(period.end);
    final truncated = <String>{};

    Future<QuerySnapshot<Map<String, dynamic>>?> run(
      bool needed,
      String label,
      Query<Map<String, dynamic>> query,
    ) async {
      if (!needed) return null;
      final snapshot = await query.limit(_limit).get();
      if (snapshot.docs.length >= _limit) truncated.add(label);
      return snapshot;
    }

    final results = await Future.wait([
      run(
        kind.needsStudents,
        'students',
        _firestore
            .collection(FirestorePaths.students(_schoolId))
            .where('isDeleted', isEqualTo: false),
      ),
      run(
        kind.needsPayments,
        'payments',
        _firestore
            .collection(FirestorePaths.payments(_schoolId))
            .where('isDeleted', isEqualTo: false)
            .where('createdAt', isGreaterThanOrEqualTo: startStamp)
            .where('createdAt', isLessThanOrEqualTo: endStamp),
      ),
      run(
        kind.needsAssessments,
        'assessments',
        _firestore
            .collection(FirestorePaths.assessments(_schoolId))
            .where('isDeleted', isEqualTo: false)
            .where('assessedAt', isGreaterThanOrEqualTo: startStamp)
            .where('assessedAt', isLessThanOrEqualTo: endStamp),
      ),
      run(
        kind.needsAttendance,
        'attendance',
        // `date` is a 'YYYY-MM-DD' string, which sorts and ranges
        // correctly as text -- that is the whole reason it is stored in
        // that form rather than as a timestamp.
        _firestore
            .collection(FirestorePaths.attendance(_schoolId))
            .where('date', isGreaterThanOrEqualTo: _dayKey(period.start))
            .where('date', isLessThanOrEqualTo: _dayKey(period.end)),
      ),
      run(
        kind.needsApprovals,
        'approvals',
        // Not filtered by date. A promissory note approved in August
        // still covers an examination in October, and a note filtered
        // out of the read is a student wrongly turned away.
        _firestore
            .collection(FirestorePaths.approvals(_schoolId))
            .where('type', isEqualTo: 'promissory_note'),
      ),
      run(
        kind.needsReceiptBooklets,
        'receiptBooklets',
        _firestore.collection(FirestorePaths.receiptBooklets(_schoolId)),
      ),
      run(
        kind.needsGrades,
        'grades',
        _firestore
            .collection(FirestorePaths.grades(_schoolId))
            .where('isDeleted', isEqualTo: false)
            .where('submittedAt', isGreaterThanOrEqualTo: startStamp)
            .where('submittedAt', isLessThanOrEqualTo: endStamp),
      ),
    ]);

    return ReportData(
      students: [
        for (final doc in results[0]?.docs ?? const [])
          StudentSummaryModel.fromFirestore(doc.id, doc.data())
      ],
      payments: [
        for (final doc in results[1]?.docs ?? const [])
          PaymentModel.fromFirestore(doc.id, doc.data())
      ],
      assessments: [
        for (final doc in results[2]?.docs ?? const [])
          AssessmentModel.fromFirestore(doc.id, doc.data())
      ],
      attendance: [
        for (final doc in results[3]?.docs ?? const [])
          AttendanceRecordModel.fromFirestore(doc.id, doc.data())
      ],
      approvals: [
        for (final doc in results[4]?.docs ?? const [])
          ApprovalRequestModel.fromFirestore(doc.id, doc.data())
      ],
      receiptBooklets: [
        for (final doc in results[5]?.docs ?? const [])
          ReceiptBooklet.fromMap(
            doc.id,
            doc.data(),
            registeredOn:
                (doc.data()['registeredOn'] as Timestamp?)?.toDate() ?? DateTime.now(),
            registeredByName: doc.data()['registeredByName'] as String? ?? 'Unknown',
          )
      ],
      grades: [
        for (final doc in results[6]?.docs ?? const [])
          GradeModel.fromFirestore(doc.id, doc.data())
      ],
      truncated: truncated,
    );
  }

  static String _dayKey(DateTime day) =>
      '${day.year.toString().padLeft(4, '0')}-'
      '${day.month.toString().padLeft(2, '0')}-'
      '${day.day.toString().padLeft(2, '0')}';
}
