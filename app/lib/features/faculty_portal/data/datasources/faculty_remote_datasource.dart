import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../../../../core/constants/firestore_paths.dart';
import '../../../../core/errors/app_exceptions.dart';
import '../../domain/entities/class_assessment.dart';
import '../models/class_record_models.dart';
import '../models/coursework_item_model.dart';
import '../models/answer_key_model.dart';
import '../models/coursework_submission_model.dart';
import '../../../registrar_portal/data/models/student_summary_model.dart';
import '../models/grade_model.dart';
import '../models/grading_scheme_model.dart';
import '../../domain/entities/grading_scheme.dart';

class ActingFaculty {
  final String uid;
  final String schoolId;
  final String name;
  const ActingFaculty({required this.uid, required this.schoolId, required this.name});
}

class FacultyRemoteDataSource {
  final FirebaseFirestore _firestore;
  final FirebaseFunctions _functions;
  final ActingFaculty _actingUser;

  const FacultyRemoteDataSource({
    required FirebaseFirestore firestore,
    required FirebaseFunctions functions,
    required ActingFaculty actingUser,
  })  : _firestore = firestore,
        _functions = functions,
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

  /// One class's marks, for one quarter.
  ///
  /// The term filter is not a convenience. Without it this returned every
  /// mark the class had ever been given, and the caller that turned them
  /// into a quarterly grade labelled the result with whichever term
  /// happened to come first -- so a teacher in Q2 was shown a number
  /// computed from Q1 and Q2 added together.
  ///
  /// The limit is per class per quarter now rather than per class for the
  /// year. On the old query a busy subject reached 300 inside a quarter
  /// and the oldest marks fell out of the window, which does not fail:
  /// it quietly moves the grade.
  Stream<List<GradeModel>> watchGradesFor({
    required String subject,
    required String section,
    String? term,
  }) {
    Query<Map<String, dynamic>> query = _firestore
        .collection(FirestorePaths.grades(_actingUser.schoolId))
        .where('subject', isEqualTo: subject)
        .where('section', isEqualTo: section)
        .where('isDeleted', isEqualTo: false);
    if (term != null && term.isNotEmpty) {
      query = query.where('term', isEqualTo: term);
    }
    return query
        .orderBy('submittedAt', descending: true)
        .limit(1000)
        .snapshots()
        .map((snap) => snap.docs.map((d) => GradeModel.fromFirestore(d.id, d.data())).toList());
  }

  /// The pieces of work one class was given in one quarter.
  Stream<List<ClassAssessmentModel>> watchClassAssessments({
    required String subject,
    required String section,
    required String term,
  }) {
    return _firestore
        .collection(FirestorePaths.classAssessments(_actingUser.schoolId))
        .where('subject', isEqualTo: subject)
        .where('section', isEqualTo: section)
        .where('term', isEqualTo: term)
        .where('isDeleted', isEqualTo: false)
        .limit(200)
        .snapshots()
        .map((snap) {
      final items = snap.docs
          .map((d) => ClassAssessmentModel.fromFirestore(d.id, d.data()))
          .toList();
      // Ordered here rather than in the query: ordering by createdAt in
      // Firestore would need a composite index for a list this small,
      // and a class record read in the order things were given out is
      // the order a teacher expects their columns in.
      items.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      return items;
    });
  }

  /// The split this class is graded on, when the teacher has set one.
  Stream<SubjectWeights?> watchClassWeights({
    required String subject,
    required String section,
  }) {
    return _firestore
        .doc(FirestorePaths.classWeightsDoc(
            _actingUser.schoolId, classKeyFor(subject, section)))
        .snapshots()
        .map((snap) => ClassWeightsModel.weightsFrom(snap.data()));
  }

  Stream<String?> watchClassWeightsSetBy({
    required String subject,
    required String section,
  }) {
    return _firestore
        .doc(FirestorePaths.classWeightsDoc(
            _actingUser.schoolId, classKeyFor(subject, section)))
        .snapshots()
        .map((snap) => ClassWeightsModel.setByName(snap.data()));
  }

  /// Creates or edits a piece of work. Returns the ids of any marks that
  /// no longer fit its total.
  Future<({String assessmentId, List<String> marksOverMax})> saveClassAssessment({
    String? assessmentId,
    required String subject,
    required String section,
    required String term,
    required String title,
    required GradingComponent component,
    required double maxScore,
  }) async {
    try {
      final callable = _functions.httpsCallable('saveClassAssessment');
      final response = await callable.call({
        'schoolId': _actingUser.schoolId,
        if (assessmentId != null) 'assessmentId': assessmentId,
        'subject': subject,
        'section': section,
        'term': term,
        'title': title,
        'component': component.value,
        'maxScore': maxScore,
      });
      final data = (response.data as Map).cast<Object?, Object?>();
      return (
        assessmentId: data['assessmentId'] as String? ?? '',
        marksOverMax: [
          for (final n in (data['marksOverMax'] as List<Object?>? ?? []))
            if (n is String) n,
        ],
      );
    } on FirebaseFunctionsException catch (e) {
      throw ServerException(e.message ?? 'Could not save that piece of work.');
    }
  }

  /// A whole column of marks at once.
  ///
  /// Each lands at `{assessment}_{student}`, so typing a corrected score
  /// over a wrong one replaces it. The old path wrote a new document
  /// every time and the arithmetic summed them: 80 out of 10 corrected
  /// to 8 out of 10 became 88 out of 20.
  Future<({int saved, int cleared})> saveAssessmentScores({
    required String assessmentId,
    required List<ScoreEntry> scores,
  }) async {
    try {
      final callable = _functions.httpsCallable('saveAssessmentScores');
      final response = await callable.call({
        'schoolId': _actingUser.schoolId,
        'assessmentId': assessmentId,
        'scores': [
          for (final entry in scores)
            {
              'studentId': entry.studentId,
              'studentName': entry.studentName,
              'score': entry.score,
            },
        ],
      });
      final data = (response.data as Map).cast<Object?, Object?>();
      return (
        saved: (data['saved'] as num?)?.toInt() ?? 0,
        cleared: (data['cleared'] as num?)?.toInt() ?? 0,
      );
    } on FirebaseFunctionsException catch (e) {
      throw ServerException(e.message ?? 'Could not save those marks.');
    }
  }

  Future<void> setClassWeights({
    required String subject,
    required String section,
    SubjectWeights? weights,
  }) async {
    try {
      final callable = _functions.httpsCallable('setClassWeights');
      await callable.call({
        'schoolId': _actingUser.schoolId,
        'subject': subject,
        'section': section,
        if (weights == null)
          'clear': true
        else ...{
          'writtenWork': weights.writtenWork,
          'performanceTask': weights.performanceTask,
          'quarterlyAssessment': weights.quarterlyAssessment,
        },
      });
    } on FirebaseFunctionsException catch (e) {
      throw ServerException(e.message ?? 'Could not save those percentages.');
    }
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

  /// One mark, posted without setting up a column first.
  ///
  /// The path the import and the single-student dialog use.
  /// `postGradeMark` finds or creates the piece of work the mark belongs
  /// to and writes the mark against it at a derived id -- so a re-run
  /// replaces rather than adds. This used to write a new document every
  /// time, and the quarterly arithmetic sums the scores and the maximums
  /// inside a component: an import run twice doubled a child's written
  /// work, and a corrected mark was added to the wrong one rather than
  /// replacing it.
  Future<void> submitGrade({
    required String studentId,
    required String studentName,
    required String subject,
    required String section,
    required String term,
    required double score,
    required double maxScore,
    required GradingComponent component,
    String? courseworkItemId,
    String? remarks,
  }) async {
    try {
      final callable = _functions.httpsCallable('postGradeMark');
      await callable.call({
        'schoolId': _actingUser.schoolId,
        'studentId': studentId,
        'studentName': studentName,
        'subject': subject,
        'section': section,
        'term': term,
        'component': component.value,
        'score': score,
        'maxScore': maxScore,
        'remarks': remarks,
      });
    } on FirebaseFunctionsException catch (e) {
      throw ServerException(e.message ?? 'Could not post that mark.');
    }
  }

  Stream<GradingSchemeModel> watchGradingScheme() {
    return _firestore
        .doc(FirestorePaths.gradingSchemeDoc(_actingUser.schoolId))
        .snapshots()
        .map((snap) => GradingSchemeModel.fromFirestore(snap.data()));
  }

  /// Saves the weights and the table, and clears the confirmation.
  ///
  /// Clearing it is the point. A scheme somebody confirmed in June and
  /// somebody else edited in October is not a confirmed scheme, and the
  /// only way that stays true is if editing revokes it rather than
  /// relying on whoever edited to remember to say so.
  Future<void> saveGradingScheme(GradingScheme scheme) async {
    await _firestore.doc(FirestorePaths.gradingSchemeDoc(_actingUser.schoolId)).set({
      ...GradingSchemeModel.toMap(scheme),
      'confirmedBySchool': false,
      'confirmedByName': null,
      'confirmedAt': null,
      'schoolId': _actingUser.schoolId,
      'updatedBy': _actingUser.uid,
      'updatedByName': _actingUser.name,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Records that a named person at the school has checked the weights
  /// against the order that is current for them.
  Future<void> confirmGradingScheme() async {
    await _firestore.doc(FirestorePaths.gradingSchemeDoc(_actingUser.schoolId)).set({
      'confirmedBySchool': true,
      'confirmedByName': _actingUser.name,
      'confirmedAt': FieldValue.serverTimestamp(),
      'schoolId': _actingUser.schoolId,
      'updatedBy': _actingUser.uid,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}
