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

  const QuarterlyGrade({
    required this.subject,
    required this.term,
    required this.weights,
    required this.components,
    required this.initialGrade,
    required this.finalGrade,
    required this.hasWork,
  });

  /// Which components the teacher has not put anything in yet. Named on
  /// the report card, because a grade computed from two of three
  /// components is not the grade the child will end with.
  List<GradingComponent> get missingComponents =>
      components.where((c) => !c.hasWork).map((c) => c.component).toList();

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
}) {
  final weights = scheme.weightsFor(subject);

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
      // A score above the maximum is bonus marks, which schools really do
      // give. Kept rather than clamped: capping it silently would erase a
      // teacher's decision, and the percentage going over 100 in one
      // component is visible and explicable.
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
/// Subjects with no work are left out entirely rather than counted as
/// zero. A general average dragged down by a subject nobody has graded
/// yet is a number that will be wrong until the day the quarter closes,
/// and it is the number parents look at first.
int? generalAverage(Iterable<QuarterlyGrade> grades) {
  final graded = grades.where((g) => g.hasWork).toList();
  if (graded.isEmpty) return null;
  final sum = graded.fold<int>(0, (running, g) => running + g.finalGrade);
  return (sum / graded.length).round();
}

double _round2(double value) => (value * 100).roundToDouble() / 100;
