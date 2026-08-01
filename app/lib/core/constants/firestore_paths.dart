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

  static String programs(String schoolId) => '${school(schoolId)}/programs';

  static String inventory(String schoolId) => '${school(schoolId)}/inventory';
  static String inventoryTransactions(String schoolId) =>
      '${school(schoolId)}/inventoryTransactions';

  static String announcements(String schoolId) => '${school(schoolId)}/announcements';

  static String meetings(String schoolId) => '${school(schoolId)}/meetings';

  static String approvals(String schoolId) => '${school(schoolId)}/approvals';

  static String expenses(String schoolId) => '${school(schoolId)}/expenses';

  static String teacherAssignments(String schoolId) => '${school(schoolId)}/teacherAssignments';

  static String courseworkItems(String schoolId) => '${school(schoolId)}/courseworkItems';

  static String grades(String schoolId) => '${school(schoolId)}/grades';

  static String checklistItems(String schoolId) => '${school(schoolId)}/checklistItems';

  static String dailyReports(String schoolId) => '${school(schoolId)}/dailyReports';

  static String guidanceRecords(String schoolId) => '${school(schoolId)}/guidanceRecords';

  static String summons(String schoolId) => '${school(schoolId)}/summons';

  static String auditLog(String schoolId) => '${school(schoolId)}/auditLog';

  static String documents(String schoolId) => '${school(schoolId)}/documents';

  static String notificationItems(String schoolId, String userId) =>
      '${school(schoolId)}/notifications/$userId/items';

  /// Per-school sequential counters (studentNumber, receiptNumber, etc.),
  /// incremented atomically inside Cloud Function transactions.
  static String counters(String schoolId) => '${school(schoolId)}/counters';
  static String counterDoc(String schoolId, String counterName) =>
      '${counters(schoolId)}/$counterName';
}
