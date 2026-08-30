import {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
  RulesTestEnvironment,
} from "@firebase/rules-unit-testing";
import * as fs from "fs";
import {
  setDoc,
  doc,
  getDoc,
  getDocs,
  updateDoc,
  deleteDoc,
  collection,
  query,
  where,
} from "firebase/firestore";

/**
 * Parent-teacher messaging.
 *
 * Two people, and nobody else. Whether they may talk at all was settled
 * by the callable; what these rules have to hold is that only the two of
 * them can read the thread, that a message carries the sender it was
 * actually sent by, and that neither side can rewrite what was said.
 */

let testEnv: RulesTestEnvironment;
const SCHOOL = "school_messaging_test";
const CONV = "teacher_a__parent_a__stu_a";

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

const message = (overrides: Record<string, unknown> = {}) => ({
  senderUid: "parent_a",
  senderName: "Rosario Torres",
  senderRole: "parent",
  text: "Good morning po, about Miguel's absences.",
  sentAt: new Date("2026-03-03T01:00:00Z"),
  ...overrides,
});

async function seed() {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await setDoc(doc(db, `platform_subscriptions/${SCHOOL}`), {
      schoolId: SCHOOL,
      currentStatus: "active",
    });
    await setDoc(doc(db, `schools/${SCHOOL}/conversations/${CONV}`), {
      id: CONV,
      participantUids: ["teacher_a", "parent_a"],
      teacherUid: "teacher_a",
      teacherName: "Maria Santos",
      parentUid: "parent_a",
      parentName: "Rosario Torres",
      studentId: "stu_a",
      studentName: "Miguel Torres",
      section: "Grade 10 - Rizal",
      lastMessage: null,
      lastMessageAt: null,
      lastSenderUid: null,
      unread: {teacher_a: 2, parent_a: 0},
      isDeleted: false,
    });
    await setDoc(
      doc(db, `schools/${SCHOOL}/conversations/${CONV}/messages/msg_1`),
      message()
    );
  });
}

beforeEach(seed);

describe("reading a conversation", () => {
  it("both participants can", async () => {
    for (const [role, uid] of [
      ["faculty", "teacher_a"],
      ["parent", "parent_a"],
    ] as const) {
      const db = contextAs(role, uid).firestore();
      await assertSucceeds(getDoc(doc(db, `schools/${SCHOOL}/conversations/${CONV}`)));
      await assertSucceeds(
        getDocs(collection(db, `schools/${SCHOOL}/conversations/${CONV}/messages`))
      );
    }
  });

  it("nobody else can -- not another teacher, not the director", async () => {
    // Deliberate, and the whole shape of the feature. A school that
    // needs to see one of these has a lawful-request path and an audit
    // trail, not a rule that quietly makes every private conversation
    // readable by the office.
    for (const [role, uid] of [
      ["faculty", "teacher_b"],
      ["parent", "parent_b"],
      ["admin", "admin_a"],
      ["director", "director_a"],
      ["guidance", "guidance_a"],
    ] as const) {
      const db = contextAs(role, uid).firestore();
      await assertFails(getDoc(doc(db, `schools/${SCHOOL}/conversations/${CONV}`)));
      await assertFails(
        getDocs(collection(db, `schools/${SCHOOL}/conversations/${CONV}/messages`))
      );
    }
  });

  it("a participant lists their own conversations", async () => {
    const db = contextAs("parent", "parent_a").firestore();
    await assertSucceeds(
      getDocs(
        query(
          collection(db, `schools/${SCHOOL}/conversations`),
          where("participantUids", "array-contains", "parent_a")
        )
      )
    );
  });

  it("but cannot list everybody's", async () => {
    const db = contextAs("parent", "parent_a").firestore();
    await assertFails(getDocs(collection(db, `schools/${SCHOOL}/conversations`)));
  });
});

describe("sending", () => {
  it("a participant sends as themselves", async () => {
    const db = contextAs("parent", "parent_a").firestore();
    await assertSucceeds(
      setDoc(
        doc(db, `schools/${SCHOOL}/conversations/${CONV}/messages/msg_2`),
        message()
      )
    );
  });

  it("but not in the other person's name", async () => {
    // Without the sender pin, either side could put words in the
    // other's mouth in a thread the school might later read.
    const db = contextAs("parent", "parent_a").firestore();
    await assertFails(
      setDoc(
        doc(db, `schools/${SCHOOL}/conversations/${CONV}/messages/msg_2`),
        message({senderUid: "teacher_a", senderName: "Maria Santos"})
      )
    );
  });

  it("an outsider cannot send at all", async () => {
    const db = contextAs("faculty", "teacher_b").firestore();
    await assertFails(
      setDoc(
        doc(db, `schools/${SCHOOL}/conversations/${CONV}/messages/msg_2`),
        message({senderUid: "teacher_b"})
      )
    );
  });

  it("an empty message is refused", async () => {
    const db = contextAs("parent", "parent_a").firestore();
    await assertFails(
      setDoc(
        doc(db, `schools/${SCHOOL}/conversations/${CONV}/messages/msg_2`),
        message({text: ""})
      )
    );
  });

  it("and one long enough to be a problem", async () => {
    const db = contextAs("parent", "parent_a").firestore();
    await assertFails(
      setDoc(
        doc(db, `schools/${SCHOOL}/conversations/${CONV}/messages/msg_2`),
        message({text: "a".repeat(4001)})
      )
    );
  });
});

describe("what was said stays said", () => {
  it("nobody edits a message", async () => {
    const db = contextAs("parent", "parent_a").firestore();
    await assertFails(
      updateDoc(doc(db, `schools/${SCHOOL}/conversations/${CONV}/messages/msg_1`), {
        text: "I never said that.",
      })
    );
  });

  it("nobody unsends one", async () => {
    const db = contextAs("parent", "parent_a").firestore();
    await assertFails(
      deleteDoc(doc(db, `schools/${SCHOOL}/conversations/${CONV}/messages/msg_1`))
    );
  });
});

describe("the conversation summary", () => {
  it("a participant clears their own unread count", async () => {
    const db = contextAs("faculty", "teacher_a").firestore();
    await assertSucceeds(
      updateDoc(doc(db, `schools/${SCHOOL}/conversations/${CONV}`), {
        unread: {teacher_a: 0, parent_a: 0},
      })
    );
  });

  it("but cannot clear the other person's", async () => {
    // Otherwise "I read it" becomes "you read it", and the other side's
    // badge disappears without them ever opening the thread.
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await updateDoc(
        doc(context.firestore(), `schools/${SCHOOL}/conversations/${CONV}`),
        {unread: {teacher_a: 2, parent_a: 3}}
      );
    });
    const db = contextAs("faculty", "teacher_a").firestore();
    await assertFails(
      updateDoc(doc(db, `schools/${SCHOOL}/conversations/${CONV}`), {
        unread: {teacher_a: 0, parent_a: 0},
      })
    );
  });

  it("cannot rewrite the last message or move the thread up the list", async () => {
    const db = contextAs("faculty", "teacher_a").firestore();
    await assertFails(
      updateDoc(doc(db, `schools/${SCHOOL}/conversations/${CONV}`), {
        unread: {teacher_a: 0, parent_a: 0},
        lastMessage: "Something else entirely",
      })
    );
  });

  it("cannot add itself to somebody else's conversation", async () => {
    const db = contextAs("faculty", "teacher_b").firestore();
    await assertFails(
      updateDoc(doc(db, `schools/${SCHOOL}/conversations/${CONV}`), {
        participantUids: ["teacher_a", "parent_a", "teacher_b"],
      })
    );
  });

  it("no client creates or deletes a conversation", async () => {
    const db = contextAs("parent", "parent_a").firestore();
    await assertFails(
      setDoc(doc(db, `schools/${SCHOOL}/conversations/forged`), {
        participantUids: ["parent_a", "teacher_b"],
      })
    );
    await assertFails(
      deleteDoc(doc(db, `schools/${SCHOOL}/conversations/${CONV}`))
    );
  });
});
