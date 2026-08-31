/// The three things a DepEd grade is made of.
///
/// Every gradable piece of work belongs to exactly one of these, and a
/// quarterly grade is these three weighted together. A raw score with no
/// component is a score nothing can be computed from -- which is where
/// this system was before: `Grade` held a score and a maximum and the
/// screen that shows it says so, "called a final grade: weighting by term
/// and by assessment type is" -- and then stops, because there was
/// nothing to weight by.
enum GradingComponent {
  writtenWork('written_work', 'Written Work', 'WW'),
  performanceTask('performance_task', 'Performance Tasks', 'PT'),
  quarterlyAssessment('quarterly_assessment', 'Quarterly Assessment', 'QA');

  final String value;
  final String displayLabel;
  final String shortLabel;
  const GradingComponent(this.value, this.displayLabel, this.shortLabel);

  static GradingComponent fromString(String value) =>
      GradingComponent.values.firstWhere(
        (c) => c.value == value,
        // A score filed under nothing is written work in practice -- it
        // is the component a quiz or a seatwork falls into, and it is
        // the least distorting default because it is the smallest weight
        // in only one of the three DepEd groupings.
        orElse: () => GradingComponent.writtenWork,
      );
}

/// How much each component counts, for one group of subjects.
///
/// ## Why this is data and not a constant
///
/// DepEd Order 8, s. 2015 sets different weights for different subject
/// groups, and different ones again for Senior High School tracks. Those
/// numbers are a matter of public record and they also change: an order
/// is superseded, a track is added, a school runs a curriculum with its
/// own approved scheme.
///
/// Hard-coding them would make this software assert a regulatory fact it
/// cannot keep current, and a school computing a wrong quarterly grade
/// because the app was written in 2026 is a school issuing wrong Form
/// 138s. So the weights are stored per school, seeded with the DepEd
/// groupings as a starting point, and **the school confirms them**. The
/// grading settings screen says so.
class SubjectWeights {
  /// What the school calls this grouping: "Science and Mathematics",
  /// "Core subjects", "TVL".
  final String label;

  /// The subjects it covers, matched case-insensitively. Empty means it
  /// is the fallback for anything not otherwise matched.
  final List<String> subjects;

  final double writtenWork;
  final double performanceTask;
  final double quarterlyAssessment;

  const SubjectWeights({
    required this.label,
    required this.writtenWork,
    required this.performanceTask,
    required this.quarterlyAssessment,
    this.subjects = const [],
  });

  bool get isFallback => subjects.isEmpty;

  double get total => writtenWork + performanceTask + quarterlyAssessment;

  /// Whether the three add up to a hundred. A scheme that does not is the
  /// one failure mode that produces plausible-looking wrong grades for a
  /// whole school year.
  bool get balances => (total - 100).abs() < 0.01;

  double weightFor(GradingComponent component) => switch (component) {
        GradingComponent.writtenWork => writtenWork,
        GradingComponent.performanceTask => performanceTask,
        GradingComponent.quarterlyAssessment => quarterlyAssessment,
      };

  bool covers(String subject) {
    final needle = subject.trim().toLowerCase();
    return subjects.any((s) => s.trim().toLowerCase() == needle);
  }

  Map<String, dynamic> toMap() => {
        'label': label,
        'subjects': subjects,
        'writtenWork': writtenWork,
        'performanceTask': performanceTask,
        'quarterlyAssessment': quarterlyAssessment,
      };

  factory SubjectWeights.fromMap(Map<String, dynamic> map) => SubjectWeights(
        label: map['label'] as String? ?? 'Subjects',
        subjects: [
          for (final s in (map['subjects'] as List<dynamic>? ?? []))
            if (s is String) s,
        ],
        writtenWork: (map['writtenWork'] as num?)?.toDouble() ?? 0,
        performanceTask: (map['performanceTask'] as num?)?.toDouble() ?? 0,
        quarterlyAssessment: (map['quarterlyAssessment'] as num?)?.toDouble() ?? 0,
      );
}

/// One band of the transmutation table.
///
/// An initial grade anywhere from [from] to [to] inclusive becomes
/// [transmuted].
class TransmutationBand {
  final double from;
  final double to;
  final int transmuted;

  const TransmutationBand({
    required this.from,
    required this.to,
    required this.transmuted,
  });

  bool covers(double initial) => initial >= from && initial <= to;

  Map<String, dynamic> toMap() =>
      {'from': from, 'to': to, 'transmuted': transmuted};

  factory TransmutationBand.fromMap(Map<String, dynamic> map) => TransmutationBand(
        from: (map['from'] as num?)?.toDouble() ?? 0,
        to: (map['to'] as num?)?.toDouble() ?? 0,
        transmuted: (map['transmuted'] as num?)?.toInt() ?? 0,
      );
}

/// A school's whole grading scheme: the weights and the transmutation.
class GradingScheme {
  final List<SubjectWeights> weights;

  /// The transmutation table, or empty for a school that reports the
  /// initial grade untransmuted.
  ///
  /// Empty is a real configuration, not a missing one: a private school
  /// running its own approved scheme may not transmute at all, and
  /// forcing a table on it would silently change every grade it issues.
  final List<TransmutationBand> transmutation;

  /// Whether the school has looked at these and said they are right.
  ///
  /// False until somebody confirms, and the report card refuses to print
  /// while it is. The defaults are a starting point transcribed from a
  /// public order; they are not this software's assertion about what a
  /// school's grades should be, and a report card issued off unconfirmed
  /// defaults would make them exactly that.
  final bool confirmedBySchool;

  final String? confirmedByName;
  final DateTime? confirmedAt;

  const GradingScheme({
    required this.weights,
    this.transmutation = const [],
    this.confirmedBySchool = false,
    this.confirmedByName,
    this.confirmedAt,
  });

  /// The weights that apply to a subject: the first group naming it, or
  /// the fallback group, or an even split if the school has configured
  /// nothing at all.
  SubjectWeights weightsFor(String subject) {
    for (final group in weights) {
      if (group.covers(subject)) return group;
    }
    for (final group in weights) {
      if (group.isFallback) return group;
    }
    // Never null, because a missing scheme must not crash a report card.
    // An even split is visibly not anybody's policy, which is the point:
    // a grade computed this way looks wrong and gets fixed.
    return const SubjectWeights(
      label: 'Unconfigured',
      writtenWork: 100 / 3,
      performanceTask: 100 / 3,
      quarterlyAssessment: 100 / 3,
    );
  }

  /// Every group whose weights do not add to a hundred. What the settings
  /// screen shows in red, and what blocks confirmation.
  List<SubjectWeights> get unbalanced =>
      weights.where((w) => !w.balances).toList();

  /// The DepEd Order 8, s. 2015 groupings for Grades 1-10, as a starting
  /// point for a school to confirm or replace.
  ///
  /// Transcribed from a public order rather than derived, and offered as
  /// a default precisely so a school does not have to type them -- but
  /// [confirmedBySchool] stays false until somebody at the school has
  /// checked them against the order that is current for them. Orders are
  /// superseded and tracks are added; this software cannot promise to be
  /// current, and a report card is not the place to find out that it was
  /// not.
  static const depEdBasicEducationDefaults = <SubjectWeights>[
    SubjectWeights(
      label: 'Languages, AP, EsP',
      subjects: [
        'English', 'Filipino', 'Mother Tongue', 'Araling Panlipunan',
        'Edukasyon sa Pagpapakatao', 'EsP',
      ],
      writtenWork: 30,
      performanceTask: 50,
      quarterlyAssessment: 20,
    ),
    SubjectWeights(
      label: 'Science and Mathematics',
      subjects: ['Science', 'Mathematics', 'Math'],
      writtenWork: 40,
      performanceTask: 40,
      quarterlyAssessment: 20,
    ),
    SubjectWeights(
      label: 'MAPEH, EPP/TLE',
      subjects: [
        'MAPEH', 'Music', 'Arts', 'Physical Education', 'Health', 'EPP', 'TLE',
      ],
      writtenWork: 20,
      performanceTask: 60,
      quarterlyAssessment: 20,
    ),
    // The catch-all. A subject nobody grouped still gets a grade rather
    // than an error, and the label says which rule produced it.
    SubjectWeights(
      label: 'Other subjects',
      writtenWork: 30,
      performanceTask: 50,
      quarterlyAssessment: 20,
    ),
  ];
}
