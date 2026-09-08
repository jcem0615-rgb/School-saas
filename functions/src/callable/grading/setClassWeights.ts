import * as admin from "firebase-admin";
import {onCall, HttpsError, CallableRequest} from "firebase-functions/v2/https";
import {requireCallerClaims, requireRole, requireSameSchool} from "../../shared/auth/claims";
import {writeAuditLog} from "../../shared/audit/writeAuditLog";
import {FirestorePaths} from "../../shared/firestore-paths";
import {GradingError, classKey} from "../../shared/grading/assessment";
import {validateWeights} from "../../shared/grading/weights";

interface SetClassWeightsData {
  schoolId: string;
  subject: string;
  section: string;
  /** Absent clears the override and the class falls back to the school's scheme. */
  writtenWork?: number;
  performanceTask?: number;
  quarterlyAssessment?: number;
  clear?: boolean;
}

const TEACHING_ROLES = ["admin", "faculty"];

/**
 * What each component counts for one class.
 *
 * The school's confirmed scheme is still the default and is what a class
 * with no override is graded on. This is for the case that scheme cannot
 * express: a subject marked on a split the department agreed, which
 * before this had to be done in a spreadsheet beside the app.
 *
 * The one rule that makes any grading scheme mean something is enforced
 * here rather than at the screen: the three add up to a hundred. Weights
 * of 30/50/30 produce grades that look entirely plausible and are wrong
 * for every child in the class, all quarter, and a check a client can
 * skip by not running it is not a check.
 *
 * Whoever set them is recorded. The class record prints it, so a set
 * nobody agreed to is visible rather than quietly in effect.
 */
export const setClassWeights = onCall(
  {region: "asia-southeast1"},
  async (request: CallableRequest<SetClassWeightsData>) => {
    const callerClaims = requireCallerClaims(request);
    const {schoolId, subject, section} = request.data ?? {};

    if (!schoolId || !subject || !section) {
      throw new HttpsError("invalid-argument", "Which class, in which school?");
    }
    requireSameSchool(callerClaims, schoolId);
    requireRole(callerClaims, TEACHING_ROLES);

    const db = admin.firestore();
    const key = classKey(subject, section);
    const ref = db.doc(FirestorePaths.classWeightsDoc(schoolId, key));
    const uid = request.auth!.uid;
    const name = (request.auth!.token.name as string) ?? "Unknown";
    const now = admin.firestore.FieldValue.serverTimestamp();

    if (request.data.clear === true) {
      await ref.delete();
      await writeAuditLog({
        schoolId,
        userId: uid,
        userRole: callerClaims.role,
        userName: name,
        module: "grading",
        action: "class_weights_cleared",
        targetCollection: FirestorePaths.classWeights(schoolId),
        targetId: key,
        newValue: {subject, section},
        success: true,
      });
      return {cleared: true};
    }

    let weights;
    try {
      weights = validateWeights({
        writtenWork: request.data.writtenWork,
        performanceTask: request.data.performanceTask,
        quarterlyAssessment: request.data.quarterlyAssessment,
      });
    } catch (error) {
      if (error instanceof GradingError) {
        throw new HttpsError("invalid-argument", error.message);
      }
      throw error;
    }

    await ref.set({
      id: key,
      schoolId,
      subject: subject.trim(),
      section: section.trim(),
      ...weights,
      setBy: uid,
      setByName: name,
      setAt: now,
      updatedAt: now,
      updatedBy: uid,
    });

    await writeAuditLog({
      schoolId,
      userId: uid,
      userRole: callerClaims.role,
      userName: name,
      module: "grading",
      action: "class_weights_set",
      targetCollection: FirestorePaths.classWeights(schoolId),
      targetId: key,
      newValue: {subject, section, ...weights},
      success: true,
    });

    return {cleared: false, ...weights};
  }
);
