import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:rxdart/rxdart.dart';

import '../../../../core/constants/education_level.dart';
import '../../../../core/constants/firestore_paths.dart';
import '../../../../core/errors/app_exceptions.dart';
import '../models/invoice_model.dart';
import '../models/revenue_summary_model.dart';
import '../models/school_summary_model.dart';

class OwnerRemoteDataSource {
  final FirebaseFirestore _firestore;
  final FirebaseFunctions _functions;

  const OwnerRemoteDataSource({
    required FirebaseFirestore firestore,
    required FirebaseFunctions functions,
  })  : _firestore = firestore,
        _functions = functions;

  /// Combines the two platform-level collections into one list of
  /// [SchoolSummaryModel]s, keyed by document ID (schoolId is the doc ID
  /// in both collections by convention). Uses rxdart's combineLatest so
  /// the list re-emits whenever *either* a school profile or a
  /// subscription doc changes -- e.g. a pause/resume action updates
  /// `platform_subscriptions` and the list reflects it within one frame.
  Stream<List<SchoolSummaryModel>> watchSchools() {
    final schoolsStream =
        _firestore.collection(FirestorePaths.platformSchools).snapshots();
    final subscriptionsStream =
        _firestore.collection(FirestorePaths.platformSubscriptions).snapshots();

    return Rx.combineLatest2(schoolsStream, subscriptionsStream, (schools, subs) {
      final subsById = {for (final doc in subs.docs) doc.id: doc.data()};
      return schools.docs
          .where((doc) => subsById.containsKey(doc.id))
          .map((doc) => SchoolSummaryModel.fromDocs(
                id: doc.id,
                schoolData: doc.data(),
                subscriptionData: subsById[doc.id]!,
              ))
          .toList();
    });
  }

  Stream<RevenueSummaryModel> watchRevenueSummary() {
    // Maintained by the billing Cloud Function, not computed on-device --
    // see functions/src/scheduled/dailyBillingJob.ts.
    return _firestore
        .doc('platform_revenue_summary/current')
        .snapshots()
        .map((snap) => RevenueSummaryModel.fromFirestore(snap.data() ?? {}));
  }

  Stream<List<InvoiceModel>> watchInvoices(String schoolId) {
    return _firestore
        .collection(FirestorePaths.platformInvoices)
        .where('schoolId', isEqualTo: schoolId)
        .orderBy('billingPeriodStart', descending: true)
        .limit(24) // two years of monthly invoices is plenty for one screen
        .snapshots()
        .map((snap) => snap.docs.map((d) => InvoiceModel.fromFirestore(d.id, d.data())).toList());
  }

  Future<void> pauseSchool({required String schoolId, required String reason}) async {
    try {
      await _functions.httpsCallable('pauseSchool').call({
        'schoolId': schoolId,
        'reason': reason,
      });
    } on FirebaseFunctionsException catch (e) {
      throw ServerException(e.message ?? 'Failed to pause school.');
    }
  }

  /// Returns the new school's id, which the callable decides -- it
  /// slugifies the name when one is not supplied, so the caller cannot
  /// assume it.
  Future<String> createSchool({
    required String name,
    required double billingRatePerStudent,
    required Set<EducationLevel> educationLevels,
    String? schoolId,
    String? addressLine,
    String? contactEmail,
    String? contactPhone,
  }) async {
    try {
      final result = await _functions.httpsCallable('createSchool').call({
        'name': name,
        'billingRatePerStudent': billingRatePerStudent,
        // Ordered lowest division first so the stored array reads the way
        // the label does, rather than in whatever order they were tapped.
        'educationLevels': EducationLevel.values
            .where(educationLevels.contains)
            .map((l) => l.value)
            .toList(),
        if (schoolId != null && schoolId.isNotEmpty) 'schoolId': schoolId,
        if (addressLine != null && addressLine.isNotEmpty) 'addressLine': addressLine,
        if (contactEmail != null && contactEmail.isNotEmpty) 'contactEmail': contactEmail,
        if (contactPhone != null && contactPhone.isNotEmpty) 'contactPhone': contactPhone,
      });
      final data = Map<String, dynamic>.from(result.data as Map);
      return data['schoolId'] as String;
    } on FirebaseFunctionsException catch (e) {
      throw ServerException(e.message ?? 'Failed to create the school.');
    }
  }

  Future<void> resumeSchool({required String schoolId}) async {
    try {
      await _functions.httpsCallable('resumeSchool').call({'schoolId': schoolId});
    } on FirebaseFunctionsException catch (e) {
      throw ServerException(e.message ?? 'Failed to resume school.');
    }
  }

  Future<void> recordManualPayment({
    required String schoolId,
    required String invoiceId,
    required double amount,
    required String method,
    String? referenceNumber,
  }) async {
    try {
      await _functions.httpsCallable('recordManualPayment').call({
        'schoolId': schoolId,
        'invoiceId': invoiceId,
        'amount': amount,
        'method': method,
        'referenceNumber': referenceNumber,
      });
    } on FirebaseFunctionsException catch (e) {
      throw ServerException(e.message ?? 'Failed to record payment.');
    }
  }
}
