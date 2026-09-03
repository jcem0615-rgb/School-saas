import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../../../../core/constants/education_level.dart';
import '../../../../core/constants/firestore_paths.dart';
import '../../../../core/errors/app_exceptions.dart';
import '../../../faculty_portal/data/models/grade_model.dart';
import '../../domain/entities/document_release.dart';
import '../models/document_release_model.dart';
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

  /// Every mark this student has been given, newest first.
  ///
  /// The transcript is built from these, so it reads them all rather
  /// than a page: a TOR missing Grade 8 because it fell past a limit is
  /// worse than no TOR at all, and it is printed rarely enough that the
  /// full read costs nothing anyone will notice.
  ///
  /// Reads the faculty portal's collection because that is where a mark
  /// is written; firestore.rules already lets a Registrar read any grade
  /// belonging to a student in their scope.
  Stream<List<GradeModel>> watchStudentGrades(String studentId) {
    return _firestore
        .collection(FirestorePaths.grades(_actingUser.schoolId))
        .where('studentId', isEqualTo: studentId)
        .where('isDeleted', isEqualTo: false)
        .orderBy('submittedAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map((d) => GradeModel.fromFirestore(d.id, d.data())).toList());
  }

  /// What has already been handed out for this student, newest first.
  Stream<List<DocumentReleaseModel>> watchDocumentReleases(String studentId) {
    return _firestore
        .collection(FirestorePaths.documentReleases(_actingUser.schoolId))
        .where('studentId', isEqualTo: studentId)
        .where('isDeleted', isEqualTo: false)
        .orderBy('releasedAt', descending: true)
        .snapshots()
        .map((snap) =>
            snap.docs.map((d) => DocumentReleaseModel.fromFirestore(d.id, d.data())).toList());
  }

  /// Writes the release log entry.
  ///
  /// An ordinary create rather than a callable: nothing here is a figure
  /// the server owns, and firestore.rules pins `releasedBy` to the
  /// caller and refuses every update and delete, which is the whole of
  /// what has to be enforced about a log like this.
  ///
  /// `releasedAt` comes from the server clock. A device with the wrong
  /// date would otherwise file a release under a day it did not happen,
  /// and this is precisely the field somebody will later be asked about.
  Future<void> recordDocumentRelease({
    required String studentId,
    required String studentName,
    required SchoolDocument document,
    required int copies,
    required String purpose,
    required String releasedToName,
    String? releasedToRelation,
    String? remarks,
  }) async {
    final ref =
        _firestore.collection(FirestorePaths.documentReleases(_actingUser.schoolId)).doc();
    await ref.set({
      'id': ref.id,
      'studentId': studentId,
      'studentName': studentName,
      'document': document.value,
      'copies': copies,
      'purpose': purpose,
      'releasedToName': releasedToName,
      'releasedToRelation': releasedToRelation,
      'releasedByName': _actingUser.name,
      'releasedBy': _actingUser.uid,
      'releasedAt': FieldValue.serverTimestamp(),
      'remarks': remarks,
      'schoolId': _actingUser.schoolId,
      'createdBy': _actingUser.uid,
      'createdAt': FieldValue.serverTimestamp(),
      'isDeleted': false,
    });
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
    String? email,
    String? phone,
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
        'email': email,
        'phone': phone,
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
    String? email,
    String? phone,
  }) async {
    await _firestore.doc(FirestorePaths.studentDoc(_actingUser.schoolId, studentId)).update({
      // Omitted rather than written as null when unset -- an edit that
      // leaves the field blank should not erase a birth date the
      // registrar entered earlier.
      if (birthDate != null) 'birthDate': Timestamp.fromDate(birthDate),
      // Written unconditionally, unlike the birth date above, and null
      // when blank. The difference is deliberate: the edit screen is the
      // only caller and it always sends what is in the two fields, so a
      // registrar who clears a wrong number means to clear it. A birth
      // date has no such screen path to empty it.
      'email': _blankToNull(email),
      'phone': _blankToNull(phone),
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
    String? phone,
  }) async {
    try {
      final callable = _functions.httpsCallable('provisionUser');
      final response = await callable.call({
        'schoolId': _actingUser.schoolId,
        'role': 'student',
        'firstName': firstName,
        'lastName': lastName,
        'email': email,
        // Carried onto the user document so a password reset by phone can
        // find this account. Without it the only way a number ever gets
        // there is the person editing their own profile -- which needs a
        // sign-in, and needing a sign-in is the situation phone recovery
        // exists for.
        'phone': phone,
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

  // ---- Year-end rollover ----

  /// Every mark posted for one section, so the rollover can compute a
  /// year's grades for a whole class in one read.
  ///
  /// A section at a time rather than the whole school. It is how a
  /// registrar works -- through class lists they recognise -- and it
  /// keeps both the read and the review list a human size. A screen
  /// asking somebody to check nine hundred rows in one sitting is a
  /// screen that gets scrolled past.
  Future<List<GradeModel>> fetchGradesForSection(String section) async {
    final snap = await _firestore
        .collection(FirestorePaths.grades(_actingUser.schoolId))
        .where('section', isEqualTo: section)
        .where('isDeleted', isEqualTo: false)
        .orderBy('submittedAt', descending: true)
        .get();
    return snap.docs.map((d) => GradeModel.fromFirestore(d.id, d.data())).toList();
  }

  /// The students already moved for this year, so the screen can show
  /// what is done rather than offering to do it again.
  Future<Set<String>> fetchRolledOverStudentIds(String schoolYear) async {
    final snap = await _firestore
        .collection(FirestorePaths.promotions(_actingUser.schoolId))
        .where('schoolYear', isEqualTo: schoolYear)
        .get();
    return {
      for (final doc in snap.docs)
        if (doc.data()['studentId'] is String) doc.data()['studentId'] as String,
    };
  }

  Future<Map<String, dynamic>> runYearEndRollover({
    required String schoolYear,
    required List<Map<String, dynamic>> decisions,
  }) async {
    try {
      final callable = _functions.httpsCallable('runYearEndRollover');
      final response = await callable.call({
        'schoolId': _actingUser.schoolId,
        'schoolYear': schoolYear,
        'decisions': decisions,
      });
      return Map<String, dynamic>.from(response.data as Map);
    } on FirebaseFunctionsException catch (e) {
      throw ServerException(e.message ?? 'The rollover did not finish.');
    }
  }

  /// An empty field means "there is none", which is null on the record --
  /// not an empty string. Mixing the two makes "which students have no
  /// number on file?" a question nobody can answer with one query.
  static String? _blankToNull(String? value) {
    final trimmed = value?.trim();
    return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
  }
}
