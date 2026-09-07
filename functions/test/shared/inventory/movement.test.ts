import {
  MOVEMENT_DIRECTION,
  MovementError,
  applyMovement,
  effectOf,
  isMovementKind,
  needsRecipient,
  round3,
  stockFromMovements,
  validateMovement,
} from "../../../src/shared/inventory/movement";

/**
 * The stock room's arithmetic.
 *
 * The two things being pinned here are the ones the client-side version
 * got wrong: that a quantity which is not a number is refused rather
 * than waved past by a comparison, and that the below-zero test is a
 * function of what is actually on hand rather than of what somebody was
 * looking at.
 */

const issue = (quantity: number) => validateMovement({kind: "issued", quantity, issuedTo: "Room 204"});

describe("what a movement may be", () => {
  it("knows the five kinds and refuses anything else", () => {
    for (const kind of ["received", "issued", "returned", "adjusted", "written_off"]) {
      expect(isMovementKind(kind)).toBe(true);
    }
    expect(isMovementKind("borrowed")).toBe(false);
    expect(() => validateMovement({kind: "borrowed", quantity: 1})).toThrow(MovementError);
  });

  it("moves the count the way the kind says", () => {
    expect(MOVEMENT_DIRECTION.received).toBe(1);
    expect(MOVEMENT_DIRECTION.returned).toBe(1);
    expect(MOVEMENT_DIRECTION.issued).toBe(-1);
    expect(MOVEMENT_DIRECTION.written_off).toBe(-1);
    // Zero, because a stock count's quantity carries its own sign -- it
    // is the one place a negative means something.
    expect(MOVEMENT_DIRECTION.adjusted).toBe(0);
    expect(effectOf("adjusted", -3)).toBe(-3);
    expect(effectOf("issued", 3)).toBe(-3);
  });

  it("refuses a quantity that is not a number", () => {
    // The bug this exists for. `NaN <= 0` and `NaN === 0` are both
    // false, so a guard written as a comparison waves NaN straight
    // through -- and `double.tryParse('NaN')` on the client returns NaN
    // for one word typed into the quantity box. Once NaN reaches the
    // total, everything added to it stays NaN.
    for (const bad of [NaN, Infinity, -Infinity, "lots", null, undefined, {}]) {
      expect(() => validateMovement({kind: "received", quantity: bad})).toThrow(
        /has to be a number/i
      );
      expect(() => validateMovement({kind: "adjusted", quantity: bad})).toThrow(
        /has to be a number/i
      );
    }
  });

  it("refuses a movement of nothing, and points at the stock count", () => {
    for (const kind of ["received", "issued", "returned", "written_off"] as const) {
      expect(() => validateMovement({kind, quantity: 0, issuedTo: "Room 204"}))
        .toThrow(/has to be of something/i);
      expect(() => validateMovement({kind, quantity: -2, issuedTo: "Room 204"}))
        .toThrow(/has to be of something/i);
    }
  });

  it("lets a stock count go either way, but not nowhere", () => {
    expect(validateMovement({kind: "adjusted", quantity: -3}).effect).toBe(-3);
    expect(validateMovement({kind: "adjusted", quantity: 3}).effect).toBe(3);
    expect(() => validateMovement({kind: "adjusted", quantity: 0})).toThrow(
      /changes nothing/i
    );
  });

  it("insists on a name for an issue, and only for an issue", () => {
    // "Where is the good projector" is the question this module exists
    // to answer, and a movement out with nobody on it leaves the same
    // shrug the logbook did.
    expect(needsRecipient("issued")).toBe(true);
    expect(() => validateMovement({kind: "issued", quantity: 1})).toThrow(/going to/i);
    expect(() => validateMovement({kind: "issued", quantity: 1, issuedTo: "   "}))
      .toThrow(/going to/i);
    expect(validateMovement({kind: "issued", quantity: 1, issuedTo: " Room 204 "}).issuedTo)
      .toBe("Room 204");
    // A delivery has nobody on it and is not supposed to.
    expect(validateMovement({kind: "received", quantity: 20}).issuedTo).toBeNull();
  });

  it("reads a blank reference or note as absent rather than as empty", () => {
    const movement = validateMovement({
      kind: "received",
      quantity: 1,
      reference: "   ",
      note: "",
    });
    expect(movement.reference).toBeNull();
    expect(movement.note).toBeNull();
  });
});

describe("what a movement does to the count", () => {
  it("adds and takes away", () => {
    expect(applyMovement(10, validateMovement({kind: "received", quantity: 5}))).toBe(15);
    expect(applyMovement(10, issue(4))).toBe(6);
  });

  it("refuses to take the count below zero, and says how many there are", () => {
    // A negative stock figure is always wrong -- either the movement is
    // a mistake or the shelf already was, and both want somebody to stop
    // and count rather than a number that cannot be true.
    expect(() => applyMovement(2, issue(3))).toThrow(/only 2 on hand/i);
    expect(() => applyMovement(2, issue(3))).toThrow(/stock count/i);
    // Exactly to zero is fine: the shelf is empty, which is a fact.
    expect(applyMovement(2, issue(2))).toBe(0);
  });

  it("checks against what is on hand, not against anything sent", () => {
    // The whole point of moving this off the device. The old check ran
    // against the copy of the item the screen was holding, so two people
    // issuing the last two projectors at once both passed it.
    expect(() => applyMovement(1, issue(2))).toThrow();
    expect(applyMovement(5, issue(2))).toBe(3);
  });

  it("treats an unreadable stored total as zero rather than spreading it", () => {
    // A document that already holds a NaN -- written before the guard
    // above existed -- must not make every later movement NaN as well.
    expect(applyMovement(NaN, validateMovement({kind: "received", quantity: 5}))).toBe(5);
  });

  it("keeps three decimals without drifting", () => {
    // Stock is counted in halves and quarters often enough: half a
    // litre, a quarter ream.
    let onHand = 0;
    for (let i = 0; i < 10; i++) {
      onHand = applyMovement(onHand, validateMovement({kind: "received", quantity: 0.1}));
    }
    expect(onHand).toBe(1);
    expect(round3(0.1 + 0.2)).toBe(0.3);
  });
});

describe("the reconciliation", () => {
  it("is what the movements add up to", () => {
    // The check that the running total has not drifted. A stock figure
    // nobody can trace back to a movement is the spreadsheet this
    // replaces.
    expect(
      stockFromMovements([
        {kind: "received", quantity: 20},
        {kind: "issued", quantity: 3},
        {kind: "returned", quantity: 1},
        {kind: "written_off", quantity: 2},
        {kind: "adjusted", quantity: -1},
      ])
    ).toBe(15);
  });

  it("is zero for a log with nothing in it", () => {
    expect(stockFromMovements([])).toBe(0);
  });
});
