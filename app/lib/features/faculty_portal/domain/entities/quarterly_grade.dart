import 'grade.dart';
import 'grading_scheme.dart';

/// One component's arithmetic, kept so the report card can show its work.
///
/// A teacher asked why a child got 87 needs to be able to point at the
/// line: "written work, 142 out of 165, that is 86.06, weighted at 40 per
/// cent, so 34.42 of the grade". A single number cannot be argued with,
/// which is not the same as being right.
class ComponentScore {
  final GradingComponent component;

  /// What the student scored across every piece of work in this
  /// component, and what those pieces were worth.
  final double raw;
  final double possible;

  /// The weight applied, as a percentage.
  final double weight;

  const ComponentScore({
    required this.component,
    required this.raw,
    required this.possible,
    required this.weight,
  });

  bool get hasWork => possible > 0;

  /// Raw over possible, as a percentage. Zero when nothing has been
  /// given out yet -- not 100, which is what dividing by zero defensively
  /// tends to produce and would hand every child a perfect mark in a
  /// component the teacher has not started.
  double get percentageScore =>
      possible <= 0 ? 0 : _round2(raw / possible * 100);

  /// The share of the final grade this component contributes.
  double get weightedScore => _round2(percentageScore * weight / 100);
}

/// One subject, one quarter, computed.
class QuarterlyGrade {
  final String subject;
  final String term;
  final SubjectWeights weights;
  final List<ComponentScore> components;

  /// The sum of the weighted scores, before transmutation.
  final double initialGrade;

  /// After the school's transmutation table, or equal to the initial
  /// grade rounded when the school does not transmute.
  final int finalGrade;

  /// True when at least one component has work in it. A subject with
  /// nothing recorded has no grade -- and reporting 0 for it would mark a
  /// child down for a teacher not having entered anything yet.
  final bool hasWork;

  /// The weight actually available to be earned: the sum of the weights
  /// of the components that have work in them.
  ///
  /// A hundred once the quarter is complete, and less than that while it
  /// is running. Carried rather than recomputed because it is the number
  /// that explains why an initial grade of 88 is 88 in week two -- the
  /// grade is out of the 80 per cent that exists so far, not out of a
  /// hundred with the exam counted as zero.
  double get availableWeight => components
      .where((c) => c.hasWork)
      .fold<double>(0, (sum, c) => sum + c.weight);

  /// Every piece of the arithmetic, in the order it happens, for a
  /// screen or a report card that has to show its work.
  ///
  /// A teacher asked why a child got 87 needs to point at the line. A
  /// single number cannot be argued with, which is not the same as being
  /// right.
  List<String> get workingOut => [
        for (final c in components)
          if (c.hasWork)
            '${c.component.displayLabel}: ${_trimNumber(c.raw)} / '
                '${_trimNumber(c.possible)} = '
                '${c.percentageScore.toStringAsFixed(2)}% '
                'x ${_trimNumber(c.weight)}% = '
                '${c.weightedScore.toStringAsFixed(2)}',
        if (availableWeight > 0 && availableWeight < 100)
          'Only ${_trimNumber(availableWeight)}% of the grade has been given '
              'out so far, so the total is taken over that rather than '
              'counting the rest as zero.',
        'Initial grade: ${initialGrade.toStringAsFixed(2)}',
        'Final grade: $finalGrade',
      ];

  const QuarterlyGrade({
    required this.subject,
    required this.term,
    required this.weights,
    required this.components,
    required this.initialGrade,
    required this.finalGrade,
    required this.hasWork,
  });

  /// Which components carry weight but have nothing in them yet. Named
  /// on the report card, because a grade computed from two of three
  /// components is not the grade the child will end with.
  ///
  /// A component the school weights at nothing is not missing anything:
  /// it cannot move the grade, so a teacher has no work to do there and
  /// naming it would send them looking for one.
  List<GradingComponent> get missingComponents => components
      .where((c) => c.weight > 0 && !c.hasWork)
      .map((c) => c.component)
      .toList();

  /// DepEd's INC: work has been recorded, but a component that counts is
  /// still empty.
  ///
  /// Deliberately not the same thing as the grade being wrong.
  /// [initialGrade] and [finalGrade] stay computed and stay honest --
  /// rescaled to the weight that exists, which is what a teacher needs
  /// to see mid-quarter. This says the figure is not yet a *final*
  /// grade, which is what a report card needs to know before it prints
  /// one. The class record shows the number; the report card prints INC.
  ///
  /// A subject with nothing at all in it is not incomplete, it is
  /// ungraded -- [hasWork] is what says so, and it is left out of
  /// averages entirely rather than marked.
  bool get isIncomplete => hasWork && missingComponents.isNotEmpty;

  ComponentScore componentFor(GradingComponent component) =>
      components.firstWhere((c) => c.component == component);
}

/// What a grade means in words. DepEd's descriptors, and the reason the
/// number 75 matters so much: it is the line.
String gradeDescriptor(int grade) {
  if (grade >= 90) return 'Outstanding';
  if (grade >= 85) return 'Very Satisfactory';
  if (grade >= 80) return 'Satisfactory';
  if (grade >= 75) return 'Fairly Satisfactory';
  return 'Did Not Meet Expectations';
}

bool isPassing(int grade) => grade >= 75;

/// Computes one subject's quarterly grade from the raw scores.
///
/// The steps are DepEd Order 8, s. 2015 and are not in dispute: sum the
/// raw scores in each component, divide by what those pieces were worth
/// to get a percentage, multiply by the component's weight, add the
/// three, transmute. What *is* a matter of configuration -- the weights
/// and the transmutation table -- comes in through [scheme], for the
/// reasons written on [GradingScheme].
///
/// Pure, and takes a list, so every awkward case can be a test: a
/// component with nothing in it, a piece of work worth zero points, a
/// score above its maximum.
QuarterlyGrade computeQuarterlyGrade({
  required String subject,
  required String term,
  required Iterable<Grade> grades,
  required GradingScheme scheme,
  /// The weights this class is actually graded on, when the subject
  /// teacher has set a split of their own. Absent means the school's
  /// confirmed scheme decides, which is the ordinary case.
  SubjectWeights? weightsOverride,
}) {
  final weights = weightsOverride ?? scheme.weightsFor(subject);

  final components = <ComponentScore>[];
  var anyWork = false;

  for (final component in GradingComponent.values) {
    var raw = 0.0;
    var possible = 0.0;
    for (final grade in grades) {
      if (grade.component != component) continue;
      // A piece of work worth nothing cannot contribute to a percentage
      // and would make the denominator wrong if counted. It is a teacher
      // recording attendance at an activity, not an assessment.
      if (grade.maxScore <= 0) continue;
      // Added as recorded, and not clamped. Every path that writes a
      // mark refuses one above its own total -- it is overwhelmingly the
      // two columns filled in the wrong order, and a school that really
      // does give bonus marks raises the total the work is out of, which
      // is the same arithmetic said honestly. Anything above the maximum
      // here therefore predates that check, and silently capping it would
      // change a grade already issued without saying so.
      raw += grade.score;
      possible += grade.maxScore;
    }
    if (possible > 0) anyWork = true;
    components.add(ComponentScore(
      component: component,
      raw: _round2(raw),
      possible: _round2(possible),
      weight: weights.weightFor(component),
    ));
  }

  // Weighted only over components that have work in them, rescaled to
  // the weight actually available.
  //
  // The alternative -- treating an empty component as zero -- is the
  // failure that matters here. In the second week of a quarter no
  // quarterly assessment has been given, and counting it as zero at 20
  // per cent caps every child in the school at 80 until the exam. A
  // teacher looking at that concludes the system is broken, and they are
  // right.
  final availableWeight = components
      .where((c) => c.hasWork)
      .fold<double>(0, (sum, c) => sum + c.weight);

  final double initial;
  if (!anyWork || availableWeight <= 0) {
    initial = 0;
  } else {
    final earned = components
        .where((c) => c.hasWork)
        .fold<double>(0, (sum, c) => sum + c.percentageScore * c.weight);
    initial = _round2(earned / availableWeight);
  }

  return QuarterlyGrade(
    subject: subject,
    term: term,
    weights: weights,
    components: components,
    initialGrade: initial,
    finalGrade: transmute(initial, scheme.transmutation),
    hasWork: anyWork,
  );
}

/// Applies the school's transmutation table.
///
/// An empty table means the school does not transmute, and the initial
/// grade is reported rounded. That is a real configuration rather than a
/// missing one -- a private school on its own approved scheme may not
/// transmute at all -- and inventing a table for it would silently change
/// every grade it issues.
int transmute(double initialGrade, List<TransmutationBand> table) {
  if (table.isEmpty) return initialGrade.round();
  for (final band in table) {
    if (band.covers(initialGrade)) return band.transmuted;
  }
  // Outside every band. Clamped to the nearest end rather than falling
  // through to zero: a table that does not reach 100 is a
  // misconfiguration, and turning a perfect paper into a zero because of
  // it is the worst way to find out.
  final lowest = table.reduce((a, b) => a.from <= b.from ? a : b);
  final highest = table.reduce((a, b) => a.to >= b.to ? a : b);
  return initialGrade < lowest.from ? lowest.transmuted : highest.transmuted;
}

/// The average across subjects, as DepEd computes it: the mean of the
/// final grades, rounded.
///
/// Subjects with no work, and subjects still marked INC, are left out
/// entirely rather than counted as zero. A general average dragged down
/// by a subject nobody has finished grading is a number that will be
/// wrong until the day the quarter closes, and it is the number parents
/// look at first.
int? generalAverage(Iterable<QuarterlyGrade> grades) {
  // Incomplete subjects are left out for the same reason ungraded ones
  // are, and one more: the report card prints INC rather than a number
  // for them, and an average cannot include a figure the document beside
  // it does not show.
  final graded = grades.where((g) => g.hasWork && !g.isIncomplete).toList();
  if (graded.isEmpty) return null;
  final sum = graded.fold<int>(0, (running, g) => running + g.finalGrade);
  return (sum / graded.length).round();
}

double _round2(double value) => (value * 100).roundToDouble() / 100;

String _trimNumber(double value) => value == value.roundToDouble()
    ? value.toStringAsFixed(0)
    : value.toStringAsFixed(2);
