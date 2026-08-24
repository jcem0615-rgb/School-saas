/**
 * Marking a set of answers against a key.
 *
 * The same rule as AnswerKey in
 * app/lib/features/faculty_portal/domain/entities/answer_key.dart, and
 * the two have to agree: the Dart copy is what demo mode marks with and
 * what a teacher sees previewed, this is what actually decides a
 * student's score. Both are covered by tests asserting the same cases.
 *
 * What this can mark: multiple choice, one-word answers, numbers --
 * anything where "correct" means "matches". What it cannot mark is an
 * essay, and no amount of fuzzy matching would change that. Coursework
 * without a key is marked by a person reading it, which is why the key
 * is optional rather than required.
 */
export interface AnswerKeyData {
  answers: string[];
  pointsPerQuestion: number;
}

export interface AutoScoreResult {
  score: number;
  correctCount: number;
  questionCount: number;
}

/**
 * Forgiving about surrounding space and capitalisation, unforgiving
 * about everything else. Marking a student wrong for the shift key would
 * make this worse than not having it.
 */
function normalise(value: unknown): string {
  return typeof value === "string" ? value.trim().toLowerCase() : "";
}

export function readAnswerKey(data: FirebaseFirestore.DocumentData | undefined): AnswerKeyData | null {
  if (!data) return null;
  const answers = Array.isArray(data.answers)
    ? data.answers.filter((a: unknown) => typeof a === "string")
    : [];
  if (answers.length === 0) return null;

  const points = typeof data.pointsPerQuestion === "number" && data.pointsPerQuestion > 0
    ? data.pointsPerQuestion
    : 1;
  return {answers, pointsPerQuestion: points};
}

export function scoreAnswers(key: AnswerKeyData, given: unknown): AutoScoreResult {
  const answers = Array.isArray(given) ? given : [];
  let correctCount = 0;

  for (let i = 0; i < key.answers.length; i++) {
    // A missing answer is a question not answered, which is wrong --
    // not skipped. Treating short submissions as partially unmarked
    // would let a student improve their percentage by answering less.
    const student = i < answers.length ? answers[i] : "";
    if (normalise(student) === normalise(key.answers[i])) correctCount++;
  }

  return {
    score: correctCount * key.pointsPerQuestion,
    correctCount,
    questionCount: key.answers.length,
  };
}
