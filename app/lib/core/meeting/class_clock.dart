/// How much of the lesson is left.
///
/// A class has a bell. A video call does not, and a lesson held in one
/// runs over because nobody in it can see the clock the timetable is
/// keeping -- so the classroom shows it: elapsed against the timetabled
/// length, and the minutes remaining said in words rather than left to
/// arithmetic.
class ClassClock {
  /// When the teacher pressed Time In.
  final DateTime openedAt;

  /// What the timetable says this class is, in minutes. Null when the
  /// block could not be read -- an unknown length is shown as elapsed
  /// time alone rather than as a guess.
  final int? scheduledMinutes;

  /// Now, passed in rather than read, so this is testable without
  /// waiting for a real minute to pass.
  final DateTime now;

  const ClassClock({
    required this.openedAt,
    required this.now,
    this.scheduledMinutes,
  });

  /// Never negative: a device whose clock runs behind the server's would
  /// otherwise show a class that has not started yet.
  Duration get elapsed {
    final raw = now.difference(openedAt);
    return raw.isNegative ? Duration.zero : raw;
  }

  Duration? get scheduled =>
      scheduledMinutes == null ? null : Duration(minutes: scheduledMinutes!);

  /// What is left, floored at zero. A class that has run past its slot
  /// shows none left rather than counting backwards.
  Duration? get remaining {
    final total = scheduled;
    if (total == null) return null;
    final left = total - elapsed;
    return left.isNegative ? Duration.zero : left;
  }

  /// True once the timetabled length is used up. The class does not stop
  /// -- ending it is the teacher's decision, not a timer's -- but the
  /// clock says so.
  bool get overrunning {
    final total = scheduled;
    return total != null && elapsed >= total;
  }

  /// 0 to 1, for the bar. Clamped, so an overrun fills it rather than
  /// painting past the end.
  double? get progress {
    final total = scheduled;
    if (total == null || total.inSeconds == 0) return null;
    return (elapsed.inSeconds / total.inSeconds).clamp(0.0, 1.0);
  }

  /// `07:12` under an hour, `1:07:12` over it.
  ///
  /// Minutes stay two digits either way so the number does not jump
  /// width as it counts, which on a clock somebody glances at is the
  /// difference between reading it and re-reading it.
  static String clock(Duration d) {
    final hours = d.inHours;
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
  }

  String get elapsedLabel => clock(elapsed);

  String? get scheduledLabel {
    final total = scheduled;
    return total == null ? null : clock(total);
  }

  /// "43:18 left of 60 minutes", or null when there is no length to
  /// count against.
  ///
  /// Null rather than a sentence saying so: a student's classroom knows
  /// when the lesson started but not how long the timetable gives it,
  /// and "this class has no set length" would be a claim about the
  /// timetable rather than about what this screen can see.
  String? get remainingLabel {
    final total = scheduledMinutes;
    if (total == null) return null;
    if (overrunning) {
      final over = elapsed - scheduled!;
      return over.inMinutes < 1
          ? 'The $total minutes are up.'
          : '${clock(over)} past the $total minutes.';
    }
    return '${clock(remaining!)} left of $total minutes.';
  }
}
