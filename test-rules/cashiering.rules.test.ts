import {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
  RulesTestEnvironment,
} from "@firebase/rules-unit-testing";
import * as fs from "fs";
import {setDoc, doc, updateDoc, deleteDoc, getDoc} from "firebase/firestore";

let testEnv: RulesTestEnvironment;
const SCHOOL = "school_cashiering_test";

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

function shiftRow(overrides: Record<string, unknown> = {}) {
  return {
    id: "shift_1",
    schoolId: SCHOOL,
    cashierUid: "registrar_1",
    cashierName: "Rosario Aguilar",
    openedAt: new Date(),
    openingFloat: 2000,
    closedAt: null,
    countedAmount: null,
    expectedAmount: null,
    varianceNote: null,
    closedByName: null,
    journalEntryId: null,
    isDeleted: false,
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
    await setDoc(doc(db, `schools/${SCHOOL}/cashierShifts/shift_1`), shiftRow());
    await setDoc(
      doc(db, `schools/${SCHOOL}/cashierShifts/shift_2`),
      shiftRow({id: "shift_2", cashierUid: "registrar_2", cashierName: "Someone Else"})
    );
  });
}

describe("reading a drawer", () => {
  test("a cashier can see their own", async () => {
    await seedFixtures();
    const db = contextAs("registrar", "registrar_1").firestore();
    await assertSucceeds(
      getDoc(doc(db, `schools/${SCHOOL}/cashierShifts/shift_1`))
    );
  });

  test("a cashier cannot see another cashier's", async () => {
    // Whose drawer was short is not something one cashier gets to look
    // up about another.
    await seedFixtures();
    const db = contextAs("registrar", "registrar_1").firestore();
    await assertFails(
      getDoc(doc(db, `schools/${SCHOOL}/cashierShifts/shift_2`))
    );
  });

  test("the Director and the Admin see everybody's", async () => {
    // "Who was short last month" is the question the module exists to
    // answer, and it is not one a cashier asks about themselves.
    await seedFixtures();
    for (const role of ["director", "admin"]) {
      const db = contextAs(role, `${role}_1`).firestore();
      await assertSucceeds(
        getDoc(doc(db, `schools/${SCHOOL}/cashierShifts/shift_1`))
      );
    }
  });

  test("nobody outside the office can see one", async () => {
    await seedFixtures();
    for (const role of ["principal", "faculty", "staff", "student", "parent"]) {
      const db = contextAs(role, `${role}_1`).firestore();
      await assertFails(
        getDoc(doc(db, `schools/${SCHOOL}/cashierShifts/shift_1`))
      );
    }
  });

  test("another school cannot see one", async () => {
    await seedFixtures();
    const outsider = testEnv.authenticatedContext("admin_elsewhere", {
      schoolId: "some_other_school",
      role: "admin",
      status: "active",
    });
    await assertFails(
      getDoc(doc(outsider.firestore(), `schools/${SCHOOL}/cashierShifts/shift_1`))
    );
  });
});

describe("writing a drawer is server-only", () => {
  test("a cashier cannot open one from a client", async () => {
    await seedFixtures();
    const db = contextAs("registrar", "registrar_1").firestore();
    await assertFails(
      setDoc(doc(db, `schools/${SCHOOL}/cashierShifts/shift_new`), shiftRow({
        id: "shift_new",
      }))
    );
  });

  test("a cashier cannot close their own drawer from a client", async () => {
    // The attack the whole rule exists for: set expectedAmount to
    // whatever was just counted and every drawer balances for ever.
    await seedFixtures();
    const db = contextAs("registrar", "registrar_1").firestore();
    await assertFails(
      updateDoc(doc(db, `schools/${SCHOOL}/cashierShifts/shift_1`), {
        closedAt: new Date(),
        countedAmount: 48000,
        expectedAmount: 48000,
      })
    );
  });

  test("not even the Admin can write one", async () => {
    await seedFixtures();
    const db = contextAs("admin", "admin_1").firestore();
    await assertFails(
      updateDoc(doc(db, `schools/${SCHOOL}/cashierShifts/shift_1`), {
        openingFloat: 999999,
      })
    );
  });

  test("a drawer can never be deleted", async () => {
    await seedFixtures();
    for (const [role, uid] of [["registrar", "registrar_1"], ["admin", "admin_1"],
      ["director", "director_1"]]) {
      const db = contextAs(role, uid).firestore();
      await assertFails(
        deleteDoc(doc(db, `schools/${SCHOOL}/cashierShifts/shift_1`))
      );
    }
  });
});
