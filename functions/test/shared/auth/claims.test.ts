import {requireRole, requireSameSchool, AppClaims} from "../../../src/shared/auth/claims";
import {HttpsError} from "firebase-functions/v2/https";

describe("requireRole", () => {
  const claims: AppClaims = {
    schoolId: "school_1",
    role: "registrar",
    status: "active",
    mustChangePassword: false,
  };

  it("does not throw when the caller's role is allowed", () => {
    expect(() => requireRole(claims, ["registrar", "admin"])).not.toThrow();
  });

  it("throws permission-denied when the caller's role is not allowed", () => {
    expect(() => requireRole(claims, ["director", "owner"])).toThrow(HttpsError);
  });
});

describe("requireSameSchool", () => {
  const claims: AppClaims = {
    schoolId: "school_1",
    role: "admin",
    status: "active",
    mustChangePassword: false,
  };

  it("does not throw when schoolId matches", () => {
    expect(() => requireSameSchool(claims, "school_1")).not.toThrow();
  });

  it("throws permission-denied when schoolId does not match", () => {
    expect(() => requireSameSchool(claims, "school_2")).toThrow(HttpsError);
  });
});
