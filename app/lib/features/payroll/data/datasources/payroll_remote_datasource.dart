import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../../core/constants/firestore_paths.dart';
import '../../domain/entities/contribution_scheme.dart';
import '../../domain/entities/payslip.dart';
import '../models/payroll_models.dart';

class ActingPayrollUser {
  final String uid;
  final String schoolId;
  final String name;
  const ActingPayrollUser({
    required this.uid,
    required this.schoolId,
    required this.name,
  });
}

class PayrollRemoteDataSource {
  final FirebaseFirestore _firestore;
  final ActingPayrollUser _actingUser;

  const PayrollRemoteDataSource({
    required FirebaseFirestore firestore,
    required ActingPayrollUser actingUser,
  })  : _firestore = firestore,
        _actingUser = actingUser;

  Stream<List<CompensationModel>> watchCompensation() => _firestore
      .collection(FirestorePaths.compensation(_actingUser.schoolId))
      .snapshots()
      .map((snap) => snap.docs
          .map((d) => CompensationModel.fromFirestore(d.id, d.data()))
          .toList());

  Future<void> saveCompensation(Compensation compensation) async {
    // The employee's uid is the document id, so a pay rate is never two
    // documents that disagree.
    await _firestore
        .doc(FirestorePaths.compensationDoc(
            _actingUser.schoolId, compensation.employeeUid))
        .set({
      ...CompensationModel.toMap(compensation),
      'schoolId': _actingUser.schoolId,
      'updatedBy': _actingUser.uid,
      'updatedByName': _actingUser.name,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Stream<ContributionSchemeModel> watchContributionScheme() => _firestore
      .doc(FirestorePaths.payrollSchemeDoc(_actingUser.schoolId))
      .snapshots()
      .map((snap) => ContributionSchemeModel.fromFirestore(snap.data()));

  Future<void> saveContributionScheme(ContributionScheme scheme) async {
    await _firestore.doc(FirestorePaths.payrollSchemeDoc(_actingUser.schoolId)).set({
      ...ContributionSchemeModel.toMap(scheme),
      // Editing revokes the confirmation, enforced here rather than left
      // to the screen -- a table somebody confirmed in January and
      // somebody else edited in June is not a confirmed table.
      'confirmedBySchool': false,
      'confirmedByName': null,
      'confirmedAt': null,
      'schoolId': _actingUser.schoolId,
      'updatedBy': _actingUser.uid,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> confirmContributionScheme() async {
    await _firestore.doc(FirestorePaths.payrollSchemeDoc(_actingUser.schoolId)).set({
      'confirmedBySchool': true,
      'confirmedByName': _actingUser.name,
      'confirmedAt': FieldValue.serverTimestamp(),
      'schoolId': _actingUser.schoolId,
      'updatedBy': _actingUser.uid,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Stream<List<PayslipModel>> watchPayslips({String? employeeUid}) {
    Query<Map<String, dynamic>> query =
        _firestore.collection(FirestorePaths.payslips(_actingUser.schoolId));
    if (employeeUid != null) {
      query = query.where('employeeUid', isEqualTo: employeeUid);
    }
    return query
        .orderBy('periodTo', descending: true)
        .snapshots()
        .map((snap) =>
            snap.docs.map((d) => PayslipModel.fromFirestore(d.id, d.data())).toList());
  }

  /// One document per payslip, at a derived id.
  ///
  /// `{period}_{employee}` rather than an auto-id, so running the same
  /// period twice cannot pay somebody twice. The second run overwrites
  /// the first rather than adding to it -- and the rules deny update, so
  /// it fails loudly instead of silently doubling the month's payroll.
  Future<int> issuePayslips(List<Payslip> payslips) async {
    final batch = _firestore.batch();
    for (final payslip in payslips) {
      final id = '${payslip.periodFrom}_${payslip.periodTo}_${payslip.employeeUid}';
      batch.set(
        _firestore.collection(FirestorePaths.payslips(_actingUser.schoolId)).doc(id),
        {
          ...PayslipModel.toMap(payslip),
          'id': id,
          'schoolId': _actingUser.schoolId,
          'issuedBy': _actingUser.uid,
          'issuedByName': _actingUser.name,
          'issuedAt': FieldValue.serverTimestamp(),
        },
      );
    }
    await batch.commit();
    return payslips.length;
  }
}
