/// One recurring class: a subject, a section, a teacher, a room, on one
/// day at one time.
///
/// A block per weekday rather than one record carrying a set of days.
/// Real timetables are not that tidy -- Math is 7:30 on Monday and 9:15
/// on Thursday far more often than it is the same slot all week -- and a
/// multi-day record would have to grow per-day times anyway, which is
/// this, with an extra layer.
///
/// Time is minutes from midnight, as two ints. TimeOfDay does not
/// serialise, a string needs parsing before it can be compared, and a
/// Timestamp would imply a date this record does not have. Minutes sort,
/// subtract and overlap-test directly, which is the entire arithmetic
/// this feature does.
class ScheduleBlock {
  final String id;
  final String subject;
  final String section;
  final String teacherId;
  final String teacherName;

  /// Where the class meets. Optional: plenty of schools timetable
  /// without assigning rooms, and requiring one would mean inventing a
  /// room name to save a block.
  final String? room;

  /// 1 = Monday through 7 = Sunday, matching `DateTime.weekday` so that
  /// "what is on today" is a comparison and not a mapping table.
  final int dayOfWeek;

  final int startMinute;
  final int endMinute;
  final String schoolYear;

  /// Semester or quarter, for schools whose timetable changes partway
  /// through the year. Null means it runs all year.
  final String? term;

  const ScheduleBlock({
    required this.id,
    required this.subject,
    required this.section,
    required this.teacherId,
    required this.teacherName,
    required this.dayOfWeek,
    required this.startMinute,
    required this.endMinute,
    required this.schoolYear,
    this.room,
    this.term,
  });

  int get durationMinutes => endMinute - startMinute;

  String get dayLabel => weekdayLabel(dayOfWeek);
  String get shortDayLabel => weekdayShortLabel(dayOfWeek);

  String get startLabel => formatMinuteOfDay(startMinute);
  String get endLabel => formatMinuteOfDay(endMinute);
  String get timeLabel => '$startLabel - $endLabel';

  /// Whether two blocks are in the room, in front of the teacher, or in
  /// the section's slot at the same moment.
  ///
  /// Touching ends do not overlap: a class ending at 9:00 and the next
  /// starting at 9:00 is how every timetable in the country is written,
  /// and treating that as a clash would make the feature unusable on the
  /// first day.
  bool overlaps(ScheduleBlock other) =>
      dayOfWeek == other.dayOfWeek &&
      startMinute < other.endMinute &&
      other.startMinute < endMinute;

  /// Same slot on the same day of the same year -- the precondition for
  /// any of the three clashes being worth checking.
  bool clashesInTimeWith(ScheduleBlock other) =>
      id != other.id && schoolYear == other.schoolYear && overlaps(other);
}

/// What kind of double-booking was found.
///
/// Named rather than a boolean, because the three cannot be fixed the
/// same way: a teacher clash needs a different teacher or a different
/// time, a section clash means the class is in two places at once, and a
/// room clash is usually fixed by moving one of them down the corridor.
enum ScheduleClash {
  teacher('This teacher is already teaching then.'),
  section('This section already has a class then.'),
  room('That room is already taken then.');

  final String message;
  const ScheduleClash(this.message);
}

/// A clash, and the block it is with, so the message can name it.
class ScheduleConflict {
  final ScheduleClash kind;
  final ScheduleBlock against;

  const ScheduleConflict({required this.kind, required this.against});

  String get message => '${kind.message} '
      '${against.subject} with ${against.teacherName} in ${against.section}, '
      '${against.dayLabel} ${against.timeLabel}.';
}

/// Every way [candidate] collides with what is already timetabled.
///
/// All three are returned rather than the first, because an admin who
/// fixes the room clash only to be told about the teacher clash has been
/// made to do the work twice for no reason.
List<ScheduleConflict> findConflicts(
  ScheduleBlock candidate,
  Iterable<ScheduleBlock> existing,
) {
  final conflicts = <ScheduleConflict>[];
  final room = candidate.room?.trim().toLowerCase();

  for (final other in existing) {
    if (!candidate.clashesInTimeWith(other)) continue;

    if (other.teacherId == candidate.teacherId) {
      conflicts.add(ScheduleConflict(kind: ScheduleClash.teacher, against: other));
    }
    if (other.section.trim().toLowerCase() == candidate.section.trim().toLowerCase()) {
      conflicts.add(ScheduleConflict(kind: ScheduleClash.section, against: other));
    }
    // A blank room is not a room. Two blocks with no room recorded are
    // not in the same place -- they are in no recorded place, and
    // reporting that as a clash would punish schools that do not
    // timetable rooms at all.
    final otherRoom = other.room?.trim().toLowerCase();
    if (room != null && room.isNotEmpty && room == otherRoom) {
      conflicts.add(ScheduleConflict(kind: ScheduleClash.room, against: other));
    }
  }
  return conflicts;
}

const _weekdayNames = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

String weekdayLabel(int dayOfWeek) =>
    dayOfWeek >= 1 && dayOfWeek <= 7 ? _weekdayNames[dayOfWeek - 1] : 'Day $dayOfWeek';

String weekdayShortLabel(int dayOfWeek) {
  final full = weekdayLabel(dayOfWeek);
  return full.length >= 3 ? full.substring(0, 3) : full;
}

/// "7:30 AM". Written by hand rather than through DateFormat because
/// there is no date here -- only a count of minutes -- and inventing one
/// to format it is how a timetable ends up an hour out on the day the
/// clocks would have changed somewhere else.
String formatMinuteOfDay(int minuteOfDay) {
  final minutes = minuteOfDay % 60;
  final hours24 = (minuteOfDay ~/ 60) % 24;
  final period = hours24 < 12 ? 'AM' : 'PM';
  final hours12 = hours24 % 12 == 0 ? 12 : hours24 % 12;
  return '$hours12:${minutes.toString().padLeft(2, '0')} $period';
}

/// Parses "7:30 AM", "7:30am", "07:30" and "1330" into minutes.
///
/// Lenient on purpose: this reads what somebody typed into a time field
/// on a phone, and refusing "730" when the intent is unmistakable is the
/// kind of strictness that gets a product abandoned.
int? parseMinuteOfDay(String text) {
  var value = text.trim().toUpperCase().replaceAll('.', '');
  if (value.isEmpty) return null;

  var isPm = false;
  var isAm = false;
  if (value.endsWith('AM')) {
    isAm = true;
    value = value.substring(0, value.length - 2).trim();
  } else if (value.endsWith('PM')) {
    isPm = true;
    value = value.substring(0, value.length - 2).trim();
  }

  int hours;
  int minutes;
  if (value.contains(':')) {
    final parts = value.split(':');
    if (parts.length != 2) return null;
    final h = int.tryParse(parts[0].trim());
    final m = int.tryParse(parts[1].trim());
    if (h == null || m == null) return null;
    hours = h;
    minutes = m;
  } else {
    final digits = int.tryParse(value);
    if (digits == null) return null;
    if (value.length <= 2) {
      hours = digits;
      minutes = 0;
    } else {
      hours = digits ~/ 100;
      minutes = digits % 100;
    }
  }

  if (minutes < 0 || minutes > 59) return null;
  if (isPm && hours < 12) hours += 12;
  if (isAm && hours == 12) hours = 0;
  if (hours < 0 || hours > 23) return null;
  return hours * 60 + minutes;
}
