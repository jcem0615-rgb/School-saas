import 'grading_scheme.dart';

/// Where the weights that produced a grade came from.
enum WeightsSource {
  /// The school's confirmed scheme, matched by subject group.
  schoolScheme,

  /// A set the subject teacher entered for this class.
  classOverride,
}

/// What each component counts for one class, and who decided.
///
/// The school's confirmed scheme is the default and is what a class with
/// no override is graded on. This is for the case that scheme cannot
/// express -- a subject marked on a split the department agreed -- which
/// before this had to be done in a spreadsheet beside the app.
///
/// The source travels with the weights on purpose. A grade computed on a
/// split nobody can see is the thing this module exists to replace, so
/// every screen that shows the number can say which weights produced it
/// and whose they were.
class ClassWeights {
  final SubjectWeights weights;
  final WeightsSource source;

  /// Who set the override, when there is one.
  final String? setByName;

  const ClassWeights({
    required this.weights,
    required this.source,
    this.setByName,
  });

  bool get isOverride => source == WeightsSource.classOverride;

  /// One line saying where the number came from.
  String get provenance => switch (source) {
        WeightsSource.schoolScheme =>
          'School scheme · ${weights.label}',
        WeightsSource.classOverride =>
          'Set for this class${setByName == null ? '' : ' by $setByName'}',
      };
}

/// The weights to grade one class on: the teacher's, or the school's.
ClassWeights weightsForClass({
  required String subject,
  required GradingScheme scheme,
  SubjectWeights? override,
  String? overrideSetByName,
}) {
  // An override that does not add up to a hundred is not honoured. It
  // should be impossible -- `setClassWeights` refuses to write one -- and
  // grading a class on a scheme known to be broken would be worse than
  // ignoring it, because the grades would look ordinary.
  if (override != null && override.balances) {
    return ClassWeights(
      weights: override,
      source: WeightsSource.classOverride,
      setByName: overrideSetByName,
    );
  }
  return ClassWeights(
    weights: scheme.weightsFor(subject),
    source: WeightsSource.schoolScheme,
  );
}
