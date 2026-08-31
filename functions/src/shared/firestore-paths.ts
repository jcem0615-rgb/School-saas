/**
 * Single source of truth for Firestore paths on the Functions side.
 * Mirrors app/lib/core/constants/firestore_paths.dart -- keep both in sync
 * whenever a collection is added or renamed.
 */
export const FirestorePaths = {
  platformSchools: "platform_schools",
  platformSchoolDoc: (schoolId: string) => `platform_schools/${schoolId}`,

  platformSubscriptions: "platform_subscriptions",
  platformSubscriptionDoc: (schoolId: string) => `platform_subscriptions/${schoolId}`,

  platformInvoices: "platform_invoices",
  platformInvoiceDoc: (invoiceId: string) => `platform_invoices/${invoiceId}`,

  platformOwnerAuditLog: "platform_owner_audit_log",

  ownerProfiles: "platform_owner_profiles",
  ownerProfileDoc: (uid: string) => `platform_owner_profiles/${uid}`,

  school: (schoolId: string) => `schools/${schoolId}`,

  users: (schoolId: string) => `schools/${schoolId}/users`,
  userDoc: (schoolId: string, userId: string) => `schools/${schoolId}/users/${userId}`,

  students: (schoolId: string) => `schools/${schoolId}/students`,
  studentDoc: (schoolId: string, studentId: string) =>
    `schools/${schoolId}/students/${studentId}`,

  // Employee leave. Its own collection rather than a row in the generic
  // approvals queue: the timesheet asks "was this day covered", which is
  // a date-range query, and an employee reads their own without reading
  // the school's.
  leaveRequests: (schoolId: string) => `schools/${schoolId}/leaveRequests`,

  // Parent-teacher messaging. Messages are a subcollection because
  // they are only ever read through their conversation -- there is no
  // "all messages in the school" screen, and there must not be.
  conversations: (schoolId: string) => `schools/${schoolId}/conversations`,
  conversationDoc: (schoolId: string, conversationId: string) =>
    `schools/${schoolId}/conversations/${conversationId}`,
  messages: (schoolId: string, conversationId: string) =>
    `schools/${schoolId}/conversations/${conversationId}/messages`,

  auditLog: (schoolId: string) => `schools/${schoolId}/auditLog`,

  attendance: (schoolId: string) => `schools/${schoolId}/attendance`,
  attendanceDoc: (schoolId: string, recordId: string) => `schools/${schoolId}/attendance/${recordId}`,

  // Per-subject attendance. Two collections rather than one, because a
  // session is a thing that happened to a class (it started at 7:32 and
  // ran 48 minutes) and a mark is a thing that happened to a student.
  // Folding the marks into the session document would cap a section at
  // whatever fits in one megabyte and make "was this child in Physics
  // all term" a scan of every session in the school.
  classSessions: (schoolId: string) => `schools/${schoolId}/classSessions`,
  classSessionDoc: (schoolId: string, sessionId: string) =>
    `schools/${schoolId}/classSessions/${sessionId}`,
  subjectAttendance: (schoolId: string) => `schools/${schoolId}/subjectAttendance`,
  subjectAttendanceDoc: (schoolId: string, markId: string) =>
    `schools/${schoolId}/subjectAttendance/${markId}`,

  // The BIR-registered booklets a school issues official receipts from,
  // and one claim document per number used. The claim's id IS the
  // number, which is what makes "one receipt, issued once" a guarantee
  // rather than a query two concurrent cashiers could both pass.
  receiptBooklets: (schoolId: string) => `schools/${schoolId}/receiptBooklets`,
  receiptClaims: (schoolId: string, bookletId: string) =>
    `schools/${schoolId}/receiptBooklets/${bookletId}/claims`,
  receiptClaimDoc: (schoolId: string, bookletId: string, number: string) =>
    `schools/${schoolId}/receiptBooklets/${bookletId}/claims/${number}`,

  payments: (schoolId: string) => `schools/${schoolId}/payments`,
  paymentDoc: (schoolId: string, paymentId: string) => `schools/${schoolId}/payments/${paymentId}`,
  // Claims of online payment awaiting a cashier's verification. Kept apart
  // from `payments`, which only ever holds money the school has confirmed.
  paymentSubmissions: (schoolId: string) => `schools/${schoolId}/paymentSubmissions`,

  // The school's published fee schedules, and the record of each
  // occasion one was charged to a student. Two collections, because a
  // schedule is a template the school edits between years and an
  // assessment is a thing that happened to a family.
  feeStructures: (schoolId: string) => `schools/${schoolId}/feeStructures`,
  feeStructureDoc: (schoolId: string, id: string) => `schools/${schoolId}/feeStructures/${id}`,
  assessments: (schoolId: string) => `schools/${schoolId}/assessments`,
  assessmentDoc: (schoolId: string, id: string) => `schools/${schoolId}/assessments/${id}`,

  programs: (schoolId: string) => `schools/${schoolId}/programs`,
  programDoc: (schoolId: string, programId: string) => `schools/${schoolId}/programs/${programId}`,

  teacherAssignments: (schoolId: string) => `schools/${schoolId}/teacherAssignments`,

  scheduleBlocks: (schoolId: string) => `schools/${schoolId}/scheduleBlocks`,
  scheduleBlockDoc: (schoolId: string, blockId: string) =>
    `schools/${schoolId}/scheduleBlocks/${blockId}`,
  emergencyAlerts: (schoolId: string) => `schools/${schoolId}/emergencyAlerts`,

  courseworkSubmissions: (schoolId: string) => `schools/${schoolId}/courseworkSubmissions`,
  // The correct answers. Never readable by students -- see firestore.rules.
  courseworkAnswerKeys: (schoolId: string) => `schools/${schoolId}/courseworkAnswerKeys`,

  counterDoc: (schoolId: string, counterName: string) =>
    `schools/${schoolId}/counters/${counterName}`,

  // ---- Admissions ----
  // Enquiries, from the first phone call to the day they enrol.
  applicants: (schoolId: string) => `schools/${schoolId}/applicants`,
  applicantDoc: (schoolId: string, applicantId: string) =>
    `schools/${schoolId}/applicants/${applicantId}`,

  // ---- Year-end rollover ----
  // One document per school year, holding what was decided and by whom.
  schoolYears: (schoolId: string) => `schools/${schoolId}/schoolYears`,
  schoolYearDoc: (schoolId: string, schoolYear: string) =>
    `schools/${schoolId}/schoolYears/${schoolYear}`,

  // One per student per year. The id is deliberate: it is what makes a
  // rollover safe to re-run, since a student already moved cannot be
  // created again.
  promotions: (schoolId: string) => `schools/${schoolId}/promotions`,
  promotionDoc: (schoolId: string, schoolYear: string, studentId: string) =>
    `schools/${schoolId}/promotions/${schoolYear}_${studentId}`,
};
