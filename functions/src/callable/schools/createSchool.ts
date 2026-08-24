import * as admin from "firebase-admin";
import {onCall, HttpsError, CallableRequest} from "firebase-functions/v2/https";
import {requireCallerClaims} from "../../shared/auth/claims";
import {writeOwnerAuditLog} from "../../shared/audit/writeOwnerAuditLog";
import {FirestorePaths} from "../../shared/firestore-paths";

interface CreateSchoolData {
  name: string;
  /**
   * Optional human-chosen document id, e.g. "sacred-heart-batangas".
   * Left out, one is generated. It is the id in all three collections and
   * in every tenant path underneath, so it cannot be changed later.
   */
  schoolId?: string;
  addressLine?: string;
  contactEmail?: string;
  contactPhone?: string;
  /** PHP per active student per billing cycle. */
  billingRatePerStudent: number;
}

/** Lowercase, digits and single hyphens: safe in a Firestore path. */
const SCHOOL_ID_PATTERN = /^[a-z0-9]+(-[a-z0-9]+)*$/;

function slugify(name: string): string {
  return name
    .toLowerCase()
    // NFKD splits an accented letter into a plain one plus a combining
    // mark; dropping those marks is what turns "Muñoz" into "munoz"
    // rather than "mun-oz", which is what happens when the tilde falls
    // through to the non-alphanumeric rule below. Filipino school names
    // carry enough enyes for that to matter.
    .normalize("NFKD")
    .replace(/[\u0300-\u036f]/g, "")
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .slice(0, 48);
}

/**
 * Creates a school. Owner only.
 *
 * A school is not one document. The Owner's list is a join of
 * platform_schools (name, logo) and platform_subscriptions (status,
 * billing), and the tenant itself needs a schools/{id} profile before
 * anyone inside it can read anything. Half a school -- a profile with no
 * subscription, or a subscription with no profile -- is invisible in the
 * Owner's list and unusable by its Director, so all three are written in
 * one transaction and the id is claimed in the same breath.
 */
export const createSchool = onCall(
  {region: "asia-southeast1"},
  async (request: CallableRequest<CreateSchoolData>) => {
    const callerClaims = requireCallerClaims(request);
    if (callerClaims.role !== "owner") {
      throw new HttpsError("permission-denied", "Only the owner can create a school.");
    }

    const {name, addressLine, contactEmail, contactPhone, billingRatePerStudent} =
      request.data ?? ({} as CreateSchoolData);

    if (!name || !name.trim()) {
      throw new HttpsError("invalid-argument", "The school needs a name.");
    }
    if (
      typeof billingRatePerStudent !== "number" ||
      !isFinite(billingRatePerStudent) ||
      billingRatePerStudent < 0
    ) {
      throw new HttpsError("invalid-argument", "Billing rate must be zero or more.");
    }

    const schoolId = (request.data.schoolId ?? slugify(name)).trim();
    if (!SCHOOL_ID_PATTERN.test(schoolId)) {
      throw new HttpsError(
        "invalid-argument",
        "School id must be lowercase letters, digits and hyphens."
      );
    }

    const db = admin.firestore();
    const platformRef = db.doc(FirestorePaths.platformSchoolDoc(schoolId));
    const subscriptionRef = db.doc(FirestorePaths.platformSubscriptionDoc(schoolId));
    const profileRef = db.doc(`schools/${schoolId}`);

    const now = admin.firestore.FieldValue.serverTimestamp();
    const actorUid = request.auth!.uid;

    await db.runTransaction(async (tx) => {
      // Reads first: a Firestore transaction rejects a read issued after
      // a write.
      const existing = await tx.get(platformRef);
      if (existing.exists) {
        throw new HttpsError(
          "already-exists",
          `A school with the id "${schoolId}" already exists.`
        );
      }

      tx.set(platformRef, {
        id: schoolId,
        name: name.trim(),
        logoUrl: null,
        addressLine: addressLine?.trim() || null,
        contactEmail: contactEmail?.trim().toLowerCase() || null,
        contactPhone: contactPhone?.trim() || null,
        billingRatePerStudent,
        createdAt: now,
        createdByUid: actorUid,
      });

      // Active from the moment it exists, with the counters the billing
      // job maintains started at zero. Without this doc the school is
      // filtered out of the Owner's list entirely -- watchSchools drops
      // any platform_schools row that has no matching subscription.
      tx.set(subscriptionRef, {
        schoolId,
        currentStatus: "active",
        activeStudentCountSnapshot: 0,
        currentCycleAccrued: 0,
        billingRatePerStudent,
        gracePeriodStartedAt: null,
        suspendedAt: null,
        createdAt: now,
      });

      // The tenant-side profile. Everyone inside the school reads this;
      // its absence is what makes a Director's first sign-in show an
      // unnamed, empty school.
      tx.set(profileRef, {
        id: schoolId,
        name: name.trim(),
        addressLine: addressLine?.trim() || null,
        contactEmail: contactEmail?.trim().toLowerCase() || null,
        contactPhone: contactPhone?.trim() || null,
        logoUrl: null,
        createdAt: now,
      });
    });

    await writeOwnerAuditLog({
      actorUid,
      actorEmail: request.auth?.token.email ?? null,
      action: "school.created",
      targetType: "school",
      targetId: schoolId,
      details: {name: name.trim(), billingRatePerStudent},
    });

    return {schoolId};
  }
);
