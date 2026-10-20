import * as admin from "firebase-admin";
import {onCall, HttpsError, CallableRequest} from "firebase-functions/v2/https";
import {requireCallerClaims, requireSameSchool} from "../../shared/auth/claims";
import {writeAuditLog} from "../../shared/audit/writeAuditLog";
import {FirestorePaths} from "../../shared/firestore-paths";
import {getNextSequence} from "../../shared/counters/getNextSequence";
import {STANDARD_CHART} from "../../shared/ledger/accounts";
import {
  ensureChartOfAccounts,
  postJournalEntryInTransaction,
  reasonEntryCannotPost,
  JournalLineInput,
} from "../../shared/ledger/postJournalEntry";

interface PostManualEntryData {
  schoolId: string;
  /** ISO date. The day the money moved, not the day this was typed. */
  date: string;
  memo: string;
  lines: JournalLineInput[];
}

/** Who may write in the books by hand. */
const LEDGER_ROLES = ["director", "admin"];

/**
 * An entry somebody wrote.
 *
 * Opening balances, a correction an auditor asked for, the depreciation
 * nobody has automated. Everything with an event behind it -- a payment,
 * an assessment, a payroll run -- is posted by that event instead, inside
 * the same transaction, so the books cannot disagree with the receipt.
 *
 * A callable rather than a client write because security rules cannot sum
 * an array: there is no way to say "debits equal credits" in rules, so a
 * client allowed to write could post books that do not balance. Here it
 * is checked before anything is written.
 */
export const postManualEntry = onCall(
  {region: "asia-southeast1"},
  async (request: CallableRequest<PostManualEntryData>) => {
    const callerClaims = requireCallerClaims(request);
    const {schoolId, date, memo, lines} = request.data ?? {};

    if (!schoolId || !date || !memo || !Array.isArray(lines)) {
      throw new HttpsError("invalid-argument", "Missing entry details.");
    }
    requireSameSchool(callerClaims, schoolId);
    if (!LEDGER_ROLES.includes(callerClaims.role)) {
      throw new HttpsError(
        "permission-denied",
        "Only the Director or an Admin can post to the books."
      );
    }

    const said = memo.trim();
    if (said.length < 4) {
      // The one thing an auditor will ask about, and the one thing
      // nobody will remember.
      throw new HttpsError("invalid-argument", "Say what this entry is for.");
    }

    const when = new Date(date);
    if (Number.isNaN(when.getTime())) {
      throw new HttpsError("invalid-argument", "That is not a date.");
    }
    // A date in the future is almost always a mistyped year, and it puts
    // the entry outside every period anyone will look at.
    if (when.getTime() > Date.now() + 24 * 60 * 60 * 1000) {
      throw new HttpsError("invalid-argument", "An entry cannot be dated in the future.");
    }

    const problem = reasonEntryCannotPost(lines);
    if (problem) {
      throw new HttpsError("invalid-argument", problem);
    }

    // Every line has to name an account that exists. A code typed into
    // the box that is not in the chart posts an entry nothing can
    // report on, and the trial balance grows a row called "Unknown".
    await ensureChartOfAccounts(schoolId, STANDARD_CHART);
    const db = admin.firestore();
    const chart = await db.collection(FirestorePaths.ledgerAccounts(schoolId)).get();
    const known = new Map(chart.docs.map((d) => [d.id, d.data()]));
    for (const line of lines) {
      const account = known.get(line.accountCode.trim());
      if (!account) {
        throw new HttpsError(
          "invalid-argument",
          `There is no account ${line.accountCode} in the chart.`
        );
      }
      if (account.isActive === false) {
        throw new HttpsError(
          "failed-precondition",
          `${line.accountCode} - ${account.name} is no longer in use.`
        );
      }
    }

    const sequence = await getNextSequence(schoolId, "journalEntryNumber");
    let posted!: {id: string; entryNumber: string};
    await db.runTransaction(async (tx) => {
      posted = postJournalEntryInTransaction(
        tx,
        {
          schoolId,
          date: when,
          memo: said,
          source: "manual",
          sourceId: null,
          postedBy: request.auth!.uid,
          postedByName: (request.auth!.token.name as string) ?? "Unknown",
          lines: lines.map((l) => ({
            ...l,
            accountName: known.get(l.accountCode.trim())?.name as string | undefined,
          })),
        },
        sequence
      );
    });

    await writeAuditLog({
      schoolId,
      userId: request.auth!.uid,
      userRole: callerClaims.role,
      userName: (request.auth!.token.name as string) ?? "Unknown",
      module: "ledger",
      action: "journal_entry_posted",
      targetCollection: FirestorePaths.journalEntries(schoolId),
      targetId: posted.id,
      newValue: {entryNumber: posted.entryNumber, memo: said, lines},
      success: true,
    });

    return posted;
  }
);
