import {HttpsError} from "firebase-functions/v2/https";

/** One discount, as it arrives from a client. */
export interface DiscountData {
  kind?: string;
  label?: string;
  amount?: number;
  percentage?: number | null;
  appliesTo?: string | null;
}

/** One discount, as it is stored. */
export interface StoredDiscount {
  kind: string;
  label: string;
  amount: number;
  percentage: number | null;
  appliesTo: string | null;
  approvedByName: string;
}

const VALID_KINDS = [
  "sibling",
  "early_bird",
  "employee_child",
  "alumni",
  "academic",
  "financial_aid",
  "other",
];

const VALID_CATEGORIES = ["tuition", "miscellaneous", "other"];

/**
 * More lines than this is somebody pasting, not a school granting.
 * Three or four is a busy case: sibling, early payment, and a board
 * resolution.
 */
const MAX_DISCOUNTS = 10;

const round2 = (value: number) => Math.round(value * 100) / 100;

/**
 * Validates the discounts on an assessment and returns them ready to
 * store, along with what they come to.
 *
 * The invariant: a school may give away up to the whole of what it is
 * charging, and not a centavo more. A discount larger than the fees
 * would produce a negative charge -- the school paying a family to
 * enrol -- and the balance arithmetic would happily carry it.
 *
 * The amount is taken as given rather than recomputed from the
 * percentage. That is deliberate and the reverse of what looks safer: a
 * percentage recomputed later, against fee items that can be edited
 * afterwards, would silently change what a family was granted, and the
 * printed assessment in their hand would stop matching the record. The
 * percentage is stored beside the amount for the audit trail and for the
 * line to read "Sibling discount (10% of tuition)". The client computes
 * both from the same shared function the screen showed the registrar.
 */
export function validateDiscounts(
  raw: DiscountData[] | undefined,
  grossTotal: number,
  approvedByName: string
): {discounts: StoredDiscount[]; discountTotal: number} {
  if (raw === undefined || raw === null) return {discounts: [], discountTotal: 0};
  if (!Array.isArray(raw)) {
    throw new HttpsError("invalid-argument", "The discounts are malformed.");
  }
  if (raw.length === 0) return {discounts: [], discountTotal: 0};
  if (raw.length > MAX_DISCOUNTS) {
    throw new HttpsError(
      "invalid-argument",
      `An assessment cannot carry more than ${MAX_DISCOUNTS} discounts.`
    );
  }

  let running = 0;
  const discounts: StoredDiscount[] = raw.map((entry, index) => {
    const label = (entry?.label ?? "").trim();
    if (!label) {
      throw new HttpsError(
        "invalid-argument",
        `Discount ${index + 1} has no label. A family reading the assessment ` +
          "has to know what was taken off and why."
      );
    }

    const amount = Number(entry?.amount);
    if (!Number.isFinite(amount) || amount <= 0) {
      throw new HttpsError(
        "invalid-argument",
        `"${label}" must take off more than zero. Remove the line instead.`
      );
    }

    const kind = VALID_KINDS.includes(entry?.kind ?? "") ? entry!.kind! : "other";

    const rawPercentage = entry?.percentage;
    let percentage: number | null = null;
    if (rawPercentage !== undefined && rawPercentage !== null) {
      const parsed = Number(rawPercentage);
      if (!Number.isFinite(parsed) || parsed <= 0 || parsed > 100) {
        throw new HttpsError(
          "invalid-argument",
          `"${label}" has a rate of ${rawPercentage}%. A discount is between ` +
            "0 and 100 per cent."
        );
      }
      percentage = round2(parsed);
    }

    const appliesTo =
      entry?.appliesTo && VALID_CATEGORIES.includes(entry.appliesTo)
        ? entry.appliesTo
        : null;

    running += amount;
    return {
      kind,
      label,
      amount: round2(amount),
      percentage,
      appliesTo,
      // Taken from the caller's token, never from the payload. A client
      // that could name its own approver could grant a scholarship in
      // the director's name.
      approvedByName,
    };
  });

  const discountTotal = round2(running);
  if (discountTotal > round2(grossTotal)) {
    throw new HttpsError(
      "invalid-argument",
      `The discounts come to ${discountTotal.toFixed(2)} against fees of ` +
        `${round2(grossTotal).toFixed(2)}. A school can waive the whole ` +
        "amount, but it cannot charge less than nothing."
    );
  }

  return {discounts, discountTotal};
}
