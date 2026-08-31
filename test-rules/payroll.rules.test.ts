import {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
  RulesTestEnvironment,
} from "@firebase/rules-unit-testing";
import * as fs from "fs";
import {setDoc, doc, getDoc, deleteDoc, updateDoc, getDocs, collection} from "firebase/firestore";

/**
 * What people are paid.
 *
 * The tightest read list in the tenant, and deliberately so: a salary is
 * the one number colleagues will read each other's if they can, and a
 * school where the pay scale leaks has a problem no software fixes
 * afterwards. The one exception is somebody's own payslip, which they
 * are handed on paper anyway.
 */

let testEnv: RulesTestEnvironment;
const SCHOOL = "school_payroll_test";
const COMPENSATION = `schools/${SCHOOL}/compensation/u_faculty`;
const MY_PAYSLIP = `schools/${SCHOOL}/payslips/2026-06-01_2026-06-30_u_faculty`;
const OTHER_PAYSLIP = `schools/${SCHOOL}/payslips/2026-06-01_2026-06-30_u_staff`;

beforeAll(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: "school-saas-test",
    firestore: {rules: fs.readFileSync("firestore.rules", "utf8")},
  });
});

afterAll(async () => {
  await testEnv.cleanup();
});

afterEach(async () => {
  await testEnv.clearFirestore();
});

function contextAs(role: string, uid: string, schoolId = SCHOOL) {
  return testEnv.authenticatedContext(uid, {
    schoolId,
    role,
    status: "active",
    mustChangePassword: false,
  });
}

const payslip = (employeeUid: string) => ({
  employeeUid,
  employeeName: "Maria Santos",
  periodFrom: "2026-06-01",
  periodTo: "2026-06-30",
  basicPay: 32000,
  grossPay: 34000,
  totalDeductions: 3300,
  netPay: 30700,
});

async function seed() {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await setDoc(doc(db, `platform_subscriptions/${SCHOOL}`), {
      schoolId: SCHOOL,
      currentStatus: "active",
    });
    await setDoc(doc(db, COMPENSATION), {
      employeeUid: "u_faculty",
      basis: "monthly",
      rate: 32000,
    });
    await setDoc(doc(db, MY_PAYSLIP), payslip("u_faculty"));
    await setDoc(doc(db, OTHER_PAYSLIP), payslip("u_staff"));
  });
}

beforeEach(seed);

describe("what somebody is paid", () => {
  it("is readable and settable by Director and Admin", async () => {
    for (const role of ["director", "admin"]) {
      const db = contextAs(role, `${role}_a`).firestore();
      await assertSucceeds(getDoc(doc(db, COMPENSATION)));
      await assertSucceeds(updateDoc(doc(db, COMPENSATION), {rate: 33000}));
    }
  });

  it("is not readable by the registrar, who handles every other peso", async () => {
    const db = contextAs("registrar", "registrar_a").firestore();
    await assertFails(getDoc(doc(db, COMPENSATION)));
  });

  it("is not readable by the principal", async () => {
    const db = contextAs("principal", "principal_a").firestore();
    await assertFails(getDoc(doc(db, COMPENSATION)));
  });

  it("is not readable by the employee it is about", async () => {
    // Their payslip is theirs; the pay scale is not. Those are
    // different documents on purpose.
    const db = contextAs("faculty", "u_faculty").firestore();
    await assertFails(getDoc(doc(db, COMPENSATION)));
  });

  it("cannot be browsed as a list by anybody else", async () => {
    const db = contextAs("faculty", "u_faculty").firestore();
    await assertFails(getDocs(collection(db, `schools/${SCHOOL}/compensation`)));
  });
});

describe("a payslip", () => {
  it("is readable by the employee it belongs to", async () => {
    // They are handed it on paper anyway, and a system that will not
    // show somebody their own deductions sends them to ask a person.
    const db = contextAs("faculty", "u_faculty").firestore();
    await assertSucceeds(getDoc(doc(db, MY_PAYSLIP)));
  });

  it("is not readable by a colleague", async () => {
    const db = contextAs("faculty", "u_faculty").firestore();
    await assertFails(getDoc(doc(db, OTHER_PAYSLIP)));
  });

  it("is readable by Director and Admin", async () => {
    for (const role of ["director", "admin"]) {
      const db = contextAs(role, `${role}_a`).firestore();
      await assertSucceeds(getDoc(doc(db, OTHER_PAYSLIP)));
    }
  });

  it("is issued by Director and Admin, and nobody else", async () => {
    const admin = contextAs("admin", "admin_a").firestore();
    await assertSucceeds(
      setDoc(doc(admin, `schools/${SCHOOL}/payslips/new_1`), payslip("u_staff"))
    );

    const registrar = contextAs("registrar", "registrar_a").firestore();
    await assertFails(
      setDoc(doc(registrar, `schools/${SCHOOL}/payslips/new_2`), payslip("u_staff"))
    );
  });

  it("cannot be edited afterwards, even by an admin", async () => {
    // A statement of what was paid on a date. Editing one turns the
    // record of a payday into whatever somebody needs it to have been.
    const db = contextAs("admin", "admin_a").firestore();
    await assertFails(updateDoc(doc(db, MY_PAYSLIP), {netPay: 1}));
  });

  it("cannot be deleted", async () => {
    const db = contextAs("director", "director_a").firestore();
    await assertFails(deleteDoc(doc(db, MY_PAYSLIP)));
  });

  it("is not readable from another school", async () => {
    const db = contextAs("admin", "admin_b", "another_school").firestore();
    await assertFails(getDoc(doc(db, MY_PAYSLIP)));
  });
});
