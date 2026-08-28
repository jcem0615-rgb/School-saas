/// One thing that has to be true before a school can be let in.
///
/// Every check names a remedy, because a red light with no next step is
/// a red light somebody clicks past. "Indexes missing" is not actionable;
/// "run firebase deploy --only firestore:indexes" is.
class SystemCheck {
  final String id;
  final String title;

  /// What was actually observed, in the words of what happened -- not
  /// "failed" but "the write succeeded, which means the rules are not
  /// deployed".
  final String detail;

  final CheckStatus status;

  /// What to do about it. Null when there is nothing to do.
  final String? remedy;

  const SystemCheck({
    required this.id,
    required this.title,
    required this.status,
    required this.detail,
    this.remedy,
  });

  SystemCheck.pass({required this.id, required this.title, required this.detail})
      : status = CheckStatus.pass,
        remedy = null;

  const SystemCheck.fail({
    required this.id,
    required this.title,
    required this.detail,
    required String this.remedy,
  }) : status = CheckStatus.fail;

  const SystemCheck.warn({
    required this.id,
    required this.title,
    required this.detail,
    this.remedy,
  }) : status = CheckStatus.warn;
}

enum CheckStatus {
  pass('Ready'),
  /// Works, but somebody should look at it before the school is let in --
  /// a school with no Data Protection Officer named, for instance. Not a
  /// deployment fault, so not red.
  warn('Check this'),
  fail('Not ready');

  final String label;
  const CheckStatus(this.label);
}

/// Everything the preflight found, and whether the deployment is usable.
class SystemCheckReport {
  final List<SystemCheck> checks;
  final DateTime ranAt;

  /// True when this ran against the in-memory demo store rather than a
  /// real deployment.
  ///
  /// Reported loudly rather than quietly passing. A preflight that goes
  /// green in demo mode is worse than no preflight: it is a green light
  /// that means nothing, shown to the one person who most needs it to
  /// mean something.
  final bool demoMode;

  const SystemCheckReport({
    required this.checks,
    required this.ranAt,
    this.demoMode = false,
  });

  int get failures => checks.where((c) => c.status == CheckStatus.fail).length;
  int get warnings => checks.where((c) => c.status == CheckStatus.warn).length;

  bool get isReady => !demoMode && failures == 0;

  String get headline {
    if (demoMode) return 'Nothing was checked';
    if (failures > 0) {
      return '$failures ${failures == 1 ? 'check' : 'checks'} failed';
    }
    if (warnings > 0) {
      return 'Ready, with $warnings to look at';
    }
    return 'Ready';
  }
}
