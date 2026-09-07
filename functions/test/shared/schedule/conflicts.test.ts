import {
  describeClash,
  findClashes,
  overlaps,
  sharesTerm,
  TimetableBlock,
} from "../../../src/shared/schedule/conflicts";

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

/**
 * Two timetables in one school year.
 *
 * `term` was on the block with the note "for schools whose timetable
 * changes partway through the year", and nothing read it -- not the
 * client copy and not this one. Two blocks in different semesters never
 * coexist, so calling them a clash made the second semester impossible
 * to enter: every block collided with its own counterpart from the
 * first. Senior High runs two semesters and a college division runs two
 * more, so that was the ordinary case for these schools, not an edge
 * one.
 */
describe("a school that timetables by semester", () => {
  const base: TimetableBlock = {
    subject: "Mathematics",
    section: "STEM 11-A",
    teacherId: "t_1",
    teacherName: "Maria Santos",
    room: "Room 204",
    dayOfWeek: 1,
    startMinute: 7 * 60 + 30,
    endMinute: 8 * 60 + 30,
    schoolYear: "2026-2027",
  };

  it("lets the same slot be used again in the other semester", () => {
    const first = {...base, id: "b1", term: "1st Semester"};
    const second = {...base, id: "b2", term: "2nd Semester", subject: "Physics"};
    // Same teacher, same section, same room, same slot -- and no clash,
    // because the two are never in the same week.
    expect(findClashes(second, [first])).toEqual([]);
    expect(sharesTerm(first, second)).toBe(false);
  });

  it("still catches a clash inside one semester", () => {
    const first = {...base, id: "b1", term: "1st Semester"};
    const second = {...base, id: "b2", term: "1st Semester", subject: "Physics"};
    expect(findClashes(second, [first]).map((c) => c.kind).sort()).toEqual([
      "room",
      "section",
      "teacher",
    ]);
  });

  it("reads a blank term as all year, so it clashes with every semester", () => {
    // A Grade 7 class runs the whole year. It genuinely is in the room
    // during both semesters, and a school that enters it that way has
    // to be told when a semester class lands on top of it.
    const allYear = {...base, id: "b1", term: null};
    const semester = {...base, id: "b2", term: "2nd Semester"};
    expect(sharesTerm(allYear, semester)).toBe(true);
    expect(findClashes(semester, [allYear]).length).toBeGreaterThan(0);
    expect(findClashes(allYear, [semester]).length).toBeGreaterThan(0);
  });

  it("treats a term typed two ways as one term", () => {
    // "1st Semester" and "1st semester " are what two people type for
    // the same thing, and reading them as different ones would let a
    // real double-booking through.
    const first = {...base, id: "b1", term: "1st Semester"};
    const second = {...base, id: "b2", term: " 1st semester "};
    expect(sharesTerm(first, second)).toBe(true);
    expect(findClashes(second, [first]).length).toBeGreaterThan(0);
  });

  it("names the semester in the refusal, so the admin knows which one", () => {
    const first = {...base, id: "b1", term: "1st Semester"};
    const clash = findClashes({...base, id: "b2"}, [first])[0];
    expect(describeClash(clash)).toContain("1st Semester");
  });

  it("says nothing about a term when there is not one", () => {
    const first = {...base, id: "b1"};
    const clash = findClashes({...base, id: "b2"}, [first])[0];
    expect(describeClash(clash)).not.toContain("(");
  });
});
