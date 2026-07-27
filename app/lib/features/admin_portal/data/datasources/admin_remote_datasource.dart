import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../../../../core/constants/firestore_paths.dart';
import '../../../../core/constants/user_roles.dart';
import '../../../../core/errors/app_exceptions.dart';
import '../models/employee_summary_model.dart';
import '../models/program_model.dart';
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
  }) async {
    final ref = _firestore.collection(FirestorePaths.teacherAssignments(_actingUser.schoolId)).doc();
    await ref.set({
      'id': ref.id,
      'teacherId': teacherId,
      'teacherName': teacherName,
      'subject': subject,
      'section': section,
      'schoolYear': schoolYear,
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

  Stream<List<ProgramModel>> watchPrograms() {
    return _firestore
        .collection(FirestorePaths.programs(_actingUser.schoolId))
        .where('isDeleted', isEqualTo: false)
        .orderBy('name')
        .snapshots()
        .map((snap) => snap.docs.map((d) => ProgramModel.fromFirestore(d.id, d.data())).toList());
  }

  Future<void> createProgram({required String name, required String code, required String department}) async {
    final ref = _firestore.collection(FirestorePaths.programs(_actingUser.schoolId)).doc();
    await ref.set({
      'id': ref.id,
      'name': name,
      'code': code,
      'department': department,
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
}
