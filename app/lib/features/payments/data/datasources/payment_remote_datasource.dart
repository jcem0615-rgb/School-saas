import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../../../../core/constants/firestore_paths.dart';
import '../../../../core/errors/app_exceptions.dart';
import '../../../../core/constants/education_level.dart';
import '../../domain/entities/fee_structure.dart';
import '../../domain/entities/discount.dart';
import '../../domain/entities/installment.dart';
import '../../domain/entities/payment.dart';
import '../../domain/entities/receipt_booklet.dart';
import '../../domain/entities/subsidy.dart';
import '../models/fee_models.dart';
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

  // -------------------------------------------------------------------
  // Fee assessment
  // -------------------------------------------------------------------

  /// The school's published fee schedules.
  ///
  /// Every one of them, including retired ones: the assessment screen
  /// only offers active schedules, but a list screen has to show what is
  /// retired so somebody can bring it back, and the volume is a handful
  /// of documents per year rather than a collection worth paging.
  Stream<List<FeeStructureModel>> watchFeeStructures() {
    return _firestore
        .collection(FirestorePaths.feeStructures(_schoolId))
        .orderBy('name')
        .snapshots()
        .map((snap) =>
            snap.docs.map((d) => FeeStructureModel.fromFirestore(d.id, d.data())).toList());
  }

  Future<void> saveFeeStructure({
    String? structureId,
    required String name,
    required EducationLevel educationLevel,
    String? gradeLevel,
    required String schoolYear,
    required List<FeeItem> items,
    required List<Installment> installments,
    required bool isActive,
  }) async {
    final data = FeeStructureModel.toFirestore(
      name: name,
      educationLevel: educationLevel,
      gradeLevel: gradeLevel,
      schoolYear: schoolYear,
      items: items,
      installments: installments,
      isActive: isActive,
    );
    final ref = structureId == null
        ? _firestore.collection(FirestorePaths.feeStructures(_schoolId)).doc()
        : _firestore.collection(FirestorePaths.feeStructures(_schoolId)).doc(structureId);

    await ref.set({
      ...data,
      'id': ref.id,
      'schoolId': _schoolId,
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedBy': _actingUser.uid,
      'updatedByName': _actingUser.name,
      if (structureId == null) 'createdAt': FieldValue.serverTimestamp(),
      if (structureId == null) 'createdBy': _actingUser.uid,
    }, SetOptions(merge: structureId != null));
  }

  /// What this student has been charged, newest first.
  Stream<List<AssessmentModel>> watchAssessments(String studentId) {
    return _firestore
        .collection(FirestorePaths.assessments(_schoolId))
        .where('studentId', isEqualTo: studentId)
        .where('isDeleted', isEqualTo: false)
        .orderBy('assessedAt', descending: true)
        .limit(200)
        .snapshots()
        .map((snap) =>
            snap.docs.map((d) => AssessmentModel.fromFirestore(d.id, d.data())).toList());
  }

  /// Charges fees and moves the balance, in one server-side transaction.
  ///
  /// A callable rather than a write: `balance` is server-owned, and the
  /// itemised record and the figure have to move together or the list
  /// stops adding up to the number.
  Future<Map<String, dynamic>> assessStudentFees({
    required String studentId,
    required String schoolYear,
    required List<FeeItem> items,
    List<Installment> installments = const [],
    List<Discount> discounts = const [],
    List<Subsidy> subsidies = const [],
    String? sourceStructureId,
    String? sourceStructureName,
    String? remarks,
  }) async {
    try {
      final callable = _functions.httpsCallable('assessStudentFees');
      final response = await callable.call({
        'schoolId': _schoolId,
        'studentId': studentId,
        'schoolYear': schoolYear,
        'items': items.map((i) => i.toMap()).toList(),
        'installments': installments.map((i) => i.toMap()).toList(),
        'discounts': discounts.map((d) => d.toMap()).toList(),
        'subsidies': subsidies.map((s) => s.toMap()).toList(),
        'sourceStructureId': sourceStructureId,
        'sourceStructureName': sourceStructureName,
        'remarks': remarks,
      });
      return Map<String, dynamic>.from(response.data as Map);
    } on FirebaseFunctionsException catch (e) {
      throw ServerException(e.message ?? 'Failed to assess fees.');
    }
  }

  Future<void> voidAssessment({required String assessmentId, required String reason}) async {
    try {
      final callable = _functions.httpsCallable('voidAssessment');
      await callable.call({
        'schoolId': _schoolId,
        'assessmentId': assessmentId,
        'reason': reason,
      });
    } on FirebaseFunctionsException catch (e) {
      throw ServerException(e.message ?? 'Failed to void the assessment.');
    }
  }

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

  /// Every payment in the school, newest first.
  ///
  /// Unfiltered by date on purpose: a receipt number issued in June is
  /// used whenever the series is reconciled, and a query that missed it
  /// would report the number as unaccounted for.
  Stream<List<Payment>> watchAllPayments() {
    return _firestore
        .collection(FirestorePaths.payments(_schoolId))
        .where('isDeleted', isEqualTo: false)
        .snapshots()
        .map((snap) =>
            snap.docs.map((d) => PaymentModel.fromFirestore(d.id, d.data())).toList());
  }

  /// The booklets the school issues official receipts from. Only the
  /// active one matters at the counter; the retired ones are what a
  /// series reconciliation reads.
  Stream<List<ReceiptBooklet>> watchReceiptBooklets() {
    return _firestore
        .collection(FirestorePaths.receiptBooklets(_schoolId))
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => ReceiptBooklet.fromMap(
                  d.id,
                  d.data(),
                  registeredOn:
                      (d.data()['registeredOn'] as Timestamp?)?.toDate() ?? DateTime.now(),
                  registeredByName: d.data()['registeredByName'] as String? ?? 'Unknown',
                ))
            .toList()
          ..sort((a, b) => b.registeredOn.compareTo(a.registeredOn)));
  }

  Future<void> saveReceiptBooklet({
    String? bookletId,
    required ReceiptBooklet booklet,
  }) async {
    final ref = bookletId == null
        ? _firestore.collection(FirestorePaths.receiptBooklets(_schoolId)).doc()
        : _firestore.collection(FirestorePaths.receiptBooklets(_schoolId)).doc(bookletId);
    await ref.set({
      ...booklet.toMap(),
      'id': ref.id,
      'schoolId': _schoolId,
      'isDeleted': false,
      if (bookletId == null) 'registeredOn': FieldValue.serverTimestamp(),
      if (bookletId == null) 'registeredBy': _actingUser.uid,
      if (bookletId == null) 'registeredByName': _actingUser.name,
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedBy': _actingUser.uid,
    }, SetOptions(merge: bookletId != null));
  }

  Future<Map<String, dynamic>> recordPayment({
    required String studentId,
    required double amount,
    required String method,
    required String purpose,
    String? referenceNumber,
    int? officialReceiptNo,
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
        'officialReceiptNo': officialReceiptNo,
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
    String? destinationLabel,
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
      'destinationLabel': destinationLabel,
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
