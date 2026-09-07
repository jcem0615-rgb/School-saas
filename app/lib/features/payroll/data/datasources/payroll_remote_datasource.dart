import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../../../../core/constants/firestore_paths.dart';
import '../../../../core/errors/app_exceptions.dart';
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
  final FirebaseFunctions _functions;
  final ActingPayrollUser _actingUser;

  const PayrollRemoteDataSource({
    required FirebaseFirestore firestore,
    required FirebaseFunctions functions,
    required ActingPayrollUser actingUser,
  })  : _firestore = firestore,
        _functions = functions,
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

  /// A payroll run, computed on the server.
  ///
  /// Nothing about the figures is sent from here -- not a pay rate, not
  /// a day count, not a deduction. The period and the cut-off flag are
  /// all this side is in a position to know; `runPayroll` reads the
  /// rates, the contribution tables, the scans and the approved leave
  /// and works the rest out itself.
  ///
  /// [commit] false previews and writes nothing. True issues, and fails
  /// if the period has already been issued for anybody in it -- the
  /// derived document id is what makes running the same period twice
  /// impossible rather than merely discouraged.
  Future<PayrollRunModel> runPayroll({
    required String periodFrom,
    required String periodTo,
    required bool deductContributions,
    required bool commit,
  }) async {
    try {
      final callable = _functions.httpsCallable('runPayroll');
      final response = await callable.call({
        'schoolId': _actingUser.schoolId,
        'periodFrom': periodFrom,
        'periodTo': periodTo,
        'deductContributions': deductContributions,
        'commit': commit,
      });
      return PayrollRunModel.fromCallable(
        (response.data as Map).cast<Object?, Object?>(),
      );
    } on FirebaseFunctionsException catch (e) {
      // The message rather than a generic one: the server's refusals
      // here name who was already paid and which agency has no table,
      // and a screen that swallowed those would leave the office with
      // nothing to act on.
      throw ServerException(e.message ?? 'Could not run payroll.');
    }
  }
}
