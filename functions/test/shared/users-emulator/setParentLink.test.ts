/**
 * Requires the Firestore emulator.
 * Run via: firebase emulators:exec --only firestore "jest test/shared/users-emulator"
 *
 * The callable itself, not the array arithmetic underneath it -- that is
 * covered pure in test/shared/users/parentLinks.test.ts. What is tested
 * here is everything the pure function cannot see: who is allowed to
 * call, what the records have to look like first, what actually lands in
 * Firestore, and what gets written to the audit trail.
 *
 * It is worth this much testing for one reason. `linkedStudentIds` is not
 * a profile field; it is the whole of a parent's access. Every parent read
 * in firestore.rules -- grades, attendance, the statement of account,
 * guidance summons, emergency alerts, the messaging thread -- resolves to
 * "is this studentId in that array?".
 *
 * So a wrong link hands one family another family's child: their marks,
 * their balance, and a private line to their teacher. Nobody is notified.
 * Nothing on either screen looks unusual. The only thing standing between
 * that and a school is this function, and the audit line it writes.
 */
import functionsTest from "firebase-functions-test";
import * as admin from "firebase-admin";
import {FirestorePaths} from "../../../src/shared/firestore-paths";

const fft = functionsTest({projectId: "school-saas-test"});

const SCHOOL = "school_parent_link";
const OTHER_SCHOOL = "school_parent_link_other";

const PARENT = "parent_rosario";
const MIGUEL = "stu_miguel";
const BEA = "stu_bea";
const ANDREA = "stu_andrea";

// eslint-disable-next-line @typescript-eslint/no-explicit-any
let callSetParentLink: any;

function db() {
  return admin.firestore();
}

/** A caller, shaped the way requireCallerClaims reads one. */
function caller(role: string, uid = `${role}_1`, schoolId: string | undefined = SCHOOL) {
  return {
    uid,
    token: {role, schoolId, status: "active", mustChangePassword: false, name: `${role} one`},
  };
}

async function call(
  data: Record<string, unknown>,
  auth: ReturnType<typeof caller> | null = caller("registrar")
) {
  return callSetParentLink({data, auth} as never);
}

/** The link array as Firestore actually holds it right now. */
async function linksOf(uid = PARENT, schoolId = SCHOOL): Promise<unknown> {
  const snap = await db().doc(FirestorePaths.userDoc(schoolId, uid)).get();
  return snap.data()?.linkedStudentIds;
}

async function auditRows(schoolId = SCHOOL) {
  const snap = await db().collection(FirestorePaths.auditLog(schoolId)).get();
  return snap.docs.map((d) => d.data());
}

async function wipe(schoolId: string) {
  for (const path of [
    FirestorePaths.users(schoolId),
    FirestorePaths.students(schoolId),
    FirestorePaths.auditLog(schoolId),
  ]) {
    const snap = await db().collection(path).get();
    await Promise.all(snap.docs.map((d) => d.ref.delete()));
  }
}

async function seed() {
  await wipe(SCHOOL);
  await wipe(OTHER_SCHOOL);

  await db().doc(FirestorePaths.userDoc(SCHOOL, PARENT)).set({
    id: PARENT,
    schoolId: SCHOOL,
    role: "parent",
    firstName: "Rosario",
    lastName: "Torres",
    email: "rosario@example.ph",
    status: "active",
    isDeleted: false,
    linkedStudentIds: [MIGUEL],
  });

  // A teacher, for the "only a parent account can be linked" case.
  await db().doc(FirestorePaths.userDoc(SCHOOL, "faculty_maria")).set({
    id: "faculty_maria",
    schoolId: SCHOOL,
    role: "faculty",
    firstName: "Maria",
    lastName: "Santos",
    status: "active",
    isDeleted: false,
  });

  // A parent whose account has been soft-deleted.
  await db().doc(FirestorePaths.userDoc(SCHOOL, "parent_gone")).set({
    id: "parent_gone",
    schoolId: SCHOOL,
    role: "parent",
    firstName: "Gone",
    lastName: "Away",
    status: "active",
    isDeleted: true,
    linkedStudentIds: [],
  });

  for (const [id, first] of [
    [MIGUEL, "Miguel"],
    [BEA, "Bea"],
    [ANDREA, "Andrea"],
  ] as const) {
    await db().doc(FirestorePaths.studentDoc(SCHOOL, id)).set({
      id,
      schoolId: SCHOOL,
      firstName: first,
      lastName: id === ANDREA ? "Villanueva" : "Torres",
      isDeleted: false,
    });
  }

  await db().doc(FirestorePaths.studentDoc(SCHOOL, "stu_withdrawn")).set({
    id: "stu_withdrawn",
    schoolId: SCHOOL,
    firstName: "Withdrawn",
    lastName: "Pupil",
    isDeleted: true,
  });
}

describe("setParentLink", () => {
  beforeAll(async () => {
    if (admin.apps.length === 0) {
      admin.initializeApp({projectId: "school-saas-test"});
    }
    const {setParentLink} = await import("../../../src/callable/users/setParentLink");
    callSetParentLink = fft.wrap(setParentLink);
  });

  afterAll(async () => {
    await wipe(SCHOOL);
    await wipe(OTHER_SCHOOL);
    fft.cleanup();
  });

  beforeEach(seed);

  describe("who may call it", () => {
    it("refuses a caller who is not signed in", async () => {
      await expect(
        call({schoolId: SCHOOL, parentUid: PARENT, studentId: BEA, linked: true}, null)
      ).rejects.toThrow(/signed in/i);
    });

    it("lets the three roles that enrol children do it", async () => {
      for (const role of ["registrar", "admin", "director"]) {
        await seed();
        const result = await call(
          {schoolId: SCHOOL, parentUid: PARENT, studentId: BEA, linked: true},
          caller(role)
        );
        expect(result.changed).toBe(true);
      }
    });

    it("refuses faculty and guidance, who know families but do not grant access", async () => {
      // Deliberate, and the reason worth stating: a class adviser knowing
      // a family is not the same as being allowed to hand somebody sight
      // of a child's record.
      for (const role of ["faculty", "guidance"]) {
        await expect(
          call(
            {schoolId: SCHOOL, parentUid: PARENT, studentId: BEA, linked: true},
            caller(role)
          )
        ).rejects.toThrow(/requires one of the following roles/i);
      }
      expect(await linksOf()).toEqual([MIGUEL]);
    });

    it("refuses a parent trying to reach a second child", async () => {
      // The write an attacker with a stolen parent login would try first.
      await expect(
        call(
          {schoolId: SCHOOL, parentUid: PARENT, studentId: ANDREA, linked: true},
          caller("parent", PARENT)
        )
      ).rejects.toThrow(/requires one of the following roles/i);
      expect(await linksOf()).toEqual([MIGUEL]);
    });

    it("refuses a registrar at a different school", async () => {
      // The tenant boundary. Their claims are valid; the school in them
      // is not this one.
      await expect(
        call(
          {schoolId: SCHOOL, parentUid: PARENT, studentId: BEA, linked: true},
          caller("registrar", "registrar_elsewhere", OTHER_SCHOOL)
        )
      ).rejects.toThrow();
      expect(await linksOf()).toEqual([MIGUEL]);
    });
  });

  describe("what it insists on being told", () => {
    it("refuses a call missing any of the four arguments", async () => {
      const full = {schoolId: SCHOOL, parentUid: PARENT, studentId: BEA, linked: true};
      for (const missing of ["schoolId", "parentUid", "studentId", "linked"]) {
        const data = {...full} as Record<string, unknown>;
        delete data[missing];
        await expect(call(data)).rejects.toThrow(/Missing schoolId/);
      }
    });

    it("refuses a linked flag that is not a boolean", async () => {
      // "false" and 0 are the shapes a hand-built client sends, and both
      // would otherwise be truthy-tested into the wrong direction.
      for (const linked of ["true", "false", 0, 1, null]) {
        await expect(
          call({schoolId: SCHOOL, parentUid: PARENT, studentId: BEA, linked})
        ).rejects.toThrow(/Missing schoolId/);
      }
    });
  });

  describe("what the records have to look like first", () => {
    it("refuses a parent account that does not exist", async () => {
      await expect(
        call({schoolId: SCHOOL, parentUid: "parent_nobody", studentId: BEA, linked: true})
      ).rejects.toThrow(/parent account was not found/i);
    });

    it("refuses a parent account that has been soft-deleted", async () => {
      // isDeleted is how this system removes anything. A closed account
      // that could still be granted access would be the quietest kind of
      // hole: it does not appear in any list the office looks at.
      await expect(
        call({schoolId: SCHOOL, parentUid: "parent_gone", studentId: BEA, linked: true})
      ).rejects.toThrow(/parent account was not found/i);
    });

    it("refuses to put linkedStudentIds on an account that is not a parent", async () => {
      // Refused rather than allowed-and-ignored. The field does nothing on
      // a faculty account today, and would silently become a grant the day
      // any rule stopped checking the role first.
      await expect(
        call({schoolId: SCHOOL, parentUid: "faculty_maria", studentId: BEA, linked: true})
      ).rejects.toThrow(/Only a parent account/i);

      const teacher = await db().doc(FirestorePaths.userDoc(SCHOOL, "faculty_maria")).get();
      expect(teacher.data()?.linkedStudentIds).toBeUndefined();
    });

    it("refuses a student who does not exist", async () => {
      // A link naming nobody is not merely useless: it is a row in an
      // access list that cannot be evaluated, and it survives every audit
      // because there is nothing left to compare it against.
      await expect(
        call({schoolId: SCHOOL, parentUid: PARENT, studentId: "stu_nobody", linked: true})
      ).rejects.toThrow(/student record was not found/i);
      expect(await linksOf()).toEqual([MIGUEL]);
    });

    it("refuses a student record that has been soft-deleted", async () => {
      await expect(
        call({schoolId: SCHOOL, parentUid: PARENT, studentId: "stu_withdrawn", linked: true})
      ).rejects.toThrow(/student record was not found/i);
    });

    it("will not reach a parent in another school by naming this one", async () => {
      // parentUid is a document id, and document ids are not unique across
      // tenants. The lookup is scoped by schoolId, so this resolves to
      // nothing rather than to somebody else's parent.
      await db().doc(FirestorePaths.userDoc(OTHER_SCHOOL, PARENT)).set({
        id: PARENT,
        schoolId: OTHER_SCHOOL,
        role: "parent",
        firstName: "Someone",
        lastName: "Else",
        isDeleted: false,
        linkedStudentIds: [],
      });

      await expect(
        call(
          {schoolId: OTHER_SCHOOL, parentUid: PARENT, studentId: MIGUEL, linked: true},
          caller("registrar", "registrar_elsewhere", OTHER_SCHOOL)
        )
      ).rejects.toThrow(/student record was not found/i);

      // And the real Rosario is untouched by the attempt.
      expect(await linksOf()).toEqual([MIGUEL]);
    });
  });

  describe("linking", () => {
    it("adds the child and says the record changed", async () => {
      const result = await call({
        schoolId: SCHOOL,
        parentUid: PARENT,
        studentId: BEA,
        linked: true,
      });

      expect(result).toEqual({changed: true, linkedStudentIds: [MIGUEL, BEA]});
      // Read back from Firestore rather than trusted from the return
      // value: what the rules will resolve against is the document.
      expect(await linksOf()).toEqual([MIGUEL, BEA]);
    });

    it("stamps who did it on the parent record", async () => {
      await call(
        {schoolId: SCHOOL, parentUid: PARENT, studentId: BEA, linked: true},
        caller("registrar", "registrar_ana")
      );
      const snap = await db().doc(FirestorePaths.userDoc(SCHOOL, PARENT)).get();
      expect(snap.data()?.updatedBy).toBe("registrar_ana");
      expect(snap.data()?.updatedAt).toBeDefined();
    });

    it("linking the same child twice writes nothing the second time", async () => {
      await call({schoolId: SCHOOL, parentUid: PARENT, studentId: BEA, linked: true});
      const afterFirst = await db().doc(FirestorePaths.userDoc(SCHOOL, PARENT)).get();

      const second = await call({
        schoolId: SCHOOL,
        parentUid: PARENT,
        studentId: BEA,
        linked: true,
      });

      expect(second).toEqual({changed: false, linkedStudentIds: [MIGUEL, BEA]});
      expect(await linksOf()).toEqual([MIGUEL, BEA]);

      // The point of returning `changed` rather than throwing: two
      // registrars working the same enrolment queue is not an error, but
      // it must not write. updateTime unchanged is the proof.
      const afterSecond = await db().doc(FirestorePaths.userDoc(SCHOOL, PARENT)).get();
      expect(afterSecond.updateTime?.isEqual(afterFirst.updateTime!)).toBe(true);
    });

    it("a re-link leaves no audit row behind", async () => {
      // Otherwise the trail fills with grants nobody made, and the rows
      // that matter get harder to find in it.
      await call({schoolId: SCHOOL, parentUid: PARENT, studentId: BEA, linked: true});
      await call({schoolId: SCHOOL, parentUid: PARENT, studentId: BEA, linked: true});
      await call({schoolId: SCHOOL, parentUid: PARENT, studentId: BEA, linked: true});

      const rows = await auditRows();
      expect(rows.filter((r) => r.action === "link_parent")).toHaveLength(1);
    });
  });

  describe("unlinking", () => {
    it("removes only the named child", async () => {
      await call({schoolId: SCHOOL, parentUid: PARENT, studentId: BEA, linked: true});
      const result = await call({
        schoolId: SCHOOL,
        parentUid: PARENT,
        studentId: MIGUEL,
        linked: false,
      });

      expect(result).toEqual({changed: true, linkedStudentIds: [BEA]});
      expect(await linksOf()).toEqual([BEA]);
    });

    it("unlinking a child who was never linked changes nothing", async () => {
      const result = await call({
        schoolId: SCHOOL,
        parentUid: PARENT,
        studentId: ANDREA,
        linked: false,
      });
      expect(result).toEqual({changed: false, linkedStudentIds: [MIGUEL]});
      expect(await linksOf()).toEqual([MIGUEL]);
    });

    it("removing the last child leaves an empty array, not a missing field", async () => {
      // A parent account with no children is a real state -- the family
      // left, or a wrong link was corrected before the right one was
      // made. It has to read correctly: `in []` is false, so the account
      // signs in and sees nothing. A deleted field would make every
      // `resource.data.linkedStudentIds` lookup in the rules error.
      const result = await call({
        schoolId: SCHOOL,
        parentUid: PARENT,
        studentId: MIGUEL,
        linked: false,
      });

      expect(result).toEqual({changed: true, linkedStudentIds: []});
      const stored = await linksOf();
      expect(stored).toEqual([]);
      expect(stored).not.toBeUndefined();
    });
  });

  describe("the audit trail", () => {
    it("records a grant, naming the child rather than only its id", async () => {
      // Somebody reviewing the trail should not have to open two other
      // records to find out what happened.
      await call(
        {schoolId: SCHOOL, parentUid: PARENT, studentId: BEA, linked: true},
        caller("registrar", "registrar_ana")
      );

      const rows = await auditRows();
      expect(rows).toHaveLength(1);
      const row = rows[0];
      expect(row.module).toBe("users");
      expect(row.action).toBe("link_parent");
      expect(row.targetId).toBe(PARENT);
      expect(row.userId).toBe("registrar_ana");
      expect(row.userRole).toBe("registrar");
      expect(row.success).toBe(true);
      expect(row.remarks).toContain("Bea Torres");
      expect((row.newValue as Record<string, unknown>).studentId).toBe(BEA);
      expect((row.newValue as Record<string, unknown>).linkedStudentIds)
        .toEqual([MIGUEL, BEA]);
    });

    it("records a removal as its own action, not as another grant", async () => {
      await call({schoolId: SCHOOL, parentUid: PARENT, studentId: MIGUEL, linked: false});

      const rows = await auditRows();
      expect(rows).toHaveLength(1);
      expect(rows[0].action).toBe("unlink_parent");
      expect(rows[0].remarks).toMatch(/Removed/i);
      expect(rows[0].remarks).toContain("Miguel Torres");
    });

    it("writes nothing at all when the call was refused", async () => {
      // A refusal is not an event the school needs in this trail, and a
      // row claiming success:false for a call that never touched the
      // record would be worse than none.
      await expect(
        call({schoolId: SCHOOL, parentUid: "faculty_maria", studentId: BEA, linked: true})
      ).rejects.toThrow();
      await expect(
        call({schoolId: SCHOOL, parentUid: PARENT, studentId: "stu_nobody", linked: true})
      ).rejects.toThrow();

      expect(await auditRows()).toHaveLength(0);
    });
  });

  describe("a mother with two children", () => {
    it("is one account linked twice, and unlinking one leaves the other", async () => {
      // The case the whole feature exists for. If the only path were
      // "create an account per student", this family would have two
      // logins and neither would show both children.
      await call({schoolId: SCHOOL, parentUid: PARENT, studentId: BEA, linked: true});
      expect(await linksOf()).toEqual([MIGUEL, BEA]);

      await call({schoolId: SCHOOL, parentUid: PARENT, studentId: MIGUEL, linked: false});
      expect(await linksOf()).toEqual([BEA]);

      // And she can be given back the first child later, at the end.
      const back = await call({
        schoolId: SCHOOL,
        parentUid: PARENT,
        studentId: MIGUEL,
        linked: true,
      });
      expect(back.linkedStudentIds).toEqual([BEA, MIGUEL]);
    });
  });
});
