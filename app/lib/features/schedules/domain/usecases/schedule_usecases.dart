import '../../../../core/errors/failures.dart';
import '../../../../core/errors/result.dart';
import '../entities/schedule_block.dart';
import '../repositories/schedule_repository.dart';

class WatchScheduleUseCase {
  final ScheduleRepository _repository;
  const WatchScheduleUseCase(this._repository);

  Stream<List<ScheduleBlock>> call(String schoolYear) => _repository.watchSchedule(schoolYear);
}

/// Adds or moves a class.
///
/// The conflict check runs here as well as on the server. The server has
/// to do it -- a callable is reachable without going through this screen
/// -- but an admin laying out a week wants to be told about the clash
/// before the round trip, with the colliding class named, while the
/// dialog is still open.
class SaveScheduleBlockUseCase {
  final ScheduleRepository _repository;
  const SaveScheduleBlockUseCase(this._repository);

  /// A class shorter than this is a typo, not a lesson. Five minutes is
  /// low enough to allow a genuinely short homeroom slot and high enough
  /// to catch 7:30-7:30, which is what an unfinished end-time field
  /// produces.
  static const int minimumMinutes = 5;

  /// Nothing in a school day runs longer than this in one block. Twelve
  /// hours catches a PM/AM slip, which otherwise books a room from
  /// half past seven in the morning until half past seven at night and
  /// clashes with everything.
  static const int maximumMinutes = 12 * 60;

  Future<Result<String>> call({
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

    /// The timetable as it stands, for the local conflict check. Pass
    /// none and the check is left to the server.
    Iterable<ScheduleBlock> existing = const [],
  }) {
    Result<String> reject(String message) => Error(ValidationFailure(message));

    if (subject.trim().isEmpty) {
      return Future.value(reject('Name the subject.'));
    }
    if (section.trim().isEmpty) {
      return Future.value(reject('Name the section.'));
    }
    if (teacherId.trim().isEmpty) {
      return Future.value(reject('Choose a teacher.'));
    }
    if (schoolYear.trim().isEmpty) {
      return Future.value(reject('A timetable belongs to a school year.'));
    }
    if (dayOfWeek < 1 || dayOfWeek > 7) {
      return Future.value(reject('Choose a day of the week.'));
    }
    if (startMinute < 0 || startMinute > 24 * 60 || endMinute < 0 || endMinute > 24 * 60) {
      return Future.value(reject('Those times are not on the clock.'));
    }
    if (endMinute <= startMinute) {
      return Future.value(
        reject('The class has to end after it starts. '
            'A class running past midnight needs to be two blocks.'),
      );
    }
    final duration = endMinute - startMinute;
    if (duration < minimumMinutes) {
      return Future.value(reject('That class is $duration minutes long. Check the times.'));
    }
    if (duration > maximumMinutes) {
      return Future.value(
        reject('That class runs for ${(duration / 60).toStringAsFixed(1)} hours. '
            'Check whether one of the times should be AM or PM.'),
      );
    }

    final candidate = ScheduleBlock(
      id: blockId ?? '',
      subject: subject.trim(),
      section: section.trim(),
      teacherId: teacherId.trim(),
      teacherName: teacherName.trim(),
      room: room?.trim().isEmpty ?? true ? null : room!.trim(),
      dayOfWeek: dayOfWeek,
      startMinute: startMinute,
      endMinute: endMinute,
      schoolYear: schoolYear.trim(),
      term: term?.trim().isEmpty ?? true ? null : term!.trim(),
    );

    // Editing a block must not clash with the version of itself already
    // on file, which is what the id comparison in clashesInTimeWith is
    // for -- but a new block has no id yet, so it is excluded by hand.
    final others = blockId == null
        ? existing
        : existing.where((b) => b.id != blockId);
    final conflicts = findConflicts(candidate, others);
    if (conflicts.isNotEmpty) {
      return Future.value(reject(conflicts.map((c) => c.message).join('\n')));
    }

    return _repository.saveScheduleBlock(
      blockId: blockId,
      subject: candidate.subject,
      section: candidate.section,
      teacherId: candidate.teacherId,
      teacherName: candidate.teacherName,
      room: candidate.room,
      dayOfWeek: dayOfWeek,
      startMinute: startMinute,
      endMinute: endMinute,
      schoolYear: candidate.schoolYear,
      term: candidate.term,
    );
  }
}

class DeleteScheduleBlockUseCase {
  final ScheduleRepository _repository;
  const DeleteScheduleBlockUseCase(this._repository);

  Future<Result<void>> call(String blockId) {
    if (blockId.trim().isEmpty) {
      return Future.value(const Error(ValidationFailure('Missing class.')));
    }
    return _repository.deleteScheduleBlock(blockId.trim());
  }
}
