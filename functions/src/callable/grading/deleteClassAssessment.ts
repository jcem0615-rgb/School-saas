import * as admin from "firebase-admin";
import {onCall, HttpsError, CallableRequest} from "firebase-functions/v2/https";
import {requireCallerClaims, requireRole, requireSameSchool} from "../../shared/auth/claims";
import {writeAuditLog} from "../../shared/audit/writeAuditLog";
import {FirestorePaths} from "../../shared/firestore-paths";
import {COMPONENT_LABELS} from "../../shared/grading/assessment";

interface DeleteAssessmentData {
  schoolId: string;
  assessmentId: string;
}

const TEACHING_ROLES = ["admin", "faculty"];

/**
 * Removes one piece of work, and the marks recorded against it.
 *
 * The marks are the reason this is a callable rather than a client
 * delete. Removing the column and leaving its marks behind would leave
 * every one of them still summing into the component total, so a class
 * would keep being graded on a quiz the teacher deleted -- and there
 * would be nothing on any screen to explain the figure. They go
 * together or not at all.
 *
 * Soft, on both. `isDeleted` is what every read in this module already
 * filters on, and it leaves the marks recoverable and the audit entry
 * meaningful. A hard delete of a child's recorded score is not a thing a
 * teacher should be able to do from a phone.
 *
 * The count of marks removed comes back so the screen can say what
 * happened. A teacher who deletes "Quiz 1" without being told it took
 * thirty-two marks with it finds out from a parent.
 */
export const deleteClassAssessment = onCall(
  {region: "asia-southeast1"},
  async (request: CallableRequest<DeleteAssessmentData>) => {
    const callerClaims = requireCallerClaims(request);
    const {schoolId, assessmentId} = request.data ?? {};

    if (!schoolId || !assessmentId) {
      throw new HttpsError("invalid-argument", "schoolId and assessmentId are required.");
    }
    requireSameSchool(callerClaims, schoolId);
    requireRole(callerClaims, TEACHING_ROLES);

    const db = admin.firestore();
    const ref = db.collection(FirestorePaths.classAssessments(schoolId)).doc(assessmentId);
    const snapshot = await ref.get();
    if (!snapshot.exists || snapshot.data()?.isDeleted === true) {
      throw new HttpsError("not-found", "That piece of work is no longer on file.");
    }
    const assessment = snapshot.data()!;

    const marks = await db
      .collection(FirestorePaths.grades(schoolId))
      .where("assessmentId", "==", assessmentId)
      .where("isDeleted", "==", false)
      .get();

    const uid = request.auth!.uid;
    const name = (request.auth!.token.name as string) ?? "Unknown";
    const now = admin.firestore.FieldValue.serverTimestamp();
    const tombstone = {
      isDeleted: true,
      deletedAt: now,
      deletedBy: uid,
      deletedByName: name,
      updatedAt: now,
      updatedBy: uid,
    };

    // One batch: the column and its marks disappear together or not at
    // all. Halfway through is the state that produces a grade computed
    // from marks whose piece of work no longer exists.
    const batch = db.batch();
    batch.update(ref, tombstone);
    for (const mark of marks.docs) {
      batch.update(mark.ref, tombstone);
    }
    await batch.commit();

    await writeAuditLog({
      schoolId,
      userId: uid,
      userRole: callerClaims.role,
      userName: name,
      module: "grading",
      action: "assessment_deleted",
      targetCollection: FirestorePaths.classAssessments(schoolId),
      targetId: assessmentId,
      previousValue: {
        subject: assessment.subject,
        section: assessment.section,
        term: assessment.term,
        title: assessment.title,
        // Falls back to the stored value: a component written before a
        // label existed for it should still name itself in the log.
        component:
          COMPONENT_LABELS[assessment.component as keyof typeof COMPONENT_LABELS] ??
          assessment.component,
        maxScore: assessment.maxScore,
      },
      success: true,
      remarks: `Removed with ${marks.size} mark${marks.size === 1 ? "" : "s"} recorded against it.`,
    });

    return {assessmentId, marksRemoved: marks.size};
  }
);
