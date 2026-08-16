import 'package:rxdart/rxdart.dart';

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
import '../features/payments/domain/entities/payment.dart';
import '../features/payments/domain/entities/payment_settings.dart';
import '../features/payments/domain/entities/payment_submission.dart';
import '../features/qr_attendance/domain/entities/attendance_record.dart';
import '../features/registrar_portal/domain/entities/student_summary.dart';
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

  int _idSeq = 0;
  String nextId(String prefix) => '${prefix}_${(++_idSeq).toString().padLeft(4, '0')}';

  // -------------------------------------------------------------------
  // Session
  // -------------------------------------------------------------------

  /// Null when signed out. The router watches a stream derived from this.
  final currentUser = BehaviorSubject<AppUser?>.seeded(null);

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
  late final attendance = BehaviorSubject<List<AttendanceRecord>>.seeded(_seedAttendance());
  late final coursework = BehaviorSubject<List<CourseworkItem>>.seeded(_seedCoursework());
  /// Named for the collection, not shortened to `submissions` -- payment
  /// submissions already own that word in this store.
  late final emergencyContacts =
      BehaviorSubject<List<EmergencyContact>>.seeded(_seedEmergencyContacts());
  late final emergencyAlerts = BehaviorSubject<List<EmergencyAlert>>.seeded(const []);
  late final answerKeys = BehaviorSubject<List<AnswerKey>>.seeded(_seedAnswerKeys());
  late final courseworkSubmissions =
      BehaviorSubject<List<CourseworkSubmission>>.seeded(_seedCourseworkSubmissions());
  late final grades = BehaviorSubject<List<Grade>>.seeded(_seedGrades());
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
    // No logo by default: an unbranded school is the honest starting state,
    // and it exercises the "upload one" path rather than hiding it.
    SchoolBranding(
      schoolName: schoolName,
      addressLine: 'Poblacion, San Nicolas, Batangas',
      schoolYear: '${DateTime.now().year}-${DateTime.now().year + 1}',
      principalName: 'Ramon Salazar',
      directorName: 'Corazon Buenaventura',
      updatedAt: _daysAgo(60),
      updatedByName: 'Grace Mendoza',
    ),
  );

  /// Prepends [item] to a collection and republishes it. Insert-at-front
  /// matches how every list screen in this app sorts (newest first).
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
      paymentSubmissions, paymentSettings, branding,
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
      ];

  List<AttendanceRecord> _seedAttendance() {
    final records = <AttendanceRecord>[];
    var seq = 0;
    // Two weeks of history for the demo student and the demo teacher, so
    // the history screens are not empty on first open.
    for (var d = 0; d < 14; d++) {
      final day = _daysAgo(d);
      if (day.weekday == DateTime.saturday || day.weekday == DateTime.sunday) continue;
      final late = d % 5 == 3;
      records.add(AttendanceRecord(
        id: 'att_${++seq}',
        personId: 'stu_001',
        personRole: 'student',
        subjectType: AttendanceSubjectType.student,
        date: _dateKey(day),
        timestampIn: DateTime(day.year, day.month, day.day, late ? 8 : 7, late ? 22 : 41),
        timestampOut: d == 0 ? null : DateTime(day.year, day.month, day.day, 16, 5),
        status: late ? AttendanceStatus.late : AttendanceStatus.present,
        location: 'Main Gate',
      ));
      records.add(AttendanceRecord(
        id: 'att_${++seq}',
        personId: 'u_faculty',
        personRole: 'faculty',
        subjectType: AttendanceSubjectType.employee,
        date: _dateKey(day),
        timestampIn: DateTime(day.year, day.month, day.day, 7, 12),
        timestampOut: d == 0 ? null : DateTime(day.year, day.month, day.day, 17, 2),
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
          attachmentUrl: 'https://example.org/demo/quiz-3-cell-division.pdf',
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
