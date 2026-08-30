import '../../../qr_attendance/domain/entities/attendance_record.dart'
    show AttendanceStatus;

/// How a class came out: how many were there, late, away, excused.
class RollCounts {
  final int present;
  final int late;
  final int absent;
  final int excused;
  final int total;

  const RollCounts({
    this.present = 0,
    this.late = 0,
    this.absent = 0,
    this.excused = 0,
    this.total = 0,
  });

  static const empty = RollCounts();

  /// Everyone who was in the room, however late.
  int get attended => present + late;

  /// Counted here rather than only server-side because the roll is live
  /// while the teacher is marking it, and a summary that only updated on
  /// Time Out would be wrong for the whole lesson.
  factory RollCounts.of(Iterable<SubjectAttendanceMark> marks) {
    var present = 0, late = 0, absent = 0, excused = 0, total = 0;
    for (final mark in marks) {
      total += 1;
      switch (mark.status) {
        case AttendanceStatus.present:
          present += 1;
        case AttendanceStatus.late:
          late += 1;
        case AttendanceStatus.absent:
          absent += 1;
        case AttendanceStatus.excused:
          excused += 1;
      }
    }
    return RollCounts(
      present: present,
      late: late,
      absent: absent,
      excused: excused,
      total: total,
    );
  }
}

/// One class, on one day, as it actually ran.
///
/// The timetable says Physics is 7:30 to 8:20 on Mondays. This says the
/// teacher started it at 7:34 and finished at 8:19, with thirty-eight of
/// forty in the room. The first is a plan and the second is a record,
/// and only the second can answer a parent asking whether their child
/// was in the lesson they failed.
class ClassSession {
  final String id;
  final String scheduleBlockId;
  final String subject;
  final String section;
  final String? room;
  final String date; // 'YYYY-MM-DD', in the school's timezone

  /// Who the timetable says teaches it.
  final String teacherName;

  /// Who actually took it. Usually the same person; when it is not, that
  /// difference is the reason a cover register is worth reading.
  final String takenByUid;
  final String takenByName;

  final DateTime openedAt;
  final DateTime? closedAt;

  /// How many were on the roll when it was built.
  final int studentCount;

  /// Written on Time Out. Null while the class is still running -- the
  /// live figures come from the marks themselves.
  final RollCounts? counts;

  const ClassSession({
    required this.id,
    required this.scheduleBlockId,
    required this.subject,
    required this.section,
    required this.date,
    required this.teacherName,
    required this.takenByUid,
    required this.takenByName,
    required this.openedAt,
    required this.studentCount,
    this.room,
    this.closedAt,
    this.counts,
  });

  bool get isOpen => closedAt == null;

  /// Whole minutes, or null while it is still running.
  ///
  /// Clamped at zero: a closedAt before the openedAt means two clocks
  /// disagreed, not that the class ran backwards, and a negative
  /// duration on an attendance record is worse than an absent one.
  int? get minutes =>
      closedAt?.difference(openedAt).inMinutes.clamp(0, 1 << 30);

  /// True when the timetabled teacher did not take this one.
  bool get wasCovered => takenByName.isNotEmpty && takenByName != teacherName;
}

/// One student's line in one class's register.
///
/// Carries the subject, section and date as well as the session id, so a
/// student's whole term in one subject is a single query on this
/// collection rather than a join back through every session they sat in.
class SubjectAttendanceMark {
  final String id;
  final String sessionId;
  final String studentId;
  final String studentName;
  final String subject;
  final String section;
  final String date;
  final AttendanceStatus status;

  /// When they arrived. The session's start time for everyone marked
  /// present at Time In; the moment they were marked for a latecomer.
  final DateTime? timeIn;

  /// Stamped at Time Out, and only for students who were in the room. An
  /// absent student has no time out because they had no time in.
  final DateTime? timeOut;

  const SubjectAttendanceMark({
    required this.id,
    required this.sessionId,
    required this.studentId,
    required this.studentName,
    required this.subject,
    required this.section,
    required this.date,
    required this.status,
    this.timeIn,
    this.timeOut,
  });

  bool get wasThere =>
      status == AttendanceStatus.present || status == AttendanceStatus.late;

  /// How long they were in the room, or null while the class runs.
  int? get minutes => (timeIn == null || timeOut == null)
      ? null
      : timeOut!.difference(timeIn!).inMinutes.clamp(0, 1 << 30);
}
