import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../../../../core/constants/firestore_paths.dart';
import '../../../../core/errors/app_exceptions.dart';
import '../models/payment_model.dart';

class PaymentRemoteDataSource {
  final FirebaseFirestore _firestore;
  final FirebaseFunctions _functions;
  final String _schoolId;

  const PaymentRemoteDataSource({
    required FirebaseFirestore firestore,
    required FirebaseFunctions functions,
    required String schoolId,
  })  : _firestore = firestore,
        _functions = functions,
        _schoolId = schoolId;

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
}
