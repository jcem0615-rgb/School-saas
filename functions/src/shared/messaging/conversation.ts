/**
 * Who may talk to whom, and what a thread between them is called.
 *
 * A parent and a teacher can message each other when the teacher teaches
 * that parent's child. That is the whole rule, and it is resolved
 * server-side from records neither of them can edit -- the teacher's
 * assignments, the student's section, the parent's linked children.
 *
 * It cannot be expressed in firestore.rules, because deciding it needs a
 * *query* (which of this teacher's assignments covers that section) and
 * rules can only `get` a document by path. So starting a conversation is
 * a callable, and the rules then police membership of the conversation
 * it produced -- which they can do, because by then the answer is a
 * field on a document.
 */

/**
 * One thread per teacher, parent and child.
 *
 * Per child, not per pair: a parent with two children taught by the same
 * teacher gets two threads, and "which child is this about" stays
 * answerable without anybody having to say so in the first message.
 *
 * Deterministic, so two people opening a conversation with each other at
 * the same moment land in the same one. A generated id gives them two
 * threads, each holding half the conversation, and neither knows the
 * other exists -- the classic way messaging goes wrong.
 */
export function conversationId(
  teacherUid: string,
  parentUid: string,
  studentId: string
): string {
  return `${teacherUid}__${parentUid}__${studentId}`;
}

/** A message long enough to be a problem rather than a message. */
export const MAX_MESSAGE_LENGTH = 4000;

/**
 * Whether [text] is something worth sending.
 *
 * Trimmed-empty is refused because an empty bubble tells the other
 * person nothing and still rings their phone.
 */
export function isSendableMessage(text: string): boolean {
  const trimmed = text.trim();
  return trimmed.length > 0 && trimmed.length <= MAX_MESSAGE_LENGTH;
}

/**
 * The one-line summary shown in the conversation list.
 *
 * Collapsed to a single line: a message with newlines in it would
 * otherwise make one row three rows tall and push the rest off screen.
 */
export function previewOf(text: string, limit = 120): string {
  const flat = text.replace(/\s+/g, " ").trim();
  return flat.length > limit ? `${flat.slice(0, limit - 1)}…` : flat;
}

export interface Assignment {
  teacherId?: string;
  section?: string;
}

/**
 * Whether this teacher teaches this student's section.
 *
 * Section names are compared case- and space-insensitively, because they
 * are typed by hand in two places -- the timetable and the student
 * record -- and "Grade 10 - Rizal" against "Grade 10 - rizal " should
 * not decide whether a parent can reach their child's teacher.
 */
export function teachesSection(
  assignments: Assignment[],
  teacherUid: string,
  section: string
): boolean {
  const wanted = normalizeSection(section);
  if (!wanted) return false;
  return assignments.some(
    (a) => a.teacherId === teacherUid && normalizeSection(a.section ?? "") === wanted
  );
}

export function normalizeSection(section: string): string {
  return section.trim().toLowerCase().replace(/\s+/g, " ");
}

/**
 * Whether this parent is linked to this student.
 *
 * Read from the parent's own user document, which only the Admin SDK
 * writes. A client-supplied list would let anybody claim any child.
 */
export function isLinkedParent(
  linkedStudentIds: unknown,
  studentId: string
): boolean {
  return Array.isArray(linkedStudentIds) && linkedStudentIds.includes(studentId);
}
