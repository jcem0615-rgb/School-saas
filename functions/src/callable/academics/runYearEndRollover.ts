import * as admin from "firebase-admin";
import {onCall, HttpsError, CallableRequest} from "firebase-functions/v2/https";
import {requireCallerClaims, requireRole, requireSameSchool} from "../../shared/auth/claims";
import {writeAuditLog} from "../../shared/audit/writeAuditLog";
import {FirestorePaths} from "../../shared/firestore-paths";
import {
  PromotionDecisionData,
  normaliseSchoolYear,
  studentUpdateFor,
  validateDecisions,
} from "../../shared/academics/rollover";

interface RunRolloverData {
  schoolId: string;
  schoolYear: string;
  decisions: PromotionDecisionData[];
}

// The registrar's office owns the academic record; a director or admin
// can run it in a school small enough that the roles overlap. Nobody
// else: this is the least reversible operation in the system.
const ROLLOVER_ALLOWED_ROLES = ["director", "admin", "registrar"];

/**
 * Moves a page of students into the next school year.
 *
 * ## Why re-running this is safe
 *
 * Each student's promotion record is written at a document id built from
 * the school year and their id, with `create`. A student who has already
 * been rolled over for 2026-2027 cannot be created again, so the second
 * attempt skips them rather than promoting them a second time. That
 * matters more here than anywhere else in this system: a rollover that
 * ran twice would put every child in the school two years above where
 * they belong, and there is no undo.
 *
 * The client sends the school in pages. A page that fails leaves the
 * students in earlier pages moved and the rest untouched, and re-sending
 * the whole thing finishes the job -- which is the behaviour a registrar
 * whose connection dropped halfway actually needs.
 */
export const runYearEndRollover = onCall(
  {region: "asia-southeast1"},
  async (request: CallableRequest<RunRolloverData>) => {
    const callerClaims = requireCallerClaims(request);
    requireRole(callerClaims, ROLLOVER_ALLOWED_ROLES);

    const {schoolId} = request.data;
    if (!schoolId) {
      throw new HttpsError("invalid-argument", "schoolId is required.");
    }
    requireSameSchool(callerClaims, schoolId);

    const schoolYear = normaliseSchoolYear(request.data.schoolYear);
    const decisions = validateDecisions(request.data.decisions);

    const db = admin.firestore();
    const callerUid = request.auth!.uid;
    const callerName = request.auth?.token?.name || callerClaims.role || "Unknown";

    const applied: string[] = [];
    const skipped: string[] = [];

    // One transaction per student rather than one batch for the page.
    //
    // A batch would be fewer round trips and could not tell which
    // students it skipped: `create` on an existing document fails the
    // whole batch, so one already-rolled-over student would abort a page
    // of two hundred. Per student, an already-moved child is a skip and
    // the rest of the page still goes through, which is exactly what a
    // re-run needs.
    for (const decision of decisions) {
      const promotionRef = db.doc(
        FirestorePaths.promotionDoc(schoolId, schoolYear, decision.studentId)
      );
      const studentRef = db.doc(FirestorePaths.studentDoc(schoolId, decision.studentId));

      try {
        // The transaction reports what it did rather than appending to
        // the tallies itself. Firestore retries a contended transaction,
        // and a push inside the body would count that student twice --
        // inflating both the message the registrar reads and the
        // increment written to the year's record.
        const outcome = await db.runTransaction<"applied" | "skipped">(async (tx) => {
          const existing = await tx.get(promotionRef);
          if (existing.exists) {
            return "skipped";
          }

          const studentSnap = await tx.get(studentRef);
          if (!studentSnap.exists) {
            // A record deleted between drawing up the plan and running
            // it. Refusing the whole page over one would be worse than
            // saying so and carrying on.
            return "skipped";
          }
          const student = studentSnap.data() ?? {};

          tx.create(promotionRef, {
            ...decision,
            id: `${schoolYear}_${decision.studentId}`,
            schoolId,
            schoolYear,
            decidedBy: callerUid,
            decidedByName: callerName,
            decidedAt: admin.firestore.FieldValue.serverTimestamp(),
            // What the student's record said at the moment it changed.
            // The decision carries where they were going; this is where
            // they actually were, which is the half that would otherwise
            // be lost if somebody edited the record afterwards.
            previousGradeLevel: student.gradeLevel ?? null,
            previousSection: student.section ?? null,
            previousStatus: student.status ?? null,
          });

          const update = studentUpdateFor(decision);
          if (update !== null) {
            tx.update(studentRef, {
              ...update,
              updatedBy: callerUid,
              updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            });
          }

          return "applied";
        });

        if (outcome === "applied") {
          applied.push(decision.studentId);
        } else {
          skipped.push(decision.studentId);
        }
      } catch (error) {
        // Said with the student's name in it. "PERMISSION_DENIED" tells a
        // registrar nothing about which of two hundred children did not
        // move.
        throw new HttpsError(
          "internal",
          `Stopped at ${decision.studentName}. ${applied.length} students were ` +
            "already moved; running it again will carry on from there. " +
            `(${error instanceof Error ? error.message : String(error)})`
        );
      }
    }

    // The year's own document: a running record of what has been done,
    // merged rather than created, because the client sends pages.
    await db.doc(FirestorePaths.schoolYearDoc(schoolId, schoolYear)).set(
      {
        id: schoolYear,
        schoolId,
        schoolYear,
        rolledOverCount: admin.firestore.FieldValue.increment(applied.length),
        lastRunBy: callerUid,
        lastRunByName: callerName,
        lastRunAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      {merge: true}
    );

    await writeAuditLog({
      schoolId,
      userId: callerUid,
      userRole: callerClaims.role,
      userName: callerName,
      module: "academics",
      action: "rollover",
      targetCollection: "promotions",
      targetId: schoolYear,
      newValue: {applied: applied.length, skipped: skipped.length},
      success: true,
    });

    return {applied: applied.length, skipped: skipped.length, schoolYear};
  }
);
