import 'package:diacritic/diacritic.dart';
import 'package:rxdart/rxdart.dart';

import 'demo_attachments.dart';
import '../core/constants/education_level.dart';
import '../core/constants/user_roles.dart';
import '../features/admin_portal/domain/entities/employee_summary.dart';
import '../features/admin_portal/domain/entities/program.dart';
import '../features/admin_portal/domain/entities/school_branding.dart';
import '../features/admin_portal/domain/entities/teacher_assignment.dart';
import '../features/audit_trail/domain/entities/audit_log_entry.dart';
import '../features/auth/domain/entities/app_user.dart';
import '../features/director_portal/domain/entities/announcement.dart';
import '../features/director_portal/domain/entities/approval_request.dart';
import '../features/director_portal/domain/entities/expense.dart';
import '../features/director_portal/domain/entities/meeting.dart';
import '../features/faculty_portal/domain/entities/coursework_item.dart';
import '../features/emergency/domain/entities/emergency_alert.dart';
import '../features/emergency/domain/entities/emergency_contact.dart';
import '../features/faculty_portal/domain/entities/answer_key.dart';
import '../features/faculty_portal/domain/entities/coursework_submission.dart';
import '../features/faculty_portal/domain/entities/grade.dart';
import '../features/guidance_portal/domain/entities/guidance_record.dart';
import '../features/guidance_portal/domain/entities/summons.dart';
// Both invoice.dart (platform billing) and payment.dart (student tuition)
// declare their own PaymentMethod. Unqualified PaymentMethod here means the
// student-payments one; the billing enum is reached via `billing.`.
import '../features/owner_portal/domain/entities/invoice.dart' hide PaymentMethod;
import '../features/owner_portal/domain/entities/invoice.dart' as billing;
import '../features/owner_portal/domain/entities/revenue_summary.dart';
import '../features/owner_portal/domain/entities/school_summary.dart';
import '../features/payments/domain/entities/assessment.dart';
import '../features/payments/domain/entities/fee_structure.dart';
import '../features/payments/domain/entities/payment.dart';
import '../features/payments/domain/entities/payment_settings.dart';
import '../features/payments/domain/entities/payment_submission.dart';
import '../features/qr_attendance/domain/entities/attendance_record.dart';
import '../features/registrar_portal/domain/entities/document_release.dart';
import '../features/registrar_portal/domain/entities/student_summary.dart';
import '../features/schedules/domain/entities/schedule_block.dart';
import '../features/data_protection/domain/entities/data_request.dart';
import '../features/data_protection/domain/entities/privacy_notice.dart';
import '../features/staff_portal/domain/entities/checklist_item.dart';
import '../features/staff_portal/domain/entities/daily_report.dart';

/// In-memory stand-in for Firestore, used only by the demo build.
///
/// Every collection is a [BehaviorSubject] so the fake repositories can
/// hand out live streams with the same semantics the real
/// `snapshots()`-backed ones have: an immediate current value, then a new
/// emission on every write. Writes go through [_replace], which swaps in a
/// fresh list -- never mutates in place -- so Riverpod's stream providers
/// see a genuinely new value and rebuild.
///
/// This exists so the app can be run and clicked through end to end with
/// no Firebase project, no emulator, and no network. It is deliberately
/// NOT a security model: the real access boundary is firestore.rules, and
/// nothing here attempts to reproduce it. What a demo session shows you is
/// the UI and the flows, not whether a role is actually allowed to do
/// something.
class DemoStore {
  static const schoolId = 'school_stnicholas';
  static const schoolName = 'St. Nicholas Academy';
  static const password = 'demo1234';

  /// Seeded so date-dependent screens (today's attendance, upcoming
  /// meetings, "due this week") always have something to show, regardless
  /// of when the demo is run.
  final DateTime now = DateTime.now();

  DateTime _daysAgo(int d) => now.subtract(Duration(days: d));
  DateTime _daysAhead(int d) => now.add(Duration(days: d));
  String _dateKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String get todayKey => _dateKey(now);

  /// Turns a school name into an id safe to use as a Firestore path
  /// segment. Kept in step with slugify() in
  /// functions/src/callable/schools/createSchool.ts, so a school created
  /// in the demo lands on the same id it would in the real backend.
  static String slugify(String name) {
    // Accents are folded, not dropped: without this "Muñoz Elementary"
    // becomes "mu-oz-elementary", because the enye is not [a-z0-9] and
    // falls through to the separator rule. Filipino school names carry
    // enough of them for that to be the common case rather than an edge
    // one. The callable folds the same way, via NFKD.
    final slug = removeDiacritics(name)
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    return slug.length > 48 ? slug.substring(0, 48) : slug;
  }

  /// A wall-clock time on one of the seeded days.
  ///
  /// Clamped to [now] so a demo opened at breakfast does not show a receipt
  /// issued at eleven -- the point of seeding today is that the figures look
  /// like a morning that has actually happened.
  DateTime _atHour(int daysAgo, int hour, int minute) {
    final day = _daysAgo(daysAgo);
    final at = DateTime(day.year, day.month, day.day, hour, minute);
    return at.isAfter(now) ? now : at;
  }

  // Starts above the seed data rather than at zero. A few seeded records
  // carry hand-written ids in this same format -- `sub_0001`, `inv_0003` --
  // so a counter starting at 0 hands the very first record created at
  // runtime an id that already belongs to a seeded one. Two rows sharing
  // an id is not a cosmetic problem: anything that looks a record up by id
  // (edit, delete, "is this one new?") then acts on the wrong row, or
  // cannot tell them apart at all.
  int _idSeq = 1000;
  String nextId(String prefix) => '${prefix}_${(++_idSeq).toString().padLeft(4, '0')}';

  // -------------------------------------------------------------------
  // Session
  // -------------------------------------------------------------------

  /// Null when signed out. The router watches a stream derived from this.
  /// Seeded from [DemoStore.new]'s [signedInAs], so a reload comes back
  /// already signed in rather than flashing the login screen first.
  late final BehaviorSubject<AppUser?> currentUser =
      BehaviorSubject<AppUser?>.seeded(_signedInAs);

  final AppUser? _signedInAs;

  /// [signedInAs] restores a session from a previous run. Everything else
  /// about the store is seeded fresh: the demo's data is a fixture, and
  /// persisting edits across reloads would mean every visitor inherited
  /// whatever the last one did to it.
  DemoStore({AppUser? signedInAs}) : _signedInAs = signedInAs;

  AppUser get requireUser {
    final u = currentUser.valueOrNull;
    if (u == null) throw StateError('Demo action attempted while signed out.');
    return u;
  }

  // -------------------------------------------------------------------
  // Collections
  // -------------------------------------------------------------------

  late final schools = BehaviorSubject<List<SchoolSummary>>.seeded(_seedSchools());
  late final revenue = BehaviorSubject<RevenueSummary>.seeded(_seedRevenue());
  late final invoices = BehaviorSubject<List<Invoice>>.seeded(_seedInvoices());
  late final students = BehaviorSubject<List<StudentSummary>>.seeded(_seedStudents());
  late final employees = BehaviorSubject<List<EmployeeSummary>>.seeded(_seedEmployees());
  late final assignments = BehaviorSubject<List<TeacherAssignment>>.seeded(_seedAssignments());
  late final programs = BehaviorSubject<List<Program>>.seeded(_seedPrograms());
  late final payments = BehaviorSubject<List<Payment>>.seeded(_seedPayments());
  late final feeStructures =
      BehaviorSubject<List<FeeStructure>>.seeded(_seedFeeStructures());
  late final assessments = BehaviorSubject<List<Assessment>>.seeded(_seedAssessments());
  late final attendance = BehaviorSubject<List<AttendanceRecord>>.seeded(_seedAttendance());
  late final scheduleBlocks =
      BehaviorSubject<List<ScheduleBlock>>.seeded(_seedScheduleBlocks());
  late final dataRequests =
      BehaviorSubject<List<DataRequest>>.seeded(_seedDataRequests());

  /// Who has already read the privacy notice this run.
  ///
  /// Held beside the accounts rather than on them because the demo
  /// accounts are const: switching to Registrar and back must not ask
  /// the same person twice, but a fresh process should still show the
  /// gate once, which is the thing worth demonstrating.
  late final acknowledgedPrivacy = BehaviorSubject<Set<String>>.seeded(<String>{});
  late final coursework = BehaviorSubject<List<CourseworkItem>>.seeded(_seedCoursework());
  /// Named for the collection, not shortened to `submissions` -- payment
  /// submissions already own that word in this store.
  late final emergencyContacts =
      BehaviorSubject<List<EmergencyContact>>.seeded(_seedEmergencyContacts());
  late final emergencyAlerts =
      BehaviorSubject<List<EmergencyAlert>>.seeded(_seedEmergencyAlerts());
  late final answerKeys = BehaviorSubject<List<AnswerKey>>.seeded(_seedAnswerKeys());
  late final courseworkSubmissions =
      BehaviorSubject<List<CourseworkSubmission>>.seeded(_seedCourseworkSubmissions());
  late final grades = BehaviorSubject<List<Grade>>.seeded(_seedGrades());
  late final documentReleases =
      BehaviorSubject<List<DocumentRelease>>.seeded(_seedDocumentReleases());
  late final announcements = BehaviorSubject<List<Announcement>>.seeded(_seedAnnouncements());
  late final meetings = BehaviorSubject<List<Meeting>>.seeded(_seedMeetings());
  late final approvals = BehaviorSubject<List<ApprovalRequest>>.seeded(_seedApprovals());
  late final expenses = BehaviorSubject<List<Expense>>.seeded(_seedExpenses());
  late final checklist = BehaviorSubject<List<ChecklistItem>>.seeded(_seedChecklist());
  late final dailyReports = BehaviorSubject<List<DailyReport>>.seeded(_seedDailyReports());
  late final guidanceRecords = BehaviorSubject<List<GuidanceRecord>>.seeded(_seedGuidanceRecords());
  late final summonses = BehaviorSubject<List<Summons>>.seeded(_seedSummonses());
  late final auditLog = BehaviorSubject<List<AuditLogEntry>>.seeded(_seedAuditLog());
  late final paymentSubmissions =
      BehaviorSubject<List<PaymentSubmission>>.seeded(_seedSubmissions());
  late final paymentSettings = BehaviorSubject<PaymentSettings>.seeded(_seedPaymentSettings());
  late final branding = BehaviorSubject<SchoolBranding>.seeded(
    // A seal is on file, because the ID card prints the school's logo as
    // its background and a demo with no logo demonstrates the absence of
    // the feature. Uploading one under School Branding replaces it, which
    // is the path this used to leave uncovered -- it is still one tap
    // away, and now you can see what changes when you take it.
    //
    // An inline data URI, because that is exactly what an upload produces
    // in demo mode (DemoUploadRepository never touches a bucket), so the
    // seeded state and the uploaded state travel the same code path.
    // Drawn by tool/generate_demo_seal.py.
    SchoolBranding(
      schoolName: schoolName,
      logoUrl: 'data:image/png;base64,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',
      logoFileName: 'st-nicholas-seal.png',
      addressLine: 'Poblacion, San Nicolas, Batangas',
      schoolYear: '${DateTime.now().year}-${DateTime.now().year + 1}',
      principalName: 'Ramon Salazar',
      directorName: 'Corazon Buenaventura',
      // A named officer, because that is what a school evaluating this
      // should be looking at. Clear the field in Branding and the
      // privacy notice says plainly that none has been named -- which is
      // the state a real school starts in.
      dpoName: 'Atty. Imelda Ferrer',
      dpoEmail: 'dpo@stnicholas.demo.ph',
      dpoPhone: '(044) 791 2201',
      // Seeded so the demo's ID cards show what a signed card looks like.
      // Inline data URIs rather than files: demo mode never touches
      // Storage, and a card whose signature is a broken image would
      // demonstrate the opposite of the feature.
      principalSignatureUrl: 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAQQAAABQCAYAAAD/YAtfAAADHUlEQVR42u3dS67bMA'
          'yF4Syigy6h69P+gXTWwa3tyLFkU+T3AwbuIM6NxcMjUn69XgAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAEB5fv'
          '3+0/Y2owPUTP73xsYggAJG0JP8h58xosD6ZtA1+3dUEIwBSFIVnE5mxgDkqwouJ+8nYzDquCoqIrqxKljpfyBgss'
          '5IXCJ6Zq1glSoEcWeV4b2icnOtFkFMCWlrBXpYoDcE++9vkRhvBpnaFNwbzM1ZZS/QA/7Xz+8lngRtGFPINbPsBm'
          '9E8v78ji0hi8i8GDIFnJ5ZRn22d39VQi4zYAqFxHRFfEf7qhLGJZ3fh1uqgwH77O6nSsg7A4vtmobQDpL06M64du'
          'J6+EPhEs41M488XmK7aLvQebfbp619e8pSeZk3wawnLBig3vvh905T9piEmaRmX26Rca3gnHogxsHpw8uXPasS8s'
          '60TCFuQA7viz+7/qDf1Cpkr3AqVQXt4jUFbdJvJZik48L0Y68ZtIvf1whGElVqfTK2C6ENgWDyl9lah7gOHdkQCC'
          'axOaoEGQLBGAMxZgjjZsfq1YEKCNMN4WwARqxBmEEc+1F7yBQWmnnunrWqiqVSdWTNKNjsc1d1QSyqA8ecqG24s1'
          '2oLJaqs6UnOC8muieFWqV1sG7y/6X1sjWg8J4WapXWwZkVD+BdQnwRhOq8PG0igAAjCTVz0kgC5hhOhDPfy2A9of'
          'u4JMDLRUsRnHjqm5usJ/TPiJTp+oRICzlT3u2opNQuaB3WNYbwr23PIhaiZ5Yo2mf2PLhWVBkmBvaZi1Q071GPtG'
          'P8wEKm0PEIe5fpfhFjo4LlTCHy2RqtA0qaQpArK92wo3VAxRn5zHstoXVA0oT8tFYgMnNaByOCISV7x1uuv9l63o'
          '05Zatq+pQu0Ucm6jvJxlhQNrlbsGR6rCqIMhaUjFmz912J/O65JuCb/Rcx1MfiIEvqJXromanzt576jEqNeUj0wQ'
          'ke6Ni7j4d2phoI43h4Fb58kIgu9+QjCp8DZFBR3jiM+sbAGxEUNQ7aBxiHyRAAAAAAAAAAAABAOf4CtNLDEAkj7o'
          'YAAAAASUVORK5CYII=',
      directorSignatureUrl: 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAQQAAABQCAYAAAD/YAtfAAADEklEQVR42u3dWU7sMB'
          'CFYRbBA0tgfexfat4QgnTHjiseyt8v5elylaSG4yoP6bc3AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAD+8/'
          '7x+XV2sRKwlxA8XlyEAcg8Aj8RgqNn+/fvPCoWEZt4Q0fgg2c6vP8TYRA0qkFEJ96oZLtyT6KQclBSDc4gBqOT7e'
          'q9jp6Tl9celFSD/R1RZNhejvhzn+p7tP5/zDkoqQb7OqLIoD0cETHCqxLyigFR6OSIHk7sNbqrEnKLgRZxAUdEOC'
          'PSuQIldwwS/wHzBr3VOdKxfwOF5/OJQXRMmzcITrpAx0a2IAQhsRiYTxgwb9BLFAgCMSAKeZwR1YYQBK0qUWg0QM'
          'l191Jh8z0IglZ11kp4JSE42+/dZatn4OoFQSAGoQPlbuX/42S/d7fDIK2iYJXBvBUCerHfhh59XDRg95l9COatMG'
          'v51TMY7FQkBkga5I2i4CzD2jFKDPRi5aJQcarSacd1Y5T9e84bZA4U30PI0SKwv1ahupQ8+RCGM/JaBGTth88+hV'
          'WyocpXdOb3IwupDqICqmRfhe/sjfXXS5+wlurgzkCruQRlu+1LKjU2Vx0sE6QCtM6+l0WXnYnBSsEtYMtbtCoRZk'
          '2twsoBv3UQl87DiCDVwU4JsKUNVU6qAzxPhq2SwEahnILAgUTBewtkai45vC8gSbwnIFm8HyBpot+NGACtopDsnY'
          'gBsGsCEQNAiZ222gFSJNOFQ1lR16XzCBGXKEImIfg6KreDknOHi8hg6qSeJXF3qA5us53oltyjgvK25Mo8kagNQY'
          '+AGTIaz5BgJhKxQ6J3S+4Mo+6F57QBCVOM5rcm+GzJNnl1QAwwfDRP3Q/OnHBaBbQm+y2JvpF9pxIFrQJKRgmJvk'
          'HyaRVQHKgSvU953vCDs80+0SqgKMhYZM6ePfKHTVQHwKLzCQUbnao+D08MgEXatMKq4Odvaz8Pb1UBmL9Nq0r0Qu'
          'F49WvWVhWAVeYUglqBR8nBJR4A1qgWIiYLXy4bszywjjC0LidaNgYAAAAAANiMbwvTB0SZP02DAAAAAElFTkSuQm'
          'CC',
      updatedAt: _daysAgo(60),
      updatedByName: 'Grace Mendoza',
    ),
  );

  /// Prepends [item] to a collection and republishes it. Insert-at-front
  /// matches how every list screen in this app sorts (newest first).
  /// [user] with the privacy acknowledgement they already gave this run.
  AppUser withAcknowledgement(AppUser user) =>
      acknowledgedPrivacy.value.contains(user.uid)
          ? user.copyWith(privacyNoticeVersion: PrivacyNotice.version)
          : user;

  void prepend<T>(BehaviorSubject<List<T>> subject, T item) {
    subject.add([item, ...subject.value]);
  }

  /// Records that have been soft-deleted, newest first.
  ///
  /// The real datasources never remove a document -- they set `isDeleted`
  /// and every read filters on it (`allow delete: if false` in
  /// firestore.rules leaves no other option). The demo store reproduces
  /// the part that is observable from the UI -- the record leaves the
  /// live list -- while keeping it here rather than dropping it, so the
  /// "recoverable, audit trail intact" property of a soft delete is not
  /// quietly lost in demo mode.
  final softDeleted = <({DateTime deletedAt, String deletedBy, Object record})>[];

  /// Moves every element matching [where] out of the live list. Mirrors
  /// flipping `isDeleted` server-side, since reads filter on that flag.
  void softDelete<T>(BehaviorSubject<List<T>> subject, bool Function(T) where) {
    final removed = subject.value.where(where).toList();
    if (removed.isEmpty) return;
    subject.add(subject.value.where((e) => !where(e)).toList());
    final by = currentUser.valueOrNull?.uid ?? 'unknown';
    for (final record in removed) {
      softDeleted.insert(
        0,
        (deletedAt: DateTime.now(), deletedBy: by, record: record as Object),
      );
    }
  }

  /// Replaces the first element matching [where] with [update] applied.
  void update<T>(
    BehaviorSubject<List<T>> subject,
    bool Function(T) where,
    T Function(T) update,
  ) {
    subject.add([
      for (final item in subject.value) if (where(item)) update(item) else item,
    ]);
  }

  /// Records an entry in the audit trail, mirroring what the real
  /// onAnyTenantDocWrite trigger does server-side. Demo writes call this so
  /// the Audit Trail screen actually fills up as you click around.
  void audit({
    required String module,
    required String action,
    required String targetCollection,
    required String targetId,
    Map<String, dynamic>? newValue,
    String? remarks,
  }) {
    final user = currentUser.valueOrNull;
    prepend(
      auditLog,
      AuditLogEntry(
        id: nextId('audit'),
        userId: user?.uid ?? 'unknown',
        userRole: user?.role.value ?? 'unknown',
        userName: user?.fullName ?? 'Unknown',
        module: module,
        action: action,
        targetCollection: targetCollection,
        targetId: targetId,
        newValue: newValue,
        remarks: remarks,
        success: true,
        timestamp: DateTime.now(),
      ),
    );
  }

  void dispose() {
    for (final s in <BehaviorSubject<dynamic>>[
      currentUser, schools, revenue, invoices, students, employees,
      assignments, programs, payments, attendance, coursework, grades,
      courseworkSubmissions, answerKeys, emergencyContacts, emergencyAlerts,
      announcements, meetings, approvals, expenses, checklist,
      dailyReports, guidanceRecords, summonses, auditLog,
      paymentSubmissions, paymentSettings, branding, documentReleases,
      feeStructures, assessments, scheduleBlocks, dataRequests,
      acknowledgedPrivacy,
    ]) {
      s.close();
    }
  }

  // -------------------------------------------------------------------
  // Demo accounts -- one per role, so every portal is reachable.
  // -------------------------------------------------------------------

  static final demoAccounts = <AppUser>[
    const AppUser(
      uid: 'u_owner',
      schoolId: null, // Owner is platform-level, outside any tenant
      role: UserRole.owner,
      firstName: 'Ramon',
      lastName: 'Valdez',
      email: 'owner@demo.ph',
      status: UserAccountStatus.active,
      mustChangePassword: false,
      qrCode: 'QR-OWNER-0001',
    ),
    const AppUser(
      uid: 'u_director',
      schoolId: schoolId,
      role: UserRole.director,
      firstName: 'Elena',
      lastName: 'Cruz',
      email: 'director@demo.ph',
      status: UserAccountStatus.active,
      mustChangePassword: false,
      qrCode: 'QR-DIR-0001',
    ),
    const AppUser(
      uid: 'u_principal',
      schoolId: schoolId,
      role: UserRole.principal,
      firstName: 'Antonio',
      lastName: 'Reyes',
      email: 'principal@demo.ph',
      status: UserAccountStatus.active,
      mustChangePassword: false,
      qrCode: 'QR-PRIN-0001',
    ),
    const AppUser(
      uid: 'u_admin',
      schoolId: schoolId,
      role: UserRole.admin,
      firstName: 'Grace',
      lastName: 'Mendoza',
      email: 'admin@demo.ph',
      status: UserAccountStatus.active,
      mustChangePassword: false,
      qrCode: 'QR-ADM-0001',
    ),
    const AppUser(
      uid: 'u_registrar',
      schoolId: schoolId,
      role: UserRole.registrar,
      firstName: 'Joel',
      lastName: 'Bautista',
      email: 'registrar@demo.ph',
      status: UserAccountStatus.active,
      mustChangePassword: false,
      qrCode: 'QR-REG-0001',
    ),
    const AppUser(
      uid: 'u_faculty',
      schoolId: schoolId,
      role: UserRole.faculty,
      firstName: 'Maria',
      lastName: 'Santos',
      email: 'faculty@demo.ph',
      status: UserAccountStatus.active,
      mustChangePassword: false,
      qrCode: 'QR-FAC-0001',
    ),
    const AppUser(
      uid: 'u_staff',
      schoolId: schoolId,
      role: UserRole.staff,
      firstName: 'Ric',
      lastName: 'Domingo',
      email: 'staff@demo.ph',
      status: UserAccountStatus.active,
      mustChangePassword: false,
      qrCode: 'QR-STF-0001',
    ),
    const AppUser(
      uid: 'u_guidance',
      schoolId: schoolId,
      role: UserRole.guidance,
      firstName: 'Cecilia',
      lastName: 'Lim',
      email: 'guidance@demo.ph',
      status: UserAccountStatus.active,
      mustChangePassword: false,
      qrCode: 'QR-GUI-0001',
    ),
    const AppUser(
      uid: 'u_student',
      schoolId: schoolId,
      role: UserRole.student,
      firstName: 'Miguel',
      lastName: 'Torres',
      email: 'student@demo.ph',
      status: UserAccountStatus.active,
      mustChangePassword: false,
      qrCode: 'QR-STU-0001',
    ),
    const AppUser(
      uid: 'u_parent',
      schoolId: schoolId,
      role: UserRole.parent,
      firstName: 'Rosario',
      lastName: 'Torres',
      email: 'parent@demo.ph',
      status: UserAccountStatus.active,
      mustChangePassword: false,
      qrCode: 'QR-PAR-0001',
      linkedStudentIds: ['stu_001', 'stu_002'],
    ),
  ];

  // -------------------------------------------------------------------
  // Seeds
  // -------------------------------------------------------------------

  List<SchoolSummary> _seedSchools() => [
        SchoolSummary(
          id: schoolId,
          name: schoolName,
          status: SchoolSubscriptionStatus.active,
          activeStudentCount: 842,
          currentCycleAccrued: 842 * 3 * 12,
        ),
        SchoolSummary(
          id: 'school_sanmateo',
          name: 'San Mateo Colleges',
          status: SchoolSubscriptionStatus.gracePeriod,
          activeStudentCount: 1310,
          currentCycleAccrued: 1310 * 3 * 12,
          gracePeriodStartedAt: _daysAgo(4),
        ),
        SchoolSummary(
          id: 'school_maryhill',
          name: 'Maryhill Learning Center',
          status: SchoolSubscriptionStatus.suspended,
          activeStudentCount: 210,
          currentCycleAccrued: 0,
          suspendedAt: _daysAgo(11),
        ),
        SchoolSummary(
          id: 'school_bayanihan',
          name: 'Bayanihan Integrated School',
          status: SchoolSubscriptionStatus.active,
          activeStudentCount: 655,
          currentCycleAccrued: 655 * 3 * 12,
        ),
      ];

  RevenueSummary _seedRevenue() => RevenueSummary(
        dailyRevenue: (842 + 1310 + 655) * 3,
        monthlyRevenue: (842 + 1310 + 655) * 3 * 30,
        yearlyRevenue: (842 + 1310 + 655) * 3 * 365,
        activeSchoolCount: 2,
        totalActiveStudents: 842 + 1310 + 655,
        overdueSchoolCount: 1,
        suspendedSchoolCount: 1,
        lastUpdated: now.subtract(const Duration(minutes: 12)),
      );

  List<Invoice> _seedInvoices() {
    List<DailyBillingLine> lines(int days, int students) => [
          for (var i = days; i > 0; i--)
            DailyBillingLine(date: _daysAgo(i), activeStudents: students, charge: students * 3),
        ];
    return [
      Invoice(
        id: 'inv_0001',
        schoolId: schoolId,
        billingPeriodStart: DateTime(now.year, now.month - 1, 1),
        billingPeriodEnd: DateTime(now.year, now.month, 0),
        dailyBreakdown: lines(30, 842),
        totalAmount: 842 * 3 * 30,
        status: InvoiceStatus.paid,
        dueDate: DateTime(now.year, now.month, 10),
        paidAt: _daysAgo(9),
        paidAmount: 842 * 3 * 30,
        paymentMethod: billing.PaymentMethod.bankTransfer,
        paymentReference: 'BPI-338291',
      ),
      Invoice(
        id: 'inv_0002',
        schoolId: schoolId,
        billingPeriodStart: DateTime(now.year, now.month, 1),
        billingPeriodEnd: DateTime(now.year, now.month + 1, 0),
        dailyBreakdown: lines(12, 842),
        totalAmount: 842 * 3 * 12,
        status: InvoiceStatus.pending,
        dueDate: _daysAhead(18),
      ),
      Invoice(
        id: 'inv_0003',
        schoolId: 'school_sanmateo',
        billingPeriodStart: DateTime(now.year, now.month - 1, 1),
        billingPeriodEnd: DateTime(now.year, now.month, 0),
        dailyBreakdown: lines(30, 1310),
        totalAmount: 1310 * 3 * 30,
        status: InvoiceStatus.overdue,
        dueDate: _daysAgo(4),
      ),
    ];
  }

  List<StudentSummary> _seedStudents() => [
        StudentSummary(
          id: 'stu_001',
          studentNumber: '2024-00001',
          firstName: 'Miguel',
          lastName: 'Torres',
          middleName: 'Aquino',
          educationLevel: EducationLevel.highSchool,
          gradeLevel: 'Grade 10',
          section: 'Grade 10 - Rizal',
          status: StudentStatus.enrolled,
          balance: 8500,
          userId: 'u_student',
          enrollmentDate: DateTime(now.year, 6, 3),
          birthDate: DateTime(now.year - 16, 3, 14),
          guardianContacts: const [
            GuardianContact(
              name: 'Rosario Torres',
              relationship: 'Mother',
              phone: '0917 555 0142',
              email: 'parent@demo.ph',
            ),
          ],
        ),
        StudentSummary(
          id: 'stu_002',
          studentNumber: '2024-00002',
          firstName: 'Bea',
          lastName: 'Torres',
          educationLevel: EducationLevel.elementary,
          gradeLevel: 'Grade 4',
          section: 'Grade 4 - Sampaguita',
          status: StudentStatus.enrolled,
          balance: 0,
          enrollmentDate: DateTime(now.year, 6, 3),
          birthDate: DateTime(now.year - 10, 11, 2),
          guardianContacts: const [
            GuardianContact(
              name: 'Rosario Torres',
              relationship: 'Mother',
              phone: '0917 555 0142',
              email: 'parent@demo.ph',
            ),
          ],
        ),
        StudentSummary(
          id: 'stu_003',
          studentNumber: '2024-00003',
          firstName: 'Andrea',
          lastName: 'Villanueva',
          educationLevel: EducationLevel.highSchool,
          gradeLevel: 'Grade 10',
          section: 'Grade 10 - Rizal',
          status: StudentStatus.enrolled,
          balance: 12750,
          enrollmentDate: DateTime(now.year, 6, 5),
          birthDate: DateTime(now.year - 16, 7, 29),
        ),
        StudentSummary(
          id: 'stu_004',
          studentNumber: '2024-00004',
          firstName: 'Paolo',
          lastName: 'Ramirez',
          educationLevel: EducationLevel.highSchool,
          gradeLevel: 'Grade 10',
          section: 'Grade 10 - Rizal',
          status: StudentStatus.enrolled,
          balance: 0,
          enrollmentDate: DateTime(now.year, 6, 5),
        ),
        // A Senior High student, so the strand path is visible in the
        // demo without anyone having to register one first.
        StudentSummary(
          id: 'stu_009',
          studentNumber: '2025-00061',
          firstName: 'Trisha',
          lastName: 'Mercado',
          educationLevel: EducationLevel.seniorHigh,
          gradeLevel: 'Grade 11',
          section: 'STEM 11-A',
          programId: 'shs_stem',
          programName: 'Science, Technology, Engineering and Mathematics',
          department: 'Academic',
          status: StudentStatus.enrolled,
          balance: 12500,
          enrollmentDate: DateTime(now.year, 6, 3),
          birthDate: DateTime(now.year - 17, 9, 8),
          guardianContacts: const [
            GuardianContact(
              name: 'Elena Mercado',
              relationship: 'Mother',
              phone: '0918 555 0177',
            ),
          ],
        ),
        StudentSummary(
          id: 'stu_005',
          studentNumber: '2023-00118',
          firstName: 'Karla',
          lastName: 'Domingo',
          educationLevel: EducationLevel.college,
          gradeLevel: '3rd Year',
          section: 'BSCS 3-A',
          programId: 'prog_001',
          programName: 'BS Computer Science',
          department: 'Computer Studies',
          status: StudentStatus.enrolled,
          balance: 24000,
          enrollmentDate: DateTime(now.year - 2, 8, 12),
        ),
        StudentSummary(
          id: 'stu_006',
          studentNumber: '2023-00204',
          firstName: 'Nico',
          lastName: 'Fernandez',
          educationLevel: EducationLevel.college,
          gradeLevel: '2nd Year',
          section: 'BSA 2-B',
          programId: 'prog_002',
          programName: 'BS Accountancy',
          department: 'Business Administration',
          status: StudentStatus.enrolled,
          balance: 3200,
          enrollmentDate: DateTime(now.year - 1, 8, 10),
        ),
        StudentSummary(
          id: 'stu_007',
          studentNumber: '2022-00061',
          firstName: 'Liza',
          lastName: 'Ocampo',
          educationLevel: EducationLevel.college,
          gradeLevel: '4th Year',
          section: 'BSCS 4-A',
          programId: 'prog_001',
          programName: 'BS Computer Science',
          department: 'Computer Studies',
          status: StudentStatus.graduated,
          balance: 0,
          enrollmentDate: DateTime(now.year - 3, 8, 9),
        ),
        StudentSummary(
          id: 'stu_008',
          studentNumber: '2024-00051',
          firstName: 'Jun',
          lastName: 'Alvarez',
          educationLevel: EducationLevel.elementary,
          gradeLevel: 'Grade 4',
          section: 'Grade 4 - Sampaguita',
          status: StudentStatus.inactive,
          balance: 4400,
          enrollmentDate: DateTime(now.year, 6, 3),
        ),
      ];

  List<EmployeeSummary> _seedEmployees() => [
        for (final u in demoAccounts.where((a) => a.role.isStaffRole))
          EmployeeSummary(
            uid: u.uid,
            firstName: u.firstName,
            lastName: u.lastName,
            email: u.email,
            role: u.role,
            status: u.status,
            employeeInfo: EmployeeInfo(
              department: switch (u.role) {
                UserRole.registrar => "Registrar's Office",
                UserRole.faculty => 'Academics',
                UserRole.guidance => 'Student Affairs',
                UserRole.staff => 'Maintenance',
                _ => 'Administration',
              },
              position: u.role.displayName,
              dateHired: DateTime(now.year - 3, 6, 1),
              assignedDivision:
                  u.role == UserRole.faculty ? EducationLevel.highSchool : null,
            ),
          ),
        EmployeeSummary(
          uid: 'u_faculty_2',
          firstName: 'Dennis',
          lastName: 'Pascual',
          email: 'dpascual@demo.ph',
          role: UserRole.faculty,
          status: UserAccountStatus.active,
          employeeInfo: EmployeeInfo(
            department: 'Academics',
            position: 'College Instructor',
            dateHired: DateTime(now.year - 1, 8, 1),
            assignedDivision: EducationLevel.college,
            assignedDepartment: 'Computer Studies',
          ),
        ),
        EmployeeSummary(
          uid: 'u_staff_2',
          firstName: 'Tess',
          lastName: 'Aguilar',
          email: 'taguilar@demo.ph',
          role: UserRole.staff,
          status: UserAccountStatus.suspended,
          employeeInfo: EmployeeInfo(
            department: 'Canteen',
            position: 'Canteen Supervisor',
            dateHired: DateTime(now.year - 5, 1, 15),
          ),
        ),
      ];

  List<TeacherAssignment> _seedAssignments() {
    final sy = '${now.year}-${now.year + 1}';
    return [
      TeacherAssignment(
        id: 'ta_001',
        teacherId: 'u_faculty',
        teacherName: 'Maria Santos',
        subject: 'Mathematics',
        section: 'Grade 10 - Rizal',
        schoolYear: sy,
        // Maria advises this section, so the demo's emergency alert has
        // somebody real to reach.
        isAdviser: true,
      ),
      TeacherAssignment(
        id: 'ta_002',
        teacherId: 'u_faculty',
        teacherName: 'Maria Santos',
        subject: 'Science',
        section: 'Grade 10 - Rizal',
        schoolYear: sy,
      ),
      TeacherAssignment(
        id: 'ta_003',
        teacherId: 'u_faculty',
        teacherName: 'Maria Santos',
        subject: 'English',
        section: 'Grade 10 - Rizal',
        schoolYear: sy,
      ),
      TeacherAssignment(
        id: 'ta_004',
        teacherId: 'u_faculty_2',
        teacherName: 'Dennis Pascual',
        subject: 'Data Structures',
        section: 'BSCS 3-A',
        schoolYear: sy,
      ),
    ];
  }

  /// A week that hangs together.
  ///
  /// Built from the same sections, subjects and teachers the rest of the
  /// demo uses, so a student's timetable names the teacher who set their
  /// coursework and a room clash demonstration has real rooms in it. The
  /// two teachers never collide -- a demo that opens on a broken
  /// timetable reads as a bug rather than as a feature.
  List<ScheduleBlock> _seedScheduleBlocks() {
    final sy = '${now.year}-${now.year + 1}';
    var counter = 0;
    ScheduleBlock block({
      required String subject,
      required String section,
      required String teacherId,
      required String teacherName,
      required String room,
      required int day,
      required int start,
      required int end,
    }) {
      counter++;
      return ScheduleBlock(
        id: 'sched_${counter.toString().padLeft(3, '0')}',
        subject: subject,
        section: section,
        teacherId: teacherId,
        teacherName: teacherName,
        room: room,
        dayOfWeek: day,
        startMinute: start,
        endMinute: end,
        schoolYear: sy,
      );
    }

    const maria = 'u_faculty';
    const dennis = 'u_faculty_2';
    const rizal = 'Grade 10 - Rizal';
    const bscs = 'BSCS 3-A';

    return [
      // Grade 10 - Rizal, Monday to Friday mornings.
      for (var day = 1; day <= 5; day++)
        block(
          subject: 'Mathematics',
          section: rizal,
          teacherId: maria,
          teacherName: 'Maria Santos',
          room: 'Room 201',
          day: day,
          start: 7 * 60 + 30,
          end: 8 * 60 + 30,
        ),
      for (final day in [1, 3, 5])
        block(
          subject: 'Science',
          section: rizal,
          teacherId: maria,
          teacherName: 'Maria Santos',
          room: 'Science Lab',
          day: day,
          start: 8 * 60 + 40,
          end: 9 * 60 + 40,
        ),
      for (final day in [2, 4])
        block(
          subject: 'English',
          section: rizal,
          teacherId: maria,
          teacherName: 'Maria Santos',
          room: 'Room 201',
          day: day,
          start: 8 * 60 + 40,
          end: 9 * 60 + 40,
        ),
      // BSCS 3-A meets in the afternoon, so Dennis and Maria never
      // contend for a room and the seeded week is clash-free.
      for (final day in [1, 3])
        block(
          subject: 'Data Structures',
          section: bscs,
          teacherId: dennis,
          teacherName: 'Dennis Pascual',
          room: 'Computer Lab',
          day: day,
          start: 13 * 60,
          end: 14 * 60 + 30,
        ),
      for (final day in [2, 4])
        block(
          subject: 'Algorithms',
          section: bscs,
          teacherId: dennis,
          teacherName: 'Dennis Pascual',
          room: 'Computer Lab',
          day: day,
          start: 13 * 60,
          end: 14 * 60 + 30,
        ),
    ];
  }

  /// Two requests, one answered and one still waiting.
  ///
  /// The answered one is a refusal, because that is the case a school
  /// evaluating this actually wants to see handled: a family asks for a
  /// record to be deleted, the school cannot agree, and the system has
  /// somewhere to put the reason rather than pushing the office into
  /// silence.
  List<DataRequest> _seedDataRequests() => [
        DataRequest(
          id: 'dsr_001',
          requestedByUid: 'u_parent',
          requestedByName: 'Rosalinda Torres',
          kind: DataRequestKind.access,
          details: 'A copy of everything on file for my son Miguel, for a '
              'transfer application.',
          requestedAt: now.subtract(const Duration(days: 3)),
          studentId: 'stu_001',
          studentName: 'Miguel Torres',
        ),
        DataRequest(
          id: 'dsr_002',
          requestedByUid: 'u_student',
          requestedByName: 'Miguel Torres',
          kind: DataRequestKind.erasure,
          details: 'Please delete my Grade 9 records.',
          requestedAt: now.subtract(const Duration(days: 20)),
          status: DataRequestStatus.refused,
          handledByName: 'Joel Bautista',
          handledAt: now.subtract(const Duration(days: 18)),
          outcome: 'Academic records are ones the school is required to keep, '
              'and a transcript issued later has to show them. Your contact '
              'details and photograph can be changed or removed on request.',
        ),
      ];

  List<Program> _seedPrograms() => const [
        // Senior High: the DepEd tracks and strands as they are actually
        // offered in a PH private school. Seeded rather than left blank
        // because these are national, not per-school -- an Admin renames
        // or removes what they do not offer instead of typing all seven.
        Program(
          id: 'shs_stem',
          name: 'Science, Technology, Engineering and Mathematics',
          code: 'STEM',
          department: 'Academic',
          educationLevel: EducationLevel.seniorHigh,
        ),
        Program(
          id: 'shs_abm',
          name: 'Accountancy, Business and Management',
          code: 'ABM',
          department: 'Academic',
          educationLevel: EducationLevel.seniorHigh,
        ),
        Program(
          id: 'shs_humss',
          name: 'Humanities and Social Sciences',
          code: 'HUMSS',
          department: 'Academic',
          educationLevel: EducationLevel.seniorHigh,
        ),
        Program(
          id: 'shs_gas',
          name: 'General Academic Strand',
          code: 'GAS',
          department: 'Academic',
          educationLevel: EducationLevel.seniorHigh,
        ),
        Program(
          id: 'shs_tvl',
          name: 'Technical-Vocational-Livelihood',
          code: 'TVL',
          department: 'Technical-Vocational-Livelihood',
          educationLevel: EducationLevel.seniorHigh,
        ),
        Program(
          id: 'shs_arts',
          name: 'Arts and Design',
          code: 'ARTS',
          department: 'Arts and Design',
          educationLevel: EducationLevel.seniorHigh,
        ),
        Program(
          id: 'shs_sports',
          name: 'Sports',
          code: 'SPORTS',
          department: 'Sports',
          educationLevel: EducationLevel.seniorHigh,
        ),
        // College.
        Program(id: 'prog_001', name: 'BS Computer Science', code: 'BSCS', department: 'Computer Studies'),
        Program(id: 'prog_002', name: 'BS Accountancy', code: 'BSA', department: 'Business Administration'),
        Program(id: 'prog_003', name: 'BS Education', code: 'BSED', department: 'Teacher Education'),
      ];


  /// Two published schedules, one per division that has a student
  /// demonstrating it. Enough to show what assessing from a schedule
  /// looks like without turning the picker into a wall.
  ///
  /// The totals are chosen so the seeded assessments reconcile exactly
  /// with the seeded balances and payments. A demo where the itemised
  /// list does not add up to the figure above it would be demonstrating
  /// the bug this feature exists to fix.
  List<FeeStructure> _seedFeeStructures() {
    final year = DateTime.now().year;
    final sy = '$year-${year + 1}';
    return [
      // Assessed to Miguel Torres (stu_001): 17,000 charged, 8,500 paid
      // across two receipts, 8,500 outstanding.
      FeeStructure(
        id: 'fee_0001',
        name: 'Junior High School - $sy',
        educationLevel: EducationLevel.highSchool,
        schoolYear: sy,
        items: const [
          FeeItem(label: 'Tuition Fee', amount: 12000, category: FeeCategory.tuition),
          FeeItem(label: 'Miscellaneous Fee', amount: 3500, category: FeeCategory.miscellaneous),
          FeeItem(label: 'Laboratory Fee', amount: 1200, category: FeeCategory.miscellaneous),
          FeeItem(label: 'Student Handbook', amount: 300, category: FeeCategory.other),
        ],
        updatedAt: _daysAgo(45),
        updatedByName: 'Grace Mendoza',
      ),
      // Assessed to Trisha Mercado (stu_009): 12,500 charged, nothing
      // paid yet, 12,500 outstanding.
      FeeStructure(
        id: 'fee_0002',
        name: 'Senior High School - $sy',
        educationLevel: EducationLevel.seniorHigh,
        schoolYear: sy,
        items: const [
          FeeItem(label: 'Tuition Fee', amount: 9000, category: FeeCategory.tuition),
          FeeItem(label: 'Miscellaneous Fee', amount: 2500, category: FeeCategory.miscellaneous),
          FeeItem(label: 'Immersion Fee', amount: 1000, category: FeeCategory.other),
        ],
        updatedAt: _daysAgo(45),
        updatedByName: 'Grace Mendoza',
      ),
    ];
  }

  /// One assessment each for the two students whose balances they
  /// explain. The rest of the roster keeps a balance with no assessment
  /// behind it, which is not an oversight: it is what a school looks
  /// like partway through adopting this, and the breakdown screen has to
  /// say so rather than implying the list is the whole story.
  List<Assessment> _seedAssessments() {
    final year = DateTime.now().year;
    final sy = '$year-${year + 1}';
    return [
      Assessment(
        id: 'asmt_0001',
        studentId: 'stu_001',
        studentName: 'Miguel Torres',
        schoolYear: sy,
        sourceStructureId: 'fee_0001',
        sourceStructureName: 'Junior High School - $sy',
        items: const [
          FeeItem(label: 'Tuition Fee', amount: 12000, category: FeeCategory.tuition),
          FeeItem(label: 'Miscellaneous Fee', amount: 3500, category: FeeCategory.miscellaneous),
          FeeItem(label: 'Laboratory Fee', amount: 1200, category: FeeCategory.miscellaneous),
          FeeItem(label: 'Student Handbook', amount: 300, category: FeeCategory.other),
        ],
        assessedByName: 'Joel Bautista',
        assessedAt: _daysAgo(40),
      ),
      Assessment(
        id: 'asmt_0002',
        studentId: 'stu_009',
        studentName: 'Trisha Mercado',
        schoolYear: sy,
        sourceStructureId: 'fee_0002',
        sourceStructureName: 'Senior High School - $sy',
        items: const [
          FeeItem(label: 'Tuition Fee', amount: 9000, category: FeeCategory.tuition),
          FeeItem(label: 'Miscellaneous Fee', amount: 2500, category: FeeCategory.miscellaneous),
          FeeItem(label: 'Immersion Fee', amount: 1000, category: FeeCategory.other),
        ],
        assessedByName: 'Joel Bautista',
        assessedAt: _daysAgo(38),
      ),
    ];
  }

  List<Payment> _seedPayments() => [
        Payment(
          id: 'pay_001',
          studentId: 'stu_001',
          amount: 5000,
          method: PaymentMethod.cash,
          receiptNumber: 'OR-2024-000117',
          collectedByName: 'Joel Bautista',
          purpose: PaymentPurpose.tuition,
          status: PaymentStatus.completed,
          createdAt: _daysAgo(21),
        ),
        Payment(
          id: 'pay_002',
          studentId: 'stu_001',
          amount: 3500,
          method: PaymentMethod.gcash,
          referenceNumber: 'GC-8871203',
          receiptNumber: 'OR-2024-000164',
          collectedByName: 'Joel Bautista',
          purpose: PaymentPurpose.miscFee,
          status: PaymentStatus.completed,
          createdAt: _daysAgo(6),
        ),
        Payment(
          id: 'pay_003',
          studentId: 'stu_003',
          amount: 7250,
          method: PaymentMethod.bankTransfer,
          referenceNumber: 'BDO-449120',
          receiptNumber: 'OR-2024-000165',
          collectedByName: 'Joel Bautista',
          purpose: PaymentPurpose.tuition,
          status: PaymentStatus.completed,
          createdAt: _daysAgo(2),
        ),
        Payment(
          id: 'pay_004',
          studentId: 'stu_003',
          amount: 1200,
          method: PaymentMethod.cash,
          receiptNumber: 'OR-2024-000166',
          collectedByName: 'Joel Bautista',
          purpose: PaymentPurpose.other,
          status: PaymentStatus.refunded,
          createdAt: _daysAgo(1),
        ),
        Payment(
          id: 'pay_005',
          studentId: 'stu_003',
          amount: -1200,
          method: PaymentMethod.cash,
          receiptNumber: 'RF-2024-000012',
          collectedByName: 'Grace Mendoza',
          purpose: PaymentPurpose.other,
          status: PaymentStatus.refunded,
          refundOf: 'pay_004',
          createdAt: _daysAgo(1),
        ),
        // Two collected today. Without them the director's "Today's
        // Collections" tile reads P0.00 on every run for the same reason
        // the attendance rate used to read 0%: the seed only ever
        // described the past, so the one figure the dashboard is actually
        // about was always empty.
        Payment(
          id: 'pay_006',
          studentId: 'stu_002',
          amount: 4500,
          method: PaymentMethod.cash,
          receiptNumber: 'OR-2024-000171',
          collectedByName: 'Joel Bautista',
          purpose: PaymentPurpose.tuition,
          status: PaymentStatus.completed,
          createdAt: _atHour(0, 9, 14),
        ),
        Payment(
          id: 'pay_007',
          studentId: 'stu_004',
          amount: 850,
          method: PaymentMethod.gcash,
          receiptNumber: 'OR-2024-000172',
          referenceNumber: 'GC-9042118',
          collectedByName: 'Grace Mendoza',
          purpose: PaymentPurpose.miscFee,
          status: PaymentStatus.completed,
          createdAt: _atHour(0, 11, 2),
        ),
      ];

  List<AttendanceRecord> _seedAttendance() {
    final records = <AttendanceRecord>[];
    var seq = 0;

    // Every enrolled student, not just one. The Director dashboard reads
    // "Attendance Rate Today" as scans-today over enrolled-students, so
    // seeding a single student made a full school look like a 14% turnout.
    final roll = students.value
        .where((s) => s.status == StudentStatus.enrolled)
        .toList();

    for (var d = 0; d < 14; d++) {
      final day = _daysAgo(d);

      // Weekends have no attendance -- except today. A demo opened on a
      // Saturday would otherwise show a school with nobody in it and a 0%
      // rate, which reads as a broken app rather than as the weekend.
      final isWeekend =
          day.weekday == DateTime.saturday || day.weekday == DateTime.sunday;
      if (isWeekend && d != 0) continue;

      // One student is out each day, rotating through the roll. Absence is
      // the *absence* of a scan, not a record saying so: that is how the QR
      // flow actually works, and it keeps the rate honest rather than
      // hard-coding a number.
      //
      // Offset by one so the rotation does not start on roll[0], who is the
      // student the demo account signs in as: their own "My Attendance"
      // opening on a blank today looked exactly like the bug this seeding
      // was written to fix.
      final absentIndex = roll.isEmpty ? -1 : (d + 1) % roll.length;

      for (var i = 0; i < roll.length; i++) {
        if (i == absentIndex) continue;
        final student = roll[i];
        final late = (i + d) % 7 == 0;
        // Scattered across the gate queue rather than repeated: a column of
        // rows all reading 7:35 AM is the tell that a record set was
        // generated, not collected.
        final minute = late ? 18 + (i + d) % 9 : 28 + (i * 3 + d * 5) % 17;
        records.add(AttendanceRecord(
          id: 'att_${++seq}',
          personId: student.id,
          personRole: 'student',
          subjectType: AttendanceSubjectType.student,
          date: _dateKey(day),
          timestampIn:
              DateTime(day.year, day.month, day.day, late ? 8 : 7, minute),
          // Nobody has tapped out yet on the current day.
          timestampOut: d == 0
              ? null
              : DateTime(day.year, day.month, day.day, 16, 2 + (i + d) % 12),
          status: late ? AttendanceStatus.late : AttendanceStatus.present,
          location: 'Main Gate',
        ));
      }

      records.add(AttendanceRecord(
        id: 'att_${++seq}',
        personId: 'u_faculty',
        personRole: 'faculty',
        subjectType: AttendanceSubjectType.employee,
        date: _dateKey(day),
        timestampIn: DateTime(day.year, day.month, day.day, 7, 12),
        timestampOut:
            d == 0 ? null : DateTime(day.year, day.month, day.day, 17, 2),
        status: AttendanceStatus.present,
        location: 'Faculty Entrance',
      ));
    }
    return records;
  }

  List<CourseworkItem> _seedCoursework() => [
        CourseworkItem(
          id: 'cw_001',
          type: CourseworkType.assignment,
          title: 'Quadratic Equations - Problem Set 4',
          description: 'Answer items 1-20 in the workbook. Show complete solutions.',
          subject: 'Mathematics',
          section: 'Grade 10 - Rizal',
          teacherId: 'u_faculty',
          teacherName: 'Maria Santos',
          // The paper the class is working from. Attached because a
          // student opening an assignment and finding only a one-line
          // description has nothing to actually do.
          attachmentUrl: DemoAttachments.problemSet4,
          attachmentName: 'problem-set-4.pdf',
          dueDate: _daysAhead(3),
          totalPoints: 40,
          published: true,
          createdAt: _daysAgo(2),
        ),
        CourseworkItem(
          id: 'cw_002',
          type: CourseworkType.quiz,
          title: 'Quiz 3 - Cell Division',
          description: 'Answer the quiz sheet and submit it before the due date.',
          subject: 'Science',
          section: 'Grade 10 - Rizal',
          teacherId: 'u_faculty',
          teacherName: 'Maria Santos',
          // The one online item in the seed, so the student portal shows
          // what taking work through the app looks like without anyone
          // having to create one first.
          delivery: CourseworkDelivery.online,
          attachmentUrl: DemoAttachments.quiz3CellDivision,
          attachmentName: 'quiz-3-cell-division.pdf',
          dueDate: _daysAhead(1),
          totalPoints: 25,
          questionCount: 4,
          published: true,
          createdAt: _daysAgo(4),
        ),
        CourseworkItem(
          id: 'cw_003',
          type: CourseworkType.exam,
          title: 'Second Quarter Exam',
          description: 'Covers Units 3 and 4.',
          subject: 'Mathematics',
          section: 'Grade 10 - Rizal',
          teacherId: 'u_faculty',
          teacherName: 'Maria Santos',
          dueDate: _daysAhead(10),
          totalPoints: 100,
          published: true,
          createdAt: _daysAgo(1),
        ),
        CourseworkItem(
          id: 'cw_004',
          type: CourseworkType.lessonPlan,
          title: 'Week 7 Lesson Plan - Polynomials',
          description: 'Objectives, materials, and activities for the week.',
          subject: 'Mathematics',
          section: 'Grade 10 - Rizal',
          teacherId: 'u_faculty',
          teacherName: 'Maria Santos',
          published: false,
          createdAt: _daysAgo(7),
        ),
        CourseworkItem(
          id: 'cw_005',
          type: CourseworkType.lesson,
          title: 'Reading: Florante at Laura, Canto 1-5',
          description: 'Read before Thursday. We will discuss in class.',
          subject: 'English',
          section: 'Grade 10 - Rizal',
          teacherId: 'u_faculty',
          teacherName: 'Maria Santos',
          attachmentUrl: DemoAttachments.floranteAtLaura,
          attachmentName: 'florante-at-laura-canto-1-5.pdf',
          published: true,
          createdAt: _daysAgo(5),
        ),
        CourseworkItem(
          id: 'cw_006',
          type: CourseworkType.project,
          title: 'Science Fair Prototype',
          description: 'Group of 3. Submit proposal first.',
          subject: 'Science',
          section: 'Grade 10 - Rizal',
          teacherId: 'u_faculty',
          teacherName: 'Maria Santos',
          dueDate: _daysAhead(21),
          totalPoints: 60,
          published: true,
          createdAt: _daysAgo(9),
        ),
      ];

  /// One release, from long enough ago to read as history rather than
  /// as something that just happened. The live state comes from
  /// releasing a document yourself -- a demo that opens on a busy
  /// history teaches nothing about how an entry gets there.
  List<DocumentRelease> _seedDocumentReleases() => [
        DocumentRelease(
          id: 'rel_001',
          studentId: 'stu_003',
          studentName: 'Andrea Villanueva',
          document: SchoolDocument.form137,
          copies: 1,
          purpose: 'Transfer to Santa Rosa National High School',
          releasedToName: 'Lourdes Villanueva',
          releasedToRelation: 'Mother',
          releasedByName: 'Rosario Aguilar',
          releasedAt: _daysAgo(23),
        ),
      ];

  List<Grade> _seedGrades() => [
        Grade(
          id: 'gr_001',
          studentId: 'stu_001',
          studentName: 'Miguel Torres',
          subject: 'Mathematics',
          section: 'Grade 10 - Rizal',
          term: '2nd Quarter',
          courseworkItemId: 'cw_001',
          score: 34,
          maxScore: 40,
          submittedByName: 'Maria Santos',
          submittedAt: _daysAgo(1),
        ),
        Grade(
          id: 'gr_002',
          studentId: 'stu_001',
          studentName: 'Miguel Torres',
          subject: 'Science',
          section: 'Grade 10 - Rizal',
          term: '2nd Quarter',
          courseworkItemId: 'cw_002',
          score: 21,
          maxScore: 25,
          remarks: 'Good improvement from Quiz 2.',
          submittedByName: 'Maria Santos',
          submittedAt: _daysAgo(3),
        ),
        Grade(
          id: 'gr_003',
          studentId: 'stu_001',
          studentName: 'Miguel Torres',
          subject: 'English',
          section: 'Grade 10 - Rizal',
          term: '1st Quarter',
          score: 88,
          maxScore: 100,
          submittedByName: 'Maria Santos',
          submittedAt: _daysAgo(40),
        ),
        Grade(
          id: 'gr_004',
          studentId: 'stu_003',
          studentName: 'Andrea Villanueva',
          subject: 'Mathematics',
          section: 'Grade 10 - Rizal',
          term: '2nd Quarter',
          courseworkItemId: 'cw_001',
          score: 39,
          maxScore: 40,
          submittedByName: 'Maria Santos',
          submittedAt: _daysAgo(1),
        ),
        Grade(
          id: 'gr_005',
          studentId: 'stu_004',
          studentName: 'Paolo Ramirez',
          subject: 'Mathematics',
          section: 'Grade 10 - Rizal',
          term: '2nd Quarter',
          courseworkItemId: 'cw_001',
          score: 27,
          maxScore: 40,
          remarks: 'Needs to review factoring.',
          submittedByName: 'Maria Santos',
          submittedAt: _daysAgo(1),
        ),
      ];

  /// One alert, already dealt with.
  ///
  /// Resolved rather than active, deliberately. A demo that always opens
  /// with a child mid-emergency is alarming and stops being informative
  /// after the first look. This gives the parent's screen a history to
  /// show; the live state is produced by pressing the button as the
  /// student and switching roles, which is the flow worth watching
  /// anyway.
  List<EmergencyAlert> _seedEmergencyAlerts() => [
        EmergencyAlert(
          id: 'alert_001',
          studentId: 'stu_001',
          studentName: 'Miguel Torres',
          section: 'Grade 10 - Rizal',
          userId: 'u_student',
          message: 'Sprained my ankle at the covered court, cannot walk.',
          raisedAt: _atHour(6, 14, 22),
          latitude: 13.9411,
          longitude: 121.1631,
          locationAccuracyMeters: 12,
          acknowledgedByName: 'Maria Santos',
          acknowledgedAt: _atHour(6, 14, 24),
          resolvedAt: _atHour(6, 14, 51),
          resolutionNote: 'Brought to the clinic, ice applied. Mother called and collected him.',
        ),
      ];

  List<Announcement> _seedAnnouncements() => [
        Announcement(
          id: 'ann_001',
          title: 'Class suspension - Typhoon Signal No. 2',
          body: 'All classes across every division are suspended tomorrow. '
              'Faculty need not report. Skeletal admin staff only.',
          audience: AnnouncementAudience.everyone,
          pinned: true,
          createdByName: 'Elena Cruz',
          createdAt: _daysAgo(1),
        ),
        Announcement(
          id: 'ann_002',
          title: 'Second Quarter exam schedule posted',
          body: 'The exam schedule is now posted on the bulletin board and in each section adviser\'s group chat.',
          audience: const AnnouncementAudience(all: false, roles: ['faculty', 'student', 'parent']),
          pinned: false,
          createdByName: 'Antonio Reyes',
          createdAt: _daysAgo(5),
        ),
        Announcement(
          id: 'ann_003',
          title: 'Payroll cut-off moved to the 25th',
          body: 'For this month only, timesheet submission closes on the 25th.',
          audience: const AnnouncementAudience(all: false, roles: ['faculty', 'staff', 'admin', 'registrar', 'guidance']),
          pinned: false,
          createdByName: 'Grace Mendoza',
          createdAt: _daysAgo(8),
        ),
        // A teacher's post to her own advisory class. Seeded so the demo
        // shows what section targeting looks like from both ends: Maria
        // Santos sees it under "Posted by you", the Grade 10 - Rizal
        // student and their parent see it in their list, and the Grade 4
        // student does not see it at all.
        Announcement(
          id: 'ann_004',
          title: 'Bring your permit slip on Friday',
          body: 'Rizal, please have a parent sign the field trip permit and '
              'bring it Friday morning. No slip, no trip — I cannot make '
              'exceptions on the day.',
          audience: AnnouncementAudience.forSections(const ['Grade 10 - Rizal']),
          pinned: false,
          createdByName: 'Maria Santos',
          createdBy: 'u_faculty',
          createdAt: _daysAgo(2),
        ),
      ];

  /// One assignment already handed in, so the student portal shows the
  /// "submitted" state and the faculty view is not empty. Quiz 3 is left
  /// undone on purpose -- the not-yet-handed-in path is the one that
  /// actually needs looking at.
  List<CourseworkSubmission> _seedCourseworkSubmissions() => [
        CourseworkSubmission(
          id: 'cw_001_stu_001',
          courseworkId: 'cw_001',
          courseworkTitle: 'Quadratic Equations - Problem Set 4',
          studentId: 'stu_001',
          studentName: 'Miguel Torres',
          section: 'Grade 10 - Rizal',
          userId: 'u_student',
          answer: 'Items 1-20 answered. Solutions attached, shown per step.',
          attachmentUrl: 'https://example.org/demo/problem-set-4-miguel.pdf',
          attachmentName: 'problem-set-4-miguel.pdf',
          submittedAt: _daysAgo(1),
        ),
      ];

  /// A key on the online quiz, so automatic marking is visible in the
  /// demo without a teacher having to write one first.
  List<AnswerKey> _seedAnswerKeys() => [
        AnswerKey(
          courseworkId: 'cw_002',
          answers: const ['Mitosis', 'Meiosis', 'Four', 'Prophase'],
          pointsPerQuestion: 6.25,
          updatedByName: 'Maria Santos',
          updatedAt: _daysAgo(4),
        ),
      ];

  /// Seeded with the numbers a PH school actually posts by the door.
  /// Real hotlines, so the demo is not teaching anyone a fake number:
  /// 911 is the national emergency line, and the rest are the local
  /// offices this fictional school would list.
  List<EmergencyContact> _seedEmergencyContacts() => [
        EmergencyContact(
          id: 'emg_911',
          label: 'National Emergency Hotline',
          phone: '911',
          notes: 'Police, fire and medical, nationwide.',
          sortOrder: 0,
          updatedAt: _daysAgo(30),
          updatedByName: 'Grace Mendoza',
        ),
        EmergencyContact(
          id: 'emg_bfp',
          label: 'BFP - San Nicolas Fire Station',
          phone: '(043) 555 0161',
          notes: 'Bureau of Fire Protection.',
          sortOrder: 1,
          updatedAt: _daysAgo(30),
          updatedByName: 'Grace Mendoza',
        ),
        EmergencyContact(
          id: 'emg_pnp',
          label: 'PNP - San Nicolas Police Station',
          phone: '(043) 555 0117',
          notes: 'Ask for the desk officer.',
          sortOrder: 2,
          updatedAt: _daysAgo(30),
          updatedByName: 'Grace Mendoza',
        ),
        EmergencyContact(
          id: 'emg_clinic',
          label: 'School Clinic',
          phone: '0917 555 0188',
          notes: 'Ground floor, beside the registrar. 7am-5pm.',
          sortOrder: 3,
          updatedAt: _daysAgo(30),
          updatedByName: 'Grace Mendoza',
        ),
      ];

  List<Meeting> _seedMeetings() => [
        Meeting(
          id: 'mtg_001',
          title: 'Department Heads Sync',
          description: 'Enrollment projections for next school year.',
          startTime: _daysAhead(2).copyWith(hour: 9, minute: 0),
          endTime: _daysAhead(2).copyWith(hour: 10, minute: 30),
          location: 'Conference Room A',
          attendeeRoles: const ['principal', 'admin', 'registrar'],
          status: MeetingStatus.scheduled,
          createdByName: 'Elena Cruz',
        ),
        Meeting(
          id: 'mtg_002',
          title: 'Faculty General Assembly',
          startTime: _daysAhead(6).copyWith(hour: 13, minute: 0),
          endTime: _daysAhead(6).copyWith(hour: 15, minute: 0),
          location: 'AVR',
          attendeeRoles: const ['faculty', 'principal'],
          status: MeetingStatus.scheduled,
          createdByName: 'Antonio Reyes',
        ),
        Meeting(
          id: 'mtg_003',
          title: 'Budget Review - Q3',
          startTime: _daysAgo(3).copyWith(hour: 14, minute: 0),
          endTime: _daysAgo(3).copyWith(hour: 16, minute: 0),
          location: 'Director\'s Office',
          attendeeRoles: const ['admin'],
          status: MeetingStatus.completed,
          createdByName: 'Elena Cruz',
        ),
      ];

  List<ApprovalRequest> _seedApprovals() => [
        ApprovalRequest(
          id: 'apr_001',
          type: 'material_request',
          title: 'Whiteboard markers and manila paper',
          description: '2 boxes of markers, 30 sheets of manila paper for Grade 10 - Rizal.',
          details: const {'quantity': 32, 'estimatedCost': 850.0},
          requestedByName: 'Maria Santos',
          requestedByRole: 'faculty',
          status: ApprovalStatus.pending,
          createdAt: _daysAgo(1),
        ),
        ApprovalRequest(
          id: 'apr_002',
          type: 'purchase_request',
          title: 'Replacement projector for AVR',
          description: 'Existing unit no longer powers on.',
          details: const {'estimatedCost': 28000.0, 'vendor': 'CDR King'},
          requestedByName: 'Grace Mendoza',
          requestedByRole: 'admin',
          status: ApprovalStatus.pending,
          createdAt: _daysAgo(3),
        ),
        ApprovalRequest(
          id: 'apr_003',
          type: 'promissory_note',
          title: 'Promissory note - Second Quarter exam permit',
          description: 'Requesting to take the exam and settle the balance by the 30th.',
          details: const {'studentId': 'stu_001', 'amount': 8500.0},
          requestedByName: 'Miguel Torres',
          requestedByRole: 'student',
          status: ApprovalStatus.approved,
          decidedByName: 'Elena Cruz',
          decidedAt: _daysAgo(2),
          decisionRemarks: 'Approved. Settle on or before the 30th.',
          createdAt: _daysAgo(4),
        ),
        ApprovalRequest(
          id: 'apr_004',
          type: 'leave_request',
          title: 'Sick leave - 2 days',
          details: const {'days': 2},
          requestedByName: 'Ric Domingo',
          requestedByRole: 'staff',
          status: ApprovalStatus.rejected,
          decidedByName: 'Grace Mendoza',
          decidedAt: _daysAgo(6),
          decisionRemarks: 'No medical certificate attached. Please refile.',
          createdAt: _daysAgo(7),
        ),
      ];

  List<Expense> _seedExpenses() => [
        Expense(
          id: 'exp_001',
          category: 'Utilities',
          description: 'Meralco - October billing',
          amount: 68400,
          date: _daysAgo(5),
          recordedByName: 'Grace Mendoza',
        ),
        Expense(
          id: 'exp_002',
          category: 'Supplies',
          description: 'Bond paper, ink, and folders',
          amount: 12350,
          date: _daysAgo(9),
          recordedByName: 'Grace Mendoza',
        ),
        Expense(
          id: 'exp_003',
          category: 'Maintenance',
          description: 'Roof repair - Building B',
          amount: 45000,
          date: _daysAgo(16),
          recordedByName: 'Elena Cruz',
        ),
      ];

  List<ChecklistItem> _seedChecklist() => [
        ChecklistItem(id: 'chk_001', task: 'Unlock all classrooms in Building A', date: todayKey, completed: true, completedAt: now.subtract(const Duration(hours: 5))),
        ChecklistItem(id: 'chk_002', task: 'Check restroom supplies', date: todayKey, completed: true, completedAt: now.subtract(const Duration(hours: 3))),
        ChecklistItem(id: 'chk_003', task: 'Sweep the quadrangle', date: todayKey, completed: false),
        ChecklistItem(id: 'chk_004', task: 'Lock the gate after dismissal', date: todayKey, completed: false),
      ];

  List<DailyReport> _seedDailyReports() => [
        DailyReport(
          id: 'rep_001',
          date: _dateKey(_daysAgo(1)),
          content: 'All rooms opened by 6:30 AM. Reported a broken faucet in the Grade 8 restroom to Admin.',
          staffName: 'Ric Domingo',
          submittedAt: _daysAgo(1),
        ),
        DailyReport(
          id: 'rep_002',
          date: _dateKey(_daysAgo(2)),
          content: 'Routine day. Quadrangle cleaned after the intramurals practice.',
          staffName: 'Ric Domingo',
          submittedAt: _daysAgo(2),
        ),
      ];

  List<GuidanceRecord> _seedGuidanceRecords() => [
        GuidanceRecord(
          id: 'gui_001',
          studentId: 'stu_001',
          studentName: 'Miguel Torres',
          section: 'Grade 10 - Rizal',
          category: GuidanceCategory.academic,
          notes: 'Discussed drop in Math scores. Student reports difficulty concentrating '
              'during afternoon classes. Advised to sit in front and follow up in two weeks.',
          recordedByName: 'Cecilia Lim',
          recordedAt: _daysAgo(10),
        ),
        GuidanceRecord(
          id: 'gui_002',
          studentId: 'stu_004',
          studentName: 'Paolo Ramirez',
          section: 'Grade 10 - Rizal',
          category: GuidanceCategory.behavioral,
          notes: 'Third tardiness this month. Parent contacted by phone.',
          recordedByName: 'Cecilia Lim',
          recordedAt: _daysAgo(4),
        ),
      ];

  List<GuidanceRecord> get _extraSectionRecord => [];

  List<Summons> _seedSummonses() => [
        Summons(
          id: 'sum_001',
          studentId: 'stu_004',
          studentName: 'Paolo Ramirez',
          reason: 'Follow-up on attendance record',
          scheduledDate: _daysAhead(2),
          status: SummonsStatus.pending,
          issuedByName: 'Cecilia Lim',
          createdAt: _daysAgo(1),
        ),
        Summons(
          id: 'sum_002',
          studentId: 'stu_001',
          studentName: 'Miguel Torres',
          reason: 'Academic counseling follow-up',
          scheduledDate: _daysAgo(3),
          status: SummonsStatus.completed,
          issuedByName: 'Cecilia Lim',
          createdAt: _daysAgo(8),
        ),
      ];

  /// One pending submission so the registrar's review queue is not empty
  /// on first open, and one already approved so the family-side history
  /// shows both outcomes.
  List<PaymentSubmission> _seedSubmissions() => [
        PaymentSubmission(
          id: 'sub_0001',
          studentId: 'stu_003',
          studentName: 'Andrea Villanueva',
          submittedByName: 'Andrea Villanueva',
          submittedByRole: 'student',
          amount: 4000,
          method: PaymentMethod.gcash,
          purpose: PaymentPurpose.tuition,
          referenceNumber: 'GC-2210044',
          status: SubmissionStatus.pending,
          submittedAt: _daysAgo(1),
        ),
        PaymentSubmission(
          id: 'sub_0002',
          studentId: 'stu_001',
          studentName: 'Miguel Torres',
          submittedByName: 'Rosario Torres',
          submittedByRole: 'parent',
          amount: 3500,
          method: PaymentMethod.gcash,
          purpose: PaymentPurpose.miscFee,
          referenceNumber: 'GC-8871203',
          status: SubmissionStatus.approved,
          reviewedByName: 'Joel Bautista',
          reviewedAt: _daysAgo(6),
          resultingPaymentId: 'pay_002',
          submittedAt: _daysAgo(6),
        ),
      ];

  PaymentSettings _seedPaymentSettings() => PaymentSettings(
        accountName: 'St. Nicholas Academy',
        accountNumber: '0917 555 0100',
        instructions:
            'Scan the QR or send to the number above, then upload your receipt '
            'with the reference number. Payments are posted once the cashier '
            'verifies them.',
        updatedAt: _daysAgo(30),
        updatedByName: 'Joel Bautista',
      );

  List<AuditLogEntry> _seedAuditLog() => [
        AuditLogEntry(
          id: 'aud_001',
          userId: 'u_registrar',
          userRole: 'registrar',
          userName: 'Joel Bautista',
          module: 'payments',
          action: 'create',
          targetCollection: 'payments',
          targetId: 'pay_003',
          newValue: const {'amount': 7250, 'method': 'bank_transfer'},
          success: true,
          timestamp: _daysAgo(2),
        ),
        AuditLogEntry(
          id: 'aud_002',
          userId: 'u_admin',
          userRole: 'admin',
          userName: 'Grace Mendoza',
          module: 'payments',
          action: 'refund',
          targetCollection: 'payments',
          targetId: 'pay_004',
          newValue: const {'reason': 'Duplicate charge'},
          remarks: 'Duplicate charge',
          success: true,
          timestamp: _daysAgo(1),
        ),
        AuditLogEntry(
          id: 'aud_003',
          userId: 'u_faculty',
          userRole: 'faculty',
          userName: 'Maria Santos',
          module: 'grades',
          action: 'create',
          targetCollection: 'grades',
          targetId: 'gr_001',
          newValue: const {'score': 34, 'maxScore': 40},
          success: true,
          timestamp: _daysAgo(1),
        ),
        AuditLogEntry(
          id: 'aud_004',
          userId: 'u_director',
          userRole: 'director',
          userName: 'Elena Cruz',
          module: 'approvals',
          action: 'approve',
          targetCollection: 'approvals',
          targetId: 'apr_003',
          success: true,
          timestamp: _daysAgo(2),
        ),
      ];
}
