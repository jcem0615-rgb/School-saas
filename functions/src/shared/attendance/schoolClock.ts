import * as admin from "firebase-admin";
import {FirestorePaths} from "../firestore-paths";

/**
 * What day it is where the school is.
 *
 * Every attendance record in this system is filed under a `YYYY-MM-DD`
 * key, and that key has to be the school's day rather than the server's.
 * A class opened at 7:30 in Manila is 23:30 the previous day in UTC, so
 * a date taken from the server clock files every early class under
 * yesterday -- which is not a rounding error, it is a register that says
 * a child was in two Physics lessons on Tuesday and none on Wednesday.
 */

/** The school's IANA timezone, or Manila. */
export async function schoolTimezone(schoolId: string): Promise<string> {
  // On the platform-level school record, which clients cannot touch.
  // Admin SDK reads bypass rules, so this is safe to read here.
  const snap = await admin
    .firestore()
    .doc(FirestorePaths.platformSchoolDoc(schoolId))
    .get();
  return (snap.data()?.timezone as string) ?? "Asia/Manila";
}

/** 'YYYY-MM-DD' in that timezone. en-CA formats exactly that way. */
export function schoolDateKey(at: Date, timezone: string): string {
  return new Intl.DateTimeFormat("en-CA", {timeZone: timezone}).format(at);
}
