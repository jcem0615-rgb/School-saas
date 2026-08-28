import {findClashes, overlaps, TimetableBlock} from "../../../src/shared/schedule/conflicts";

/**
 * The client checks clashes too, so an admin is told before the round
 * trip. This is the copy that has to be right: a callable is reachable
 * without going through that screen.
 */
const block = (over: Partial<TimetableBlock> = {}): TimetableBlock => ({
  id: "b1",
  subject: "Mathematics",
  section: "Grade 10 - Rizal",
  teacherId: "u_faculty",
  teacherName: "Maria Santos",
  room: "Room 201",
  dayOfWeek: 1,
  startMinute: 450,
  endMinute: 510,
  schoolYear: "2026-2027",
  ...over,
});

describe("overlaps", () => {
  // Back-to-back is how every timetable in the country is written.
  it("does not treat touching ends as an overlap", () => {
    expect(overlaps(block({endMinute: 510}), block({id: "b2", startMinute: 510, endMinute: 570})))
      .toBe(false);
  });

  it("catches a partial overlap from either side", () => {
    const a = block({startMinute: 450, endMinute: 510});
    const b = block({id: "b2", startMinute: 500, endMinute: 560});
    expect(overlaps(a, b)).toBe(true);
    expect(overlaps(b, a)).toBe(true);
  });

  it("catches a class wholly inside another", () => {
    const outer = block({startMinute: 450, endMinute: 570});
    const inner = block({id: "b2", startMinute: 480, endMinute: 500});
    expect(overlaps(outer, inner)).toBe(true);
  });

  it("ignores a different day", () => {
    expect(overlaps(block({dayOfWeek: 1}), block({id: "b2", dayOfWeek: 2}))).toBe(false);
  });
});

describe("findClashes", () => {
  it("catches a teacher in two places at once", () => {
    const clashes = findClashes(
      block({id: undefined, section: "Grade 9 - Mabini", room: "Room 105"}),
      [block()]
    );
    expect(clashes.map((c) => c.kind)).toEqual(["teacher"]);
  });

  it("catches a section booked twice", () => {
    const clashes = findClashes(
      block({id: undefined, teacherId: "u_other", room: "Room 105"}),
      [block()]
    );
    expect(clashes.map((c) => c.kind)).toEqual(["section"]);
  });

  it("catches a room booked twice", () => {
    const clashes = findClashes(
      block({id: undefined, teacherId: "u_other", section: "Grade 9 - Mabini"}),
      [block()]
    );
    expect(clashes.map((c) => c.kind)).toEqual(["room"]);
  });

  it("reports every clash at once rather than the first", () => {
    const clashes = findClashes(block({id: undefined}), [block()]);
    expect(new Set(clashes.map((c) => c.kind))).toEqual(new Set(["teacher", "section", "room"]));
  });

  // Punishing schools that do not timetable rooms would make the
  // feature useless to most of them.
  it("does not put two roomless classes in the same room", () => {
    const clashes = findClashes(
      block({id: undefined, teacherId: "u_other", section: "Grade 9 - Mabini", room: null}),
      [block({room: ""})]
    );
    expect(clashes).toEqual([]);
  });

  it("matches sections and rooms regardless of case and padding", () => {
    const clashes = findClashes(
      block({
        id: undefined,
        teacherId: "u_other",
        section: "  grade 10 - rizal ",
        room: " ROOM 201 ",
      }),
      [block()]
    );
    expect(new Set(clashes.map((c) => c.kind))).toEqual(new Set(["section", "room"]));
  });

  // Editing a block must not clash with the copy of itself on file.
  it("does not clash a block with itself", () => {
    expect(findClashes(block({id: "b1"}), [block({id: "b1"})])).toEqual([]);
  });

  it("ignores another school year", () => {
    expect(findClashes(block({id: undefined, schoolYear: "2027-2028"}), [block()])).toEqual([]);
  });
});
