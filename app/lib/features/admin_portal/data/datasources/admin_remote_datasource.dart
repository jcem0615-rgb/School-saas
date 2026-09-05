import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../../../../core/constants/firestore_paths.dart';
import '../../../../core/errors/app_exceptions.dart';
import '../models/employee_summary_model.dart';
import '../models/program_model.dart';
import '../models/school_branding_model.dart';
import '../models/teacher_assignment_model.dart';

/// Snapshot of who is performing the write, rebuilt whenever the signed-in
/// user changes (see adminRemoteDataSourceProvider).
class ActingAdmin {
  final String uid;
  final String schoolId;
  final String name;
  const ActingAdmin({required this.uid, required this.schoolId, required this.name});
}

class AdminRemoteDataSource {
  final FirebaseFirestore _firestore;
  final FirebaseFunctions _functions;
  final ActingAdmin _actingUser;

  const AdminRemoteDataSource({
    required FirebaseFirestore firestore,
    required FirebaseFunctions functions,
    required ActingAdmin actingUser,
  })  : _firestore = firestore,
        _functions = functions,
        _actingUser = actingUser;

  static const _staffRoles = ['director', 'admin', 'registrar', 'faculty', 'staff', 'guidance'];

  Map<String, dynamic> _editFields() => {
        'updatedBy': _actingUser.uid,
        'updatedAt': FieldValue.serverTimestamp(),
      };

  /// Deletion is a flag flip: programs and teacherAssignments both set
  /// `allow delete: if false`, and both reads filter on isDeleted.
  Map<String, dynamic> _softDeleteFields() => {
        'isDeleted': true,
        'deletedAt': FieldValue.serverTimestamp(),
        'deletedBy': _actingUser.uid,
        ..._editFields(),
      };

  Stream<List<EmployeeSummaryModel>> watchEmployees() {
    return _firestore
        .collection(FirestorePaths.users(_actingUser.schoolId))
        .where('role', whereIn: _staffRoles)
        .where('isDeleted', isEqualTo: false)
        .orderBy('lastName')
        .snapshots()
        .map((snap) => snap.docs.map((d) => EmployeeSummaryModel.fromFirestore(d.id, d.data())).toList());
  }

  Future<Map<String, dynamic>> createEmployee({
    required String role,
    required String firstName,
    required String lastName,
    required String email,
    String? phone,
    Map<String, dynamic>? employeeInfo,
  }) async {
    try {
      final callable = _functions.httpsCallable('provisionUser');
      final response = await callable.call({
        'schoolId': _actingUser.schoolId,
        'role': role,
        'firstName': firstName,
        'lastName': lastName,
        'email': email,
        // Written onto the user document, which is what
        // resetPasswordByPhone matches against. Provisioning is the only
        // moment the office has the number and the person has no way in.
        'phone': phone,
        'employeeInfo': employeeInfo,
      });
      return Map<String, dynamic>.from(response.data as Map);
    } on FirebaseFunctionsException catch (e) {
      throw ServerException(e.message ?? 'Failed to create employee account.');
    }
  }

  Future<void> updateEmployeeInfo({required String uid, required Map<String, dynamic> employeeInfo}) async {
    await _firestore.doc(FirestorePaths.userDoc(_actingUser.schoolId, uid)).update({
      'employeeInfo': employeeInfo,
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedBy': _actingUser.uid,
    });
  }

  Future<void> setUserStatus({required String uid, required bool active}) async {
    try {
      final callable = _functions.httpsCallable('setUserStatus');
      await callable.call({
        'schoolId': _actingUser.schoolId,
        'targetUserId': uid,
        'status': active ? 'active' : 'suspended',
      });
    } on FirebaseFunctionsException catch (e) {
      throw ServerException(e.message ?? 'Failed to update account status.');
    }
  }

  Future<String> resetUserPassword(String uid) async {
    try {
      final callable = _functions.httpsCallable('resetPasswordAdmin');
      final response = await callable.call({'schoolId': _actingUser.schoolId, 'targetUserId': uid});
      return (response.data as Map)['resetLink'] as String? ?? '';
    } on FirebaseFunctionsException catch (e) {
      throw ServerException(e.message ?? 'Failed to reset password.');
    }
  }

  Stream<List<TeacherAssignmentModel>> watchTeacherAssignments() {
    return _firestore
        .collection(FirestorePaths.teacherAssignments(_actingUser.schoolId))
        .where('isDeleted', isEqualTo: false)
        .orderBy('subject')
        .snapshots()
        .map((snap) => snap.docs.map((d) => TeacherAssignmentModel.fromFirestore(d.id, d.data())).toList());
  }

  Future<void> createTeacherAssignment({
    required String teacherId,
    required String teacherName,
    required String subject,
    required String section,
    required String schoolYear,
    bool isAdviser = false,
  }) async {
    final ref = _firestore.collection(FirestorePaths.teacherAssignments(_actingUser.schoolId)).doc();
    await ref.set({
      'id': ref.id,
      'teacherId': teacherId,
      'teacherName': teacherName,
      'subject': subject,
      'section': section,
      'schoolYear': schoolYear,
      'isAdviser': isAdviser,
      'schoolId': _actingUser.schoolId,
      'createdBy': _actingUser.uid,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedBy': _actingUser.uid,
      'updatedAt': FieldValue.serverTimestamp(),
      'deletedAt': null,
      'deletedBy': null,
      'isDeleted': false,
    });
  }

  /// createdBy stays untouched -- the teacherAssignments rule rejects any
  /// update that changes it.
  Future<void> updateTeacherAssignment({
    required String assignmentId,
    required String teacherId,
    required String teacherName,
    required String subject,
    required String section,
    required String schoolYear,
    bool isAdviser = false,
  }) async {
    await _firestore
        .collection(FirestorePaths.teacherAssignments(_actingUser.schoolId))
        .doc(assignmentId)
        .update({
      'teacherId': teacherId,
      'teacherName': teacherName,
      'subject': subject,
      'section': section,
      'schoolYear': schoolYear,
      'isAdviser': isAdviser,
      ..._editFields(),
    });
  }

  Future<void> softDeleteTeacherAssignment(String assignmentId) async {
    await _firestore
        .collection(FirestorePaths.teacherAssignments(_actingUser.schoolId))
        .doc(assignmentId)
        .update(_softDeleteFields());
  }

  Stream<List<ProgramModel>> watchPrograms() {
    return _firestore
        .collection(FirestorePaths.programs(_actingUser.schoolId))
        .where('isDeleted', isEqualTo: false)
        .orderBy('name')
        .snapshots()
        .map((snap) => snap.docs.map((d) => ProgramModel.fromFirestore(d.id, d.data())).toList());
  }

  Future<void> createProgram({
    required String name,
    required String code,
    required String department,
    required String educationLevel,
  }) async {
    final ref = _firestore.collection(FirestorePaths.programs(_actingUser.schoolId)).doc();
    await ref.set({
      'id': ref.id,
      'name': name,
      'code': code,
      'department': department,
      'educationLevel': educationLevel,
      'schoolId': _actingUser.schoolId,
      'createdBy': _actingUser.uid,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedBy': _actingUser.uid,
      'updatedAt': FieldValue.serverTimestamp(),
      'deletedAt': null,
      'deletedBy': null,
      'isDeleted': false,
    });
  }

  Future<void> updateProgram({
    required String programId,
    required String name,
    required String code,
    required String department,
  }) async {
    await _firestore
        .collection(FirestorePaths.programs(_actingUser.schoolId))
        .doc(programId)
        .update({
      'name': name,
      'code': code,
      'department': department,
      ..._editFields(),
    });
  }

  /// Note: students carry a denormalized programName/department captured
  /// at registration (see docs/15-divisions-and-programs.md), so deleting
  /// a program does not orphan or rewrite existing student records -- it
  /// only removes the option from the catalogue going forward.
  Future<void> softDeleteProgram(String programId) async {
    await _firestore
        .collection(FirestorePaths.programs(_actingUser.schoolId))
        .doc(programId)
        .update(_softDeleteFields());
  }

  // ---- School branding ----

  Stream<SchoolBrandingModel> watchBranding() {
    return _firestore
        .doc(FirestorePaths.brandingDoc(_actingUser.schoolId))
        .snapshots()
        .map((snap) => SchoolBrandingModel.fromFirestore(snap.data()));
  }

  Future<void> updateBranding(Map<String, dynamic> fields) async {
    // merge: saving the school name must not clear a previously uploaded
    // logo, and vice versa.
    await _firestore.doc(FirestorePaths.brandingDoc(_actingUser.schoolId)).set({
      ...fields,
      'schoolId': _actingUser.schoolId,
      'updatedBy': _actingUser.uid,
      'updatedByName': _actingUser.name,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}
