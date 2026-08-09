/// The correct answers for one piece of coursework.
///
/// **Stored apart from the coursework item, and that is the whole point.**
/// Students read courseworkItems -- they have to, it is how they see the
/// assignment -- so an answer key living on that document would be an
/// answer key published to the class. It lives in
/// `courseworkAnswerKeys/{courseworkId}` instead, which firestore.rules
/// makes readable by staff and by nobody else.
///
/// What the student's copy of the coursework item does carry is
/// [CourseworkItem.questionCount]: enough to render the right number of
/// answer boxes, and nothing about what belongs in them.
class AnswerKey {
  final String courseworkId;

  /// The correct answer to each question, in order. Position is the
  /// question number -- answers[0] is question 1.
  final List<String> answers;

  /// Marks per question. Every question is worth the same: partial
  /// weighting is a real thing teachers want, but guessing at it here
  /// would bake in a policy nobody asked for, and an even split is the
  /// one rule that needs no explaining to a student disputing a mark.
  final double pointsPerQuestion;

  final String updatedByName;
  final DateTime updatedAt;

  const AnswerKey({
    required this.courseworkId,
    required this.answers,
    required this.pointsPerQuestion,
    required this.updatedByName,
    required this.updatedAt,
  });

  int get questionCount => answers.length;
  double get totalPoints => answers.length * pointsPerQuestion;

  /// Whether a student's answer to question [index] is correct.
  ///
  /// Deliberately forgiving about the things that are not the point:
  /// surrounding space, and capitalisation. "Manila", "manila " and
  /// "MANILA" are the same answer, and marking a student wrong for the
  /// shift key would make the feature worse than no feature.
  ///
  /// Deliberately unforgiving about everything else. This can only ever
  /// mark exact-match work -- multiple choice, one-word answers, numbers.
  /// It cannot mark an essay, and pretending otherwise would hand back
  /// confident wrong scores.
  bool isCorrect(int index, String given) {
    if (index < 0 || index >= answers.length) return false;
    return _normalise(given) == _normalise(answers[index]);
  }

  /// Scores a whole set of answers. Missing answers count as wrong
  /// rather than skipped -- a blank is a question not answered.
  double scoreFor(List<String> given) {
    var correct = 0;
    for (var i = 0; i < answers.length; i++) {
      final answer = i < given.length ? given[i] : '';
      if (isCorrect(i, answer)) correct++;
    }
    return correct * pointsPerQuestion;
  }

  int correctCount(List<String> given) {
    var correct = 0;
    for (var i = 0; i < answers.length; i++) {
      final answer = i < given.length ? given[i] : '';
      if (isCorrect(i, answer)) correct++;
    }
    return correct;
  }

  static String _normalise(String value) => value.trim().toLowerCase();
}
