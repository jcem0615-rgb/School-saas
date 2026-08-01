import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../../../../core/constants/firestore_paths.dart';
import '../../../../core/errors/app_exceptions.dart';
import '../models/payment_model.dart';
import '../models/payment_settings_model.dart';
import '../models/payment_submission_model.dart';

/// Who is acting. Submissions record the submitter because "who says they
/// paid" is part of what a reviewer verifies.
class ActingPayer {
  final String uid;
  final String name;
  final String role;
  const ActingPayer({required this.uid, required this.name, required this.role});
}

class PaymentRemoteDataSource {
  final FirebaseFirestore _firestore;
  final FirebaseFunctions _functions;
  final String _schoolId;
  final ActingPayer _actingUser;

  const PaymentRemoteDataSource({
    required FirebaseFirestore firestore,
    required FirebaseFunctions functions,
    required String schoolId,
    required ActingPayer actingUser,
  })  : _firestore = firestore,
        _functions = functions,
        _schoolId = schoolId,
        _actingUser = actingUser;

  Stream<List<PaymentModel>> watchPaymentsForStudent(String studentId) {
    return _firestore
        .collection(FirestorePaths.payments(_schoolId))
        .where('studentId', isEqualTo: studentId)
        .where('isDeleted', isEqualTo: false)
        .orderBy('createdAt', descending: true)
        .limit(200)
        .snapshots()
        .map((snap) => snap.docs.map((d) => PaymentModel.fromFirestore(d.id, d.data())).toList());
  }

  Stream<double> watchStudentBalance(String studentId) {
    return _firestore
        .doc(FirestorePaths.studentDoc(_schoolId, studentId))
        .snapshots()
        .map((snap) => (snap.data()?['balance'] as num?)?.toDouble() ?? 0.0);
  }

  Future<Map<String, dynamic>> recordPayment({
    required String studentId,
    required double amount,
    required String method,
    required String purpose,
    String? referenceNumber,
  }) async {
    try {
      final callable = _functions.httpsCallable('recordPayment');
      final response = await callable.call({
        'schoolId': _schoolId,
        'studentId': studentId,
        'amount': amount,
        'method': method,
        'purpose': purpose,
        'referenceNumber': referenceNumber,
      });
      return Map<String, dynamic>.from(response.data as Map);
    } on FirebaseFunctionsException catch (e) {
      throw ServerException(e.message ?? 'Failed to record payment.');
    }
  }

  Future<void> recordRefund({required String paymentId, required String reason}) async {
    try {
      final callable = _functions.httpsCallable('recordRefund');
      await callable.call({'schoolId': _schoolId, 'paymentId': paymentId, 'reason': reason});
    } on FirebaseFunctionsException catch (e) {
      throw ServerException(e.message ?? 'Failed to process refund.');
    }
  }

  // ---- Online payment submissions ----

  Stream<List<PaymentSubmissionModel>> watchSubmissionsForStudent(String studentId) {
    return _firestore
        .collection(FirestorePaths.paymentSubmissions(_schoolId))
        .where('studentId', isEqualTo: studentId)
        .where('isDeleted', isEqualTo: false)
        .orderBy('submittedAt', descending: true)
        .limit(100)
        .snapshots()
        .map((snap) =>
            snap.docs.map((d) => PaymentSubmissionModel.fromFirestore(d.id, d.data())).toList());
  }

  Stream<List<PaymentSubmissionModel>> watchSubmissions({bool pendingOnly = true}) {
    Query<Map<String, dynamic>> query = _firestore
        .collection(FirestorePaths.paymentSubmissions(_schoolId))
        .where('isDeleted', isEqualTo: false);
    if (pendingOnly) {
      query = query.where('status', isEqualTo: 'pending');
    }
    return query
        .orderBy('submittedAt', descending: true)
        .limit(200)
        .snapshots()
        .map((snap) =>
            snap.docs.map((d) => PaymentSubmissionModel.fromFirestore(d.id, d.data())).toList());
  }

  /// Written straight to Firestore rather than through a callable: this
  /// creates no money and moves no balance, so the rules can gate it on
  /// their own (submitter must be the student or a linked parent).
  Future<void> submitOnlinePayment({
    required String studentId,
    required String studentName,
    required double amount,
    required String method,
    required String purpose,
    required String referenceNumber,
    String? receiptUrl,
    String? receiptFileName,
  }) async {
    final ref = _firestore.collection(FirestorePaths.paymentSubmissions(_schoolId)).doc();
    await ref.set({
      'id': ref.id,
      'schoolId': _schoolId,
      'studentId': studentId,
      'studentName': studentName,
      'submittedByName': _actingUser.name,
      'submittedByRole': _actingUser.role,
      'amount': amount,
      'method': method,
      'purpose': purpose,
      'referenceNumber': referenceNumber,
      'receiptUrl': receiptUrl,
      'receiptFileName': receiptFileName,
      'status': 'pending',
      'reviewedByName': null,
      'reviewedAt': null,
      'decisionRemarks': null,
      'resultingPaymentId': null,
      'submittedAt': FieldValue.serverTimestamp(),
      'createdBy': _actingUser.uid,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedBy': _actingUser.uid,
      'updatedAt': FieldValue.serverTimestamp(),
      'deletedAt': null,
      'deletedBy': null,
      'isDeleted': false,
    });
  }

  /// Goes through a callable, unlike the submission itself: approving
  /// creates a Payment and moves a balance, which only the server may do.
  Future<void> decideSubmission({
    required String submissionId,
    required bool approve,
    String? remarks,
  }) async {
    try {
      final callable = _functions.httpsCallable('decidePaymentSubmission');
      await callable.call({
        'schoolId': _schoolId,
        'submissionId': submissionId,
        'approve': approve,
        'remarks': remarks,
      });
    } on FirebaseFunctionsException catch (e) {
      throw ServerException(e.message ?? 'Failed to record the decision.');
    }
  }

  // ---- Payment settings (the school's QR) ----

  Stream<PaymentSettingsModel> watchPaymentSettings() {
    return _firestore
        .doc(FirestorePaths.paymentSettingsDoc(_schoolId))
        .snapshots()
        .map((snap) => PaymentSettingsModel.fromFirestore(snap.data()));
  }

  Future<void> updatePaymentSettings(Map<String, dynamic> fields) async {
    await _firestore.doc(FirestorePaths.paymentSettingsDoc(_schoolId)).set({
      ...fields,
      'schoolId': _schoolId,
      'updatedBy': _actingUser.uid,
      'updatedByName': _actingUser.name,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}
