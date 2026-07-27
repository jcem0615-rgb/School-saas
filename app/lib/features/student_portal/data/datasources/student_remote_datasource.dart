import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../../core/constants/firestore_paths.dart';
import '../../../admin_portal/data/models/teacher_assignment_model.dart';
import '../../../faculty_portal/data/models/coursework_item_model.dart';
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
