import * as admin from "firebase-admin";
import {onCall, HttpsError, CallableRequest} from "firebase-functions/v2/https";
import {requireCallerClaims, requireRole, requireSameSchool} from "../../shared/auth/claims";
import {writeAuditLog} from "../../shared/audit/writeAuditLog";
import {FirestorePaths} from "../../shared/firestore-paths";
import {
  AdmissionStage,
  isAdmissionStage,
  requireLegalTransition,
  validateExamResult,
  validateReservationFee,
} from "../../shared/admissions/applicant";

interface AdvanceApplicantData {
  schoolId: string;
  applicantId: string;
  /** Where they are being moved to. */
  stage: string;
  /** When the entrance exam is booked for, moving to exam_scheduled. */
  examScheduledFor?: string;
  /** The result, moving to exam_taken. */
  examScore?: number;
  examMaxScore?: number;
  /** What was paid to hold the place, moving to reserved. */
  reservationFee?: number;
  reservationReference?: string;
  notes?: string;
}

const ADMISSIONS_ROLES = ["director", "admin", "registrar"];

/**
 * Moves a family one step, and records what that step produced.
 *
 * The step and its evidence are one act rather than two. A family is not
 * at "exam taken" without a score and not at "reserved" without a
 * payment, and a system that lets the stage be set first and the number
 * filled in later is one where half the pipeline is stages with nothing
 * behind them -- which is the logbook this module replaces.
 */
export const advanceApplicant = onCall(
  {region: "asia-southeast1"},
  async (request: CallableRequest<AdvanceApplicantData>) => {
    const callerClaims = requireCallerClaims(request);
    requireRole(callerClaims, ADMISSIONS_ROLES);

    const {schoolId, applicantId, stage} = request.data;
    if (!schoolId || !applicantId) {
      throw new HttpsError("invalid-argument", "schoolId and applicantId are required.");
    }
    requireSameSchool(callerClaims, schoolId);
    if (!isAdmissionStage(stage)) {
      throw new HttpsError("invalid-argument", `"${stage}" is not an admission stage.`);
    }
    const target = stage as AdmissionStage;

    const db = admin.firestore();
    const ref = db.doc(FirestorePaths.applicantDoc(schoolId, applicantId));
    const callerUid = request.auth!.uid;
    const callerName = (request.auth!.token.name as string) ?? "Unknown";

    const from = await db.runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      if (!snap.exists || snap.data()?.isDeleted === true) {
        throw new HttpsError("not-found", "That enquiry is not on file.");
      }
      const current = snap.data() ?? {};
      const currentStage = String(current.stage ?? "inquiry") as AdmissionStage;

      requireLegalTransition(currentStage, target);

      const update: Record<string, unknown> = {
        stage: target,
        stageChangedAt: admin.firestore.FieldValue.serverTimestamp(),
        lastUpdatedByName: callerName,
        updatedBy: callerUid,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      };

      if (typeof request.data.notes === "string") {
        update.notes = request.data.notes.trim() || null;
      }

      if (target === "exam_scheduled") {
        const when = request.data.examScheduledFor;
        const parsed = when ? new Date(when) : null;
        if (!parsed || Number.isNaN(parsed.getTime())) {
          throw new HttpsError(
            "invalid-argument",
            "Booking a family in for the entrance exam needs a date. Without " +
              "one, \"exam scheduled\" says nothing anybody can act on."
          );
        }
        update.examScheduledFor = admin.firestore.Timestamp.fromDate(parsed);
      }

      if (target === "exam_taken") {
        const result = validateExamResult(request.data.examScore, request.data.examMaxScore);
        update.examScore = result.score;
        update.examMaxScore = result.maxScore;
      }

      if (target === "reserved") {
        const fee = validateReservationFee(request.data.reservationFee);
        // Added to what is already there rather than replacing it: a
        // family paying the reservation in two instalments is ordinary,
        // and overwriting would lose the first payment -- money the
        // school has taken and would then not credit at enrolment.
        const alreadyPaid = Number(current.reservationFeePaid ?? 0) || 0;
        update.reservationFeePaid = Math.round((alreadyPaid + fee) * 100) / 100;
        update.reservationPaidAt = admin.firestore.FieldValue.serverTimestamp();
        const reference = String(request.data.reservationReference ?? "").trim();
        if (reference) update.reservationReference = reference;
      }

      tx.update(ref, update);
      return currentStage;
    });

    await writeAuditLog({
      schoolId,
      userId: callerUid,
      userRole: callerClaims.role,
      userName: callerName,
      module: "admissions",
      action: "advance",
      targetCollection: FirestorePaths.applicants(schoolId),
      targetId: applicantId,
      previousValue: {stage: from},
      newValue: {stage: target},
      success: true,
    });

    return {applicantId, stage: target};
  }
);
