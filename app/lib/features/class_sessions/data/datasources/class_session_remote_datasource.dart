import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../../../../core/constants/firestore_paths.dart';
import '../../../../core/errors/app_exceptions.dart';
import '../../domain/entities/class_session.dart';
import '../models/class_session_model.dart';

/// Reads the register; never writes it.
///
/// Every write goes through a callable, and `firestore.rules` refuses
/// client writes to both collections outright. That is not belt and
/// braces: the roll is built server-side from the section's enrolment,
/// the school's own timezone decides which day a 7:30 class belongs to,
/// and the register is the record a disputed grade gets argued over. A
/// client that could write it could mark itself present in a lesson it
/// never attended.
class ClassSessionRemoteDataSource {
  final FirebaseFirestore _firestore;
  final FirebaseFunctions _functions;
  final String _schoolId;

  /// A term of eight lessons a day is a thousand rows, and no screen
  /// shows a thousand rows. The recent ones are what anybody looks at.
  static const studentHistoryLimit = 200;

  ClassSessionRemoteDataSource({
    required FirebaseFirestore firestore,
    required FirebaseFunctions functions,
    required String schoolId,
  })  : _firestore = firestore,
        _functions = functions,
        _schoolId = schoolId;

  CollectionReference<Map<String, dynamic>> get _sessions =>
      _firestore.collection(FirestorePaths.classSessions(_schoolId));

  CollectionReference<Map<String, dynamic>> get _marks =>
      _firestore.collection(FirestorePaths.subjectAttendance(_schoolId));

  /// Today's classes across the school.
  ///
  /// Not filtered to the signed-in teacher, and deliberately: the caller
  /// already holds today's timetable rows and matches them up by block
  /// id, and a school runs a few dozen classes a day. Filtering by
  /// `takenByUid` would also hide a session a colleague opened as cover,
  /// which is exactly the row a returning teacher needs to see.
  Stream<List<ClassSession>> watchSessionsOn(String dateKey) {
    return _sessions
        .where('date', isEqualTo: dateKey)
        .where('isDeleted', isEqualTo: false)
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => ClassSessionModel.fromFirestore(d.id, d.data()))
            .toList());
  }

  Stream<ClassSession?> watchSession(String sessionId) {
    return _sessions.doc(sessionId).snapshots().map((snap) {
      final data = snap.data();
      if (data == null) return null;
      return ClassSessionModel.fromFirestore(snap.id, data);
    });
  }

  Stream<List<SubjectAttendanceMark>> watchRoll(String sessionId) {
    return _marks
        .where('sessionId', isEqualTo: sessionId)
        .where('isDeleted', isEqualTo: false)
        .snapshots()
        .map((snap) {
      final marks = snap.docs
          .map((d) => SubjectAttendanceMarkModel.fromFirestore(d.id, d.data()))
          .toList();
      // Sorted here rather than by Firestore. Ordering by studentName
      // would need a composite index for the sake of a list of forty
      // that is already in memory.
      marks.sort((a, b) => a.studentName.compareTo(b.studentName));
      return marks;
    });
  }

  Stream<List<SubjectAttendanceMark>> watchStudentMarks(String studentId) {
    return _marks
        .where('studentId', isEqualTo: studentId)
        .where('isDeleted', isEqualTo: false)
        .orderBy('date', descending: true)
        .limit(studentHistoryLimit)
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => SubjectAttendanceMarkModel.fromFirestore(d.id, d.data()))
            .toList());
  }

  Future<String> openSession(String scheduleBlockId) async {
    try {
      final result = await _functions
          .httpsCallable('openClassSession')
          .call<Map<String, dynamic>>({
        'schoolId': _schoolId,
        'scheduleBlockId': scheduleBlockId,
      });
      return result.data['sessionId'] as String;
    } on FirebaseFunctionsException catch (e) {
      throw ServerException(e.message ?? 'The class could not be started.');
    }
  }

  /// Takes today's lesson online, or brings it back into the room.
  ///
  /// Returns the room to join, or null when the class has come back in
  /// person. The room is never invented here: the server generates it,
  /// because a client-chosen room name is one a compromised client can
  /// choose to be somebody else's.
  Future<String?> setMode({required String sessionId, required bool online}) async {
    try {
      final result =
          await _functions.httpsCallable('setClassSessionMode').call<Map<String, dynamic>>({
        'schoolId': _schoolId,
        'sessionId': sessionId,
        'mode': online ? 'online' : 'in_person',
      });
      return result.data['meetingRoom'] as String?;
    } on FirebaseFunctionsException catch (e) {
      throw ServerException(e.message ?? 'The class could not be moved online.');
    }
  }

  /// The pass that gets this person into this lesson without signing in.
  ///
  /// Null is a normal answer, not a failure: a school that has not
  /// configured a signing key joins its Jitsi without a token, which is
  /// what this app did before tokens existed.
  Future<String?> meetingToken(String sessionId) async {
    try {
      final result =
          await _functions.httpsCallable('issueMeetingToken').call<Map<String, dynamic>>({
        'schoolId': _schoolId,
        'sessionId': sessionId,
      });
      return result.data['token'] as String?;
    } on FirebaseFunctionsException catch (e) {
      // A callable that is not deployed is not a refusal, and must not
      // be turned into one. The web app and the functions ship
      // separately, so there is a window -- minutes at best, a forgotten
      // `firebase deploy` at worst -- where the site asks for a token
      // from something that is not there yet. Refusing then would stop
      // every lesson in the school rather than degrade one feature: the
      // sign-in comes back, which is where we were, instead of the class
      // not opening at all.
      if (meansNotDeployed(e.code)) return null;
      throw ServerException(e.message ?? 'You could not be let into the class.');
    }
  }

  /// Whether a callable error means "no such function" rather than "no".
  ///
  /// Kept as a named decision because the two look identical at the call
  /// site and only one of them should ever stop a lesson. Our own
  /// refusals come back as permission-denied, failed-precondition,
  /// unauthenticated or invalid-argument, and every one of those is a
  /// real answer to be shown to somebody.
  @visibleForTesting
  static bool meansNotDeployed(String code) =>
      code == 'not-found' || code == 'unimplemented';

  Future<void> closeSession(String sessionId) async {
    try {
      await _functions.httpsCallable('closeClassSession').call<Map<String, dynamic>>({
        'schoolId': _schoolId,
        'sessionId': sessionId,
      });
    } on FirebaseFunctionsException catch (e) {
      throw ServerException(e.message ?? 'The class could not be ended.');
    }
  }

  Future<void> mark({
    required String sessionId,
    required String studentId,
    required String status,
  }) async {
    try {
      await _functions
          .httpsCallable('markSubjectAttendance')
          .call<Map<String, dynamic>>({
        'schoolId': _schoolId,
        'sessionId': sessionId,
        'studentId': studentId,
        'status': status,
      });
    } on FirebaseFunctionsException catch (e) {
      throw ServerException(e.message ?? 'That mark could not be saved.');
    }
  }
}
