import {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
  RulesTestEnvironment,
} from "@firebase/rules-unit-testing";
import * as fs from "fs";
import {setDoc, doc, updateDoc, deleteDoc, getDoc} from "firebase/firestore";

let testEnv: RulesTestEnvironment;
const SCHOOL = "school_budgets_test";
const YEAR = "2026-2027";

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

function contextAs(role: string, uid: string) {
  return testEnv.authenticatedContext(uid, {
    schoolId: SCHOOL,
    role,
    status: "active",
    mustChangePassword: false,
  });
}

function budgetRow(overrides: Record<string, unknown> = {}) {
  return {
    schoolYear: YEAR,
    accountCode: "5100",
    accountName: "Utilities",
    amount: 120000,
    note: null,
    schoolId: SCHOOL,
    setBy: "director_1",
    setByName: "Grace Mendoza",
    setAt: new Date(),
    ...overrides,
  };
}

async function seedFixtures() {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    // One firestore() handle per callback: a second context.firestore()
    // after a write throws "Firestore has already been started".
    const db = context.firestore();
    await setDoc(doc(db, `platform_subscriptions/${SCHOOL}`), {
      schoolId: SCHOOL,
      currentStatus: "active",
    });
    await setDoc(doc(db, `schools/${SCHOOL}/budgets/${YEAR}_5100`), budgetRow());
  });
}

describe("setting a budget", () => {
  test("the Director and the Admin can set one", async () => {
    // An ordinary client write, unlike a bill or a journal entry: a
    // budget is a plan, not a record of money that moved. Nothing has
    // to balance and nothing has to commit with anything else.
    await seedFixtures();
    for (const role of ["director", "admin"]) {
      const db = contextAs(role, `${role}_1`).firestore();
      await assertSucceeds(
        setDoc(
          doc(db, `schools/${SCHOOL}/budgets/${YEAR}_520${role === "admin" ? 1 : 0}`),
          budgetRow({accountCode: `520${role === "admin" ? 1 : 0}`})
        )
      );
    }
  });

  test("nobody below the Director can read or set one", async () => {
    await seedFixtures();
    for (const role of ["principal", "registrar", "faculty", "staff", "student", "parent"]) {
      const db = contextAs(role, `${role}_1`).firestore();
      await assertFails(getDoc(doc(db, `schools/${SCHOOL}/budgets/${YEAR}_5100`)));
      await assertFails(
        setDoc(doc(db, `schools/${SCHOOL}/budgets/${YEAR}_5300`), budgetRow({
          accountCode: "5300",
        }))
      );
    }
  });

  test("the id has to be the year and the account", async () => {
    // One budget per account per year, by construction. A school with
    // two has no way to tell which one anybody meant.
    await seedFixtures();
    const db = contextAs("director", "director_1").firestore();
    await assertFails(
      setDoc(doc(db, `schools/${SCHOOL}/budgets/whatever`), budgetRow({
        accountCode: "5300",
      }))
    );
    await assertFails(
      setDoc(doc(db, `schools/${SCHOOL}/budgets/${YEAR}_5300`), budgetRow({
        accountCode: "5900",
      }))
    );
  });

  test("a negative budget is refused", async () => {
    await seedFixtures();
    const db = contextAs("director", "director_1").firestore();
    await assertFails(
      setDoc(doc(db, `schools/${SCHOOL}/budgets/${YEAR}_5300`), budgetRow({
        accountCode: "5300",
        amount: -1,
      }))
    );
  });

  test("an amount that is not a number is refused", async () => {
    await seedFixtures();
    const db = contextAs("director", "director_1").firestore();
    await assertFails(
      setDoc(doc(db, `schools/${SCHOOL}/budgets/${YEAR}_5300`), budgetRow({
        accountCode: "5300",
        amount: "lots",
      }))
    );
  });

  test("zero is allowed, because that is how a line comes off the plan", async () => {
    await seedFixtures();
    const db = contextAs("admin", "admin_1").firestore();
    await assertSucceeds(
      updateDoc(doc(db, `schools/${SCHOOL}/budgets/${YEAR}_5100`), {amount: 0})
    );
  });

  test("a budget can never be deleted", async () => {
    // Setting it to zero leaves the spending against it visible as
    // unbudgeted, which a deleted row would not.
    await seedFixtures();
    for (const role of ["director", "admin"]) {
      const db = contextAs(role, `${role}_1`).firestore();
      await assertFails(
        deleteDoc(doc(db, `schools/${SCHOOL}/budgets/${YEAR}_5100`))
      );
    }
  });

  test("another school cannot read or set one", async () => {
    await seedFixtures();
    const outsider = testEnv.authenticatedContext("director_elsewhere", {
      schoolId: "some_other_school",
      role: "director",
      status: "active",
    });
    await assertFails(
      getDoc(doc(outsider.firestore(), `schools/${SCHOOL}/budgets/${YEAR}_5100`))
    );
  });
});
