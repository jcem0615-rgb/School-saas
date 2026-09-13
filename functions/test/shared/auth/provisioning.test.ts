import {refuseProvisioning, PROVISIONING_MATRIX} from "../../../src/shared/auth/provisioning";

const may = (caller: string, target: string) => refuseProvisioning(caller, target) === null;

/// Who may hand somebody else a password, and for which role.
describe("who may create an account", () => {
  describe("the Admin, who runs the office", () => {
    // The change this file was written for. An admin office is a
    // department, not a person: the version where only the vendor's
    // Owner account could mint a second Admin meant one person's
    // resignation stopped a school from enrolling anybody.
    it("creates another Admin", () => {
      expect(may("admin", "admin")).toBe(true);
    });

    it("fills every other post the school has", () => {
      for (const role of [
        "director",
        "principal",
        "registrar",
        "faculty",
        "staff",
        "guidance",
        "student",
        "parent",
      ]) {
        expect(may("admin", role)).toBe(true);
      }
    });
  });

  describe("the Owner, who stands a school up and then stays out", () => {
    it("creates the first Director and the first Admin", () => {
      expect(may("owner", "director")).toBe(true);
      expect(may("owner", "admin")).toBe(true);
    });

    it("does not staff the school beyond that", () => {
      // Not a capability worth having: the Owner is the vendor. A
      // vendor account creating a school's teachers is a vendor account
      // that has to be trusted with the school's staffing.
      for (const role of ["faculty", "registrar", "staff", "guidance", "student"]) {
        expect(may("owner", role)).toBe(false);
      }
    });
  });

  describe("everybody else", () => {
    it("lets the Registrar enrol families and nothing more", () => {
      expect(may("registrar", "student")).toBe(true);
      expect(may("registrar", "parent")).toBe(true);
      // The reason the matrix is a list and not a rank: a compromised
      // registrar session must not be able to promote itself.
      for (const role of ["admin", "director", "principal", "faculty", "registrar"]) {
        expect(may("registrar", role)).toBe(false);
      }
    });

    it("refuses a caller whose role is not in the matrix at all", () => {
      for (const caller of ["director", "principal", "faculty", "staff", "guidance", "student", "parent"]) {
        expect(may(caller, "faculty")).toBe(false);
      }
    });

    it("refuses a role nobody has heard of, rather than defaulting open", () => {
      expect(may("admin", "superuser")).toBe(false);
      expect(may("lunch_monitor", "faculty")).toBe(false);
    });
  });

  describe("the Owner account itself", () => {
    // There is exactly one, established by bootstrapOwner against a
    // server-side email. Two checks rather than one: that no row offers
    // it, and that the separate refusal catches it even if a future edit
    // puts it in a row by accident.
    it("appears in no row of the matrix", () => {
      for (const [caller, targets] of Object.entries(PROVISIONING_MATRIX)) {
        expect(targets).not.toContain("owner");
        expect(caller).not.toBe("");
      }
    });

    it("is refused for its own reason, not for the caller's", () => {
      for (const caller of Object.keys(PROVISIONING_MATRIX)) {
        expect(refuseProvisioning(caller, "owner")).toMatchObject({
          kind: "unprovisionable",
        });
      }
    });
  });

  describe("what the refusal says", () => {
    it("tells a caller reaching too high which role stopped them", () => {
      const refusal = refuseProvisioning("registrar", "director");
      expect(refusal).toMatchObject({kind: "not-permitted"});
      expect(refusal!.message).toContain("registrar");
      expect(refusal!.message).toContain("director");
    });
  });
});
