import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../../../../core/constants/firestore_paths.dart';
import '../../../../core/errors/app_exceptions.dart';
import '../models/student_summary_model.dart';

class ActingRegistrar {
  final String uid;
  final String schoolId;
  final String name;
  const ActingRegistrar({required this.uid, required this.schoolId, required this.name});
}

class RegistrarRemoteDataSource {
  final FirebaseFirestore _firestore;
  final FirebaseFunctions _functions;
  final ActingRegistrar _actingUser;

  const RegistrarRemoteDataSource({
    required FirebaseFirestore firestore,
    required FirebaseFunctions functions,
    required ActingRegistrar actingUser,
  })  : _firestore = firestore,
        _functions = functions,
        _actingUser = actingUser;

  Stream<List<StudentSummaryModel>> watchStudents() {
    return _firestore
        .collection(FirestorePaths.students(_actingUser.schoolId))
        .where('isDeleted', isEqualTo: false)
        .orderBy('lastName')
        .snapshots()
        .map((snap) => snap.docs.map((d) => StudentSummaryModel.fromFirestore(d.id, d.data())).toList());
  }

  Future<Map<String, dynamic>> registerStudent({
    required String firstName,
    required String lastName,
    String? middleName,
    required String educationLevel,
    required String gradeLevel,
    required String section,
    String? programId,
    DateTime? birthDate,
    required List<Map<String, dynamic>> guardianContacts,
  }) async {
    try {
      final callable = _functions.httpsCallable('registerStudent');
      final response = await callable.call({
        'schoolId': _actingUser.schoolId,
        'firstName': firstName,
        'lastName': lastName,
        'middleName': middleName,
        'educationLevel': educationLevel,
        'gradeLevel': gradeLevel,
        'section': section,
        'programId': programId,
        'birthDate': birthDate?.toIso8601String(),
        'guardianContacts': guardianContacts,
      });
      return Map<String, dynamic>.from(response.data as Map);
    } on FirebaseFunctionsException catch (e) {
      throw ServerException(e.message ?? 'Failed to register student.');
    }
  }

  Future<void> updateStudent({
    required String studentId,
    required String firstName,
    required String lastName,
    required String gradeLevel,
    required String section,
    required String status,
    DateTime? birthDate,
  }) async {
    await _firestore.doc(FirestorePaths.studentDoc(_actingUser.schoolId, studentId)).update({
      // Omitted rather than written as null when unset -- an edit that
      // leaves the field blank should not erase a birth date the
      // registrar entered earlier.
      if (birthDate != null) 'birthDate': Timestamp.fromDate(birthDate),
      'firstName': firstName,
      'lastName': lastName,
      'gradeLevel': gradeLevel,
      'section': section,
      'status': status,
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedBy': _actingUser.uid,
    });
  }

  Future<Map<String, dynamic>> provisionStudentAccount({
    required String studentId,
    required String email,
    required String firstName,
    required String lastName,
  }) async {
    try {
      final callable = _functions.httpsCallable('provisionUser');
      final response = await callable.call({
        'schoolId': _actingUser.schoolId,
        'role': 'student',
        'firstName': firstName,
        'lastName': lastName,
        'email': email,
        'linkedStudentId': studentId,
      });
      return Map<String, dynamic>.from(response.data as Map);
    } on FirebaseFunctionsException catch (e) {
      throw ServerException(e.message ?? 'Failed to create student portal account.');
    }
  }

  /// Goes through a callable rather than writing the field directly:
  /// firestore.rules rejects any client update that touches `balance`, so
  /// the payment transactions stay its only other writer and every manual
  /// assessment lands in the audit trail with a reason attached.
  Future<void> setStudentBalance({
    required String studentId,
    required double balance,
    required String remarks,
  }) async {
    try {
      final callable = _functions.httpsCallable('setStudentBalance');
      await callable.call({
        'schoolId': _actingUser.schoolId,
        'studentId': studentId,
        'balance': balance,
        'remarks': remarks,
      });
    } on FirebaseFunctionsException catch (e) {
      throw ServerException(e.message ?? 'Failed to update the balance.');
    }
  }
}
