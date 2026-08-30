import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../qr_attendance/domain/entities/attendance_record.dart'
    show AttendanceStatus;
import '../../domain/entities/class_session.dart';

class ClassSessionModel {
  const ClassSessionModel._();

  static ClassSession fromFirestore(String id, Map<String, dynamic> data) {
    return ClassSession(
      id: id,
      scheduleBlockId: (data['scheduleBlockId'] as String?) ?? '',
      subject: (data['subject'] as String?) ?? '',
      section: (data['section'] as String?) ?? '',
      room: data['room'] as String?,
      date: (data['date'] as String?) ?? '',
      teacherName: (data['teacherName'] as String?) ?? '',
      takenByUid: (data['takenByUid'] as String?) ?? '',
      takenByName: (data['takenByName'] as String?) ?? '',
      // Falls back to the epoch rather than throwing: a session with no
      // start time is a broken record, and a screen that cannot open is
      // a worse way to find that out than a row that looks wrong.
      openedAt: (data['openedAt'] as Timestamp?)?.toDate() ??
          DateTime.fromMillisecondsSinceEpoch(0),
      closedAt: (data['closedAt'] as Timestamp?)?.toDate(),
      studentCount: (data['studentCount'] as num?)?.toInt() ?? 0,
      counts: _counts(data['counts']),
    );
  }

  static RollCounts? _counts(Object? raw) {
    if (raw is! Map) return null;
    int at(String key) => (raw[key] as num?)?.toInt() ?? 0;
    return RollCounts(
      present: at('present'),
      late: at('late'),
      absent: at('absent'),
      excused: at('excused'),
      total: at('total'),
    );
  }
}

class SubjectAttendanceMarkModel {
  const SubjectAttendanceMarkModel._();

  static SubjectAttendanceMark fromFirestore(String id, Map<String, dynamic> data) {
    return SubjectAttendanceMark(
      id: id,
      sessionId: (data['sessionId'] as String?) ?? '',
      studentId: (data['studentId'] as String?) ?? '',
      studentName: (data['studentName'] as String?) ?? '',
      subject: (data['subject'] as String?) ?? '',
      section: (data['section'] as String?) ?? '',
      date: (data['date'] as String?) ?? '',
      // An unknown mark reads as absent rather than throwing. Wrong in
      // the safe direction: a status this build has never heard of
      // showing as absent is a question somebody asks, where a crash on
      // the register screen is a class that cannot be taken.
      status: AttendanceStatus.values.firstWhere(
        (s) => s.value == data['status'],
        orElse: () => AttendanceStatus.absent,
      ),
      timeIn: (data['timeIn'] as Timestamp?)?.toDate(),
      timeOut: (data['timeOut'] as Timestamp?)?.toDate(),
    );
  }
}
