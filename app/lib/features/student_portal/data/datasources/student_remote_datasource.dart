import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../../core/constants/firestore_paths.dart';
import '../../../admin_portal/data/models/teacher_assignment_model.dart';
import '../../../faculty_portal/data/models/coursework_item_model.dart';
import '../../../faculty_portal/data/models/coursework_submission_model.dart';
import '../../../faculty_portal/data/models/grade_model.dart';
import '../../../faculty_portal/domain/entities/coursework_item.dart';
import '../../../registrar_portal/data/models/student_summary_model.dart';

class StudentRemoteDataSource {
  final FirebaseFirestore _firestore;
  final String _schoolId;
  final String _uid;

  const StudentRemoteDataSource({
    required FirebaseFirestore firestore,
    required String schoolId,
    required String uid,
  })  : _firestore = firestore,
        _schoolId = schoolId,
        _uid = uid;

  Stream<StudentSummaryModel?> watchMyStudentRecord() {
    return _firestore
        .collection(FirestorePaths.students(_schoolId))
        .where('userId', isEqualTo: _uid)
        .limit(1)
        .snapshots()
        .map((snap) => snap.docs.isEmpty ? null : StudentSummaryModel.fromFirestore(snap.docs.first.id, snap.docs.first.data()));
  }

  Stream<List<TeacherAssignmentModel>> watchMySubjects(String section) {
    return _firestore
        .collection(FirestorePaths.teacherAssignments(_schoolId))
        .where('section', isEqualTo: section)
        .where('isDeleted', isEqualTo: false)
        .snapshots()
        .map((snap) => snap.docs.map((d) => TeacherAssignmentModel.fromFirestore(d.id, d.data())).toList());
  }

  Stream<List<CourseworkSubmissionModel>> watchMySubmissions(String studentId) {
    return _firestore
        .collection(FirestorePaths.courseworkSubmissions(_schoolId))
        .where('studentId', isEqualTo: studentId)
        .limit(300)
        .snapshots()
        .map((snap) =>
            snap.docs.map((d) => CourseworkSubmissionModel.fromFirestore(d.id, d.data())).toList());
  }

  /// One document per student per coursework item, keyed deterministically
  /// as `{courseworkId}_{studentId}`.
  ///
  /// That key is what makes resubmission idempotent: a student who taps
  /// Submit twice replaces their answer instead of creating a second
  /// document that a teacher would have to reconcile. It also lets
  /// firestore.rules tell create from update without a query.
  Future<void> submitCoursework({
    required String courseworkId,
    required String courseworkTitle,
    required String studentId,
    required String studentName,
    required String section,
    required String answer,
    required List<String> answers,
    String? attachmentUrl,
    String? attachmentName,
    required bool isRevision,
  }) async {
    final ref = _firestore
        .collection(FirestorePaths.courseworkSubmissions(_schoolId))
        .doc('${courseworkId}_$studentId');

    await ref.set({
      'courseworkId': courseworkId,
      'courseworkTitle': courseworkTitle,
      'studentId': studentId,
      'studentName': studentName,
      'section': section,
      'userId': _uid,
      'answer': answer,
      'answers': answers,
      'attachmentUrl': attachmentUrl,
      'attachmentName': attachmentName,
      'schoolId': _schoolId,
      // Server clock, always. Whether work arrived before a deadline is
      // precisely the field a client has a motive to shade, so the
      // device clock never touches it.
      if (!isRevision) 'submittedAt': FieldValue.serverTimestamp(),
      if (isRevision) 'updatedAt': FieldValue.serverTimestamp(),
      'isDeleted': false,
    }, SetOptions(merge: true));
  }

  Stream<List<CourseworkItemModel>> watchMyCoursework(String section, {CourseworkType? typeFilter}) {
    Query<Map<String, dynamic>> query = _firestore
        .collection(FirestorePaths.courseworkItems(_schoolId))
        .where('section', isEqualTo: section)
        .where('published', isEqualTo: true)
        .where('isDeleted', isEqualTo: false);
    if (typeFilter != null) {
      query = query.where('type', isEqualTo: typeFilter.value);
    }
    return query
        .orderBy('createdAt', descending: true)
        .limit(200)
        .snapshots()
        .map((snap) => snap.docs.map((d) => CourseworkItemModel.fromFirestore(d.id, d.data())).toList());
  }

  Stream<List<GradeModel>> watchMyGrades(String studentId) {
    return _firestore
        .collection(FirestorePaths.grades(_schoolId))
        .where('studentId', isEqualTo: studentId)
        .where('isDeleted', isEqualTo: false)
        .orderBy('submittedAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map((d) => GradeModel.fromFirestore(d.id, d.data())).toList());
  }
}
