import '../../../../core/errors/result.dart';
import '../../../qr_attendance/domain/entities/attendance_record.dart'
    show AttendanceStatus;
import '../entities/class_session.dart';

abstract class ClassSessionRepository {
  /// Today's sessions, so a teacher's list of classes can say which have
  /// been started and which have not.
  Stream<List<ClassSession>> watchTodaysSessions();

  Stream<ClassSession?> watchSession(String sessionId);

  /// The register for one class, as it is being marked.
  Stream<List<SubjectAttendanceMark>> watchRoll(String sessionId);

  /// Every mark for one student, newest first -- their term in every
  /// subject. Bounded, because a year of eight lessons a day is a
  /// thousand rows and no screen shows a thousand rows.
  Stream<List<SubjectAttendanceMark>> watchStudentMarks(String studentId);

  /// Time In. Returns the session id, whether it was opened now or was
  /// already running -- pressing twice is what happens when the first
  /// press is slow, and it must not produce two registers.
  Future<Result<String>> openSession(String scheduleBlockId);

  /// Time Out.
  Future<Result<void>> closeSession(String sessionId);

  Future<Result<void>> mark({
    required String sessionId,
    required String studentId,
    required AttendanceStatus status,
  });
}
