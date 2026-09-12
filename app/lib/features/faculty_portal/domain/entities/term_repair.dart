/// One group of marks that would move, or would not.
class TermRepairMove {
  final String from;
  final String to;
  final int count;

  /// Why it was left alone. Null on a move that will happen.
  final String? reason;

  const TermRepairMove({
    required this.from,
    required this.to,
    required this.count,
    this.reason,
  });

  bool get isSkipped => reason != null;
}

/// What repairing the terms would do, or did.
///
/// The same shape whether it was a dry run or not, so the screen that
/// shows the preview and the screen that shows the result are one screen.
class TermRepairReport {
  final int scanned;
  final int moved;
  final bool applied;
  final List<TermRepairMove> moves;
  final List<TermRepairMove> skipped;

  const TermRepairReport({
    required this.scanned,
    required this.moved,
    required this.applied,
    required this.moves,
    required this.skipped,
  });

  bool get hasWork => moves.isNotEmpty || skipped.isNotEmpty;
}
