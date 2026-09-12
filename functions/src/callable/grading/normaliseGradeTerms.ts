import * as admin from "firebase-admin";
import {onCall, HttpsError, CallableRequest} from "firebase-functions/v2/https";
import {requireCallerClaims, requireRole, requireSameSchool} from "../../shared/auth/claims";
import {writeAuditLog} from "../../shared/audit/writeAuditLog";
import {FirestorePaths} from "../../shared/firestore-paths";
import {canonicalTerm} from "../../shared/grading/terms";

interface NormaliseData {
  schoolId: string;
  /** Absent or false reports what would change and writes nothing. */
  apply?: boolean;
}

/** Only the Admin. This rewrites marks across the whole school. */
const ALLOWED_ROLES = ["admin"];

/** Firestore's per-batch ceiling. */
const BATCH_LIMIT = 500;

interface Move {
  from: string;
  to: string;
  count: number;
}

interface Skip {
  from: string;
  to: string;
  count: number;
  reason: string;
}

/**
 * Repairs marks filed under a term no screen queries.
 *
 * Grade Submission used to ship a free-text term box defaulting to "Q1"
 * while the class record's dropdown offered "1st Quarter". Every query on
 * `term` is an equality match, so those marks were saved, confirmed, and
 * invisible -- present in the database, absent from every screen that
 * would show them. The write paths are fixed; this is for what they wrote
 * before they were.
 *
 * ## It reports before it writes
 *
 * `apply` defaults to false and the reply is the same shape either way,
 * so a screen can show exactly what will happen and the same call with
 * `apply: true` does it. A migration that rewrites a school's grades on
 * the strength of one button press, with no way to see the damage first,
 * is not one anybody should run.
 *
 * ## What it refuses to do
 *
 * Moving a mark into a quarter can double-count it. A student with one
 * written-work mark under "Q1" and an identical one under "1st Quarter"
 * is almost always the same quiz entered through both screens; renaming
 * the first turns 18/20 into 36/40, which is a wrong grade produced by
 * the repair itself.
 *
 * So a move is skipped when the destination already holds a mark with the
 * same student, subject, component, score and maximum. That is the test
 * the spreadsheet import uses to catch a file run twice, and for the same
 * reason: without an assessment id there is no other identity a mark has.
 * Skipped marks are listed rather than silently dropped -- a person has
 * to decide which of the two is real.
 *
 * Marks tied to a piece of work cannot collide by construction: they live
 * at `{assessment}_{student}`, so one assessment and one student is one
 * document however many times it is written.
 *
 * Terms it does not recognise are left exactly as they are. A school
 * running "Prelim" and "Midterm" keeps them.
 */
export const normaliseGradeTerms = onCall(
  {region: "asia-southeast1"},
  async (request: CallableRequest<NormaliseData>) => {
    const callerClaims = requireCallerClaims(request);
    const {schoolId, apply = false} = request.data ?? {};

    if (!schoolId) {
      throw new HttpsError("invalid-argument", "Which school?");
    }
    requireSameSchool(callerClaims, schoolId);
    requireRole(callerClaims, ALLOWED_ROLES);

    const db = admin.firestore();
    const snapshot = await db
      .collection(FirestorePaths.grades(schoolId))
      .where("isDeleted", "==", false)
      .get();

    // What each quarter already holds, so a move can be checked against
    // it. Keyed on everything that identifies a mark without an
    // assessment id.
    const occupied = new Set<string>();
    const fingerprint = (data: FirebaseFirestore.DocumentData, term: string) =>
      [
        data.studentId,
        data.subject,
        term,
        data.component,
        data.score,
        data.maxScore,
      ].join(" ");

    for (const doc of snapshot.docs) {
      const data = doc.data();
      occupied.add(fingerprint(data, String(data.term ?? "")));
    }

    const moves = new Map<string, Move>();
    const skips = new Map<string, Skip>();
    const toWrite: Array<{ref: FirebaseFirestore.DocumentReference; to: string}> = [];

    for (const doc of snapshot.docs) {
      const data = doc.data();
      const from = String(data.term ?? "");
      const to = canonicalTerm(from);
      if (to === from) continue;

      const key = `${from} -> ${to}`;
      const clash = !data.assessmentId && occupied.has(fingerprint(data, to));

      if (clash) {
        const already = skips.get(key);
        if (already) {
          already.count++;
        } else {
          skips.set(key, {
            from,
            to,
            count: 1,
            reason:
              "the same student already has an identical mark in that " +
              "quarter, so moving it would count the work twice",
          });
        }
        continue;
      }

      const already = moves.get(key);
      if (already) {
        already.count++;
      } else {
        moves.set(key, {from, to, count: 1});
      }
      // Claimed, so two marks under the same wrong term do not both move
      // onto one fingerprint and create the collision themselves.
      if (!data.assessmentId) occupied.add(fingerprint(data, to));
      toWrite.push({ref: doc.ref, to});
    }

    const report = {
      scanned: snapshot.size,
      moved: toWrite.length,
      applied: apply,
      moves: [...moves.values()].sort((a, b) => b.count - a.count),
      skipped: [...skips.values()].sort((a, b) => b.count - a.count),
    };

    if (!apply || toWrite.length === 0) return report;

    const uid = request.auth!.uid;
    const name = (request.auth!.token.name as string) ?? "Unknown";
    const now = admin.firestore.FieldValue.serverTimestamp();

    for (let i = 0; i < toWrite.length; i += BATCH_LIMIT) {
      const batch = db.batch();
      for (const {ref, to} of toWrite.slice(i, i + BATCH_LIMIT)) {
        batch.update(ref, {term: to, updatedAt: now, updatedBy: uid});
      }
      await batch.commit();
    }

    await writeAuditLog({
      schoolId,
      userId: uid,
      userRole: callerClaims.role,
      userName: name,
      module: "grading",
      action: "grade_terms_normalised",
      targetCollection: FirestorePaths.grades(schoolId),
      targetId: "all",
      newValue: {moves: report.moves, skipped: report.skipped},
      success: true,
      remarks:
        `${toWrite.length} mark${toWrite.length === 1 ? "" : "s"} moved to a ` +
        `quarter the app queries. ${report.skipped.length} kind` +
        `${report.skipped.length === 1 ? "" : "s"} of clash left alone.`,
    });

    return report;
  }
);
