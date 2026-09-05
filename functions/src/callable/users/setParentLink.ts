import * as admin from "firebase-admin";
import {onCall, HttpsError, CallableRequest} from "firebase-functions/v2/https";
import {requireCallerClaims, requireRole, requireSameSchool} from "../../shared/auth/claims";
import {writeAuditLog} from "../../shared/audit/writeAuditLog";
import {FirestorePaths} from "../../shared/firestore-paths";
import {withLink, withoutLink, ParentLinkError} from "../../shared/users/parentLinks";

interface SetParentLinkData {
  schoolId: string;
  parentUid: string;
  studentId: string;
  /** true to give this parent access to this child, false to take it away. */
  linked: boolean;
}

// The same roles that may create a parent account may say which children
// it sees. Faculty and guidance are deliberately absent: a class adviser
// knowing a family is not the same as being allowed to grant somebody
// access to a child's record.
const ALLOWED_ROLES = ["director", "admin", "registrar"];

/**
 * Attaches a parent account to a child's record, or detaches it.
 *
 * This is the only writer of `linkedStudentIds`, and firestore.rules
 * refuses the field on every client path, because that array IS the
 * parent's access -- every parent read in the rules resolves to "is this
 * studentId in it?". Granting one family sight of another family's child
 * is silent on both screens, so it goes through here, where it is checked
 * and written to the audit log with a name against it.
 */
export const setParentLink = onCall(
  {region: "asia-southeast1"},
  async (request: CallableRequest<SetParentLinkData>) => {
    const callerClaims = requireCallerClaims(request);
    requireRole(callerClaims, ALLOWED_ROLES);

    const {schoolId, parentUid, studentId, linked} = request.data;
    if (!schoolId || !parentUid || !studentId || typeof linked !== "boolean") {
      throw new HttpsError("invalid-argument", "Missing schoolId, parentUid, studentId or linked.");
    }
    requireSameSchool(callerClaims, schoolId);

    const db = admin.firestore();
    const parentRef = db.doc(FirestorePaths.userDoc(schoolId, parentUid));
    const studentRef = db.doc(FirestorePaths.studentDoc(schoolId, studentId));

    // Read both before writing either. A link naming a student who does
    // not exist is not merely useless -- it is a row in an access list
    // that nobody can look at and evaluate, and it survives every audit
    // because there is nothing left to compare it against.
    const [parentSnap, studentSnap] = await Promise.all([parentRef.get(), studentRef.get()]);

    if (!parentSnap.exists || parentSnap.data()?.isDeleted) {
      throw new HttpsError("not-found", "That parent account was not found at this school.");
    }
    if (parentSnap.data()?.role !== "parent") {
      // Refused rather than allowed-and-ignored. linkedStudentIds on a
      // faculty account would do nothing today, and would silently become
      // a grant the day any rule stopped checking the role first.
      throw new HttpsError(
        "failed-precondition",
        "Only a parent account can be linked to a student."
      );
    }
    if (!studentSnap.exists || studentSnap.data()?.isDeleted) {
      throw new HttpsError("not-found", "That student record was not found at this school.");
    }

    let result;
    try {
      result = linked
        ? withLink(parentSnap.data()?.linkedStudentIds, studentId)
        : withoutLink(parentSnap.data()?.linkedStudentIds, studentId);
    } catch (err) {
      if (err instanceof ParentLinkError) {
        throw new HttpsError("invalid-argument", err.message);
      }
      throw err;
    }

    // Already in the state asked for. Returns rather than throwing: two
    // registrars working the same enrolment queue should not see an error
    // for a state that is already correct. Nothing is written, so the
    // audit log does not fill with links nobody made.
    if (!result.changed) {
      return {changed: false, linkedStudentIds: result.links};
    }

    await parentRef.update({
      linkedStudentIds: result.links,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedBy: request.auth!.uid,
    });

    const studentName = [studentSnap.data()?.firstName, studentSnap.data()?.lastName]
      .filter(Boolean)
      .join(" ");

    await writeAuditLog({
      schoolId,
      userId: request.auth!.uid,
      userRole: callerClaims.role,
      userName: (request.auth!.token.name as string) ?? "Unknown",
      module: "users",
      action: linked ? "link_parent" : "unlink_parent",
      targetCollection: FirestorePaths.users(schoolId),
      targetId: parentUid,
      newValue: {studentId, studentName, linkedStudentIds: result.links},
      // Says what access changed and about whom, in a line somebody
      // reviewing the trail can read without opening two other records.
      remarks: linked
        ? `Gave this parent access to ${studentName || studentId}.`
        : `Removed this parent's access to ${studentName || studentId}.`,
      success: true,
    });

    return {changed: true, linkedStudentIds: result.links};
  }
);
