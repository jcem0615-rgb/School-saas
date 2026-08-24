import * as admin from "firebase-admin";
import {CallableRequest, HttpsError} from "firebase-functions/v2/https";

/**
 * Shape of the custom claims embedded in every user's ID token.
 * `schoolId` is undefined for the platform-level Owner account.
 */
export interface AppClaims {
  schoolId?: string;
  role: string;
  status: "pending_approval" | "active" | "suspended";
  mustChangePassword: boolean;
}

/**
 * Sets custom claims for a user. This is the ONLY function in the codebase
 * allowed to call admin.auth().setCustomUserClaims -- funneling every claim
 * write through one function makes the claim shape impossible to drift
 * between different call sites.
 */
export async function setUserClaims(uid: string, claims: AppClaims): Promise<void> {
  await admin.auth().setCustomUserClaims(uid, {...claims});
}

/**
 * Extracts and validates the caller's claims from a callable request's
 * auth context. Throws HttpsError('unauthenticated') if there is no
 * signed-in caller at all -- every privileged callable function must call
 * this first, before touching Firestore.
 */
export function requireCallerClaims(request: CallableRequest): AppClaims {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "You must be signed in to perform this action.");
  }
  const token = request.auth.token;
  const role = token.role as string | undefined;
  if (!role) {
    throw new HttpsError(
      "failed-precondition",
      "Your account is not fully provisioned. Contact your administrator."
    );
  }
  return {
    schoolId: token.schoolId as string | undefined,
    role,
    status: (token.status as AppClaims["status"]) ?? "active",
    mustChangePassword: (token.mustChangePassword as boolean) ?? false,
  };
}

/** Throws PermissionDenied unless the caller's role is in [allowedRoles]. */
export function requireRole(claims: AppClaims, allowedRoles: string[]): void {
  if (!allowedRoles.includes(claims.role)) {
    throw new HttpsError(
      "permission-denied",
      `This action requires one of the following roles: ${allowedRoles.join(", ")}.`
    );
  }
}

/** Throws PermissionDenied unless the caller belongs to [schoolId]. */
export function requireSameSchool(claims: AppClaims, schoolId: string): void {
  if (claims.schoolId !== schoolId) {
    throw new HttpsError("permission-denied", "You do not have access to this school's data.");
  }
}
