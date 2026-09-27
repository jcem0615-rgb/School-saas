/// How long the lesson has been running.
///
/// Elapsed only. It used to count down against the timetabled length and
/// show "59:47 left of 60 minutes", which was wrong in the way that
/// matters: a lesson is not over because an hour passed. A teacher
/// finishing a topic, a class that started late, a review session that
/// runs long -- none of those are a fault, and a screen telling a
/// teacher in front of thirty children that their time is up is a screen
/// making a decision that is not its to make.
///
/// So there is no limit and nothing to run out. The clock says how long
/// they have been going, which is the thing a teacher actually glances
/// down for, and the lesson ends when the teacher ends it.
class ClassClock {
  /// When the register was opened.
  final DateTime openedAt;

  /// Taken as an argument rather than read, so the awkward cases are
  /// testable: a device whose clock is behind the server's used to make
  /// this run backwards.
  final DateTime now;

  const ClassClock({required this.openedAt, required this.now});

  /// Never negative. A phone a few seconds behind the server would
  /// otherwise show a lesson that has not started yet.
  Duration get elapsed {
    final run = now.difference(openedAt);
    return run.isNegative ? Duration.zero : run;
  }

  /// `H:MM:SS` past an hour, `MM:SS` before it.
  ///
  /// A lesson that has been going eight minutes should not be padded out
  /// to `0:08:12`; one that has been going ninety should not read
  /// `90:00` and leave somebody working out the hours.
  String get elapsedLabel {
    final run = elapsed;
    final hours = run.inHours;
    final minutes = run.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = run.inSeconds.remainder(60).toString().padLeft(2, '0');
    return hours == 0 ? '$minutes:$seconds' : '$hours:$minutes:$seconds';
  }
}
