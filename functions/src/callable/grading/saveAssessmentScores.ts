import * as admin from "firebase-admin";
import {onCall, HttpsError, CallableRequest} from "firebase-functions/v2/https";
import {requireCallerClaims, requireRole, requireSameSchool} from "../../shared/auth/claims";
import {writeAuditLog} from "../../shared/audit/writeAuditLog";
import {FirestorePaths} from "../../shared/firestore-paths";
import {
  GradingError,
  scoreDocId,
  validateScore,
} from "../../shared/grading/assessment";

interface ScoreEntry {
  studentId: string;
  studentName?: string;
  /** Null clears the mark: the student has not sat it. */
  score: number | null;
  remarks?: string;
}

interface SaveScoresData {
  schoolId: string;
  assessmentId: string;
  scores: ScoreEntry[];
}

const TEACHING_ROLES = ["admin", "faculty"];

/** A class is one screenful of students; a batch is 500 writes. */
const MAX_SCORES_PER_CALL = 200;

/**
 * A whole column of marks, entered at once.
 *
 * The flow this exists for: the teacher types down the roster and
 * presses save once, instead of opening a dialog per child. Every mark
 * lands at a derived id -- `{assessment}_{student}` -- so typing a
 * corrected score over a wrong one **replaces** it. Before this, every
 * submission wrote a new document and the quarterly arithmetic summed
 * them: 80 out of 10 corrected to 8 out of 10 became 88 out of 20, and
 * nothing on any screen said so.
 *
 * The assessment is read here rather than trusted from the caller. Its
 * total is what each mark is checked against and what the arithmetic
 * divides by, and a client that could name it could hand a class any
 * percentage it liked.
 */
export const saveAssessmentScores = onCall(
  {region: "asia-southeast1"},
  async (request: CallableRequest<SaveScoresData>) => {
    const callerClaims = requireCallerClaims(request);
    const {schoolId, assessmentId, scores} = request.data ?? {};

    if (!schoolId || !assessmentId) {
      throw new HttpsError("invalid-argument", "Which piece of work, in which school?");
    }
    requireSameSchool(callerClaims, schoolId);
    requireRole(callerClaims, TEACHING_ROLES);

    if (!Array.isArray(scores) || scores.length === 0) {
      throw new HttpsError("invalid-argument", "No marks to save.");
    }
    if (scores.length > MAX_SCORES_PER_CALL) {
      throw new HttpsError(
        "invalid-argument",
        `That is more than ${MAX_SCORES_PER_CALL} marks at once. Save the class in parts.`
      );
    }

    const db = admin.firestore();
    const assessmentSnap = await db
      .doc(FirestorePaths.classAssessmentDoc(schoolId, assessmentId))
      .get();
    if (!assessmentSnap.exists || assessmentSnap.data()?.isDeleted === true) {
      throw new HttpsError("not-found", "That piece of work is no longer on file.");
    }
    const assessment = assessmentSnap.data() ?? {};
    const maxScore = Number(assessment.maxScore);
    if (!Number.isFinite(maxScore) || maxScore <= 0) {
      throw new HttpsError(
        "failed-precondition",
        "That piece of work has no usable total to mark against."
      );
    }

    const uid = request.auth!.uid;
    const name = (request.auth!.token.name as string) ?? "Unknown";
    const now = admin.firestore.FieldValue.serverTimestamp();

    const batch = db.batch();
    let saved = 0;
    let cleared = 0;

    const seen = new Set<string>();
    for (const entry of scores) {
      const studentId = typeof entry?.studentId === "string" ? entry.studentId.trim() : "";
      if (!studentId) {
        throw new HttpsError("invalid-argument", "A mark with no student on it.");
      }
      // One entry per student per call. Two rows for the same child in
      // one payload are two different intentions, and the batch would
      // apply whichever came last with nothing said.
      if (seen.has(studentId)) {
        throw new HttpsError(
          "invalid-argument",
          "The same student appears twice in this set of marks."
        );
      }
      seen.add(studentId);

      let score: number | null;
      try {
        score = validateScore(entry.score, maxScore);
      } catch (error) {
        if (error instanceof GradingError) {
          const who = entry.studentName ?? studentId;
          throw new HttpsError("invalid-argument", `${who}: ${error.message}`);
        }
        throw error;
      }

      const ref = db.doc(
        FirestorePaths.gradeDoc(schoolId, scoreDocId(assessmentId, studentId))
      );

      if (score === null) {
        // A blank is not a zero. The mark is removed from the record
        // rather than stored as nothing, so the piece of work drops out
        // of both the student's score and the total it is over -- which
        // is what "did not sit it" means, and is not what "scored
        // nothing" means.
        batch.set(
          ref,
          {
            isDeleted: true,
            deletedAt: now,
            deletedBy: uid,
            updatedAt: now,
            updatedBy: uid,
          },
          {merge: true}
        );
        cleared += 1;
        continue;
      }

      const studentName =
        typeof entry.studentName === "string" && entry.studentName.trim().length > 0
          ? entry.studentName.trim()
          : null;

      batch.set(
        ref,
        {
          id: ref.id,
          schoolId,
          assessmentId,
          studentId,
          // Merged, so a save that omits the name does not blank one
          // already on the record -- the class record sends it, an
          // import might not.
          ...(studentName === null ? {} : {studentName}),
          subject: assessment.subject,
          section: assessment.section,
          term: assessment.term,
          component: assessment.component,
          courseworkItemId: null,
          score,
          maxScore,
          remarks:
            typeof entry.remarks === "string" && entry.remarks.trim().length > 0
              ? entry.remarks.trim()
              : null,
          // Stamped from the token, never from the payload. A grade is a
          // record of what a named teacher marked, and "who gave this
          // grade" must not be answerable with whatever a client typed.
          submittedByName: name,
          submittedAt: now,
          isDeleted: false,
          createdAt: now,
          createdBy: uid,
          updatedAt: now,
          updatedBy: uid,
          deletedAt: null,
          deletedBy: null,
        },
        {merge: true}
      );
      saved += 1;
    }

    await batch.commit();

    await writeAuditLog({
      schoolId,
      userId: uid,
      userRole: callerClaims.role,
      userName: name,
      module: "grading",
      action: "scores_saved",
      targetCollection: FirestorePaths.grades(schoolId),
      targetId: assessmentId,
      newValue: {
        subject: assessment.subject,
        section: assessment.section,
        term: assessment.term,
        title: assessment.title,
        marked: saved,
        cleared,
      },
      success: true,
    });

    return {saved, cleared};
  }
);
