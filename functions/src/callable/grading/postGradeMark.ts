import * as admin from "firebase-admin";
import {onCall, HttpsError, CallableRequest} from "firebase-functions/v2/https";
import {requireCallerClaims, requireRole, requireSameSchool} from "../../shared/auth/claims";
import {writeAuditLog} from "../../shared/audit/writeAuditLog";
import {FirestorePaths} from "../../shared/firestore-paths";
import {
  GradingError,
  classKey,
  scoreDocId,
  validateAssessment,
  validateScore,
} from "../../shared/grading/assessment";

interface PostMarkData {
  schoolId: string;
  studentId: string;
  studentName: string;
  subject: string;
  section: string;
  term: string;
  component: string;
  score: number;
  maxScore: number;
  /** What the work was called. Blank becomes the component's own name. */
  title?: string;
  remarks?: string;
}

const TEACHING_ROLES = ["admin", "faculty"];

/**
 * One mark, posted without setting up a column first.
 *
 * The path the spreadsheet import and the single-student dialog use. It
 * finds or creates the piece of work the mark belongs to, keyed by what
 * makes it that piece of work -- class, quarter, component, name, and
 * what it is out of -- and then writes the mark against it at the same
 * derived id `saveAssessmentScores` uses.
 *
 * That last part is the whole point. Before this, every post wrote a new
 * document, and the quarterly arithmetic sums the scores and the
 * maximums inside a component: re-running an import doubled a child's
 * written work, and correcting 80-out-of-10 to 8-out-of-10 left them on
 * 88 out of 20. The import worked around the first case by refusing a
 * row identical to one already on file and could do nothing about the
 * second, because a corrected mark is not an identical one.
 */
export const postGradeMark = onCall(
  {region: "asia-southeast1"},
  async (request: CallableRequest<PostMarkData>) => {
    const callerClaims = requireCallerClaims(request);
    const data = request.data ?? ({} as PostMarkData);
    const {schoolId, studentId} = data;

    if (!schoolId || !studentId) {
      throw new HttpsError("invalid-argument", "Which student, in which school?");
    }
    requireSameSchool(callerClaims, schoolId);
    requireRole(callerClaims, TEACHING_ROLES);

    const title =
      typeof data.title === "string" && data.title.trim().length > 0
        ? data.title.trim()
        : typeof data.remarks === "string" && data.remarks.trim().length > 0
          ? data.remarks.trim()
          : null;

    let assessment;
    let score;
    try {
      assessment = validateAssessment({
        subject: data.subject,
        section: data.section,
        term: data.term,
        // A mark posted with nothing naming it still belongs to
        // something. Named after its component so the class record shows
        // a column a teacher recognises rather than a blank header.
        title: title ?? labelFor(data.component),
        component: data.component,
        maxScore: data.maxScore,
      });
      score = validateScore(data.score, assessment.maxScore);
    } catch (error) {
      if (error instanceof GradingError) {
        throw new HttpsError("invalid-argument", error.message);
      }
      throw error;
    }
    if (score === null) {
      throw new HttpsError("invalid-argument", "A mark needs a score.");
    }

    // Deterministic, so the same piece of work posted for thirty
    // children is one column rather than thirty. Two genuinely different
    // quizzes with the same name and the same total in one quarter land
    // on one column -- the same caveat the import has always carried,
    // and naming one of them is the way through.
    const assessmentId = [
      classKey(assessment.subject, assessment.section, assessment.term),
      assessment.component,
      slug(assessment.title),
      String(assessment.maxScore),
    ].join("__");

    const db = admin.firestore();
    const uid = request.auth!.uid;
    const name = (request.auth!.token.name as string) ?? "Unknown";
    const now = admin.firestore.FieldValue.serverTimestamp();

    const assessmentRef = db.doc(
      FirestorePaths.classAssessmentDoc(schoolId, assessmentId)
    );
    const markRef = db.doc(
      FirestorePaths.gradeDoc(schoolId, scoreDocId(assessmentId, studentId))
    );

    const batch = db.batch();
    batch.set(
      assessmentRef,
      {
        id: assessmentId,
        schoolId,
        classKey: classKey(assessment.subject, assessment.section, assessment.term),
        subject: assessment.subject,
        section: assessment.section,
        term: assessment.term,
        title: assessment.title,
        component: assessment.component,
        maxScore: assessment.maxScore,
        isDeleted: false,
        createdAt: now,
        createdBy: uid,
        createdByName: name,
        updatedAt: now,
        updatedBy: uid,
      },
      {merge: true}
    );
    batch.set(
      markRef,
      {
        id: markRef.id,
        schoolId,
        assessmentId,
        studentId,
        studentName: typeof data.studentName === "string" ? data.studentName.trim() : "",
        subject: assessment.subject,
        section: assessment.section,
        term: assessment.term,
        component: assessment.component,
        courseworkItemId: null,
        score,
        maxScore: assessment.maxScore,
        remarks:
          typeof data.remarks === "string" && data.remarks.trim().length > 0
            ? data.remarks.trim()
            : null,
        submittedByName: name,
        submittedAt: now,
        isDeleted: false,
        createdAt: now,
        createdBy: uid,
        updatedAt: now,
        updatedBy: uid,
        deletedAt: null,
        deletedBy: null,
      },
      {merge: true}
    );
    await batch.commit();

    await writeAuditLog({
      schoolId,
      userId: uid,
      userRole: callerClaims.role,
      userName: name,
      module: "grading",
      action: "mark_posted",
      targetCollection: FirestorePaths.grades(schoolId),
      targetId: markRef.id,
      newValue: {
        studentId,
        subject: assessment.subject,
        term: assessment.term,
        title: assessment.title,
        score,
        maxScore: assessment.maxScore,
      },
      success: true,
    });

    return {assessmentId, gradeId: markRef.id};
  }
);

function slug(value: string): string {
  return (
    value
      .trim()
      .toLowerCase()
      .replace(/[^a-z0-9]+/g, "-")
      .replace(/^-+|-+$/g, "")
      .slice(0, 60) || "untitled"
  );
}

function labelFor(component: unknown): string {
  switch (component) {
  case "performance_task":
    return "Performance task";
  case "quarterly_assessment":
    return "Quarterly assessment";
  default:
    return "Written work";
  }
}
