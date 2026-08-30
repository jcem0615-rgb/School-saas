import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/result.dart';
import '../../../auth/presentation/controllers/auth_controller.dart'
    show authStateProvider, firestoreProvider, firebaseFunctionsProvider;
import '../../../qr_attendance/domain/entities/attendance_record.dart'
    show AttendanceStatus;
import '../../../schedules/domain/entities/schedule_block.dart';
import '../../../schedules/presentation/controllers/schedule_controller.dart'
    show teacherScheduleProvider;
import '../../data/datasources/class_session_remote_datasource.dart';
import '../../data/repositories_impl/class_session_repository_impl.dart';
import '../../domain/entities/class_session.dart';
import '../../domain/repositories/class_session_repository.dart';

final classSessionRepositoryProvider = Provider<ClassSessionRepository>((ref) {
  final user = ref.watch(authStateProvider).valueOrNull;
  if (user == null || user.schoolId == null) {
    throw StateError('Class attendance requires a signed-in, school-scoped user.');
  }
  return ClassSessionRepositoryImpl(
    ClassSessionRemoteDataSource(
      firestore: ref.watch(firestoreProvider),
      functions: ref.watch(firebaseFunctionsProvider),
      schoolId: user.schoolId!,
    ),
  );
});

/// Every session opened in the school today.
///
/// One subscription rather than one per class row: a school runs a few
/// dozen classes a day, and the teacher's list needs to know which of
/// their own are already started, which is a lookup into this.
final todaysSessionsProvider =
    StreamProvider.autoDispose<List<ClassSession>>((ref) {
  return ref.watch(classSessionRepositoryProvider).watchTodaysSessions();
});

/// The classes on the signed-in teacher's timetable for today, in the
/// order the day runs.
final myClassesTodayProvider = Provider.autoDispose<List<ScheduleBlock>>((ref) {
  final user = ref.watch(authStateProvider).valueOrNull;
  if (user == null) return const [];
  final mine = ref.watch(teacherScheduleProvider(user.uid));
  final today = DateTime.now().weekday;
  final blocks = mine.where((b) => b.dayOfWeek == today).toList()
    ..sort((a, b) => a.startMinute.compareTo(b.startMinute));
  return blocks;
});

/// Today's session for one timetabled class, if it has been started.
///
/// Null means Time In has not been pressed. Matched on the block id
/// rather than by rebuilding the session id here, so the one place that
/// decides how a session is identified stays the server.
final sessionForBlockProvider =
    Provider.autoDispose.family<ClassSession?, String>((ref, blockId) {
  final sessions = ref.watch(todaysSessionsProvider).valueOrNull ?? const [];
  for (final session in sessions) {
    if (session.scheduleBlockId == blockId) return session;
  }
  return null;
});

final classSessionProvider =
    StreamProvider.autoDispose.family<ClassSession?, String>((ref, sessionId) {
  return ref.watch(classSessionRepositoryProvider).watchSession(sessionId);
});

final classRollProvider = StreamProvider.autoDispose
    .family<List<SubjectAttendanceMark>, String>((ref, sessionId) {
  return ref.watch(classSessionRepositoryProvider).watchRoll(sessionId);
});

/// One student's marks across every subject, newest first.
final studentSubjectMarksProvider = StreamProvider.autoDispose
    .family<List<SubjectAttendanceMark>, String>((ref, studentId) {
  return ref.watch(classSessionRepositoryProvider).watchStudentMarks(studentId);
});

/// One subject's worth of a student's marks, and how it stands.
class SubjectAttendanceSummary {
  final String subject;
  final RollCounts counts;
  final List<SubjectAttendanceMark> marks;

  const SubjectAttendanceSummary({
    required this.subject,
    required this.counts,
    required this.marks,
  });

  /// Present or late over lessons held, as a fraction.
  ///
  /// Excused lessons stay in the denominator. A school that quietly
  /// dropped them would report a child who missed half a term with a
  /// note as having a perfect record, which is not what either the
  /// teacher or the parent is asking.
  double? get attendanceRate =>
      counts.total == 0 ? null : counts.attended / counts.total;
}

/// A student's marks, grouped by subject and ordered worst first.
///
/// Worst first because the reason anybody opens this screen is to find
/// the subject that is going wrong. Alphabetical order makes somebody
/// read all eight to find it.
final studentSubjectSummaryProvider = Provider.autoDispose
    .family<List<SubjectAttendanceSummary>, String>((ref, studentId) {
  final marks =
      ref.watch(studentSubjectMarksProvider(studentId)).valueOrNull ?? const [];

  final bySubject = <String, List<SubjectAttendanceMark>>{};
  for (final mark in marks) {
    bySubject.putIfAbsent(mark.subject, () => []).add(mark);
  }

  final summaries = bySubject.entries
      .map((entry) => SubjectAttendanceSummary(
            subject: entry.key,
            counts: RollCounts.of(entry.value),
            marks: entry.value,
          ))
      .toList();

  summaries.sort((a, b) {
    final rateA = a.attendanceRate ?? 1;
    final rateB = b.attendanceRate ?? 1;
    final byRate = rateA.compareTo(rateB);
    return byRate != 0 ? byRate : a.subject.compareTo(b.subject);
  });
  return summaries;
});

/// Time In, Time Out, and one tap on a name.
///
/// Failures carry the server's own message rather than a generic one,
/// because these are the messages worth reading: "that class is not
/// timetabled today", "this register is from an earlier day, ask the
/// registrar". A teacher told only "something went wrong" tries again.
class ClassSessionActionController extends StateNotifier<AsyncValue<void>> {
  /// Resolved per call rather than captured once.
  ///
  /// The repository providers rebuild whenever `authStateProvider`
  /// emits, and a controller holding an instance would be torn down with
  /// it -- mid-write, if the emission lands during a Time Out. Holding a
  /// getter instead means this notifier outlives those rebuilds and each
  /// call uses whatever repository is current, which is also the right
  /// answer after a role switch.
  final ClassSessionRepository Function() _repository;

  ClassSessionActionController(this._repository)
      : super(const AsyncValue.data(null));

  /// Returns the session id, or null when it could not be started.
  Future<String?> openSession(String scheduleBlockId) async {
    _set(const AsyncValue.loading());
    final result = await _repository().openSession(scheduleBlockId);
    switch (result) {
      case Success(:final value):
        _set(const AsyncValue.data(null));
        return value;
      case Error(:final failure):
        _set(AsyncValue.error(failure.message, StackTrace.current));
        return null;
    }
  }

  Future<bool> closeSession(String sessionId) =>
      _run(() => _repository().closeSession(sessionId));

  Future<bool> mark({
    required String sessionId,
    required String studentId,
    required AttendanceStatus status,
  }) =>
      _run(() => _repository().mark(
            sessionId: sessionId,
            studentId: studentId,
            status: status,
          ));

  Future<bool> _run(Future<Result<void>> Function() action) async {
    _set(const AsyncValue.loading());
    final result = await action();
    switch (result) {
      case Success():
        _set(const AsyncValue.data(null));
        return true;
      case Error(:final failure):
        _set(AsyncValue.error(failure.message, StackTrace.current));
        return false;
    }
  }

  /// Every state write goes through here. Assigning to a disposed
  /// notifier throws, and the symptom is a button that appears to do
  /// nothing even though the write landed.
  void _set(AsyncValue<void> next) {
    if (mounted) state = next;
  }

  /// What went wrong last, for a snackbar. Null when nothing did.
  String? get errorMessage => state.hasError ? state.error.toString() : null;
}

final classSessionActionControllerProvider =
    StateNotifierProvider<ClassSessionActionController, AsyncValue<void>>((ref) {
  // `ref.read`, deliberately: watching would rebuild this controller
  // every time the repository does, which is every time the signed-in
  // user's stream emits.
  return ClassSessionActionController(() => ref.read(classSessionRepositoryProvider));
});
