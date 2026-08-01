import {canScan} from "../../../src/callable/attendance/markAttendance";

/**
 * Scanning is scoped by whose attendance a role is responsible for. These
 * assertions are the specification: a teacher takes class attendance, an
 * admin runs staff timekeeping, and neither should be able to do the
 * other's job by pointing a phone at the wrong ID.
 */
describe("who may scan whom", () => {
  test("faculty scan students, and only students", () => {
    expect(canScan("faculty", "student")).toBe(true);
    expect(canScan("faculty", "faculty")).toBe(false);
    expect(canScan("faculty", "staff")).toBe(false);
    expect(canScan("faculty", "admin")).toBe(false);
  });

  test("admin scan employees, and not students", () => {
    expect(canScan("admin", "faculty")).toBe(true);
    expect(canScan("admin", "staff")).toBe(true);
    expect(canScan("admin", "guidance")).toBe(true);
    expect(canScan("admin", "student")).toBe(false);
  });

  test("registrar scan students, matching their own dashboard entry", () => {
    expect(canScan("registrar", "student")).toBe(true);
    expect(canScan("registrar", "staff")).toBe(false);
  });

  test("director and principal can cover any gate", () => {
    for (const role of ["director", "principal"]) {
      expect(canScan(role, "student")).toBe(true);
      expect(canScan(role, "faculty")).toBe(true);
      expect(canScan(role, "staff")).toBe(true);
    }
  });

  // The one-way boundary: attendance is something done TO you, never by
  // you, so a compromised student or parent device cannot mark anyone
  // present -- including itself.
  test("students, parents and staff cannot operate the scanner at all", () => {
    for (const role of ["student", "parent", "staff", "guidance"]) {
      expect(canScan(role, "student")).toBe(false);
      expect(canScan(role, "faculty")).toBe(false);
    }
  });

  test("an unknown role scans nobody", () => {
    expect(canScan("", "student")).toBe(false);
    expect(canScan("janitor", "student")).toBe(false);
  });
});
