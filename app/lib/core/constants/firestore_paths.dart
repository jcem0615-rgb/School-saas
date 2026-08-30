/// Single source of truth for every Firestore collection/document path.
///
/// Why this exists: a typo'd path string (`'shcools'`) doesn't throw --
/// Firestore just silently creates/reads a different, empty location.
/// Routing every access through these builders makes path typos a
/// compile-time problem instead of a "why is my data missing" bug report.
///
/// Mirrors functions/src/shared/firestore-paths.ts -- keep both in sync.
class FirestorePaths {
  FirestorePaths._();

  // ---- Platform-level (Owner only) ----
  static const String platformSchools = 'platform_schools';
  static String platformSchoolDoc(String schoolId) => '$platformSchools/$schoolId';

  static const String platformSubscriptions = 'platform_subscriptions';
  static String platformSubscriptionDoc(String schoolId) =>
      '$platformSubscriptions/$schoolId';

  static const String platformInvoices = 'platform_invoices';
  static String platformInvoiceDoc(String invoiceId) => '$platformInvoices/$invoiceId';

  static const String platformOwnerAuditLog = 'platform_owner_audit_log';

  static const String ownerProfiles = 'platform_owner_profiles';
  static String ownerProfileDoc(String uid) => '$ownerProfiles/$uid';

  // ---- Tenant root ----
  static String school(String schoolId) => 'schools/$schoolId';

  static String users(String schoolId) => '${school(schoolId)}/users';
  static String userDoc(String schoolId, String userId) => '${users(schoolId)}/$userId';

  static String students(String schoolId) => '${school(schoolId)}/students';
  static String studentDoc(String schoolId, String studentId) =>
      '${students(schoolId)}/$studentId';

  static String employees(String schoolId) => '${school(schoolId)}/employees';

  static String attendance(String schoolId) => '${school(schoolId)}/attendance';

  static String payments(String schoolId) => '${school(schoolId)}/payments';

  /// Claims of online payment awaiting a cashier's verification. Separate
  /// from `payments`, which only ever holds money the school has confirmed.
  static String paymentSubmissions(String schoolId) =>
      '${school(schoolId)}/paymentSubmissions';

  /// Single document: the school's e-wallet QR and account details.
  static String paymentSettingsDoc(String schoolId) =>
      '${school(schoolId)}/settings/payments';

  /// Single document: logo and school name for the app and printed IDs.
  static String brandingDoc(String schoolId) => '${school(schoolId)}/settings/branding';

  /// The school's published fee schedules, and the record of each
  /// occasion one was charged to a student.
  static String feeStructures(String schoolId) => '${school(schoolId)}/feeStructures';

  static String assessments(String schoolId) => '${school(schoolId)}/assessments';

  static String programs(String schoolId) => '${school(schoolId)}/programs';

  static String inventory(String schoolId) => '${school(schoolId)}/inventory';
  static String inventoryTransactions(String schoolId) =>
      '${school(schoolId)}/inventoryTransactions';

  static String announcements(String schoolId) => '${school(schoolId)}/announcements';

  static String meetings(String schoolId) => '${school(schoolId)}/meetings';

  static String approvals(String schoolId) => '${school(schoolId)}/approvals';

  static String expenses(String schoolId) => '${school(schoolId)}/expenses';

  static String teacherAssignments(String schoolId) => '${school(schoolId)}/teacherAssignments';

  /// The weekly timetable. Written only by saveScheduleBlock and
  /// deleteScheduleBlock -- clash detection is the whole feature, and a
  /// client that could write here directly could book two classes into
  /// one room.
  static String scheduleBlocks(String schoolId) => '${school(schoolId)}/scheduleBlocks';

  /// What a person asked the school to do with their own information,
  /// and what the school did about it. Append-and-answer: the request
  /// itself never changes, and nothing is ever deleted -- a school asked
  /// how it handles these has to be able to show the refusals too.
  static String dataRequests(String schoolId) => '${school(schoolId)}/dataRequests';

  static String courseworkItems(String schoolId) => '${school(schoolId)}/courseworkItems';

  /// What students hand in against a courseworkItem. A sibling
  /// collection rather than a subcollection: a teacher's "who has
  /// submitted" view and a student's "what have I handed in" view are
  /// both flat queries across many items, which a subcollection would
  /// turn into a collectionGroup query and a second index.
  static String courseworkSubmissions(String schoolId) =>
      '${school(schoolId)}/courseworkSubmissions';

  /// The correct answers. Never readable by students -- see
  /// firestore.rules. Keyed by courseworkId so there is exactly one key
  /// per item and no way to end up with two disagreeing.
  static String courseworkAnswerKeys(String schoolId) =>
      '${school(schoolId)}/courseworkAnswerKeys';

  /// Published emergency numbers (BFP, PNP, clinic). Readable by every
  /// role in the school -- a number nobody can reach is not a safety
  /// feature.
  static String emergencyContacts(String schoolId) =>
      '${school(schoolId)}/emergencyContacts';

  /// Emergency alerts raised by students.
  static String emergencyAlerts(String schoolId) =>
      '${school(schoolId)}/emergencyAlerts';

  static String grades(String schoolId) => '${school(schoolId)}/grades';

  static String checklistItems(String schoolId) => '${school(schoolId)}/checklistItems';

  static String dailyReports(String schoolId) => '${school(schoolId)}/dailyReports';

  static String guidanceRecords(String schoolId) => '${school(schoolId)}/guidanceRecords';

  static String summons(String schoolId) => '${school(schoolId)}/summons';

  /// Per-subject attendance: the class the teacher opened, and the marks
  /// taken in it. Two collections rather than marks nested in the
  /// session, because "was this child in Physics all term" is a query
  /// across sessions, and a subcollection cannot be asked that without a
  /// collection-group index the marks do not otherwise need.
  static String classSessions(String schoolId) => '${school(schoolId)}/classSessions';
  static String subjectAttendance(String schoolId) =>
      '${school(schoolId)}/subjectAttendance';

  /// Employee leave. A collection of its own rather than a row in the
  /// generic approvals queue: the timesheet has to ask "was this day
  /// covered", which is a date-range query, and an employee has to be
  /// able to read their own without being able to read the school's.
  static String leaveRequests(String schoolId) => '${school(schoolId)}/leaveRequests';

  /// Parent-teacher messaging. Messages are a subcollection of their
  /// conversation because they are only ever read through it: there is
  /// no "all messages in the school" screen, and there must not be.
  static String conversations(String schoolId) => '${school(schoolId)}/conversations';
  static String messages(String schoolId, String conversationId) =>
      '${conversations(schoolId)}/$conversationId/messages';

  static String auditLog(String schoolId) => '${school(schoolId)}/auditLog';

  static String documents(String schoolId) => '${school(schoolId)}/documents';

  /// The log of TORs and Form 137s handed over the counter. Separate
  /// from `documents`, which holds files the school stores; this holds
  /// the record of a physical release.
  static String documentReleases(String schoolId) =>
      '${school(schoolId)}/documentReleases';

  static String notificationItems(String schoolId, String userId) =>
      '${school(schoolId)}/notifications/$userId/items';

  /// Per-school sequential counters (studentNumber, receiptNumber, etc.),
  /// incremented atomically inside Cloud Function transactions.
  static String counters(String schoolId) => '${school(schoolId)}/counters';
  static String counterDoc(String schoolId, String counterName) =>
      '${counters(schoolId)}/$counterName';
}
