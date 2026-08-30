import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../../core/constants/firestore_paths.dart';
import '../../../qr_attendance/data/models/attendance_record_model.dart';
import '../../../qr_attendance/domain/entities/attendance_record.dart';
import '../../domain/entities/leave_request.dart';
import '../models/leave_request_model.dart';

/// Who is acting, denormalised onto every request they file.
class ActingEmployee {
  final String uid;
  final String schoolId;
  final String name;
  final String role;
  const ActingEmployee({
    required this.uid,
    required this.schoolId,
    required this.name,
    required this.role,
  });
}

class TimekeepingRemoteDataSource {
  final FirebaseFirestore _firestore;
  final ActingEmployee _actingUser;

  /// A school of a hundred staff does not file more than this in a term,
  /// and a queue nobody can scroll past is a queue nobody works through.
  static const pageSize = 200;

  const TimekeepingRemoteDataSource({
    required FirebaseFirestore firestore,
    required ActingEmployee actingUser,
  })  : _firestore = firestore,
        _actingUser = actingUser;

  CollectionReference<Map<String, dynamic>> get _leave =>
      _firestore.collection(FirestorePaths.leaveRequests(_actingUser.schoolId));

  Stream<List<LeaveRequest>> watchMyLeave() => _watchLeaveFor(_actingUser.uid);

  Stream<List<LeaveRequest>> watchLeaveFor(String employeeUid) =>
      _watchLeaveFor(employeeUid);

  Stream<List<LeaveRequest>> _watchLeaveFor(String employeeUid) {
    return _leave
        .where('employeeUid', isEqualTo: employeeUid)
        .where('isDeleted', isEqualTo: false)
        .orderBy('createdAt', descending: true)
        .limit(pageSize)
        .snapshots()
        .map(_toRequests);
  }

  /// The whole school's, for the office.
  ///
  /// Not filtered to pending: a queue that hides what it decided
  /// yesterday is a queue nobody can check, and the decision history is
  /// half of what makes a leave record worth keeping.
  Stream<List<LeaveRequest>> watchAllLeave() {
    return _leave
        .where('isDeleted', isEqualTo: false)
        .orderBy('createdAt', descending: true)
        .limit(pageSize)
        .snapshots()
        .map(_toRequests);
  }

  Stream<List<AttendanceRecord>> watchAttendanceFor({
    required String employeeUid,
    required String fromDate,
    required String toDate,
  }) {
    // Matches the existing (personId ASC, date DESC) index rather than
    // asking for a new one. The timesheet builder does not care what
    // order these arrive in.
    return _firestore
        .collection(FirestorePaths.attendance(_actingUser.schoolId))
        .where('personId', isEqualTo: employeeUid)
        .where('date', isGreaterThanOrEqualTo: fromDate)
        .where('date', isLessThanOrEqualTo: toDate)
        .orderBy('date', descending: true)
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => AttendanceRecordModel.fromFirestore(d.id, d.data()))
            .toList());
  }

  Future<void> fileLeave({
    required LeaveType type,
    required String fromDate,
    required String toDate,
    required int days,
    required String reason,
  }) async {
    final ref = _leave.doc();
    await ref.set({
      'id': ref.id,
      'schoolId': _actingUser.schoolId,
      // Pinned to the caller. The rules require it to equal their own
      // uid, so nobody files leave in a colleague's name.
      'employeeUid': _actingUser.uid,
      'employeeName': _actingUser.name,
      'employeeRole': _actingUser.role,
      'type': type.value,
      'fromDate': fromDate,
      'toDate': toDate,
      'days': days,
      'reason': reason,
      'status': 'pending',
      'decidedByUid': null,
      'decidedByName': null,
      'decidedByRole': null,
      'decidedAt': null,
      'decisionRemarks': null,
      'createdAt': FieldValue.serverTimestamp(),
      'createdBy': _actingUser.uid,
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedBy': _actingUser.uid,
      'deletedAt': null,
      'deletedBy': null,
      'isDeleted': false,
    });
  }

  Future<void> cancelLeave(String requestId) async {
    await _leave.doc(requestId).update({
      'status': 'cancelled',
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedBy': _actingUser.uid,
    });
  }

  Future<void> decideLeave({
    required String requestId,
    required bool approved,
    String? remarks,
  }) async {
    await _leave.doc(requestId).update({
      'status': approved ? 'approved' : 'declined',
      // The three the rules check against the caller's own token, so a
      // decision cannot be recorded under somebody else's name.
      'decidedByUid': _actingUser.uid,
      'decidedByName': _actingUser.name,
      'decidedByRole': _actingUser.role,
      'decidedAt': FieldValue.serverTimestamp(),
      'decisionRemarks': (remarks == null || remarks.trim().isEmpty)
          ? null
          : remarks.trim(),
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedBy': _actingUser.uid,
    });
  }

  List<LeaveRequest> _toRequests(QuerySnapshot<Map<String, dynamic>> snap) =>
      snap.docs
          .map((d) => LeaveRequestModel.fromFirestore(d.id, d.data()))
          .toList();
}
