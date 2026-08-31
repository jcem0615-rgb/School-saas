import {HttpsError} from "firebase-functions/v2/https";

/** One subsidy, as it arrives from a client. */
export interface SubsidyData {
  programme?: string;
  referenceNumber?: string;
  amount?: number;
  remarks?: string | null;
}

/** One subsidy, as it is stored. */
export interface StoredSubsidy {
  programme: string;
  referenceNumber: string;
  amount: number;
  remarks: string | null;
  recordedByName: string;
}

const VALID_PROGRAMMES = ["esc", "shs_voucher", "other"];

/**
 * A student on both ESC and a city scholarship is two; more than four is
 * somebody pasting.
 */
const MAX_SUBSIDIES = 4;

const round2 = (value: number) => Math.round(value * 100) / 100;

/**
 * Validates the subsidies on an assessment.
 *
 * The reference number is required, and that is the whole discipline of
 * this feature. A subsidy with no certificate behind it is one the school
 * cannot bill for, so a family charged less on the strength of it is a
 * family the school has quietly given money to -- the exact mistake this
 * is meant to prevent, arrived at from the other direction.
 *
 * The ceiling is checked against what is left after discounts, not
 * against the gross. A student with a 10% sibling discount and an ESC
 * grant must not have the two together exceed the fees, and checking the
 * subsidy against the gross alone would let them.
 */
export function validateSubsidies(
  raw: SubsidyData[] | undefined,
  remainingAfterDiscounts: number,
  recordedByName: string
): {subsidies: StoredSubsidy[]; subsidyTotal: number} {
  if (raw === undefined || raw === null) return {subsidies: [], subsidyTotal: 0};
  if (!Array.isArray(raw)) {
    throw new HttpsError("invalid-argument", "The subsidies are malformed.");
  }
  if (raw.length === 0) return {subsidies: [], subsidyTotal: 0};
  if (raw.length > MAX_SUBSIDIES) {
    throw new HttpsError(
      "invalid-argument",
      `An assessment cannot carry more than ${MAX_SUBSIDIES} subsidies.`
    );
  }

  const seen = new Set<string>();
  let running = 0;

  const subsidies: StoredSubsidy[] = raw.map((entry) => {
    const programme = VALID_PROGRAMMES.includes(entry?.programme ?? "")
      ? entry!.programme!
      : "other";

    const referenceNumber = (entry?.referenceNumber ?? "").trim();
    if (!referenceNumber) {
      throw new HttpsError(
        "invalid-argument",
        "A subsidy needs the certificate or voucher number it will be " +
          "claimed against. Without one the school cannot bill for it, and " +
          "the family has simply been charged less."
      );
    }
    // Two lines citing one certificate is a double claim, and PEAC will
    // reject the second -- after the family has already been charged as
    // though both were coming.
    const key = `${programme}|${referenceNumber.toLowerCase()}`;
    if (seen.has(key)) {
      throw new HttpsError(
        "invalid-argument",
        `${referenceNumber} appears twice on this assessment. One ` +
          "certificate is claimed once."
      );
    }
    seen.add(key);

    const amount = Number(entry?.amount);
    if (!Number.isFinite(amount) || amount <= 0) {
      throw new HttpsError(
        "invalid-argument",
        `The subsidy against ${referenceNumber} must be more than zero.`
      );
    }

    running += amount;
    return {
      programme,
      referenceNumber,
      amount: round2(amount),
      remarks: (entry?.remarks ?? "")?.trim() || null,
      // From the caller's token, like a discount's approver.
      recordedByName,
    };
  });

  const subsidyTotal = round2(running);
  if (subsidyTotal > round2(remainingAfterDiscounts)) {
    throw new HttpsError(
      "invalid-argument",
      `The subsidies come to ${subsidyTotal.toFixed(2)} against ` +
        `${round2(remainingAfterDiscounts).toFixed(2)} still chargeable after ` +
        "discounts. A grant can cover the whole of what is left and no more."
    );
  }

  return {subsidies, subsidyTotal};
}
