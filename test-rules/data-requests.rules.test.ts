import {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
  RulesTestEnvironment,
} from "@firebase/rules-unit-testing";
import * as fs from "fs";
import {setDoc, doc, getDoc, updateDoc, deleteDoc} from "firebase/firestore";

/**
 * A person may ask the school about their own information, and only the
 * office may answer. The two things that must hold:
 *
 *  1. Nobody files a request that arrives already answered, and nobody
 *     files one in somebody else's name. A queue you can pre-close is a
 *     queue that proves nothing.
 *  2. Nothing is ever deleted, and the question asked cannot be edited.
 *     A school asked how it handles these has to be able to show the
 *     refusals as well as the grants, in the words they were asked in.
 */

let testEnv: RulesTestEnvironment;
const SCHOOL = "school_dsr_test";

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

function contextAs(role: string, uid = `${role}_1`, schoolId = SCHOOL) {
  return testEnv.authenticatedContext(uid, {
    schoolId,
    role,
    status: "active",
    mustChangePassword: false,
  });
}

const request = (uid: string, extra: Record<string, unknown> = {}) => ({
  schoolId: SCHOOL,
  requestedByUid: uid,
  requestedByName: "Test Person",
  kind: "access",
  details: "A copy of everything on file.",
  status: "open",
  handledByName: null,
  handledAt: null,
  outcome: null,
  isDeleted: false,
  ...extra,
});

async function seedFixtures() {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await setDoc(doc(db, `platform_subscriptions/${SCHOOL}`), {
      schoolId: SCHOOL,
      currentStatus: "active",
    });
    await setDoc(doc(db, `schools/${SCHOOL}/dataRequests/dsr_mine`), request("student_1"));
    await setDoc(doc(db, `schools/${SCHOOL}/dataRequests/dsr_other`), request("student_other"));
  });
}

beforeEach(seedFixtures);

describe("raising a request", () => {
  test("a student can raise one about themselves", async () => {
    const student = contextAs("student");
    await assertSucceeds(
      setDoc(doc(student.firestore(), `schools/${SCHOOL}/dataRequests/new1`), request("student_1"))
    );
  });

  test("a parent can raise one", async () => {
    const parent = contextAs("parent");
    await assertSucceeds(
      setDoc(doc(parent.firestore(), `schools/${SCHOOL}/dataRequests/new2`), request("parent_1"))
    );
  });

  // Filing in somebody else's name would let one person exercise
  // another's rights, and would poison the record of who asked.
  test("nobody can raise one in somebody else's name", async () => {
    const student = contextAs("student");
    await assertFails(
      setDoc(
        doc(student.firestore(), `schools/${SCHOOL}/dataRequests/new3`),
        request("student_other")
      )
    );
  });

  test("a request cannot arrive already answered", async () => {
    const student = contextAs("student");
    await assertFails(
      setDoc(
        doc(student.firestore(), `schools/${SCHOOL}/dataRequests/new4`),
        request("student_1", {status: "actioned", outcome: "done", handledByName: "Me"})
      )
    );
  });
});

describe("reading requests", () => {
  test("a student can read their own", async () => {
    const student = contextAs("student");
    await assertSucceeds(
      getDoc(doc(student.firestore(), `schools/${SCHOOL}/dataRequests/dsr_mine`))
    );
  });

  test("a student cannot read somebody else's", async () => {
    const student = contextAs("student");
    await assertFails(
      getDoc(doc(student.firestore(), `schools/${SCHOOL}/dataRequests/dsr_other`))
    );
  });

  for (const role of ["director", "admin", "registrar"]) {
    test(`the office (${role}) can read any of them`, async () => {
      const office = contextAs(role);
      await assertSucceeds(
        getDoc(doc(office.firestore(), `schools/${SCHOOL}/dataRequests/dsr_other`))
      );
    });
  }

  // A teacher has no business in the queue of who asked the school about
  // their own records.
  test("a faculty member cannot read them", async () => {
    const faculty = contextAs("faculty");
    await assertFails(
      getDoc(doc(faculty.firestore(), `schools/${SCHOOL}/dataRequests/dsr_mine`))
    );
  });
});

describe("answering requests", () => {
  test("the office can close one", async () => {
    const registrar = contextAs("registrar");
    await assertSucceeds(
      updateDoc(doc(registrar.firestore(), `schools/${SCHOOL}/dataRequests/dsr_mine`), {
        status: "actioned",
        outcome: "Printed and handed over.",
        handledByName: "Joel Bautista",
      })
    );
  });

  test("the person who asked cannot close their own", async () => {
    const student = contextAs("student");
    await assertFails(
      updateDoc(doc(student.firestore(), `schools/${SCHOOL}/dataRequests/dsr_mine`), {
        status: "actioned",
        outcome: "I marked this done myself.",
      })
    );
  });

  // The record of what was asked has to survive the answer.
  test("the office cannot rewrite the question", async () => {
    const registrar = contextAs("registrar");
    await assertFails(
      updateDoc(doc(registrar.firestore(), `schools/${SCHOOL}/dataRequests/dsr_mine`), {
        details: "Actually they asked for something much smaller.",
        status: "actioned",
        outcome: "done",
      })
    );
  });

  test("the office cannot reassign who asked", async () => {
    const registrar = contextAs("registrar");
    await assertFails(
      updateDoc(doc(registrar.firestore(), `schools/${SCHOOL}/dataRequests/dsr_mine`), {
        requestedByUid: "someone_else",
      })
    );
  });

  test("nobody can delete one", async () => {
    const director = contextAs("director");
    await assertFails(
      deleteDoc(doc(director.firestore(), `schools/${SCHOOL}/dataRequests/dsr_mine`))
    );
  });
});

describe("acknowledging the privacy notice", () => {
  beforeEach(async () => {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await setDoc(doc(context.firestore(), `schools/${SCHOOL}/users/student_1`), {
        schoolId: SCHOOL,
        role: "student",
        firstName: "Test",
        lastName: "Student",
      });
    });
  });

  test("a person can record that they read it", async () => {
    const student = contextAs("student", "student_1");
    await assertSucceeds(
      updateDoc(doc(student.firestore(), `schools/${SCHOOL}/users/student_1`), {
        privacyNoticeVersion: 1,
        privacyNoticeAcknowledgedAt: new Date(),
      })
    );
  });

  // The acknowledgement is a self-assertion. Asserting it about somebody
  // else is the one thing that would make the record worthless.
  test("nobody can record it on somebody else's behalf", async () => {
    const other = contextAs("student", "student_other");
    await assertFails(
      updateDoc(doc(other.firestore(), `schools/${SCHOOL}/users/student_1`), {
        privacyNoticeVersion: 1,
      })
    );
  });

  test("it cannot be smuggled in beside a role change", async () => {
    const student = contextAs("student", "student_1");
    await assertFails(
      updateDoc(doc(student.firestore(), `schools/${SCHOOL}/users/student_1`), {
        privacyNoticeVersion: 1,
        role: "director",
      })
    );
  });
});
