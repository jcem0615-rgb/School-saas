import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../../../../core/constants/education_level.dart';
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

  /// The roster, oldest-surname first.
  ///
  /// [limit] caps how many documents the query returns. A school with
  /// three thousand students otherwise costs three thousand reads every
  /// time someone opens the list, which is the single largest line on the
  /// Firestore bill and the reason the list screen asks for a page at a
  /// time. Left null the query is unbounded, which is what the screens
  /// that genuinely need the whole roster -- the faculty submission
  /// sheet, the export -- still ask for.
  ///
  /// [educationLevel] is applied server-side rather than by filtering the
  /// page after it arrives. Filtering afterwards would silently shrink the
  /// page: ask for twenty and get the four Senior High students that
  /// happened to fall inside those twenty.
  Stream<List<StudentSummaryModel>> watchStudents({int? limit, EducationLevel? educationLevel}) {
    Query<Map<String, dynamic>> query = _firestore
        .collection(FirestorePaths.students(_actingUser.schoolId))
        .where('isDeleted', isEqualTo: false);
    if (educationLevel != null) {
      query = query.where('educationLevel', isEqualTo: educationLevel.value);
    }
    query = query.orderBy('lastName');
    if (limit != null) query = query.limit(limit);
    return query
        .snapshots()
        .map((snap) => snap.docs.map((d) => StudentSummaryModel.fromFirestore(d.id, d.data())).toList());
  }

  /// One unbounded read of the whole roster, on demand.
  ///
  /// Export needs every student, but it is a button someone presses rather
  /// than something the screen does on open, so it pays for the full read
  /// only when asked. A one-shot `get()` and not a stream: the CSV is a
  /// snapshot of a moment, and a listener left open would keep charging
  /// for a list nobody is looking at any more.
  Future<List<StudentSummaryModel>> fetchAllStudents() async {
    final snap = await _firestore
        .collection(FirestorePaths.students(_actingUser.schoolId))
        .where('isDeleted', isEqualTo: false)
        .orderBy('lastName')
        .get();
    return snap.docs.map((d) => StudentSummaryModel.fromFirestore(d.id, d.data())).toList();
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

  /// Sets the student's ID photo.
  ///
  /// An ordinary field update, not a callable: firestore.rules names
  /// `photoUrl` among the fields a Registrar may write directly, and it
  /// carries none of the weight that put `balance`, `studentNumber` and
  /// `userId` behind the server. Kept apart from [updateStudent] so that
  /// uploading a photo does not have to resend the name, grade and
  /// section -- and so it cannot overwrite an edit someone else is in the
  /// middle of making.
  Future<void> setStudentPhoto({
    required String studentId,
    required String photoUrl,
  }) async {
    await _firestore.doc(FirestorePaths.studentDoc(_actingUser.schoolId, studentId)).update({
      'photoUrl': photoUrl,
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
