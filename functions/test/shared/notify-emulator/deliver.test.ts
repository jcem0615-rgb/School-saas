/**
 * Requires the Firestore emulator.
 * Run via: firebase emulators:exec --only firestore "jest test/shared/notify-emulator"
 *
 * What "notify somebody" is allowed to mean.
 *
 * `deliver` is the one place in the system that writes an inbox item and
 * sends a push, so the guarantees it makes are the guarantees every
 * notification in the app has. Three are pinned here: the durable half
 * survives a retried trigger, the fast half cannot take the trigger down
 * with it, and a caller's own payload cannot quietly redirect where the
 * notification opens.
 */
import * as admin from "firebase-admin";
import {FirestorePaths} from "../../../src/shared/firestore-paths";
import {deliver} from "../../../src/shared/notify/deliver";

const SCHOOL = "school_notify";

function db() {
  return admin.firestore();
}

/** The push FCM was asked to send, or null if it was never asked. */
let lastSend: Record<string, unknown> | null = null;
let sendResult: {responses: Array<{success: boolean; error?: {code: string}}>} = {
  responses: [{success: true}],
};
let sendThrows = false;

async function inboxOf(uid: string) {
  const snap = await db()
    .collection(`${FirestorePaths.school(SCHOOL)}/notifications/${uid}/items`)
    .get();
  return snap.docs.map((d) => ({id: d.id, ...d.data()}));
}

async function clearAll() {
  const snap = await db().collectionGroup("items").get();
  await Promise.all(
    snap.docs
      .filter((d) => d.ref.path.startsWith(`schools/${SCHOOL}/`))
      .map((d) => d.ref.delete())
  );
  // listDocuments, not get: these tests register device tokens under
  // user documents they never create, and a subcollection under a
  // missing parent is invisible to a read of the parent collection. A
  // token surviving into the next test is a push nobody asked for.
  const users = await db().collection(FirestorePaths.users(SCHOOL)).listDocuments();
  await Promise.all(
    users.map(async (ref) => {
      const tokens = await ref.collection("deviceTokens").get();
      await Promise.all(tokens.docs.map((t) => t.ref.delete()));
      await ref.delete();
    })
  );
}

async function giveDevice(uid: string, token: string) {
  await db()
    .doc(`${FirestorePaths.userDoc(SCHOOL, uid)}/deviceTokens/${token}`)
    .set({createdAt: new Date()});
}

const base = {
  schoolId: SCHOOL,
  kind: "announcement" as const,
  title: "Classes suspended",
  body: "No classes tomorrow.",
  link: "/announcements",
  sourceId: "ann_1",
};

describe("delivering a notification", () => {
  beforeAll(() => {
    if (admin.apps.length === 0) {
      admin.initializeApp({projectId: "school-saas-test"});
    }
    jest.spyOn(admin, "messaging").mockReturnValue({
      sendEachForMulticast: async (message: Record<string, unknown>) => {
        lastSend = message;
        if (sendThrows) throw new Error("FCM is having a day");
        return sendResult;
      },
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
    } as any);
  });

  afterAll(() => {
    jest.restoreAllMocks();
  });

  beforeEach(async () => {
    lastSend = null;
    sendThrows = false;
    sendResult = {responses: [{success: true}]};
    await clearAll();
  });

  describe("the durable half", () => {
    it("writes one item per recipient and nobody else", async () => {
      const result = await deliver({...base, recipientUids: ["u_a", "u_b"]});
      expect(result.delivered).toBe(2);
      expect(await inboxOf("u_a")).toHaveLength(1);
      expect(await inboxOf("u_b")).toHaveLength(1);
      expect(await inboxOf("u_c")).toHaveLength(0);
    });

    it("carries the whole body, not the push preview", async () => {
      // The lock screen gets a line; the inbox is where somebody reads
      // what was actually said.
      const long = "x".repeat(400);
      await giveDevice("u_a", "tok_a");
      await deliver({...base, body: long, recipientUids: ["u_a"]});
      expect((await inboxOf("u_a"))[0].body).toBe(long);
      expect(String((lastSend!.notification as Record<string, string>).body))
        .toHaveLength(180);
    });

    it("is safe to run twice, which a trigger is", async () => {
      // Cloud Functions delivers at least once. A second run must not
      // mark an already-read notification unread again, so this uses
      // `create` and swallows ALREADY_EXISTS.
      await deliver({...base, recipientUids: ["u_a"]});
      const items = await inboxOf("u_a");
      await db()
        .doc(`${FirestorePaths.school(SCHOOL)}/notifications/u_a/items/${items[0].id}`)
        .update({isRead: true});

      const second = await deliver({...base, recipientUids: ["u_a"]});

      expect(second.delivered).toBe(0);
      const after = await inboxOf("u_a");
      expect(after).toHaveLength(1);
      expect(after[0].isRead).toBe(true);
    });

    it("collapses somebody who qualifies twice", async () => {
      const result = await deliver({...base, recipientUids: ["u_a", "u_a", "u_a"]});
      expect(result.delivered).toBe(1);
    });

    it("does nothing at all for an empty list", async () => {
      const result = await deliver({...base, recipientUids: []});
      expect(result).toEqual({delivered: 0, pushed: 0, pruned: 0});
      expect(lastSend).toBeNull();
    });
  });

  describe("what the push carries", () => {
    it("cannot have its routing keys overwritten by the caller", async () => {
      // The defect this pins: `data` was spread AFTER the routing keys,
      // so a caller passing `link` -- or `type`, or `schoolId` -- would
      // silently replace the key the app navigates by, and the
      // notification would open somewhere else or nowhere. No caller did;
      // the ordering is what makes sure none can.
      await giveDevice("u_a", "tok_a");
      await deliver({
        ...base,
        recipientUids: ["u_a"],
        data: {
          link: "/somewhere-else",
          type: "general",
          schoolId: "another_school",
          sourceId: "not_this_one",
          announcementId: "ann_1",
        },
      });

      const data = lastSend!.data as Record<string, string>;
      expect(data.link).toBe("/announcements");
      expect(data.type).toBe("announcement");
      expect(data.schoolId).toBe(SCHOOL);
      expect(data.sourceId).toBe("ann_1");
      // The caller's own keys still come through; only the four the app
      // routes on are held.
      expect(data.announcementId).toBe("ann_1");
    });

    it("rings through when it is urgent, and does not otherwise", async () => {
      await giveDevice("u_a", "tok_a");

      await deliver({...base, recipientUids: ["u_a"], kind: "emergency", urgent: true});
      expect((lastSend!.android as Record<string, string>).priority).toBe("high");
      expect((lastSend!.webpush as Record<string, unknown>).headers)
        .toEqual({Urgency: "high"});

      await clearAll();
      await giveDevice("u_a", "tok_a");
      await deliver({...base, recipientUids: ["u_a"]});
      expect(lastSend!.android).toBeUndefined();
    });
  });

  describe("the fast half never takes the trigger down", () => {
    it("still writes the inbox when FCM throws", async () => {
      // A thrown trigger is a retried trigger, and a retried fan-out
      // notifies a whole school twice.
      sendThrows = true;
      await giveDevice("u_a", "tok_a");

      const result = await deliver({...base, recipientUids: ["u_a"]});

      expect(result.pushed).toBe(0);
      expect(result.delivered).toBe(1);
      expect(await inboxOf("u_a")).toHaveLength(1);
    });

    it("prunes a token FCM says is dead", async () => {
      // Otherwise the list grows forever with every reinstalled app, and
      // each send spends a slot on a device that will never receive.
      await giveDevice("u_a", "tok_dead");
      sendResult = {
        responses: [
          {success: false, error: {code: "messaging/registration-token-not-registered"}},
        ],
      };

      const result = await deliver({...base, recipientUids: ["u_a"]});

      expect(result.pruned).toBe(1);
      const left = await db()
        .collection(`${FirestorePaths.userDoc(SCHOOL, "u_a")}/deviceTokens`)
        .get();
      expect(left.empty).toBe(true);
    });

    it("keeps a token that failed for some other reason", async () => {
      // A transient server error is not a dead device. Deleting on any
      // failure would quietly unsubscribe a working phone.
      await giveDevice("u_a", "tok_ok");
      sendResult = {
        responses: [{success: false, error: {code: "messaging/server-unavailable"}}],
      };

      const result = await deliver({...base, recipientUids: ["u_a"]});

      expect(result.pruned).toBe(0);
      const left = await db()
        .collection(`${FirestorePaths.userDoc(SCHOOL, "u_a")}/deviceTokens`)
        .get();
      expect(left.size).toBe(1);
    });

    it("sends nothing when nobody has a device registered", async () => {
      const result = await deliver({...base, recipientUids: ["u_a"]});
      expect(result).toMatchObject({delivered: 1, pushed: 0, pruned: 0});
      expect(lastSend).toBeNull();
    });
  });
});
