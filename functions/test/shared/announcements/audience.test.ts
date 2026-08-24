import {audienceIncludes, readAudience} from "../../../src/shared/announcements/audience";

/**
 * This table is the same one asserted on the client, in
 * app/test/unit/features/director_portal/domain/usecases/announcement_audience_test.dart.
 * The two implementations are separate on purpose -- one decides what a
 * list shows, the other decides whose phone rings -- so the tests are
 * what keep them honest.
 */
describe("audienceIncludes", () => {
  const everyone = {all: true, roles: []};
  const staffOnly = {
    all: false,
    roles: ["director", "principal", "admin", "registrar", "faculty", "staff", "guidance"],
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
    const audience = {all: false, roles: ["faculty", "student"]};
    expect(audienceIncludes(audience, "faculty")).toBe(true);
    expect(audienceIncludes(audience, "student")).toBe(true);
    expect(audienceIncludes(audience, "parent")).toBe(false);
    expect(audienceIncludes(audience, "admin")).toBe(false);
  });

  it("reaches nobody when the role list is empty", () => {
    const audience = {all: false, roles: []};
    for (const role of ["director", "faculty", "student"]) {
      expect(audienceIncludes(audience, role)).toBe(false);
    }
  });
});

describe("readAudience", () => {
  // A push cannot be unsent, so anything malformed has to fail closed.
  // Reaching nobody is a bug someone reports; reaching every parent in
  // the school with a payroll notice is not recoverable.
  it("treats a missing audience as reaching nobody", () => {
    expect(readAudience(undefined)).toEqual({all: false, roles: []});
    expect(readAudience({})).toEqual({all: false, roles: []});
    expect(readAudience({audience: null})).toEqual({all: false, roles: []});
  });

  it("treats a non-object audience as reaching nobody", () => {
    expect(readAudience({audience: "everyone"})).toEqual({all: false, roles: []});
    expect(readAudience({audience: 1})).toEqual({all: false, roles: []});
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
});
