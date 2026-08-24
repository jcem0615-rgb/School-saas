import {formatStudentNumber} from "../../../src/shared/students/studentNumber";

describe("formatStudentNumber", () => {
  it("pads the sequence to 6 digits", () => {
    expect(formatStudentNumber(7, 2026)).toBe("S-2026-000007");
  });

  it("handles large sequences without truncation", () => {
    expect(formatStudentNumber(1234567, 2026)).toBe("S-2026-1234567");
  });
});
