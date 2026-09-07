/**
 * One movement of one thing in or out of the stock room.
 *
 * A port of `app/lib/features/inventory/domain/entities/inventory_item.dart`,
 * and here for the reason `recordPayment` and `runPayroll` are here: the
 * quantity on an item is a running total, the movement log is the record
 * it is supposed to be derivable from, and neither of those survives the
 * client being the one that decides.
 *
 * Two specific things it fixes, both of which the old client-side
 * transaction claimed and did not do:
 *
 *   * The below-zero check ran against the copy of the item the screen
 *     was holding. Two people issuing the last two projectors at once
 *     both passed it, and the shelf went to -2 -- the exact case the
 *     transaction was written for, with a comment saying so.
 *   * `quantity` was checked with `<= 0`, which is false for NaN.
 *     `double.tryParse('NaN')` returns NaN, so typing it into the
 *     quantity box wrote NaN into the item's total, permanently: every
 *     later movement added to NaN and stayed there.
 */

export const MOVEMENT_KINDS = [
  "received",
  "issued",
  "returned",
  "adjusted",
  "written_off",
] as const;

export type MovementKind = (typeof MOVEMENT_KINDS)[number];

export const MOVEMENT_LABELS: Record<MovementKind, string> = {
  received: "Received",
  issued: "Issued",
  returned: "Returned",
  adjusted: "Stock count",
  written_off: "Written off",
};

/**
 * Which way a kind moves the count.
 *
 * Zero for a stock count, whose quantity carries its own sign -- it is
 * the one place a negative quantity means something, because the count
 * can disagree with the books in either direction.
 */
export const MOVEMENT_DIRECTION: Record<MovementKind, number> = {
  received: 1,
  issued: -1,
  returned: 1,
  adjusted: 0,
  written_off: -1,
};

export function isMovementKind(value: unknown): value is MovementKind {
  return (MOVEMENT_KINDS as readonly string[]).includes(String(value));
}

/**
 * Whether this movement needs somebody's name against it.
 *
 * Issuing does: "where is the good projector" is the question this
 * module exists to answer, and a movement out with nobody on it leaves
 * the same shrug the logbook did.
 */
export function needsRecipient(kind: MovementKind): boolean {
  return kind === "issued";
}

export class MovementError extends Error {}

/** Three decimal places, rounding a half away from zero. */
export function round3(value: number): number {
  const scaled = value * 1000;
  const rounded = scaled < 0 ? -Math.round(-scaled) : Math.round(scaled);
  return rounded / 1000 + 0;
}

/** The signed effect of a movement on the count. */
export function effectOf(kind: MovementKind, quantity: number): number {
  return kind === "adjusted" ? quantity : quantity * MOVEMENT_DIRECTION[kind];
}

export interface ValidatedMovement {
  kind: MovementKind;
  quantity: number;
  effect: number;
  issuedTo: string | null;
  reference: string | null;
  note: string | null;
}

function trimmed(raw: unknown): string | null {
  if (typeof raw !== "string") return null;
  const value = raw.trim();
  return value.length === 0 ? null : value;
}

/**
 * Everything about a movement that can be judged without the item.
 *
 * `Number.isFinite` rather than a comparison, because the comparisons
 * are what let NaN through: `NaN <= 0` and `NaN === 0` are both false,
 * so every guard written as a comparison waves it past. Infinity is
 * refused for the same reason -- `1e400` parses to it, and a total of
 * Infinity is as unrecoverable as a total of NaN.
 */
export function validateMovement(input: {
  kind: unknown;
  quantity: unknown;
  issuedTo?: unknown;
  reference?: unknown;
  note?: unknown;
}): ValidatedMovement {
  if (!isMovementKind(input.kind)) {
    throw new MovementError("That is not a kind of movement this records.");
  }
  const kind = input.kind;

  // Not `Number(raw)`: that reads null as 0 and "" as 0, so a missing
  // quantity would be refused a step later with "a movement has to be of
  // something" -- a true sentence about the wrong problem, which is the
  // kind of message that sends somebody back to the shelf to recount.
  const raw = input.quantity;
  const quantity =
    typeof raw === "number"
      ? raw
      : typeof raw === "string" && raw.trim().length > 0
        ? Number(raw.trim())
        : NaN;
  if (!Number.isFinite(quantity)) {
    throw new MovementError("A quantity has to be a number.");
  }

  if (kind === "adjusted") {
    if (quantity === 0) {
      throw new MovementError(
        "A stock count that changes nothing is not worth recording."
      );
    }
  } else if (quantity <= 0) {
    throw new MovementError(
      "A movement has to be of something. Use a stock count to correct a " +
        "figure downwards."
    );
  }

  const issuedTo = trimmed(input.issuedTo);
  if (needsRecipient(kind) && issuedTo === null) {
    throw new MovementError("Who or where is it going to? A person, or a room.");
  }

  return {
    kind,
    quantity: round3(quantity),
    effect: round3(effectOf(kind, quantity)),
    issuedTo,
    reference: trimmed(input.reference),
    note: trimmed(input.note),
  };
}

/**
 * The new total, or a refusal.
 *
 * Separate from `validateMovement` because this is the half that needs
 * the item, and the half that has to run inside the transaction against
 * what is actually on file rather than against what a screen was showing
 * a moment ago.
 *
 * Below zero is refused rather than allowed and flagged. A negative
 * stock figure is always wrong -- either the movement is a mistake or
 * the shelf was already wrong, and both want somebody to stop and count
 * rather than a number that cannot be true.
 */
export function applyMovement(
  onHand: number,
  movement: ValidatedMovement
): number {
  const current = Number.isFinite(onHand) ? onHand : 0;
  const next = round3(current + movement.effect);
  if (next < 0) {
    throw new MovementError(
      `There ${current === 1 ? "is" : "are"} only ${round3(current)} on hand.` +
        " Record a stock count first if the shelf disagrees with the books."
    );
  }
  return next;
}

/** What the movements say the stock should be. */
export function stockFromMovements(
  movements: Iterable<{kind: MovementKind; quantity: number}>
): number {
  let total = 0;
  for (const movement of movements) total += effectOf(movement.kind, movement.quantity);
  return round3(total);
}
