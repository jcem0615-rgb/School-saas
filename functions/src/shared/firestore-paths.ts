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

  auditLog: (schoolId: string) => `schools/${schoolId}/auditLog`,

  attendance: (schoolId: string) => `schools/${schoolId}/attendance`,
  attendanceDoc: (schoolId: string, recordId: string) => `schools/${schoolId}/attendance/${recordId}`,

  payments: (schoolId: string) => `schools/${schoolId}/payments`,
  paymentDoc: (schoolId: string, paymentId: string) => `schools/${schoolId}/payments/${paymentId}`,
  // Claims of online payment awaiting a cashier's verification. Kept apart
  // from `payments`, which only ever holds money the school has confirmed.
  paymentSubmissions: (schoolId: string) => `schools/${schoolId}/paymentSubmissions`,

  programs: (schoolId: string) => `schools/${schoolId}/programs`,
  programDoc: (schoolId: string, programId: string) => `schools/${schoolId}/programs/${programId}`,

  courseworkSubmissions: (schoolId: string) => `schools/${schoolId}/courseworkSubmissions`,
  // The correct answers. Never readable by students -- see firestore.rules.
  courseworkAnswerKeys: (schoolId: string) => `schools/${schoolId}/courseworkAnswerKeys`,

  counterDoc: (schoolId: string, counterName: string) =>
    `schools/${schoolId}/counters/${counterName}`,
};
