/**
 * Requires the Firestore emulator.
 * Run via: firebase emulators:exec --only firestore "jest test/shared/audit-emulator"
 *
 * What the audit trail records, and what it must not.
 *
 * The trail exists so a school can answer "who changed this, and when".
 * It does that by copying the document into the log entry, which is
 * useful and is also the part that needs a boundary: the log is read
 * school-wide by the Director and the Admin, so anything copied into it
 * is readable by them -- whatever the collection's own read rule says.
 *
 * `conversations` is the collection where that mattered. Its rule says,
 * in as many words, that nobody but the two participants may read a
 * thread -- "not an admin, not the director" -- and that a school need-
 * ing to see one has a lawful-request path "and an audit trail, not a
 * back door". The audit trail was the back door: every message updates
 * the conversation with a preview of what was said, and the trigger
 * copied that preview into the log.
 */
import functionsTest from "firebase-functions-test";
import * as admin from "firebase-admin";
import {FirestorePaths} from "../../../src/shared/firestore-paths";

const fft = functionsTest({projectId: "school-saas-test"});

const SCHOOL = "school_audit";

/* eslint-disable @typescript-eslint/no-explicit-any */
let onWrite: any;
/* eslint-enable @typescript-eslint/no-explicit-any */

function db() {
  return admin.firestore();
}

async function clearLog() {
  const snap = await db().collection(FirestorePaths.auditLog(SCHOOL)).get();
  await Promise.all(snap.docs.map((d) => d.ref.delete()));
}

/** Runs the trigger over a write and returns the entry it produced. */
async function auditOf(
  collectionId: string,
  docId: string,
  before: Record<string, unknown> | null,
  after: Record<string, unknown> | null
): Promise<FirebaseFirestore.DocumentData | undefined> {
  await clearLog();
  const path = `schools/${SCHOOL}/${collectionId}/${docId}`;
  const event = {
    data: {
      before: before === null ?
        fft.firestore.makeDocumentSnapshot({}, path) :
        fft.firestore.makeDocumentSnapshot(before, path),
      after: after === null ?
        fft.firestore.makeDocumentSnapshot({}, path) :
        fft.firestore.makeDocumentSnapshot(after, path),
    },
    params: {schoolId: SCHOOL, collectionId, docId},
  };
  await onWrite(event as never);
  const snap = await db().collection(FirestorePaths.auditLog(SCHOOL)).get();
  return snap.docs[0]?.data();
}

describe("the audit trail", () => {
  beforeAll(async () => {
    if (admin.apps.length === 0) {
      admin.initializeApp({projectId: "school-saas-test"});
    }
    const mod = await import("../../../src/triggers/audit/onAnyTenantDocWrite");
    onWrite = fft.wrap(mod.onAnyTenantDocWrite);
    await db().doc(FirestorePaths.userDoc(SCHOOL, "u_admin")).set({
      role: "admin",
      firstName: "Grace",
      lastName: "Lim",
    });
  });

  afterAll(async () => {
    await clearLog();
    fft.cleanup();
  });

  describe("what it records", () => {
    it("names who made the change, from the document itself", async () => {
      const entry = await auditOf("expenses", "exp_1", null, {
        category: "Utilities",
        amount: 1200,
        createdBy: "u_admin",
        updatedBy: "u_admin",
      });
      expect(entry!.userId).toBe("u_admin");
      expect(entry!.userName).toBe("Grace Lim");
      expect(entry!.userRole).toBe("admin");
      expect(entry!.action).toBe("create");
    });

    it("keeps both sides of an edit, so the change itself is readable", async () => {
      const entry = await auditOf(
        "expenses",
        "exp_1",
        {amount: 1200, updatedBy: "u_admin"},
        {amount: 9999, updatedBy: "u_admin"}
      );
      expect(entry!.action).toBe("update");
      expect((entry!.previousValue as Record<string, unknown>).amount).toBe(1200);
      expect((entry!.newValue as Record<string, unknown>).amount).toBe(9999);
    });

    it("still names somebody when a document is deleted outright", async () => {
      // A hard delete has no `after`, so there is nothing on the document
      // to read the actor from. Falling through to "unknown" made the
      // audit trail answer "who deleted this?" with the one word it
      // exists to avoid.
      const entry = await auditOf("expenses", "exp_1", {
        amount: 1200,
        createdBy: "u_admin",
        updatedBy: "u_admin",
      }, null);
      expect(entry!.action).toBe("delete");
      expect(entry!.userId).not.toBe("unknown");
      expect(entry!.userId).toBe("u_admin");
    });

    it("says nothing about its own writes, or it would never stop", async () => {
      await clearLog();
      await onWrite({
        data: {
          before: fft.firestore.makeDocumentSnapshot({}, `schools/${SCHOOL}/auditLog/x`),
          after: fft.firestore.makeDocumentSnapshot({a: 1}, `schools/${SCHOOL}/auditLog/x`),
        },
        params: {schoolId: SCHOOL, collectionId: "auditLog", docId: "x"},
      } as never);
      const snap = await db().collection(FirestorePaths.auditLog(SCHOOL)).get();
      expect(snap.docs).toHaveLength(0);
    });
  });

  describe("what it must not copy", () => {
    it("records that a conversation changed without recording what was said", async () => {
      // The defect. `firestore.rules` says nobody but the two
      // participants reads a thread -- "not an admin, not the director"
      // -- and the log is read by both of them school-wide.
      const entry = await auditOf(
        "conversations",
        "conv_1",
        {
          participantUids: ["u_faculty", "u_parent"],
          studentName: "Miguel Torres",
          lastMessage: "He has been absent three times this week.",
        },
        {
          participantUids: ["u_faculty", "u_parent"],
          studentName: "Miguel Torres",
          lastMessage: "Thank you po. I will talk to him tonight.",
          updatedBy: "u_faculty",
        }
      );

      // The fact of it is still recorded: who, when, which thread.
      expect(entry!.module).toBe("conversations");
      expect(entry!.targetId).toBe("conv_1");
      expect(entry!.action).toBe("update");

      const asText = JSON.stringify(entry);
      expect(asText).not.toContain("absent three times");
      expect(asText).not.toContain("talk to him tonight");
    });

    it("and says plainly that it withheld it, rather than looking empty", async () => {
      const entry = await auditOf("conversations", "conv_1", null, {
        participantUids: ["u_faculty", "u_parent"],
        lastMessage: "Good morning po.",
        createdBy: "u_faculty",
      });
      expect(String(entry!.remarks ?? "")).toMatch(/not recorded|withheld|redact/i);
    });

    it("still copies an ordinary record in full", async () => {
      // The redaction is a short, named list -- not a general retreat
      // from recording what changed.
      const entry = await auditOf("expenses", "exp_2", null, {
        category: "Repairs",
        description: "Roof of the covered court",
        updatedBy: "u_admin",
      });
      expect((entry!.newValue as Record<string, unknown>).description)
        .toBe("Roof of the covered court");
    });
  });
});
