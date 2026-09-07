import {
  audienceIncludes,
  reachesNobody,
  readAudience,
} from "../../../src/shared/announcements/audience";

/**
 * This table is the same one asserted on the client, in
 * app/test/unit/features/director_portal/domain/usecases/announcement_audience_test.dart.
 * The two implementations are separate on purpose -- one decides what a
 * list shows, the other decides whose phone rings -- so the tests are
 * what keep them honest.
 */
describe("audienceIncludes", () => {
  const everyone = {all: true, roles: [], sections: []};
  const staffOnly = {
    all: false,
    roles: ["director", "principal", "admin", "registrar", "faculty", "staff", "guidance"],
    sections: [],
  };

  it("reaches every role when addressed to everyone", () => {
    for (const role of ["director", "faculty", "student", "parent", "staff"]) {
      expect(audienceIncludes(everyone, role)).toBe(true);
    }
  });

  it("reaches staff but not students or parents when addressed to staff", () => {
    expect(audienceIncludes(staffOnly, "faculty")).toBe(true);
    expect(audienceIncludes(staffOnly, "guidance")).toBe(true);
    expect(audienceIncludes(staffOnly, "student")).toBe(false);
    expect(audienceIncludes(staffOnly, "parent")).toBe(false);
  });

  it("reaches exactly the roles named", () => {
    const audience = {all: false, roles: ["faculty", "student"], sections: []};
    expect(audienceIncludes(audience, "faculty")).toBe(true);
    expect(audienceIncludes(audience, "student")).toBe(true);
    expect(audienceIncludes(audience, "parent")).toBe(false);
    expect(audienceIncludes(audience, "admin")).toBe(false);
  });

  it("reaches nobody when the role list is empty", () => {
    const audience = {all: false, roles: [], sections: []};
    for (const role of ["director", "faculty", "student"]) {
      expect(audienceIncludes(audience, role)).toBe(false);
    }
  });
});

/**
 * The half this file was missing.
 *
 * Teachers were given a way to post to one class; the client learned
 * about `sections` and this side did not, so every class notice was read
 * as addressed to nobody and rang no phone at all. The table had no
 * section case in it, which is how that lasted.
 */
describe("a notice addressed to one class", () => {
  const rizal = {all: false, roles: [], sections: ["Grade 10 - Rizal"]};

  it("reaches somebody in that class, whatever their role", () => {
    // A student, their parent and another of the section's teachers are
    // three different roles and one class.
    expect(audienceIncludes(rizal, "student", ["Grade 10 - Rizal"])).toBe(true);
    expect(audienceIncludes(rizal, "parent", ["Grade 10 - Rizal"])).toBe(true);
    expect(audienceIncludes(rizal, "faculty", ["Grade 10 - Rizal"])).toBe(true);
  });

  it("does not reach the same roles in another class", () => {
    expect(audienceIncludes(rizal, "student", ["Grade 10 - Mabini"])).toBe(false);
    expect(audienceIncludes(rizal, "parent", ["Grade 9 - Bonifacio"])).toBe(false);
  });

  it("does not reach somebody in no class at all", () => {
    // An admin or a cashier belongs to no section, which is exactly
    // right: a class notice is not for them.
    expect(audienceIncludes(rizal, "admin")).toBe(false);
    expect(audienceIncludes(rizal, "registrar", [])).toBe(false);
  });

  it("reaches a parent with one child in the class and one elsewhere", () => {
    expect(
      audienceIncludes(rizal, "parent", ["Grade 3 - Sampaguita", "Grade 10 - Rizal"])
    ).toBe(true);
  });

  it("matches the class however the name was typed", () => {
    // Section names are typed by hand on the student record and on the
    // teacher's assignment. Matching them exactly means a parent
    // silently misses the notice about tomorrow's field trip.
    expect(audienceIncludes(rizal, "student", ["grade 10 - rizal"])).toBe(true);
    expect(audienceIncludes(rizal, "student", ["  Grade 10  -  Rizal "])).toBe(true);
  });

  it("does not treat a blank section as a match for one", () => {
    expect(audienceIncludes(rizal, "student", ["", "   "])).toBe(false);
    expect(
      audienceIncludes({all: false, roles: [], sections: ["  "]}, "student", ["Grade 10 - Rizal"])
    ).toBe(false);
  });

  it("is an OR with the roles, not an AND", () => {
    // A notice to "faculty" and to one class reaches every teacher, and
    // reaches that class's parents too.
    const both = {all: false, roles: ["faculty"], sections: ["Grade 10 - Rizal"]};
    expect(audienceIncludes(both, "faculty", [])).toBe(true);
    expect(audienceIncludes(both, "parent", ["Grade 10 - Rizal"])).toBe(true);
    expect(audienceIncludes(both, "parent", ["Grade 9 - Bonifacio"])).toBe(false);
  });
});

describe("reachesNobody", () => {
  it("is true only when nothing at all was chosen", () => {
    expect(reachesNobody({all: false, roles: [], sections: []})).toBe(true);
    expect(reachesNobody({all: true, roles: [], sections: []})).toBe(false);
    expect(reachesNobody({all: false, roles: ["faculty"], sections: []})).toBe(false);
  });

  it("is false for a class notice, which used to read as addressed to nobody", () => {
    // The whole defect in one line: the trigger returned early here and
    // notified no one.
    expect(reachesNobody({all: false, roles: [], sections: ["Grade 10 - Rizal"]})).toBe(false);
  });
});

describe("readAudience", () => {
  // A push cannot be unsent, so anything malformed has to fail closed.
  // Reaching nobody is a bug someone reports; reaching every parent in
  // the school with a payroll notice is not recoverable.
  it("treats a missing audience as reaching nobody", () => {
    expect(readAudience(undefined)).toEqual({all: false, roles: [], sections: []});
    expect(readAudience({})).toEqual({all: false, roles: [], sections: []});
    expect(readAudience({audience: null})).toEqual({all: false, roles: [], sections: []});
  });

  it("treats a non-object audience as reaching nobody", () => {
    expect(readAudience({audience: "everyone"})).toEqual({all: false, roles: [], sections: []});
    expect(readAudience({audience: 1})).toEqual({all: false, roles: [], sections: []});
  });

  it("only accepts a literal true for all", () => {
    expect(readAudience({audience: {all: true, roles: []}}).all).toBe(true);
    // A truthy string must not widen the audience to the whole school.
    expect(readAudience({audience: {all: "yes", roles: []}}).all).toBe(false);
    expect(readAudience({audience: {all: 1, roles: []}}).all).toBe(false);
  });

  it("drops non-string entries rather than carrying them into a comparison", () => {
    const audience = readAudience({audience: {all: false, roles: ["faculty", 7, null, "student"]}});
    expect(audience.roles).toEqual(["faculty", "student"]);
  });

  it("treats a non-array roles field as empty", () => {
    expect(readAudience({audience: {all: false, roles: "faculty"}}).roles).toEqual([]);
  });

  it("reads sections, and reads their absence as none", () => {
    // Absent on every announcement posted before teachers could target
    // a class, which is most of what a school already has on file.
    expect(readAudience({audience: {all: false, roles: []}}).sections).toEqual([]);
    expect(
      readAudience({audience: {all: false, roles: [], sections: ["Grade 10 - Rizal"]}}).sections
    ).toEqual(["Grade 10 - Rizal"]);
  });

  it("drops non-string sections the same way it drops non-string roles", () => {
    const audience = readAudience({
      audience: {all: false, roles: [], sections: ["Grade 10 - Rizal", 7, null]},
    });
    expect(audience.sections).toEqual(["Grade 10 - Rizal"]);
    expect(readAudience({audience: {all: false, sections: "Grade 10"}}).sections).toEqual([]);
  });
});
