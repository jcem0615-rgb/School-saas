import * as admin from "firebase-admin";
import {FirestorePaths} from "../firestore-paths";

/**
 * One place that decides what "notify somebody" means in this system.
 *
 * It means two things, and the order matters:
 *
 *  1. An item is written to the person's inbox at
 *     `schools/{schoolId}/notifications/{uid}/items/{itemId}`. This is
 *     the dependable channel. It survives a phone that was off, a
 *     browser that never granted permission, and a token that went stale
 *     three weeks ago -- and it is still there tomorrow, which a push
 *     notification is not.
 *
 *  2. A push is sent to whatever devices that person has registered.
 *     This is the fast channel, and it is best-effort by design. A
 *     failure here is never allowed to throw, because a thrown trigger
 *     is a retried trigger, and a retried fan-out notifies everybody a
 *     second time.
 *
 * Before this existed, "notify" meant only the second one, written out
 * twice -- in the announcement trigger and the emergency trigger, each
 * with its own copy of the stale-token pruning. So a parent whose phone
 * was in a bag during a suspension notice had no way to find out that it
 * had been sent: nothing was recorded anywhere they could read.
 */

/** What kind of thing happened. Drives the icon in the app's list. */
export type NotificationKind =
  | "announcement"
  | "emergency"
  | "summons"
  | "payment"
  | "approval"
  | "general";

export interface Delivery {
  schoolId: string;
  /** Who to tell. Duplicates are collapsed; an empty list is a no-op. */
  recipientUids: string[];
  kind: NotificationKind;
  title: string;
  /** The whole message. Truncated for the push preview, not for the inbox. */
  body: string;
  /**
   * Where tapping it should land, as an in-app route ('/my-school').
   * Also used for the web push click target.
   */
  link: string;
  /**
   * What this notification is *about* -- a summons id, an announcement
   * id. Combined with `kind` it forms the inbox document id, which is
   * what makes a retried trigger overwrite nothing and duplicate
   * nothing.
   *
   * When one source can notify twice (a summons issued, then cancelled)
   * the caller must distinguish them: `${summonsId}:cancelled`.
   */
  sourceId: string;
  /** Extra values carried on the push payload. FCM requires strings. */
  data?: Record<string, string>;
  /** Bypasses batching windows and rings through. Emergencies only. */
  urgent?: boolean;
}

/** What actually happened, so callers and tests can assert on it. */
export interface DeliveryResult {
  /** Inbox items written. Excludes ones that already existed. */
  delivered: number;
  /** Devices the push reached. */
  pushed: number;
  /** Dead tokens removed on the way through. */
  pruned: number;
}

/** FCM refuses a multicast of more than 500 tokens. */
const MAX_TOKENS_PER_SEND = 500;

/** A lock-screen line, not a document. The rest is one tap away. */
const PUSH_BODY_LIMIT = 180;

export async function deliver(delivery: Delivery): Promise<DeliveryResult> {
  const uids = [...new Set(delivery.recipientUids.filter((uid) => !!uid))];
  if (uids.length === 0) return {delivered: 0, pushed: 0, pruned: 0};

  const db = admin.firestore();
  const delivered = await writeInbox(db, delivery, uids);
  const {pushed, pruned} = await push(db, delivery, uids);
  return {delivered, pushed, pruned};
}

/**
 * The durable half.
 *
 * `create`, not `set`, and the difference is the whole reason this is
 * idempotent: a Cloud Functions trigger is delivered at least once, and
 * a `set` on the second delivery would quietly mark an already-read
 * notification unread again. `create` fails on the second attempt, which
 * is exactly the outcome wanted, so ALREADY_EXISTS is swallowed and
 * everything else is not.
 */
async function writeInbox(
  db: FirebaseFirestore.Firestore,
  delivery: Delivery,
  uids: string[]
): Promise<number> {
  const itemId = `${delivery.kind}_${delivery.sourceId}`.replace(/\//g, "_");
  let delivered = 0;

  const writer = db.bulkWriter();
  writer.onWriteError((error) => {
    // 6 = ALREADY_EXISTS: this trigger already ran. Not an error.
    if (error.code === 6) return false;
    return error.failedAttempts < 3;
  });
  writer.onWriteResult(() => {
    delivered += 1;
  });

  for (const uid of uids) {
    const ref = db
      .collection(`${FirestorePaths.school(delivery.schoolId)}/notifications/${uid}/items`)
      .doc(itemId);
    // Deliberately fire-and-forget: BulkWriter batches and throttles
    // these itself, and awaiting each one in turn would serialise eight
    // hundred round trips.
    void writer.create(ref, {
      id: itemId,
      kind: delivery.kind,
      title: delivery.title,
      body: delivery.body,
      link: delivery.link,
      sourceId: delivery.sourceId,
      data: delivery.data ?? {},
      isRead: false,
      readAt: null,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    }).catch(() => {
      // Already handled in onWriteError; this only stops an unhandled
      // rejection from taking the whole function down.
    });
  }

  await writer.close();
  return delivered;
}

/**
 * The fast half. Never throws.
 *
 * Tokens live in a per-user subcollection rather than an array on the
 * user document, because `users/{uid}` is readable by everybody in the
 * school and anyone holding a token can push to that device.
 */
async function push(
  db: FirebaseFirestore.Firestore,
  delivery: Delivery,
  uids: string[]
): Promise<{pushed: number; pruned: number}> {
  try {
    const snaps = await Promise.all(
      uids.map((uid) =>
        db.collection(`${FirestorePaths.userDoc(delivery.schoolId, uid)}/deviceTokens`).get()
      )
    );

    const tokens: string[] = [];
    const refs = new Map<string, FirebaseFirestore.DocumentReference>();
    for (const snap of snaps) {
      for (const doc of snap.docs) {
        // The document id *is* the token -- that is what makes
        // registering the same device twice idempotent.
        tokens.push(doc.id);
        refs.set(doc.id, doc.ref);
      }
    }
    if (tokens.length === 0) return {pushed: 0, pruned: 0};

    const body =
      delivery.body.length > PUSH_BODY_LIMIT ?
        `${delivery.body.slice(0, PUSH_BODY_LIMIT - 3)}...` :
        delivery.body;

    let pushed = 0;
    const stale: Promise<unknown>[] = [];

    // Chunked because sendEachForMulticast rejects more than 500 tokens
    // outright. A school large enough to cross that line is a school
    // whose announcements would otherwise silently stop going out.
    for (let i = 0; i < tokens.length; i += MAX_TOKENS_PER_SEND) {
      const chunk = tokens.slice(i, i + MAX_TOKENS_PER_SEND);
      const response = await admin.messaging().sendEachForMulticast({
        tokens: chunk,
        notification: {title: delivery.title, body},
        data: {
          type: delivery.kind,
          schoolId: delivery.schoolId,
          sourceId: delivery.sourceId,
          link: delivery.link,
          ...(delivery.data ?? {}),
        },
        ...(delivery.urgent ?
          {
            android: {priority: "high" as const},
            apns: {
              payload: {aps: {sound: "default"}},
              headers: {"apns-priority": "10"},
            },
          } :
          {}),
        webpush: {
          notification: {
            icon: "/icons/Icon-192.png",
            ...(delivery.urgent ? {requireInteraction: true} : {}),
          },
          fcmOptions: {link: `/#${delivery.link}`},
          ...(delivery.urgent ? {headers: {Urgency: "high"}} : {}),
        },
      });

      response.responses.forEach((result, index) => {
        if (result.success) {
          pushed += 1;
          return;
        }
        // Prune what FCM tells us is dead. Without this the token list
        // grows forever with every reinstalled app and cleared browser,
        // and each send wastes a slot on a device that will never
        // receive again.
        if (isDeadToken(result.error?.code)) {
          const ref = refs.get(chunk[index]);
          if (ref) stale.push(ref.delete());
        }
      });
    }

    await Promise.all(stale);
    return {pushed, pruned: stale.length};
  } catch (error) {
    // A push failure must not fail the trigger. The inbox item is
    // already written, which is the part that has to be right.
    console.error("push fan-out failed", error);
    return {pushed: 0, pruned: 0};
  }
}

function isDeadToken(code?: string): boolean {
  return (
    code === "messaging/registration-token-not-registered" ||
    code === "messaging/invalid-registration-token" ||
    code === "messaging/invalid-argument"
  );
}
