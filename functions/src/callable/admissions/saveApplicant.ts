import * as admin from "firebase-admin";
import {onCall, HttpsError, CallableRequest} from "firebase-functions/v2/https";
import {requireCallerClaims, requireRole, requireSameSchool} from "../../shared/auth/claims";
import {writeAuditLog} from "../../shared/audit/writeAuditLog";
import {FirestorePaths} from "../../shared/firestore-paths";
import {getNextSequence} from "../../shared/counters/getNextSequence";
import {ApplicantData, validateApplicant} from "../../shared/admissions/applicant";

interface SaveApplicantData extends ApplicantData {
  schoolId: string;
  /** Omitted to create a new enquiry, supplied to edit an existing one. */
  applicantId?: string;
}

// The admissions office. Registrar-primary, with Director and Admin for
// the smaller schools where the roles overlap.
const ADMISSIONS_ROLES = ["director", "admin", "registrar"];

/**
 * Takes down an enquiry, or corrects one.
 *
 * Details only. The stage is not settable here: an edit to a phone
 * number and a decision to offer a family a place are different acts,
 * and a single save that could do both is one where a typo moves
 * somebody through the pipeline.
 */
export const saveApplicant = onCall(
  {region: "asia-southeast1"},
  async (request: CallableRequest<SaveApplicantData>) => {
    const callerClaims = requireCallerClaims(request);
    requireRole(callerClaims, ADMISSIONS_ROLES);

    const {schoolId, applicantId} = request.data;
    if (!schoolId) {
      throw new HttpsError("invalid-argument", "schoolId is required.");
    }
    requireSameSchool(callerClaims, schoolId);

    const details = validateApplicant(request.data);
    const db = admin.firestore();
    const callerUid = request.auth!.uid;
    const callerName = (request.auth!.token.name as string) ?? "Unknown";

    if (applicantId) {
      const ref = db.doc(FirestorePaths.applicantDoc(schoolId, applicantId));
      const snap = await ref.get();
      if (!snap.exists || snap.data()?.isDeleted === true) {
        throw new HttpsError("not-found", "That enquiry is not on file.");
      }
      await ref.update({
        ...details,
        lastUpdatedByName: callerName,
        updatedBy: callerUid,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      await writeAuditLog({
        schoolId,
        userId: callerUid,
        userRole: callerClaims.role,
        userName: callerName,
        module: "admissions",
        action: "update",
        targetCollection: FirestorePaths.applicants(schoolId),
        targetId: applicantId,
        newValue: {name: `${details.firstName} ${details.lastName}`},
        success: true,
      });

      return {applicantId};
    }

    // A reference a family can quote when they ring back, which is the
    // whole reason it exists -- "I called about my son last week" is not
    // findable, "A-2026-0042" is.
    const sequence = await getNextSequence(schoolId, "applicantNumber");
    const referenceNumber = `A-${new Date().getFullYear()}-${String(sequence).padStart(4, "0")}`;

    const ref = db.collection(FirestorePaths.applicants(schoolId)).doc();
    const now = admin.firestore.FieldValue.serverTimestamp();
    await ref.set({
      id: ref.id,
      schoolId,
      referenceNumber,
      ...details,
      stage: "inquiry",
      inquiredAt: now,
      // Every enquiry starts its clock now. The follow-up list is drawn
      // from this, not from inquiredAt, so a family being actively
      // worked through the stages does not show up as gone cold.
      stageChangedAt: now,
      examScheduledFor: null,
      examScore: null,
      examMaxScore: null,
      reservationFeePaid: 0,
      reservationPaidAt: null,
      reservationReference: null,
      studentId: null,
      lastUpdatedByName: callerName,
      createdAt: now,
      createdBy: callerUid,
      updatedAt: now,
      updatedBy: callerUid,
      deletedAt: null,
      deletedBy: null,
      isDeleted: false,
    });

    await writeAuditLog({
      schoolId,
      userId: callerUid,
      userRole: callerClaims.role,
      userName: callerName,
      module: "admissions",
      action: "create",
      targetCollection: FirestorePaths.applicants(schoolId),
      targetId: ref.id,
      newValue: {referenceNumber, name: `${details.firstName} ${details.lastName}`},
      success: true,
    });

    return {applicantId: ref.id, referenceNumber};
  }
);
