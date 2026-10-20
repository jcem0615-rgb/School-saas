import {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
  RulesTestEnvironment,
} from "@firebase/rules-unit-testing";
import * as fs from "fs";
import {setDoc, doc, updateDoc, deleteDoc, getDoc} from "firebase/firestore";

let testEnv: RulesTestEnvironment;
const SCHOOL = "school_ledger_test";

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

function entryRow(overrides: Record<string, unknown> = {}) {
  return {
    id: "je_1",
    schoolId: SCHOOL,
    entryNumber: "JE-2026-0001",
    date: new Date(),
    memo: "Collection OR-2026-000118",
    source: "payment",
    sourceId: "pay_1",
    lines: [
      {accountCode: "1000", accountName: "Cash on Hand", debit: 1500, credit: 0, memo: null},
      {
        accountCode: "1200",
        accountName: "Accounts Receivable - Students",
        debit: 0,
        credit: 1500,
        memo: null,
      },
    ],
    totalDebits: 1500,
    totalCredits: 1500,
    postedBy: "director_1",
    postedByName: "Grace Mendoza",
    postedAt: new Date(),
    reversalOf: null,
    reversedBy: null,
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
    await setDoc(doc(db, `schools/${SCHOOL}/ledgerAccounts/1000`), {
      code: "1000",
      name: "Cash on Hand",
      type: "asset",
      isSystem: true,
      isActive: true,
      schoolId: SCHOOL,
    });
    await setDoc(doc(db, `schools/${SCHOOL}/ledgerAccounts/5100`), {
      code: "5100",
      name: "Utilities",
      type: "expense",
      isSystem: false,
      isActive: true,
      schoolId: SCHOOL,
    });
    await setDoc(doc(db, `schools/${SCHOOL}/journalEntries/je_1`), entryRow());
  });
}

describe("the journal is read-only to every client there is", () => {
  test("the Director and the Admin can read it", async () => {
    await seedFixtures();
    for (const role of ["director", "admin"]) {
      const db = contextAs(role, `${role}_1`).firestore();
      await assertSucceeds(
        getDoc(doc(db, `schools/${SCHOOL}/journalEntries/je_1`))
      );
    }
  });

  test("nobody else can read it", async () => {
    // A principal runs a division, not a set of books. A chart of
    // accounts tells you what the school spends on what, and that is not
    // theirs, the registrar's, or anybody's below them.
    await seedFixtures();
    for (const role of ["principal", "registrar", "faculty", "staff", "student", "parent"]) {
      const db = contextAs(role, `${role}_1`).firestore();
      await assertFails(
        getDoc(doc(db, `schools/${SCHOOL}/journalEntries/je_1`))
      );
    }
  });

  test("another school cannot read it", async () => {
    await seedFixtures();
    const outsider = testEnv.authenticatedContext("director_elsewhere", {
      schoolId: "some_other_school",
      role: "director",
      status: "active",
    });
    await assertFails(
      getDoc(doc(outsider.firestore(), `schools/${SCHOOL}/journalEntries/je_1`))
    );
  });

  test("not even the Director can post an entry from a client", async () => {
    // Security rules cannot sum an array, so there is no way to say
    // "debits equal credits" here. A client allowed to write could post
    // books that do not balance, so none is. The callables check it.
    await seedFixtures();
    const db = contextAs("director", "director_1").firestore();
    await assertFails(
      setDoc(doc(db, `schools/${SCHOOL}/journalEntries/je_forged`), entryRow({id: "je_forged"}))
    );
  });

  test("an entry cannot be edited, by anyone", async () => {
    // A book you can go back and tidy is a book nobody can rely on. A
    // mistake is corrected by posting the reverse of it.
    await seedFixtures();
    for (const role of ["director", "admin"]) {
      const db = contextAs(role, `${role}_1`).firestore();
      await assertFails(
        updateDoc(doc(db, `schools/${SCHOOL}/journalEntries/je_1`), {memo: "Something else"})
      );
      await assertFails(
        updateDoc(doc(db, `schools/${SCHOOL}/journalEntries/je_1`), {reversedBy: "je_2"})
      );
    }
  });

  test("an entry cannot be deleted, by anyone", async () => {
    await seedFixtures();
    for (const role of ["director", "admin"]) {
      const db = contextAs(role, `${role}_1`).firestore();
      await assertFails(
        deleteDoc(doc(db, `schools/${SCHOOL}/journalEntries/je_1`))
      );
    }
  });
});

describe("the chart of accounts", () => {
  test("the Director can add an account", async () => {
    await seedFixtures();
    const db = contextAs("director", "director_1").firestore();
    await assertSucceeds(
      setDoc(doc(db, `schools/${SCHOOL}/ledgerAccounts/5400`), {
        code: "5400",
        name: "Transport",
        type: "expense",
        isSystem: false,
        isActive: true,
        schoolId: SCHOOL,
      })
    );
  });

  test("a new account cannot declare itself a system account", async () => {
    // System accounts are the ones the automatic postings find by code.
    // One a person could mint would be a posting target nothing posts to.
    await seedFixtures();
    const db = contextAs("director", "director_1").firestore();
    await assertFails(
      setDoc(doc(db, `schools/${SCHOOL}/ledgerAccounts/5401`), {
        code: "5401",
        name: "Pretend system account",
        type: "expense",
        isSystem: true,
        isActive: true,
        schoolId: SCHOOL,
      })
    );
  });

  test("the code in the document has to match the document id", async () => {
    // "Charge it to 5100" has to find the document without a query, so
    // the id is the code. A row whose code says otherwise would be found
    // by one and not the other.
    await seedFixtures();
    const db = contextAs("director", "director_1").firestore();
    await assertFails(
      setDoc(doc(db, `schools/${SCHOOL}/ledgerAccounts/5402`), {
        code: "9999",
        name: "Mismatched",
        type: "expense",
        isSystem: false,
        isActive: true,
        schoolId: SCHOOL,
      })
    );
  });

  test("an account can be renamed but never renumbered or retyped", async () => {
    await seedFixtures();
    const db = contextAs("director", "director_1").firestore();

    await assertSucceeds(
      updateDoc(doc(db, `schools/${SCHOOL}/ledgerAccounts/5100`), {
        name: "Light and Water",
      })
    );
    await assertFails(
      updateDoc(doc(db, `schools/${SCHOOL}/ledgerAccounts/5100`), {code: "5101"})
    );
    await assertFails(
      updateDoc(doc(db, `schools/${SCHOOL}/ledgerAccounts/5100`), {type: "asset"})
    );
  });

  test("a system account can be renamed but not switched off", async () => {
    // The postings find it by code. One that could be deactivated would
    // take the next payment down with it.
    await seedFixtures();
    const db = contextAs("director", "director_1").firestore();

    await assertSucceeds(
      updateDoc(doc(db, `schools/${SCHOOL}/ledgerAccounts/1000`), {
        name: "Cash at the window",
      })
    );
    await assertFails(
      updateDoc(doc(db, `schools/${SCHOOL}/ledgerAccounts/1000`), {isActive: false})
    );
    // An ordinary one can be.
    await assertSucceeds(
      updateDoc(doc(db, `schools/${SCHOOL}/ledgerAccounts/5100`), {isActive: false})
    );
  });

  test("an account can never be deleted", async () => {
    // One with entries against it cannot go without the trial balance
    // silently losing them; one with none costs nothing to leave off.
    await seedFixtures();
    const db = contextAs("admin", "admin_1").firestore();
    await assertFails(
      deleteDoc(doc(db, `schools/${SCHOOL}/ledgerAccounts/5100`))
    );
  });

  test("a registrar cannot touch the chart at all", async () => {
    await seedFixtures();
    const db = contextAs("registrar", "registrar_1").firestore();
    await assertFails(getDoc(doc(db, `schools/${SCHOOL}/ledgerAccounts/1000`)));
    await assertFails(
      setDoc(doc(db, `schools/${SCHOOL}/ledgerAccounts/5500`), {
        code: "5500",
        name: "Sneaked in",
        type: "expense",
        isSystem: false,
        isActive: true,
        schoolId: SCHOOL,
      })
    );
  });
});
