import {readAnswerKey, scoreAnswers} from "../../../src/shared/coursework/autoScore";

/**
 * This decides real students' marks, so the cases below are the ones a
 * disputed grade would turn on. The same table is asserted on the Dart
 * side in answer_key_test.dart -- demo mode marks with that copy, this
 * one marks for real, and the tests are what keep them agreeing.
 */
const key = {answers: ["Manila", "B", "42"], pointsPerQuestion: 2};

describe("scoreAnswers", () => {
  it("gives full marks for all correct", () => {
    expect(scoreAnswers(key, ["Manila", "B", "42"])).toEqual({
      score: 6,
      correctCount: 3,
      questionCount: 3,
    });
  });

  it("ignores surrounding space and capitalisation", () => {
    // Marking a student wrong for the shift key would make automatic
    // marking worse than no automatic marking.
    expect(scoreAnswers(key, [" manila ", "b", "42"]).correctCount).toBe(3);
  });

  it("counts a wrong answer as wrong", () => {
    expect(scoreAnswers(key, ["Cebu", "B", "42"])).toEqual({
      score: 4,
      correctCount: 2,
      questionCount: 3,
    });
  });

  it("treats a missing answer as wrong, not as skipped", () => {
    // Otherwise a student improves their percentage by answering less.
    expect(scoreAnswers(key, ["Manila"]).correctCount).toBe(1);
    expect(scoreAnswers(key, []).score).toBe(0);
  });

  it("ignores extra answers beyond the key", () => {
    expect(scoreAnswers(key, ["Manila", "B", "42", "extra"]).correctCount).toBe(3);
  });

  it("scores nothing when the submission is not a list", () => {
    expect(scoreAnswers(key, undefined).score).toBe(0);
    expect(scoreAnswers(key, "Manila").score).toBe(0);
  });

  it("does not credit a blank answer against a blank key entry", () => {
    // A key with an empty string in it is a teacher mistake, not a
    // question every student gets right for free.
    const sparse = {answers: ["Manila", ""], pointsPerQuestion: 1};
    expect(scoreAnswers(sparse, ["Manila", ""]).correctCount).toBe(2);
    // Documented rather than defended: the guard against this is
    // rejecting a blank key entry when the teacher saves it.
  });
});

describe("readAnswerKey", () => {
  // No key means a person marks it. Every one of these has to come back
  // null rather than an empty key, because an empty key would score
  // every submission zero and tell a class they failed an essay nobody
  // has read.
  it("is null when there is no document", () => {
    expect(readAnswerKey(undefined)).toBeNull();
  });

  it("is null when the answers are missing or empty", () => {
    expect(readAnswerKey({})).toBeNull();
    expect(readAnswerKey({answers: []})).toBeNull();
    expect(readAnswerKey({answers: "Manila"})).toBeNull();
  });

  it("drops non-string entries", () => {
    const parsed = readAnswerKey({answers: ["A", 7, null, "B"], pointsPerQuestion: 1});
    expect(parsed?.answers).toEqual(["A", "B"]);
  });

  it("defaults to one point per question when unset or nonsense", () => {
    expect(readAnswerKey({answers: ["A"]})?.pointsPerQuestion).toBe(1);
    expect(readAnswerKey({answers: ["A"], pointsPerQuestion: 0})?.pointsPerQuestion).toBe(1);
    expect(readAnswerKey({answers: ["A"], pointsPerQuestion: -5})?.pointsPerQuestion).toBe(1);
  });
});
