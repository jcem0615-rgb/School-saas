import {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
  RulesTestEnvironment,
} from "@firebase/rules-unit-testing";
import * as fs from "fs";
import {setDoc, doc, updateDoc, deleteDoc, getDoc} from "firebase/firestore";

let testEnv: RulesTestEnvironment;
const SCHOOL = "school_payables_test";

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

function billRow(overrides: Record<string, unknown> = {}) {
  return {
    id: "bill_1",
    schoolId: SCHOOL,
    vendorId: "ven_1",
    vendorName: "National Book Store",
    billNumber: "SI-99321",
    billDate: new Date(),
    dueDate: new Date(),
    lines: [
      {accountCode: "5200", accountName: "Supplies", description: "Bond paper", amount: 5000},
    ],
    total: 5000,
    amountPaid: 0,
    status: "open",
    journalEntryId: "je_1",
    payments: [],
    recordedBy: "director_1",
    recordedByName: "Grace Mendoza",
    recordedAt: new Date(),
    voidedAt: null,
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
    await setDoc(doc(db, `schools/${SCHOOL}/vendors/ven_1`), {
      id: "ven_1",
      schoolId: SCHOOL,
      name: "National Book Store",
      paymentTermsDays: 30,
      isActive: true,
    });
    await setDoc(doc(db, `schools/${SCHOOL}/bills/bill_1`), billRow());
  });
}

describe("the supplier list", () => {
  test("the Director and the Admin can read and add", async () => {
    await seedFixtures();
    for (const role of ["director", "admin"]) {
      const db = contextAs(role, `${role}_1`).firestore();
      await assertSucceeds(getDoc(doc(db, `schools/${SCHOOL}/vendors/ven_1`)));
      await assertSucceeds(
        setDoc(doc(db, `schools/${SCHOOL}/vendors/ven_${role}`), {
          id: `ven_${role}`,
          schoolId: SCHOOL,
          name: "Meralco",
          paymentTermsDays: 15,
          isActive: true,
        })
      );
    }
  });

  test("a vendor with no name is refused", async () => {
    // A supplier list whose rows say nothing is a supplier list nobody
    // can pick from.
    await seedFixtures();
    const db = contextAs("director", "director_1").firestore();
    await assertFails(
      setDoc(doc(db, `schools/${SCHOOL}/vendors/ven_blank`), {
        id: "ven_blank",
        schoolId: SCHOOL,
        name: "",
        isActive: true,
      })
    );
  });

  test("a vendor can be deactivated but never deleted", async () => {
    // One with bills against it cannot go without those bills losing the
    // name they were raised under.
    await seedFixtures();
    const db = contextAs("admin", "admin_1").firestore();
    await assertSucceeds(
      updateDoc(doc(db, `schools/${SCHOOL}/vendors/ven_1`), {isActive: false})
    );
    await assertFails(deleteDoc(doc(db, `schools/${SCHOOL}/vendors/ven_1`)));
  });

  test("nobody below the Director can see it", async () => {
    await seedFixtures();
    for (const role of ["principal", "registrar", "faculty", "staff", "student", "parent"]) {
      const db = contextAs(role, `${role}_1`).firestore();
      await assertFails(getDoc(doc(db, `schools/${SCHOOL}/vendors/ven_1`)));
    }
  });
});

describe("bills are read-only to every client there is", () => {
  test("the Director and the Admin can read them", async () => {
    await seedFixtures();
    for (const role of ["director", "admin"]) {
      const db = contextAs(role, `${role}_1`).firestore();
      await assertSucceeds(getDoc(doc(db, `schools/${SCHOOL}/bills/bill_1`)));
    }
  });

  test("nobody else can read them", async () => {
    await seedFixtures();
    for (const role of ["principal", "registrar", "faculty", "staff", "student", "parent"]) {
      const db = contextAs(role, `${role}_1`).firestore();
      await assertFails(getDoc(doc(db, `schools/${SCHOOL}/bills/bill_1`)));
    }
  });

  test("another school cannot read them", async () => {
    await seedFixtures();
    const outsider = testEnv.authenticatedContext("director_elsewhere", {
      schoolId: "some_other_school",
      role: "director",
      status: "active",
    });
    await assertFails(
      getDoc(doc(outsider.firestore(), `schools/${SCHOOL}/bills/bill_1`))
    );
  });

  test("not even the Director can record a bill from a client", async () => {
    // A client allowed to write here could record a liability the books
    // never hear about, which is the gap between a payables list and an
    // accounting system.
    await seedFixtures();
    const db = contextAs("director", "director_1").firestore();
    await assertFails(
      setDoc(doc(db, `schools/${SCHOOL}/bills/bill_forged`), billRow({id: "bill_forged"}))
    );
  });

  test("a bill cannot be marked paid from a client", async () => {
    // Which is the whole attack: mark it paid, no money moves, and the
    // ledger still says the school owes it.
    await seedFixtures();
    const db = contextAs("admin", "admin_1").firestore();
    await assertFails(
      updateDoc(doc(db, `schools/${SCHOOL}/bills/bill_1`), {
        amountPaid: 5000,
        status: "paid",
      })
    );
  });

  test("a bill can never be deleted", async () => {
    // One entered by mistake is voided, with the reason on it and the
    // liability reversed by its own entry.
    await seedFixtures();
    for (const role of ["director", "admin"]) {
      const db = contextAs(role, `${role}_1`).firestore();
      await assertFails(deleteDoc(doc(db, `schools/${SCHOOL}/bills/bill_1`)));
    }
  });
});
