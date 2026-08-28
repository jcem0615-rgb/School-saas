import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../../../../core/constants/firestore_paths.dart';
import '../../../../core/errors/app_exceptions.dart';
import '../models/schedule_block_model.dart';

class ScheduleRemoteDataSource {
  final FirebaseFirestore _firestore;
  final FirebaseFunctions _functions;
  final String _schoolId;

  ScheduleRemoteDataSource({
    required FirebaseFirestore firestore,
    required FirebaseFunctions functions,
    required String schoolId,
  })  : _firestore = firestore,
        _functions = functions,
        _schoolId = schoolId;

  /// The whole year's timetable, ordered as a week reads.
  ///
  /// Every view is a different cut of the same few hundred documents --
  /// by section, by teacher, by room -- and the clash check needs all of
  /// it anyway, so it is one subscription rather than one per screen.
  Stream<List<ScheduleBlockModel>> watchSchedule(String schoolYear) {
    return _firestore
        .collection(FirestorePaths.scheduleBlocks(_schoolId))
        .where('schoolYear', isEqualTo: schoolYear)
        .where('isDeleted', isEqualTo: false)
        .orderBy('dayOfWeek')
        .orderBy('startMinute')
        .snapshots()
        .map((snap) =>
            snap.docs.map((d) => ScheduleBlockModel.fromFirestore(d.id, d.data())).toList());
  }

  Future<String> saveScheduleBlock({
    String? blockId,
    required String subject,
    required String section,
    required String teacherId,
    required String teacherName,
    String? room,
    required int dayOfWeek,
    required int startMinute,
    required int endMinute,
    required String schoolYear,
    String? term,
  }) async {
    try {
      final result = await _functions.httpsCallable('saveScheduleBlock').call<Map<String, dynamic>>({
        'schoolId': _schoolId,
        if (blockId != null) 'blockId': blockId,
        'subject': subject,
        'section': section,
        'teacherId': teacherId,
        'teacherName': teacherName,
        'room': room,
        'dayOfWeek': dayOfWeek,
        'startMinute': startMinute,
        'endMinute': endMinute,
        'schoolYear': schoolYear,
        'term': term,
      });
      return result.data['blockId'] as String;
    } on FirebaseFunctionsException catch (e) {
      throw ServerException(e.message ?? 'The class could not be saved.');
    }
  }

  Future<void> deleteScheduleBlock(String blockId) async {
    try {
      await _functions.httpsCallable('deleteScheduleBlock').call<Map<String, dynamic>>({
        'schoolId': _schoolId,
        'blockId': blockId,
      });
    } on FirebaseFunctionsException catch (e) {
      throw ServerException(e.message ?? 'The class could not be removed.');
    }
  }
}
