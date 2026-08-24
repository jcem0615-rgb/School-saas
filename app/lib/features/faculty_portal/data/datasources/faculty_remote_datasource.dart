import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../../core/constants/firestore_paths.dart';
import '../models/coursework_item_model.dart';
import '../models/answer_key_model.dart';
import '../models/coursework_submission_model.dart';
import '../../../registrar_portal/data/models/student_summary_model.dart';
import '../models/grade_model.dart';

class ActingFaculty {
  final String uid;
  final String schoolId;
  final String name;
  const ActingFaculty({required this.uid, required this.schoolId, required this.name});
}

class FacultyRemoteDataSource {
  final FirebaseFirestore _firestore;
  final ActingFaculty _actingUser;

  const FacultyRemoteDataSource({required FirebaseFirestore firestore, required ActingFaculty actingUser})
      : _firestore = firestore,
        _actingUser = actingUser;

  Stream<List<CourseworkItemModel>> watchMyCourseworkItems() {
    return _firestore
        .collection(FirestorePaths.courseworkItems(_actingUser.schoolId))
        .where('teacherId', isEqualTo: _actingUser.uid)
        .where('isDeleted', isEqualTo: false)
        .orderBy('createdAt', descending: true)
        .limit(200)
        .snapshots()
        .map((snap) => snap.docs.map((d) => CourseworkItemModel.fromFirestore(d.id, d.data())).toList());
  }

  Stream<List<CourseworkSubmissionModel>> watchSubmissionsFor(String courseworkId) {
    return _firestore
        .collection(FirestorePaths.courseworkSubmissions(_actingUser.schoolId))
        .where('courseworkId', isEqualTo: courseworkId)
        .limit(300)
        .snapshots()
        .map((snap) =>
            snap.docs.map((d) => CourseworkSubmissionModel.fromFirestore(d.id, d.data())).toList());
  }

  Stream<AnswerKeyModel?> watchAnswerKey(String courseworkId) {
    return _firestore
        .doc('${FirestorePaths.courseworkAnswerKeys(_actingUser.schoolId)}/$courseworkId')
        .snapshots()
        .map((snap) => snap.exists ? AnswerKeyModel.fromFirestore(courseworkId, snap.data()!) : null);
  }

  Future<void> saveAnswerKey({
    required String courseworkId,
    required List<String> answers,
    required double pointsPerQuestion,
  }) async {
    await _firestore
        .doc('${FirestorePaths.courseworkAnswerKeys(_actingUser.schoolId)}/$courseworkId')
        .set({
      'courseworkId': courseworkId,
      'answers': answers,
      'pointsPerQuestion': pointsPerQuestion,
      'schoolId': _actingUser.schoolId,
      'updatedBy': _actingUser.uid,
      'updatedByName': _actingUser.name,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    // The count lives on the coursework item because the student form
    // needs it and must never see the key itself.
    await _firestore
        .doc('${FirestorePaths.courseworkItems(_actingUser.schoolId)}/$courseworkId')
        .update({
      'questionCount': answers.length,
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedBy': _actingUser.uid,
    });
  }

  Future<void> gradeSubmission({
    required String submissionId,
    required double score,
    String? feedback,
  }) async {
    await _firestore
        .doc('${FirestorePaths.courseworkSubmissions(_actingUser.schoolId)}/$submissionId')
        .update({
      'score': score,
      'feedback': feedback,
      'gradedBy': _actingUser.uid,
      'gradedByName': _actingUser.name,
      'gradedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> createCourseworkItem({
    required String type,
    required String delivery,
    required String title,
    required String description,
    required String subject,
    required String section,
    DateTime? dueDate,
    double? totalPoints,
    required bool published,
    String? attachmentUrl,
    String? attachmentName,
  }) async {
    final ref = _firestore.collection(FirestorePaths.courseworkItems(_actingUser.schoolId)).doc();
    await ref.set({
      'id': ref.id,
      'type': type,
      'delivery': delivery,
      'title': title,
      'description': description,
      'subject': subject,
      'section': section,
      'teacherId': _actingUser.uid,
      'teacherName': _actingUser.name,
      'dueDate': dueDate != null ? Timestamp.fromDate(dueDate) : null,
      'totalPoints': totalPoints,
      'attachmentUrl': attachmentUrl,
      'attachmentName': attachmentName,
      'published': published,
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

  /// teacherId is deliberately absent from the payload: firestore.rules
  /// rejects any update that changes it, so an edit can never reassign
  /// another teacher's coursework to the editor.
  Future<void> updateCourseworkItem({
    required String itemId,
    required String type,
    required String delivery,
    required String title,
    required String description,
    required String subject,
    required String section,
    DateTime? dueDate,
    double? totalPoints,
    required bool published,
    String? attachmentUrl,
    String? attachmentName,
  }) async {
    await _firestore
        .collection(FirestorePaths.courseworkItems(_actingUser.schoolId))
        .doc(itemId)
        .update({
      'attachmentUrl': attachmentUrl,
      'attachmentName': attachmentName,
      'type': type,
      'delivery': delivery,
      'title': title,
      'description': description,
      'subject': subject,
      'section': section,
      'dueDate': dueDate != null ? Timestamp.fromDate(dueDate) : null,
      'totalPoints': totalPoints,
      'published': published,
      'updatedBy': _actingUser.uid,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Soft delete -- courseworkItems sets `allow delete: if false`, and
  /// watchMyCourseworkItems already filters on isDeleted.
  Future<void> softDeleteCourseworkItem(String itemId) async {
    await _firestore
        .collection(FirestorePaths.courseworkItems(_actingUser.schoolId))
        .doc(itemId)
        .update({
      'isDeleted': true,
      'deletedAt': FieldValue.serverTimestamp(),
      'deletedBy': _actingUser.uid,
      'updatedBy': _actingUser.uid,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Stream<List<GradeModel>> watchGradesFor({required String subject, required String section}) {
    return _firestore
        .collection(FirestorePaths.grades(_actingUser.schoolId))
        .where('subject', isEqualTo: subject)
        .where('section', isEqualTo: section)
        .where('isDeleted', isEqualTo: false)
        .orderBy('submittedAt', descending: true)
        .limit(300)
        .snapshots()
        .map((snap) => snap.docs.map((d) => GradeModel.fromFirestore(d.id, d.data())).toList());
  }

  /// Students in one section, for the grade roster.
  ///
  /// Faculty are allowed to read student records (firestore.rules grants
  /// it, subject to division scoping), which is what makes a roster
  /// possible without going through the Registrar's repository.
  Stream<List<StudentSummaryModel>> watchStudentsInSection(String section) {
    return _firestore
        .collection(FirestorePaths.students(_actingUser.schoolId))
        .where('section', isEqualTo: section)
        .where('isDeleted', isEqualTo: false)
        .orderBy('lastName')
        .limit(200)
        .snapshots()
        .map((snap) => snap.docs.map((d) => StudentSummaryModel.fromFirestore(d.id, d.data())).toList());
  }

  Future<void> submitGrade({
    required String studentId,
    required String studentName,
    required String subject,
    required String section,
    required String term,
    required double score,
    required double maxScore,
    String? courseworkItemId,
    String? remarks,
  }) async {
    final ref = _firestore.collection(FirestorePaths.grades(_actingUser.schoolId)).doc();
    await ref.set({
      'id': ref.id,
      'studentId': studentId,
      'studentName': studentName,
      'subject': subject,
      'section': section,
      'term': term,
      'courseworkItemId': courseworkItemId,
      'score': score,
      'maxScore': maxScore,
      'remarks': remarks,
      'submittedByName': _actingUser.name,
      'submittedAt': FieldValue.serverTimestamp(),
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
