import * as admin from "firebase-admin";
import {onCall, HttpsError, CallableRequest} from "firebase-functions/v2/https";
import {requireCallerClaims, requireRole, requireSameSchool} from "../../shared/auth/claims";
import {writeAuditLog} from "../../shared/audit/writeAuditLog";
import {FirestorePaths} from "../../shared/firestore-paths";
import {
  COMPONENT_LABELS,
  GradingError,
  classKey,
  validateAssessment,
} from "../../shared/grading/assessment";

interface SaveAssessmentData {
  schoolId: string;
  /** Absent to create; present to rename or re-weight an existing one. */
  assessmentId?: string;
  subject: string;
  section: string;
  term: string;
  title: string;
  component: string;
  maxScore: number;
}

const TEACHING_ROLES = ["director", "admin", "faculty"];

/**
 * One piece of work a class was given: one column in the class record.
 *
 * Created before anything is marked, so every mark against it has the
 * same total behind it and one student's mark has somewhere to live that
 * entering it twice cannot duplicate.
 *
 * Changing `maxScore` after marks exist is allowed and deliberate -- a
 * teacher who set 20 and meant 25 has to be able to say so -- but it
 * re-scales nothing: the marks stay as typed, and any that now exceed
 * the new total are named in the reply so the teacher can fix them
 * rather than discovering it on a report card.
 */
export const saveClassAssessment = onCall(
  {region: "asia-southeast1"},
  async (request: CallableRequest<SaveAssessmentData>) => {
    const callerClaims = requireCallerClaims(request);
    const {schoolId, assessmentId} = request.data ?? {};

    if (!schoolId) {
      throw new HttpsError("invalid-argument", "Which school?");
    }
    requireSameSchool(callerClaims, schoolId);
    requireRole(callerClaims, TEACHING_ROLES);

    let assessment;
    try {
      assessment = validateAssessment(request.data);
    } catch (error) {
      if (error instanceof GradingError) {
        throw new HttpsError("invalid-argument", error.message);
      }
      throw error;
    }

    const db = admin.firestore();
    const collection = db.collection(FirestorePaths.classAssessments(schoolId));
    const ref = assessmentId ? collection.doc(assessmentId) : collection.doc();
    const uid = request.auth!.uid;
    const name = (request.auth!.token.name as string) ?? "Unknown";
    const now = admin.firestore.FieldValue.serverTimestamp();

    if (assessmentId) {
      const existing = await ref.get();
      if (!existing.exists || existing.data()?.isDeleted === true) {
        throw new HttpsError("not-found", "That piece of work is no longer on file.");
      }
    }

    await ref.set(
      {
        id: ref.id,
        schoolId,
        classKey: classKey(assessment.subject, assessment.section, assessment.term),
        subject: assessment.subject,
        section: assessment.section,
        term: assessment.term,
        title: assessment.title,
        component: assessment.component,
        maxScore: assessment.maxScore,
        isDeleted: false,
        ...(assessmentId
          ? {}
          : {createdAt: now, createdBy: uid, createdByName: name}),
        updatedAt: now,
        updatedBy: uid,
        updatedByName: name,
      },
      {merge: true}
    );

    // Marks that no longer fit the total. Named rather than clamped or
    // silently left: either number could be the right one, and only the
    // teacher knows which.
    const marks = await db
      .collection(FirestorePaths.grades(schoolId))
      .where("assessmentId", "==", ref.id)
      .get();
    const overMax = marks.docs
      .filter((doc) => Number(doc.data().score) > assessment.maxScore)
      .map((doc) => (doc.data().studentName as string) ?? doc.id);

    await writeAuditLog({
      schoolId,
      userId: uid,
      userRole: callerClaims.role,
      userName: name,
      module: "grading",
      action: assessmentId ? "assessment_updated" : "assessment_created",
      targetCollection: FirestorePaths.classAssessments(schoolId),
      targetId: ref.id,
      newValue: {
        subject: assessment.subject,
        section: assessment.section,
        term: assessment.term,
        title: assessment.title,
        component: COMPONENT_LABELS[assessment.component],
        maxScore: assessment.maxScore,
      },
      success: true,
    });

    return {assessmentId: ref.id, marksOverMax: overMax};
  }
);
