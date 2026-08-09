import * as admin from "firebase-admin";
import {onDocumentWritten} from "firebase-functions/v2/firestore";
import {FirestorePaths} from "../../shared/firestore-paths";
import {readAnswerKey, scoreAnswers} from "../../shared/coursework/autoScore";

/**
 * Marks a submission against the teacher's answer key.
 *
 * This runs server-side because it has to. The key lives in a collection
 * firestore.rules does not let students read, and the score is written
 * with the Admin SDK -- the same rules forbid any client from writing a
 * score field at all. Marking in the app would mean either shipping the
 * answers to the device that is being marked, or trusting that device's
 * arithmetic about its own grade. Neither is a real option.
 *
 * onDocumentWritten rather than onCreate: a student resubmitting has to
 * be re-marked, or their first attempt's score would stand over their
 * corrected answers.
 */
export const onCourseworkSubmissionWritten = onDocumentWritten(
  {region: "asia-southeast1", document: "schools/{schoolId}/courseworkSubmissions/{submissionId}"},
  async (event) => {
    const after = event.data?.after;
    if (!after?.exists) return; // deleted, nothing to mark

    const data = after.data();
    if (!data) return;

    const schoolId = event.params.schoolId;
    const courseworkId = data.courseworkId as string | undefined;
    if (!courseworkId) return;

    const db = admin.firestore();
    const keySnap = await db
      .doc(`${FirestorePaths.courseworkAnswerKeys(schoolId)}/${courseworkId}`)
      .get();

    const key = readAnswerKey(keySnap.data());
    // No key means this is work a person reads and marks. Leaving the
    // score fields untouched is the whole behaviour -- writing a zero
    // would tell a student they failed an essay nobody has read yet.
    if (!key) return;

    const result = scoreAnswers(key, data.answers);

    // Nothing to do if the mark has not moved. Without this the write
    // below retriggers this same function on every submission forever.
    if (data.autoScore === result.score && data.correctCount === result.correctCount) return;

    await after.ref.update({
      autoScore: result.score,
      correctCount: result.correctCount,
      autoScoredAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  }
);
