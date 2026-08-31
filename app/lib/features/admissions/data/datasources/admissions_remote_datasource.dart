import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../../../../core/constants/firestore_paths.dart';
import '../../../../core/errors/app_exceptions.dart';
import '../models/applicant_model.dart';

class ActingAdmissionsUser {
  final String uid;
  final String schoolId;
  final String name;
  const ActingAdmissionsUser({
    required this.uid,
    required this.schoolId,
    required this.name,
  });
}

class AdmissionsRemoteDataSource {
  final FirebaseFirestore _firestore;
  final FirebaseFunctions _functions;
  final ActingAdmissionsUser _actingUser;

  const AdmissionsRemoteDataSource({
    required FirebaseFirestore firestore,
    required FirebaseFunctions functions,
    required ActingAdmissionsUser actingUser,
  })  : _firestore = firestore,
        _functions = functions,
        _actingUser = actingUser;

  /// Every enquiry, newest first.
  ///
  /// The whole collection rather than a page. An admissions pipeline is
  /// a few hundred rows for a school of a thousand, the screen groups
  /// them by stage, and a funnel computed from a page would be a funnel
  /// that reports the wrong numbers.
  Stream<List<ApplicantModel>> watchApplicants() {
    return _firestore
        .collection(FirestorePaths.applicants(_actingUser.schoolId))
        .where('isDeleted', isEqualTo: false)
        .orderBy('inquiredAt', descending: true)
        .snapshots()
        .map((snap) =>
            snap.docs.map((d) => ApplicantModel.fromFirestore(d.id, d.data())).toList());
  }

  Future<Map<String, dynamic>> saveApplicant(Map<String, dynamic> fields) async {
    try {
      final callable = _functions.httpsCallable('saveApplicant');
      final response = await callable.call({
        ...fields,
        'schoolId': _actingUser.schoolId,
      });
      return Map<String, dynamic>.from(response.data as Map);
    } on FirebaseFunctionsException catch (e) {
      throw ServerException(e.message ?? 'Could not save that enquiry.');
    }
  }

  Future<void> advanceApplicant(Map<String, dynamic> fields) async {
    try {
      final callable = _functions.httpsCallable('advanceApplicant');
      await callable.call({...fields, 'schoolId': _actingUser.schoolId});
    } on FirebaseFunctionsException catch (e) {
      throw ServerException(e.message ?? 'Could not move that applicant.');
    }
  }

  Future<Map<String, dynamic>> enrolApplicant({
    required String applicantId,
    required String section,
    required DateTime birthDate,
  }) async {
    try {
      final callable = _functions.httpsCallable('enrolApplicant');
      final response = await callable.call({
        'schoolId': _actingUser.schoolId,
        'applicantId': applicantId,
        'section': section,
        'birthDate': birthDate.toIso8601String(),
      });
      return Map<String, dynamic>.from(response.data as Map);
    } on FirebaseFunctionsException catch (e) {
      throw ServerException(e.message ?? 'Could not enrol that applicant.');
    }
  }
}
