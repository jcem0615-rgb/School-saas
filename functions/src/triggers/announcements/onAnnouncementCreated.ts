import * as admin from "firebase-admin";
import {onDocumentCreated} from "firebase-functions/v2/firestore";
import {FirestorePaths} from "../../shared/firestore-paths";
import {
  audienceIncludes,
  readAudience,
  reachesNobody,
} from "../../shared/announcements/audience";
import {deliver} from "../../shared/notify/deliver";

/**
 * Puts a new announcement in the inbox of everyone it is addressed to,
 * and on their phones.
 *
 * The audience is resolved *here*, server-side, not trusted from the
 * client. The list filter in the app decides what a screen shows; this
 * decides whose phone rings at 5am about a typhoon suspension, and the
 * two failure modes are not comparable. A notification cannot be unsent.
 *
 * Draft/unpublished announcements do not exist for this collection --
 * every announcement is live the moment it is written -- so creation is
 * the right hook. Edits deliberately do not re-notify: correcting a typo
 * in a suspension notice should not buzz eight hundred phones a second
 * time.
 */
export const onAnnouncementCreated = onDocumentCreated(
  {region: "asia-southeast1", document: "schools/{schoolId}/announcements/{announcementId}"},
  async (event) => {
    const schoolId = event.params.schoolId;
    const data = event.data?.data();
    if (!data) return;
    if (data.isDeleted === true) return;

    const audience = readAudience(data);
    if (reachesNobody(audience)) {
      // Addressed to nobody. The editor disables Post in this state; this
      // is the second line, for anything written straight to Firestore.
      return;
    }

    const db = admin.firestore();

    // Every active user in the school, filtered in memory by the same
    // rule the app's list uses. A role-based `where in` query cannot
    // express "all OR one of these roles" in one pass, and a school's
    // user count is in the hundreds, not the millions.
    const usersSnap = await db.collection(FirestorePaths.users(schoolId)).get();
    const active = usersSnap.docs.filter((doc) => doc.data().status === "active");

    // Only for a class notice, and only then: it costs two more
    // collection reads, and a school-wide notice has no use for them.
    const sections = audience.sections.length > 0 ?
      await sectionsByUid(db, schoolId, active) :
      new Map<string, string[]>();

    const recipients = active
      .filter((doc) =>
        audienceIncludes(audience, doc.data().role as string, sections.get(doc.id) ?? [])
      )
      .map((doc) => doc.id);

    await deliver({
      schoolId,
      recipientUids: recipients,
      kind: "announcement",
      title: (data.title as string) ?? "Announcement",
      body: (data.body as string) ?? "",
      link: "/notifications",
      sourceId: event.params.announcementId,
      data: {announcementId: event.params.announcementId},
    });
  }
);

/**
 * Which classes each person is in.
 *
 * Four roles reach a section by four different routes, and this has to
 * know all of them -- the same list `viewerSectionsProvider` holds on the
 * client, resolved from the same records:
 *
 *   student -- their own student record's section
 *   parent  -- the sections of the children they are linked to
 *   faculty -- the sections they are assigned to, advisory or not
 *   anybody else -- none, which is right: a cashier is not in a class
 *
 * Read whole rather than queried by section. `where("section", "in", ...)`
 * would match exactly, and section names are typed by hand in two places
 * -- the failure would be a parent silently missing the notice about
 * tomorrow's field trip, which is the failure this function exists to
 * prevent. A school's roll is in the hundreds; the audience filter that
 * follows is in memory anyway.
 */
async function sectionsByUid(
  db: FirebaseFirestore.Firestore,
  schoolId: string,
  activeUsers: FirebaseFirestore.QueryDocumentSnapshot[]
): Promise<Map<string, string[]>> {
  const [studentsSnap, assignmentsSnap] = await Promise.all([
    db.collection(FirestorePaths.students(schoolId)).where("isDeleted", "==", false).get(),
    db.collection(FirestorePaths.teacherAssignments(schoolId)).get(),
  ]);

  const sections = new Map<string, string[]>();
  const add = (uid: string | undefined, section: string | undefined) => {
    if (!uid || !section) return;
    const existing = sections.get(uid);
    if (existing) existing.push(section);
    else sections.set(uid, [section]);
  };

  // studentId -> section, for the parents below. A student's academic
  // record exists whether or not they have a portal account, which is
  // why `linkedStudentIds` holds that id and not a uid.
  const sectionOfStudent = new Map<string, string>();
  for (const doc of studentsSnap.docs) {
    const student = doc.data();
    const section = student.section as string | undefined;
    if (section) sectionOfStudent.set(doc.id, section);
    add(student.userId as string | undefined, section);
  }

  for (const doc of assignmentsSnap.docs) {
    const assignment = doc.data();
    add(assignment.teacherId as string | undefined, assignment.section as string | undefined);
  }

  for (const doc of activeUsers) {
    const user = doc.data();
    if (user.role !== "parent") continue;
    const linked = user.linkedStudentIds;
    if (!Array.isArray(linked)) continue;
    for (const studentId of linked) {
      add(doc.id, sectionOfStudent.get(studentId as string));
    }
  }

  return sections;
}
