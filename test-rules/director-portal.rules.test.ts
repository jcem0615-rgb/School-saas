import {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
  RulesTestEnvironment,
} from "@firebase/rules-unit-testing";
import * as fs from "fs";
import {setDoc, doc, getDoc, updateDoc} from "firebase/firestore";

let testEnv: RulesTestEnvironment;
const SCHOOL = "school_director_test";

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

async function seedActiveSubscription() {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), `platform_subscriptions/${SCHOOL}`), {
      schoolId: SCHOOL,
      currentStatus: "active",
    });
  });
}

function contextAs(role: string, uid = `${role}_1`) {
  return testEnv.authenticatedContext(uid, {
    schoolId: SCHOOL,
    role,
    status: "active",
    mustChangePassword: false,
  });
}

describe("announcements", () => {
  // Faculty gained this when teachers were given a way to address their
  // own classes. The audience field is targeting, not access control, so
  // what the rule actually has to hold is authorship -- which is what
  // these two check.
  test("faculty can post as themselves", async () => {
    await seedActiveSubscription();
    const faculty = contextAs("faculty");
    await assertSucceeds(
      setDoc(doc(faculty.firestore(), `schools/${SCHOOL}/announcements/ann_1`), {
        title: "Test",
        body: "Body",
        createdBy: "faculty_1",
      })
    );
  });

  test("faculty cannot post under someone else's name", async () => {
    await seedActiveSubscription();
    const faculty = contextAs("faculty");
    await assertFails(
      setDoc(doc(faculty.firestore(), `schools/${SCHOOL}/announcements/ann_2`), {
        title: "Test",
        body: "Body",
        createdBy: "director_1",
      })
    );
  });

  test("director can create an announcement", async () => {
    await seedActiveSubscription();
    const director = contextAs("director");
    await assertSucceeds(
      setDoc(doc(director.firestore(), `schools/${SCHOOL}/announcements/ann_1`), {
        title: "Test",
        body: "Body",
        createdBy: "director_1",
      })
    );
  });

  test("a teacher cannot re-sign their own notice with somebody else's name", async () => {
    // The rule pinned `createdBy` and left `createdByName` free -- and
    // the name is the half every reader sees under the notice. Same
    // defect the grades rule had with `submittedByName`.
    await seedActiveSubscription();
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await setDoc(doc(context.firestore(), `schools/${SCHOOL}/announcements/ann_own`), {
        title: "Test",
        body: "Body",
        createdBy: "faculty_1",
        createdByName: "Maria Santos",
      });
    });
    const faculty = contextAs("faculty");
    await assertFails(
      updateDoc(doc(faculty.firestore(), `schools/${SCHOOL}/announcements/ann_own`), {
        body: "Classes are suspended.",
        createdByName: "The Principal",
      })
    );
  });

  test("but may still correct the notice it is signed with", async () => {
    await seedActiveSubscription();
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await setDoc(doc(context.firestore(), `schools/${SCHOOL}/announcements/ann_own2`), {
        title: "Test",
        body: "Body",
        createdBy: "faculty_1",
        createdByName: "Maria Santos",
      });
    });
    const faculty = contextAs("faculty");
    await assertSucceeds(
      updateDoc(doc(faculty.firestore(), `schools/${SCHOOL}/announcements/ann_own2`), {
        body: "Bring the permit slip on Friday instead.",
      })
    );
  });

  test("any tenant member can read announcements", async () => {
    await seedActiveSubscription();
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await setDoc(doc(context.firestore(), `schools/${SCHOOL}/announcements/ann_1`), {
        title: "Test",
        body: "Body",
      });
    });
    const student = contextAs("student");
    await assertSucceeds(getDoc(doc(student.firestore(), `schools/${SCHOOL}/announcements/ann_1`)));
  });
});

describe("approvals", () => {
  test("staff can file a request for themselves", async () => {
    await seedActiveSubscription();
    const staff = contextAs("staff");
    await assertSucceeds(
      setDoc(doc(staff.firestore(), `schools/${SCHOOL}/approvals/req_1`), {
        type: "material_request",
        title: "Need more chalk",
        requestedByRole: "staff",
        status: "pending",
        createdBy: "staff_1",
      })
    );
  });

  test("staff cannot file a request impersonating another role", async () => {
    await seedActiveSubscription();
    const staff = contextAs("staff");
    await assertFails(
      setDoc(doc(staff.firestore(), `schools/${SCHOOL}/approvals/req_2`), {
        type: "material_request",
        title: "Suspicious",
        requestedByRole: "director", // lying about role
        status: "pending",
        createdBy: "staff_1",
      })
    );
  });

  test("staff cannot decide their own request", async () => {
    await seedActiveSubscription();
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await setDoc(doc(context.firestore(), `schools/${SCHOOL}/approvals/req_3`), {
        status: "pending",
        requestedByRole: "staff",
      });
    });
    const staff = contextAs("staff");
    await assertFails(
      updateDoc(doc(staff.firestore(), `schools/${SCHOOL}/approvals/req_3`), {status: "approved"})
    );
  });

  test("director CAN decide a pending request", async () => {
    await seedActiveSubscription();
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await setDoc(doc(context.firestore(), `schools/${SCHOOL}/approvals/req_4`), {
        status: "pending",
        requestedByRole: "staff",
      });
    });
    const director = contextAs("director");
    await assertSucceeds(
      updateDoc(doc(director.firestore(), `schools/${SCHOOL}/approvals/req_4`), {
        status: "approved",
        decidedByUid: "director_1",
        decidedByRole: "director",
      })
    );
  });

  // The header of firestore.rules gives "an Admin deciding requests they
  // filed themselves, which is not an approval" as the reason the
  // Director and the Principal keep this power at all. The rule did not
  // check it until now, so the stated reason for the role was not
  // enforced against anybody -- including the two roles it was meant to
  // protect.
  describe("nobody decides their own request", () => {
    const filedBy = async (id: string, uid: string, role: string) => {
      await testEnv.withSecurityRulesDisabled(async (context) => {
        await setDoc(doc(context.firestore(), `schools/${SCHOOL}/approvals/${id}`), {
          status: "pending",
          requestedByRole: role,
          createdBy: uid,
        });
      });
    };

    test("not the director", async () => {
      await seedActiveSubscription();
      await filedBy("own_1", "director_1", "director");
      const director = contextAs("director");
      await assertFails(
        updateDoc(doc(director.firestore(), `schools/${SCHOOL}/approvals/own_1`), {
          status: "approved",
          decidedByUid: "director_1",
          decidedByRole: "director",
        })
      );
    });

    test("not the admin, which is the case the rule was written for", async () => {
      await seedActiveSubscription();
      await filedBy("own_2", "admin_1", "admin");
      const admin = contextAs("admin");
      await assertFails(
        updateDoc(doc(admin.firestore(), `schools/${SCHOOL}/approvals/own_2`), {
          status: "approved",
          decidedByUid: "admin_1",
          decidedByRole: "admin",
        })
      );
    });

    test("not the principal either", async () => {
      await seedActiveSubscription();
      await filedBy("own_3", "principal_1", "principal");
      const principal = contextAs("principal");
      await assertFails(
        updateDoc(doc(principal.firestore(), `schools/${SCHOOL}/approvals/own_3`), {
          status: "approved",
          decidedByUid: "principal_1",
          decidedByRole: "principal",
        })
      );
    });

    test("but somebody else decides the same request", async () => {
      // The other half. A test that only proves the refusal passes just
      // as well if the rule refuses everybody.
      await seedActiveSubscription();
      await filedBy("own_4", "admin_1", "admin");
      const director = contextAs("director");
      await assertSucceeds(
        updateDoc(doc(director.firestore(), `schools/${SCHOOL}/approvals/own_4`), {
          status: "approved",
          decidedByUid: "director_1",
          decidedByRole: "director",
        })
      );
    });

    test("and a request written before createdBy existed is still decidable", async () => {
      // The rule reads createdBy with a default rather than directly. A
      // missing field would otherwise throw and fail the whole rule,
      // which would strand an old request nobody could ever decide.
      await seedActiveSubscription();
      await testEnv.withSecurityRulesDisabled(async (context) => {
        await setDoc(doc(context.firestore(), `schools/${SCHOOL}/approvals/legacy_1`), {
          status: "pending",
          requestedByRole: "staff",
        });
      });
      const director = contextAs("director");
      await assertSucceeds(
        updateDoc(doc(director.firestore(), `schools/${SCHOOL}/approvals/legacy_1`), {
          status: "approved",
          decidedByUid: "director_1",
          decidedByRole: "director",
        })
      );
    });
  });

  test("a decision must be signed by the account making it", async () => {
    // The approval history exists to answer "who approved this?". If a
    // decider can write somebody else's uid beside their decision, it
    // answers with whatever the client typed.
    await seedActiveSubscription();
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await setDoc(doc(context.firestore(), `schools/${SCHOOL}/approvals/req_5`), {
        status: "pending",
        requestedByRole: "staff",
      });
    });
    const director = contextAs("director");
    await assertFails(
      updateDoc(doc(director.firestore(), `schools/${SCHOOL}/approvals/req_5`), {
        status: "approved",
        decidedByUid: "admin_1", // somebody else
        decidedByRole: "director",
      })
    );
  });

  test("a decision cannot claim a role the decider does not hold", async () => {
    await seedActiveSubscription();
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await setDoc(doc(context.firestore(), `schools/${SCHOOL}/approvals/req_6`), {
        status: "pending",
        requestedByRole: "staff",
      });
    });
    const admin = contextAs("admin");
    await assertFails(
      updateDoc(doc(admin.firestore(), `schools/${SCHOOL}/approvals/req_6`), {
        status: "approved",
        decidedByUid: "admin_1",
        decidedByRole: "director", // an Admin signing as the Director
      })
    );
  });

  test("an unsigned decision is refused outright", async () => {
    await seedActiveSubscription();
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await setDoc(doc(context.firestore(), `schools/${SCHOOL}/approvals/req_7`), {
        status: "pending",
        requestedByRole: "staff",
      });
    });
    const director = contextAs("director");
    await assertFails(
      updateDoc(doc(director.firestore(), `schools/${SCHOOL}/approvals/req_7`), {
        status: "approved",
      })
    );
  });
});

describe("expenses", () => {
  test("faculty cannot read expenses", async () => {
    await seedActiveSubscription();
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await setDoc(doc(context.firestore(), `schools/${SCHOOL}/expenses/exp_1`), {amount: 500});
    });
    const faculty = contextAs("faculty");
    await assertFails(getDoc(doc(faculty.firestore(), `schools/${SCHOOL}/expenses/exp_1`)));
  });

  test("registrar CAN read expenses", async () => {
    await seedActiveSubscription();
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await setDoc(doc(context.firestore(), `schools/${SCHOOL}/expenses/exp_1`), {amount: 500});
    });
    const registrar = contextAs("registrar");
    await assertSucceeds(getDoc(doc(registrar.firestore(), `schools/${SCHOOL}/expenses/exp_1`)));
  });

  test("registrar cannot CREATE an expense (read-only role for this collection)", async () => {
    await seedActiveSubscription();
    const registrar = contextAs("registrar");
    await assertFails(
      setDoc(doc(registrar.firestore(), `schools/${SCHOOL}/expenses/exp_2`), {
        amount: 500,
        createdBy: "registrar_1",
      })
    );
  });
});
