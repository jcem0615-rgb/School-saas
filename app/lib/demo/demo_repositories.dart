import '../core/constants/education_level.dart';
import '../core/constants/user_roles.dart';
import '../core/errors/failures.dart';
import '../core/errors/result.dart';
import '../features/admin_portal/domain/entities/employee_summary.dart';
import '../features/admin_portal/domain/entities/program.dart';
import '../features/admin_portal/domain/entities/teacher_assignment.dart';
import '../features/admin_portal/domain/repositories/admin_repository.dart';
import '../features/audit_trail/domain/entities/audit_log_entry.dart';
import '../features/audit_trail/domain/repositories/audit_trail_repository.dart';
import '../features/auth/domain/entities/app_user.dart';
import '../features/auth/domain/repositories/auth_repository.dart';
import '../features/director_portal/domain/entities/announcement.dart';
import '../features/director_portal/domain/entities/approval_request.dart';
import '../features/director_portal/domain/entities/director_dashboard_summary.dart';
import '../features/director_portal/domain/entities/expense.dart';
import '../features/director_portal/domain/entities/meeting.dart';
import '../features/director_portal/domain/repositories/director_repository.dart';
import '../features/faculty_portal/domain/entities/coursework_item.dart';
import '../features/faculty_portal/domain/entities/grade.dart';
import '../features/faculty_portal/domain/repositories/faculty_repository.dart';
import '../features/guidance_portal/domain/entities/guidance_record.dart';
import '../features/guidance_portal/domain/entities/summons.dart';
import '../features/guidance_portal/domain/repositories/guidance_repository.dart';
// See the note in demo_store.dart: unqualified PaymentMethod is the
// student-payments enum; the platform-billing one is `billing.PaymentMethod`.
import '../features/owner_portal/domain/entities/invoice.dart' hide PaymentMethod;
import '../features/owner_portal/domain/entities/invoice.dart' as billing;
import '../features/owner_portal/domain/entities/revenue_summary.dart';
import '../features/owner_portal/domain/entities/school_summary.dart';
import '../features/owner_portal/domain/repositories/owner_repository.dart';
import '../features/parent_portal/domain/repositories/parent_repository.dart';
import '../features/payments/domain/entities/payment.dart';
import '../features/payments/domain/repositories/payment_repository.dart';
import '../features/profile/domain/repositories/profile_repository.dart';
import '../features/qr_attendance/domain/entities/attendance_record.dart';
import '../features/qr_attendance/domain/entities/qr_scan_result.dart';
import '../features/qr_attendance/domain/repositories/qr_attendance_repository.dart';
import '../features/registrar_portal/domain/entities/student_summary.dart';
import '../features/registrar_portal/domain/repositories/registrar_repository.dart';
import '../features/staff_portal/domain/entities/checklist_item.dart';
import '../features/staff_portal/domain/entities/daily_report.dart';
import '../features/staff_portal/domain/repositories/staff_repository.dart';
import '../features/student_portal/domain/repositories/student_repository.dart';
import 'demo_store.dart';

/// Fake, in-memory implementations of every domain repository, backed by
/// [DemoStore]. Injected in place of the real `*RepositoryImpl`s by
/// demo_overrides.dart so the app runs with no Firebase project attached.
///
/// Each fake honours the same contract the Firestore-backed one does --
/// streams stay live, writes are visible immediately on every screen
/// watching them, and failures come back as typed [Failure]s rather than
/// thrown exceptions -- but there is no access control here whatsoever.
/// Anything the UI lets you tap, these will happily do. Role enforcement
/// lives in firestore.rules, which a demo run does not exercise.

/// Small artificial delay on writes so loading spinners and disabled
/// buttons actually get a chance to render -- with a synchronous fake,
/// every async state transition would be invisible.
Future<void> _latency([int ms = 350]) => Future<void>.delayed(Duration(milliseconds: ms));

// ---------------------------------------------------------------------------
// Auth
// ---------------------------------------------------------------------------

class DemoAuthRepository implements AuthRepository {
  final DemoStore _store;
  DemoAuthRepository(this._store);

  @override
  Stream<AppUser?> watchAuthState() => _store.currentUser.stream;

  @override
  Future<Result<AppUser>> login({required String email, required String password}) async {
    await _latency(500);
    final normalized = email.trim().toLowerCase();
    final match = DemoStore.demoAccounts
        .where((a) => a.email.toLowerCase() == normalized)
        .firstOrNull;

    if (match == null) {
      return const Error(AuthFailure(
        'user-not-found',
        'No demo account with that email. Use the "Demo accounts" button to pick one.',
      ));
    }
    if (password != DemoStore.password) {
      return const Error(AuthFailure(
        'wrong-password',
        'Incorrect password. Every demo account uses: ${DemoStore.password}',
      ));
    }

    _store.currentUser.add(match);
    _store.audit(
      module: 'auth',
      action: 'login',
      targetCollection: 'users',
      targetId: match.uid,
    );
    return Success(match);
  }

  @override
  Future<Result<void>> logout() async {
    await _latency(200);
    _store.currentUser.add(null);
    return const Success(null);
  }

  @override
  Future<Result<void>> sendPasswordResetEmail(String email) async {
    await _latency();
    return const Success(null);
  }

  @override
  Future<Result<void>> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    await _latency();
    if (currentPassword != DemoStore.password) {
      return const Error(AuthFailure('wrong-password', 'Current password is incorrect.'));
    }
    _store.audit(
      module: 'auth',
      action: 'update',
      targetCollection: 'users',
      targetId: _store.requireUser.uid,
      remarks: 'Password changed',
    );
    return const Success(null);
  }

  @override
  Future<Result<void>> clearForcePasswordChangeFlag() async {
    await _latency(150);
    final user = _store.currentUser.valueOrNull;
    if (user != null) {
      _store.currentUser.add(user.copyWith(mustChangePassword: false));
    }
    return const Success(null);
  }

  @override
  Future<Result<AppUser>> getCurrentUserProfile() async {
    final user = _store.currentUser.valueOrNull;
    return user == null
        ? const Error(AuthFailure('no-current-user', 'Not signed in.'))
        : Success(user);
  }

  /// Demo-only: jump straight into a role without going through the login
  /// form. Backs the floating role switcher.
  void signInAs(AppUser user) => _store.currentUser.add(user);
}

// ---------------------------------------------------------------------------
// Owner
// ---------------------------------------------------------------------------

class DemoOwnerRepository implements OwnerRepository {
  final DemoStore _store;
  DemoOwnerRepository(this._store);

  @override
  Stream<List<SchoolSummary>> watchSchools() => _store.schools.stream;

  @override
  Stream<RevenueSummary> watchRevenueSummary() => _store.revenue.stream;

  @override
  Stream<List<Invoice>> watchInvoices(String schoolId) => _store.invoices.stream.map(
        (all) => all.where((i) => i.schoolId == schoolId).toList()
          ..sort((a, b) => b.billingPeriodStart.compareTo(a.billingPeriodStart)),
      );

  @override
  Future<Result<void>> pauseSchool({required String schoolId, required String reason}) async {
    await _latency();
    _store.update<SchoolSummary>(
      _store.schools,
      (s) => s.id == schoolId,
      (s) => SchoolSummary(
        id: s.id,
        name: s.name,
        logoUrl: s.logoUrl,
        status: SchoolSubscriptionStatus.suspended,
        activeStudentCount: s.activeStudentCount,
        currentCycleAccrued: s.currentCycleAccrued,
        suspendedAt: DateTime.now(),
      ),
    );
    _store.audit(
      module: 'platform',
      action: 'suspend',
      targetCollection: 'schools',
      targetId: schoolId,
      remarks: reason,
    );
    return const Success(null);
  }

  @override
  Future<Result<void>> resumeSchool({required String schoolId}) async {
    await _latency();
    _store.update<SchoolSummary>(
      _store.schools,
      (s) => s.id == schoolId,
      (s) => SchoolSummary(
        id: s.id,
        name: s.name,
        logoUrl: s.logoUrl,
        status: SchoolSubscriptionStatus.active,
        activeStudentCount: s.activeStudentCount,
        currentCycleAccrued: s.currentCycleAccrued,
      ),
    );
    _store.audit(
      module: 'platform',
      action: 'resume',
      targetCollection: 'schools',
      targetId: schoolId,
    );
    return const Success(null);
  }

  @override
  Future<Result<void>> recordManualPayment({
    required String schoolId,
    required String invoiceId,
    required double amount,
    required billing.PaymentMethod method,
    String? referenceNumber,
  }) async {
    await _latency();
    _store.update<Invoice>(
      _store.invoices,
      (i) => i.id == invoiceId,
      (i) => Invoice(
        id: i.id,
        schoolId: i.schoolId,
        billingPeriodStart: i.billingPeriodStart,
        billingPeriodEnd: i.billingPeriodEnd,
        dailyBreakdown: i.dailyBreakdown,
        totalAmount: i.totalAmount,
        status: InvoiceStatus.paid,
        dueDate: i.dueDate,
        paidAt: DateTime.now(),
        paidAmount: amount,
        paymentMethod: method,
        paymentReference: referenceNumber,
      ),
    );
    // Mirrors the real callable: settling an invoice reactivates a school
    // that was suspended or in grace period for non-payment.
    await resumeSchool(schoolId: schoolId);
    _store.audit(
      module: 'billing',
      action: 'payment',
      targetCollection: 'platform_invoices',
      targetId: invoiceId,
      newValue: {'amount': amount, 'method': method.value},
    );
    return const Success(null);
  }
}

// ---------------------------------------------------------------------------
// Director
// ---------------------------------------------------------------------------

class DemoDirectorRepository implements DirectorRepository {
  final DemoStore _store;
  DemoDirectorRepository(this._store);

  /// The uid behind each approval request. [ApprovalRequest] only carries
  /// the requester's display name and role, but watchApprovals filters by
  /// uid (Firestore stores both), so the fake tracks it alongside.
  final Map<String, String> _approvalOwners = {
    'apr_001': 'u_faculty',
    'apr_002': 'u_admin',
    'apr_003': 'u_student',
    'apr_004': 'u_staff',
  };

  @override
  Future<Result<DirectorDashboardSummary>> getDashboardSummary() async {
    await _latency(250);
    final today = _store.todayKey;
    final todays = _store.attendance.value.where((a) => a.date == today).toList();
    final todaysPayments = _store.payments.value.where((p) {
      final c = p.createdAt;
      return _sameDay(c, DateTime.now()) && !p.isRefund;
    });
    return Success(DirectorDashboardSummary(
      todayAttendancePresentCount:
          todays.where((a) => a.status != AttendanceStatus.absent).length,
      todayAttendanceTotalCount: _store.students.value
          .where((s) => s.status == StudentStatus.enrolled)
          .length,
      todayPaymentsTotal: todaysPayments.fold<double>(0, (sum, p) => sum + p.amount),
      pendingApprovalsCount:
          _store.approvals.value.where((a) => a.status == ApprovalStatus.pending).length,
      upcomingMeetingsCount: _store.meetings.value.where((m) => m.isUpcoming).length,
    ));
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  @override
  Stream<List<Announcement>> watchAnnouncements() => _store.announcements.stream.map(
        (all) => [...all]..sort((a, b) {
            if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
            return b.createdAt.compareTo(a.createdAt);
          }),
      );

  @override
  Future<Result<void>> createAnnouncement({
    required String title,
    required String body,
    required AnnouncementAudience audience,
    required bool pinned,
  }) async {
    await _latency();
    final id = _store.nextId('ann');
    _store.prepend(
      _store.announcements,
      Announcement(
        id: id,
        title: title,
        body: body,
        audience: audience,
        pinned: pinned,
        createdByName: _store.requireUser.fullName,
        createdAt: DateTime.now(),
      ),
    );
    _store.audit(
      module: 'announcements',
      action: 'create',
      targetCollection: 'announcements',
      targetId: id,
      newValue: {'title': title, 'pinned': pinned},
    );
    return const Success(null);
  }

  @override
  Future<Result<void>> updateAnnouncement({
    required String announcementId,
    required String title,
    required String body,
    required AnnouncementAudience audience,
    required bool pinned,
  }) async {
    await _latency();
    _store.update<Announcement>(
      _store.announcements,
      (a) => a.id == announcementId,
      (a) => Announcement(
        id: a.id,
        title: title,
        body: body,
        audience: audience,
        pinned: pinned,
        // Authorship is never re-attributed by an edit -- firestore.rules
        // rejects any update that changes createdBy.
        createdByName: a.createdByName,
        createdAt: a.createdAt,
      ),
    );
    _store.audit(
      module: 'announcements',
      action: 'update',
      targetCollection: 'announcements',
      targetId: announcementId,
      newValue: {'title': title, 'pinned': pinned},
    );
    return const Success(null);
  }

  @override
  Future<Result<void>> deleteAnnouncement(String announcementId) async {
    await _latency();
    _store.softDelete(_store.announcements, (a) => a.id == announcementId);
    _store.audit(
      module: 'announcements',
      action: 'delete',
      targetCollection: 'announcements',
      targetId: announcementId,
      remarks: 'Soft deleted',
    );
    return const Success(null);
  }

  @override
  Stream<List<Meeting>> watchMeetings() => _store.meetings.stream
      .map((all) => [...all]..sort((a, b) => b.startTime.compareTo(a.startTime)));

  @override
  Future<Result<void>> createMeeting({
    required String title,
    String? description,
    required DateTime startTime,
    required DateTime endTime,
    String? location,
    required List<String> attendeeRoles,
  }) async {
    await _latency();
    final id = _store.nextId('mtg');
    _store.prepend(
      _store.meetings,
      Meeting(
        id: id,
        title: title,
        description: description,
        startTime: startTime,
        endTime: endTime,
        location: location,
        attendeeRoles: attendeeRoles,
        status: MeetingStatus.scheduled,
        createdByName: _store.requireUser.fullName,
      ),
    );
    _store.audit(
      module: 'meetings',
      action: 'create',
      targetCollection: 'meetings',
      targetId: id,
      newValue: {'title': title},
    );
    return const Success(null);
  }

  @override
  Future<Result<void>> updateMeeting({
    required String meetingId,
    required String title,
    String? description,
    required DateTime startTime,
    required DateTime endTime,
    String? location,
    required List<String> attendeeRoles,
  }) async {
    await _latency();
    _store.update<Meeting>(
      _store.meetings,
      (m) => m.id == meetingId,
      (m) => Meeting(
        id: m.id,
        title: title,
        description: description,
        startTime: startTime,
        endTime: endTime,
        location: location,
        attendeeRoles: attendeeRoles,
        status: m.status,
        createdByName: m.createdByName,
      ),
    );
    _store.audit(
      module: 'meetings',
      action: 'update',
      targetCollection: 'meetings',
      targetId: meetingId,
      newValue: {'title': title},
    );
    return const Success(null);
  }

  @override
  Future<Result<void>> deleteMeeting(String meetingId) async {
    await _latency();
    _store.softDelete(_store.meetings, (m) => m.id == meetingId);
    _store.audit(
      module: 'meetings',
      action: 'delete',
      targetCollection: 'meetings',
      targetId: meetingId,
      remarks: 'Soft deleted',
    );
    return const Success(null);
  }

  @override
  Future<Result<void>> cancelMeeting(String meetingId) async {
    await _latency();
    _store.update<Meeting>(
      _store.meetings,
      (m) => m.id == meetingId,
      (m) => Meeting(
        id: m.id,
        title: m.title,
        description: m.description,
        startTime: m.startTime,
        endTime: m.endTime,
        location: m.location,
        attendeeRoles: m.attendeeRoles,
        status: MeetingStatus.cancelled,
        createdByName: m.createdByName,
      ),
    );
    _store.audit(
      module: 'meetings',
      action: 'cancel',
      targetCollection: 'meetings',
      targetId: meetingId,
    );
    return const Success(null);
  }

  @override
  Stream<List<ApprovalRequest>> watchApprovals({
    ApprovalStatus? statusFilter,
    String? requestedByUid,
  }) {
    return _store.approvals.stream.map((all) {
      var list = all;
      if (statusFilter != null) {
        list = list.where((a) => a.status == statusFilter).toList();
      }
      if (requestedByUid != null) {
        list = list.where((a) => _approvalOwners[a.id] == requestedByUid).toList();
      }
      return [...list]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    });
  }

  @override
  Future<Result<void>> createApprovalRequest({
    required String type,
    required String title,
    String? description,
    Map<String, dynamic> details = const {},
  }) async {
    await _latency();
    final user = _store.requireUser;
    final id = _store.nextId('apr');
    _approvalOwners[id] = user.uid;
    _store.prepend(
      _store.approvals,
      ApprovalRequest(
        id: id,
        type: type,
        title: title,
        description: description,
        details: details,
        requestedByName: user.fullName,
        requestedByRole: user.role.value,
        status: ApprovalStatus.pending,
        createdAt: DateTime.now(),
      ),
    );
    _store.audit(
      module: 'approvals',
      action: 'create',
      targetCollection: 'approvals',
      targetId: id,
      newValue: {'type': type, 'title': title},
    );
    return const Success(null);
  }

  @override
  Future<Result<void>> decideApproval({
    required String approvalId,
    required bool approve,
    String? remarks,
  }) async {
    await _latency();
    _store.update<ApprovalRequest>(
      _store.approvals,
      (a) => a.id == approvalId,
      (a) => ApprovalRequest(
        id: a.id,
        type: a.type,
        title: a.title,
        description: a.description,
        details: a.details,
        requestedByName: a.requestedByName,
        requestedByRole: a.requestedByRole,
        status: approve ? ApprovalStatus.approved : ApprovalStatus.rejected,
        decidedByName: _store.requireUser.fullName,
        decidedAt: DateTime.now(),
        decisionRemarks: remarks,
        createdAt: a.createdAt,
      ),
    );
    _store.audit(
      module: 'approvals',
      action: approve ? 'approve' : 'reject',
      targetCollection: 'approvals',
      targetId: approvalId,
      remarks: remarks,
    );
    return const Success(null);
  }

  @override
  Stream<List<Expense>> watchExpenses() =>
      _store.expenses.stream.map((all) => [...all]..sort((a, b) => b.date.compareTo(a.date)));

  @override
  Future<Result<void>> createExpense({
    required String category,
    required String description,
    required double amount,
    required DateTime date,
    String? receiptUrl,
  }) async {
    await _latency();
    final id = _store.nextId('exp');
    _store.prepend(
      _store.expenses,
      Expense(
        id: id,
        category: category,
        description: description,
        amount: amount,
        date: date,
        recordedByName: _store.requireUser.fullName,
        receiptUrl: receiptUrl,
      ),
    );
    _store.audit(
      module: 'expenses',
      action: 'create',
      targetCollection: 'expenses',
      targetId: id,
      newValue: {'category': category, 'amount': amount},
    );
    return const Success(null);
  }

  @override
  Future<Result<void>> updateExpense({
    required String expenseId,
    required String category,
    required String description,
    required double amount,
    required DateTime date,
    String? receiptUrl,
  }) async {
    await _latency();
    _store.update<Expense>(
      _store.expenses,
      (e) => e.id == expenseId,
      (e) => Expense(
        id: e.id,
        category: category,
        description: description,
        amount: amount,
        date: date,
        recordedByName: e.recordedByName,
        receiptUrl: receiptUrl ?? e.receiptUrl,
      ),
    );
    _store.audit(
      module: 'expenses',
      action: 'update',
      targetCollection: 'expenses',
      targetId: expenseId,
      newValue: {'category': category, 'amount': amount},
    );
    return const Success(null);
  }

  @override
  Future<Result<void>> deleteExpense(String expenseId) async {
    await _latency();
    _store.softDelete(_store.expenses, (e) => e.id == expenseId);
    _store.audit(
      module: 'expenses',
      action: 'delete',
      targetCollection: 'expenses',
      targetId: expenseId,
      remarks: 'Soft deleted',
    );
    return const Success(null);
  }
}

// ---------------------------------------------------------------------------
// Admin
// ---------------------------------------------------------------------------

class DemoAdminRepository implements AdminRepository {
  final DemoStore _store;
  DemoAdminRepository(this._store);

  @override
  Stream<List<EmployeeSummary>> watchEmployees() =>
      _store.employees.stream.map((all) => [...all]..sort((a, b) => a.lastName.compareTo(b.lastName)));

  @override
  Future<Result<CreateEmployeeOutcome>> createEmployee({
    required UserRole role,
    required String firstName,
    required String lastName,
    required String email,
    EmployeeInfo? employeeInfo,
  }) async {
    await _latency(600);
    if (_store.employees.value.any((e) => e.email.toLowerCase() == email.toLowerCase())) {
      return const Error(ValidationFailure('An account with that email already exists.'));
    }
    final uid = _store.nextId('u');
    _store.prepend(
      _store.employees,
      EmployeeSummary(
        uid: uid,
        firstName: firstName,
        lastName: lastName,
        email: email,
        role: role,
        status: UserAccountStatus.active,
        employeeInfo: employeeInfo,
      ),
    );
    _store.audit(
      module: 'users',
      action: 'create',
      targetCollection: 'users',
      targetId: uid,
      newValue: {'role': role.value, 'email': email},
    );
    return Success(CreateEmployeeOutcome(uid: uid, tempPassword: _tempPassword()));
  }

  @override
  Future<Result<void>> updateEmployeeInfo({
    required String uid,
    required EmployeeInfo employeeInfo,
  }) async {
    await _latency();
    _store.update<EmployeeSummary>(
      _store.employees,
      (e) => e.uid == uid,
      (e) => EmployeeSummary(
        uid: e.uid,
        firstName: e.firstName,
        lastName: e.lastName,
        email: e.email,
        role: e.role,
        status: e.status,
        photoUrl: e.photoUrl,
        employeeInfo: employeeInfo,
      ),
    );
    _store.audit(
      module: 'users',
      action: 'update',
      targetCollection: 'users',
      targetId: uid,
      newValue: {'position': employeeInfo.position, 'department': employeeInfo.department},
    );
    return const Success(null);
  }

  @override
  Future<Result<void>> setUserStatus({required String uid, required bool active}) async {
    await _latency();
    _store.update<EmployeeSummary>(
      _store.employees,
      (e) => e.uid == uid,
      (e) => EmployeeSummary(
        uid: e.uid,
        firstName: e.firstName,
        lastName: e.lastName,
        email: e.email,
        role: e.role,
        status: active ? UserAccountStatus.active : UserAccountStatus.suspended,
        photoUrl: e.photoUrl,
        employeeInfo: e.employeeInfo,
      ),
    );
    _store.audit(
      module: 'users',
      action: active ? 'activate' : 'suspend',
      targetCollection: 'users',
      targetId: uid,
    );
    return const Success(null);
  }

  @override
  Future<Result<String>> resetUserPassword(String uid) async {
    await _latency(600);
    _store.audit(
      module: 'users',
      action: 'reset_password',
      targetCollection: 'users',
      targetId: uid,
    );
    return Success(_tempPassword());
  }

  @override
  Stream<List<TeacherAssignment>> watchTeacherAssignments() => _store.assignments.stream;

  @override
  Future<Result<void>> createTeacherAssignment({
    required String teacherId,
    required String teacherName,
    required String subject,
    required String section,
    required String schoolYear,
  }) async {
    await _latency();
    final id = _store.nextId('ta');
    _store.prepend(
      _store.assignments,
      TeacherAssignment(
        id: id,
        teacherId: teacherId,
        teacherName: teacherName,
        subject: subject,
        section: section,
        schoolYear: schoolYear,
      ),
    );
    _store.audit(
      module: 'assignments',
      action: 'create',
      targetCollection: 'teacher_assignments',
      targetId: id,
      newValue: {'subject': subject, 'section': section},
    );
    return const Success(null);
  }

  @override
  Stream<List<Program>> watchPrograms() => _store.programs.stream;

  @override
  Future<Result<void>> createProgram({
    required String name,
    required String code,
    required String department,
  }) async {
    await _latency();
    final id = _store.nextId('prog');
    _store.prepend(_store.programs, Program(id: id, name: name, code: code, department: department));
    _store.audit(
      module: 'programs',
      action: 'create',
      targetCollection: 'programs',
      targetId: id,
      newValue: {'name': name, 'code': code},
    );
    return const Success(null);
  }

  /// Same shape the real provisionUser callable returns: a readable
  /// one-time password the admin reads out to the new employee.
  String _tempPassword() {
    final n = DateTime.now().millisecondsSinceEpoch % 10000;
    return 'Temp${n.toString().padLeft(4, '0')}';
  }
}

// ---------------------------------------------------------------------------
// Registrar
// ---------------------------------------------------------------------------

class DemoRegistrarRepository implements RegistrarRepository {
  final DemoStore _store;
  DemoRegistrarRepository(this._store);

  @override
  Stream<List<StudentSummary>> watchStudents() => _store.students.stream
      .map((all) => [...all]..sort((a, b) => a.lastName.compareTo(b.lastName)));

  @override
  Future<Result<RegisterStudentOutcome>> registerStudent({
    required String firstName,
    required String lastName,
    String? middleName,
    required EducationLevel educationLevel,
    required String gradeLevel,
    required String section,
    String? programId,
    required List<GuardianContact> guardianContacts,
  }) async {
    await _latency(600);
    final id = _store.nextId('stu');
    // Mirrors studentNumber.ts: <enrollment year>-<zero-padded sequence>.
    final year = DateTime.now().year;
    final sequence = _store.students.value.length + 1;
    final studentNumber = '$year-${sequence.toString().padLeft(5, '0')}';
    final program = programId == null
        ? null
        : _store.programs.value.where((p) => p.id == programId).firstOrNull;

    _store.prepend(
      _store.students,
      StudentSummary(
        id: id,
        studentNumber: studentNumber,
        firstName: firstName,
        lastName: lastName,
        middleName: middleName,
        educationLevel: educationLevel,
        gradeLevel: gradeLevel,
        section: section,
        programId: program?.id,
        programName: program?.name,
        department: program?.department,
        status: StudentStatus.enrolled,
        balance: 0,
        enrollmentDate: DateTime.now(),
        guardianContacts: guardianContacts,
      ),
    );
    _store.audit(
      module: 'students',
      action: 'create',
      targetCollection: 'students',
      targetId: id,
      newValue: {'studentNumber': studentNumber, 'educationLevel': educationLevel.value},
    );
    return Success(RegisterStudentOutcome(studentId: id, studentNumber: studentNumber));
  }

  @override
  Future<Result<void>> updateStudent({
    required String studentId,
    required String firstName,
    required String lastName,
    required String gradeLevel,
    required String section,
    required StudentStatus status,
  }) async {
    await _latency();
    _store.update<StudentSummary>(
      _store.students,
      (s) => s.id == studentId,
      (s) => _copyStudent(
        s,
        firstName: firstName,
        lastName: lastName,
        gradeLevel: gradeLevel,
        section: section,
        status: status,
      ),
    );
    _store.audit(
      module: 'students',
      action: 'update',
      targetCollection: 'students',
      targetId: studentId,
      newValue: {'gradeLevel': gradeLevel, 'section': section, 'status': status.value},
    );
    return const Success(null);
  }

  @override
  Future<Result<ProvisionStudentAccountOutcome>> provisionStudentAccount({
    required String studentId,
    required String firstName,
    required String lastName,
    required String email,
  }) async {
    await _latency(600);
    final uid = _store.nextId('u');
    _store.update<StudentSummary>(
      _store.students,
      (s) => s.id == studentId,
      (s) => _copyStudent(s, userId: uid),
    );
    _store.audit(
      module: 'students',
      action: 'provision_account',
      targetCollection: 'users',
      targetId: uid,
      newValue: {'email': email, 'linkedStudentId': studentId},
    );
    final n = DateTime.now().millisecondsSinceEpoch % 10000;
    return Success(ProvisionStudentAccountOutcome(
      uid: uid,
      tempPassword: 'Temp${n.toString().padLeft(4, '0')}',
    ));
  }
}

/// [StudentSummary] has no copyWith; every fake that edits a student goes
/// through this so a new field on the entity only has to be added once.
StudentSummary _copyStudent(
  StudentSummary s, {
  String? firstName,
  String? lastName,
  String? gradeLevel,
  String? section,
  StudentStatus? status,
  double? balance,
  String? userId,
}) {
  return StudentSummary(
    id: s.id,
    studentNumber: s.studentNumber,
    firstName: firstName ?? s.firstName,
    lastName: lastName ?? s.lastName,
    middleName: s.middleName,
    educationLevel: s.educationLevel,
    gradeLevel: gradeLevel ?? s.gradeLevel,
    section: section ?? s.section,
    programId: s.programId,
    programName: s.programName,
    department: s.department,
    status: status ?? s.status,
    balance: balance ?? s.balance,
    userId: userId ?? s.userId,
    photoUrl: s.photoUrl,
    enrollmentDate: s.enrollmentDate,
    guardianContacts: s.guardianContacts,
  );
}

// ---------------------------------------------------------------------------
// Faculty
// ---------------------------------------------------------------------------

class DemoFacultyRepository implements FacultyRepository {
  final DemoStore _store;
  DemoFacultyRepository(this._store);

  @override
  Stream<List<CourseworkItem>> watchMyCourseworkItems() {
    final uid = _store.requireUser.uid;
    return _store.coursework.stream.map(
      (all) => all.where((c) => c.teacherId == uid).toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt)),
    );
  }

  @override
  Future<Result<void>> createCourseworkItem({
    required CourseworkType type,
    required String title,
    required String description,
    required String subject,
    required String section,
    DateTime? dueDate,
    double? totalPoints,
    required bool published,
  }) async {
    await _latency();
    final user = _store.requireUser;
    final id = _store.nextId('cw');
    _store.prepend(
      _store.coursework,
      CourseworkItem(
        id: id,
        type: type,
        title: title,
        description: description,
        subject: subject,
        section: section,
        teacherId: user.uid,
        teacherName: user.fullName,
        dueDate: dueDate,
        totalPoints: totalPoints,
        published: published,
        createdAt: DateTime.now(),
      ),
    );
    _store.audit(
      module: 'coursework',
      action: 'create',
      targetCollection: 'coursework',
      targetId: id,
      newValue: {'type': type.value, 'title': title, 'published': published},
    );
    return const Success(null);
  }

  @override
  Stream<List<Grade>> watchGradesFor({required String subject, required String section}) {
    return _store.grades.stream.map(
      (all) => all.where((g) => g.subject == subject && g.section == section).toList()
        ..sort((a, b) => a.studentName.compareTo(b.studentName)),
    );
  }

  @override
  Future<Result<void>> submitGrade({
    required String studentId,
    required String studentName,
    required String subject,
    required String section,
    required String term,
    required double score,
    required double maxScore,
    String? courseworkItemId,
    String? remarks,
  }) async {
    await _latency();
    final id = _store.nextId('gr');
    _store.prepend(
      _store.grades,
      Grade(
        id: id,
        studentId: studentId,
        studentName: studentName,
        subject: subject,
        section: section,
        term: term,
        courseworkItemId: courseworkItemId,
        score: score,
        maxScore: maxScore,
        remarks: remarks,
        submittedByName: _store.requireUser.fullName,
        submittedAt: DateTime.now(),
      ),
    );
    _store.audit(
      module: 'grades',
      action: 'create',
      targetCollection: 'grades',
      targetId: id,
      newValue: {'studentId': studentId, 'score': score, 'maxScore': maxScore},
    );
    return const Success(null);
  }
}

// ---------------------------------------------------------------------------
// Student
// ---------------------------------------------------------------------------

class DemoStudentRepository implements StudentRepository {
  final DemoStore _store;
  DemoStudentRepository(this._store);

  @override
  Stream<StudentSummary?> watchMyStudentRecord() {
    final uid = _store.requireUser.uid;
    return _store.students.stream.map((all) => all.where((s) => s.userId == uid).firstOrNull);
  }

  @override
  Stream<List<TeacherAssignment>> watchMySubjects(String section) =>
      _store.assignments.stream.map((all) => all.where((a) => a.section == section).toList());

  @override
  Stream<List<CourseworkItem>> watchMyCoursework(String section, {CourseworkType? typeFilter}) {
    return _store.coursework.stream.map((all) {
      // Students only ever see published items -- an unpublished lesson
      // plan is the teacher's working draft.
      var list = all.where((c) => c.section == section && c.published);
      if (typeFilter != null) list = list.where((c) => c.type == typeFilter);
      return list.toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    });
  }

  @override
  Stream<List<Grade>> watchMyGrades(String studentId) => _store.grades.stream.map(
        (all) => all.where((g) => g.studentId == studentId).toList()
          ..sort((a, b) => b.submittedAt.compareTo(a.submittedAt)),
      );
}

// ---------------------------------------------------------------------------
// Parent
// ---------------------------------------------------------------------------

class DemoParentRepository implements ParentRepository {
  final DemoStore _store;
  DemoParentRepository(this._store);

  @override
  Stream<List<StudentSummary>> watchChildren(List<String> linkedStudentIds) =>
      _store.students.stream.map((all) => all.where((s) => linkedStudentIds.contains(s.id)).toList());
}

// ---------------------------------------------------------------------------
// Payments
// ---------------------------------------------------------------------------

class DemoPaymentRepository implements PaymentRepository {
  final DemoStore _store;
  DemoPaymentRepository(this._store);

  @override
  Stream<List<Payment>> watchPaymentsForStudent(String studentId) => _store.payments.stream.map(
        (all) => all.where((p) => p.studentId == studentId).toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt)),
      );

  @override
  Stream<double> watchStudentBalance(String studentId) => _store.students.stream
      .map((all) => all.where((s) => s.id == studentId).firstOrNull?.balance ?? 0);

  @override
  Future<Result<RecordPaymentOutcome>> recordPayment({
    required String studentId,
    required double amount,
    required PaymentMethod method,
    required PaymentPurpose purpose,
    String? referenceNumber,
  }) async {
    await _latency(600);
    if (amount <= 0) {
      return const Error(ValidationFailure('Amount must be greater than zero.'));
    }
    final id = _store.nextId('pay');
    final receiptNumber =
        'OR-${DateTime.now().year}-${(_store.payments.value.length + 1).toString().padLeft(6, '0')}';

    _store.prepend(
      _store.payments,
      Payment(
        id: id,
        studentId: studentId,
        amount: amount,
        method: method,
        referenceNumber: referenceNumber,
        receiptNumber: receiptNumber,
        collectedByName: _store.requireUser.fullName,
        purpose: purpose,
        status: PaymentStatus.completed,
        createdAt: DateTime.now(),
      ),
    );

    // The real recordPayment callable recomputes and writes the student's
    // denormalized balance in the same transaction; the client never does
    // this arithmetic itself (docs/08-payments.md).
    double newBalance = 0;
    _store.update<StudentSummary>(
      _store.students,
      (s) => s.id == studentId,
      (s) {
        newBalance = s.balance - amount;
        return _copyStudent(s, balance: newBalance);
      },
    );

    _store.audit(
      module: 'payments',
      action: 'create',
      targetCollection: 'payments',
      targetId: id,
      newValue: {'amount': amount, 'method': method.value, 'purpose': purpose.value},
    );
    return Success(RecordPaymentOutcome(
      paymentId: id,
      receiptNumber: receiptNumber,
      newBalance: newBalance,
    ));
  }

  @override
  Future<Result<void>> recordRefund({required String paymentId, required String reason}) async {
    await _latency(600);
    final original = _store.payments.value.where((p) => p.id == paymentId).firstOrNull;
    if (original == null) {
      return const Error(ValidationFailure('Original payment not found.'));
    }
    if (original.status == PaymentStatus.refunded) {
      return const Error(ValidationFailure('That payment has already been refunded.'));
    }

    // A refund is its own row with a negative amount pointing back at the
    // original, rather than an edit to payment history.
    final id = _store.nextId('pay');
    _store.prepend(
      _store.payments,
      Payment(
        id: id,
        studentId: original.studentId,
        amount: -original.amount,
        method: original.method,
        receiptNumber:
            'RF-${DateTime.now().year}-${(_store.payments.value.length + 1).toString().padLeft(6, '0')}',
        collectedByName: _store.requireUser.fullName,
        purpose: original.purpose,
        status: PaymentStatus.refunded,
        refundOf: paymentId,
        createdAt: DateTime.now(),
      ),
    );
    _store.update<Payment>(
      _store.payments,
      (p) => p.id == paymentId,
      (p) => Payment(
        id: p.id,
        studentId: p.studentId,
        amount: p.amount,
        method: p.method,
        referenceNumber: p.referenceNumber,
        receiptNumber: p.receiptNumber,
        collectedByName: p.collectedByName,
        purpose: p.purpose,
        status: PaymentStatus.refunded,
        refundOf: p.refundOf,
        createdAt: p.createdAt,
      ),
    );
    _store.update<StudentSummary>(
      _store.students,
      (s) => s.id == original.studentId,
      (s) => _copyStudent(s, balance: s.balance + original.amount),
    );
    _store.audit(
      module: 'payments',
      action: 'refund',
      targetCollection: 'payments',
      targetId: paymentId,
      remarks: reason,
    );
    return const Success(null);
  }
}

// ---------------------------------------------------------------------------
// QR Attendance
// ---------------------------------------------------------------------------

class DemoQrAttendanceRepository implements QrAttendanceRepository {
  final DemoStore _store;
  DemoQrAttendanceRepository(this._store);

  /// Cut-off after which a time-in is recorded as Late, matching
  /// attendanceStatus.ts's default school-hours configuration.
  static const _lateAfterHour = 8;

  @override
  Future<Result<QrScanResult>> scanQrCode({required String qrToken, String? location}) async {
    await _latency(500);

    final account = DemoStore.demoAccounts.where((a) => a.qrCode == qrToken).firstOrNull;
    final student = _store.students.value
        .where((s) => 'QR-STU-${s.studentNumber}' == qrToken || s.id == qrToken)
        .firstOrNull;

    final String personId;
    final String personName;
    final String personRole;
    final AttendanceSubjectType subjectType;

    if (account != null) {
      personId = account.uid;
      personName = account.fullName;
      personRole = account.role.value;
      subjectType = account.role == UserRole.student
          ? AttendanceSubjectType.student
          : AttendanceSubjectType.employee;
    } else if (student != null) {
      personId = student.id;
      personName = student.fullName;
      personRole = 'student';
      subjectType = AttendanceSubjectType.student;
    } else {
      return const Error(ValidationFailure(
        'QR code not recognized. In demo mode, scan a code from the "My QR ID" screen.',
      ));
    }

    final now = DateTime.now();
    final today = _store.todayKey;
    final existing = _store.attendance.value
        .where((a) => a.personId == personId && a.date == today)
        .firstOrNull;

    // Time-in on first scan of the day, time-out on the second, no-op
    // after that -- the same three-way outcome markAttendance.ts returns.
    if (existing == null) {
      final status =
          now.hour >= _lateAfterHour ? AttendanceStatus.late : AttendanceStatus.present;
      final id = _store.nextId('att');
      _store.prepend(
        _store.attendance,
        AttendanceRecord(
          id: id,
          personId: personId,
          personRole: personRole,
          subjectType: subjectType,
          date: today,
          timestampIn: now,
          status: status,
          location: location,
        ),
      );
      _store.audit(
        module: 'attendance',
        action: 'time_in',
        targetCollection: 'attendance',
        targetId: id,
        newValue: {'personId': personId, 'status': status.value},
      );
      return Success(QrScanResult(
        personId: personId,
        personName: personName,
        personRole: personRole,
        action: ScanAction.timeIn,
        status: status,
        timestamp: now,
      ));
    }

    if (existing.timestampOut == null) {
      _store.update<AttendanceRecord>(
        _store.attendance,
        (a) => a.id == existing.id,
        (a) => AttendanceRecord(
          id: a.id,
          personId: a.personId,
          personRole: a.personRole,
          subjectType: a.subjectType,
          date: a.date,
          timestampIn: a.timestampIn,
          timestampOut: now,
          status: a.status,
          location: a.location,
        ),
      );
      _store.audit(
        module: 'attendance',
        action: 'time_out',
        targetCollection: 'attendance',
        targetId: existing.id,
        newValue: {'personId': personId},
      );
      return Success(QrScanResult(
        personId: personId,
        personName: personName,
        personRole: personRole,
        action: ScanAction.timeOut,
        status: existing.status,
        timestamp: now,
      ));
    }

    return Success(QrScanResult(
      personId: personId,
      personName: personName,
      personRole: personRole,
      action: ScanAction.alreadyCompleted,
      status: existing.status,
      timestamp: now,
    ));
  }

  @override
  Stream<List<AttendanceRecord>> watchAttendanceHistory(String personId, {int limit = 60}) {
    return _store.attendance.stream.map(
      (all) => (all.where((a) => a.personId == personId).toList()
            ..sort((a, b) => b.timestampIn.compareTo(a.timestampIn)))
          .take(limit)
          .toList(),
    );
  }
}

// ---------------------------------------------------------------------------
// Staff
// ---------------------------------------------------------------------------

class DemoStaffRepository implements StaffRepository {
  final DemoStore _store;
  DemoStaffRepository(this._store);

  @override
  Stream<List<ChecklistItem>> watchMyChecklist(String date) =>
      _store.checklist.stream.map((all) => all.where((c) => c.date == date).toList());

  @override
  Future<Result<void>> addChecklistItem({required String task, required String date}) async {
    await _latency(250);
    final id = _store.nextId('chk');
    _store.checklist.add([
      ..._store.checklist.value,
      ChecklistItem(id: id, task: task, date: date, completed: false),
    ]);
    _store.audit(
      module: 'checklist',
      action: 'create',
      targetCollection: 'checklists',
      targetId: id,
      newValue: {'task': task},
    );
    return const Success(null);
  }

  @override
  Future<Result<void>> toggleChecklistItem({required String itemId, required bool completed}) async {
    await _latency(150);
    _store.update<ChecklistItem>(
      _store.checklist,
      (c) => c.id == itemId,
      (c) => ChecklistItem(
        id: c.id,
        task: c.task,
        date: c.date,
        completed: completed,
        completedAt: completed ? DateTime.now() : null,
        notes: c.notes,
      ),
    );
    return const Success(null);
  }

  @override
  Stream<List<DailyReport>> watchMyDailyReports() =>
      _store.dailyReports.stream.map((all) => [...all]..sort((a, b) => b.date.compareTo(a.date)));

  @override
  Future<Result<void>> submitDailyReport({required String date, required String content}) async {
    await _latency();
    final id = _store.nextId('rep');
    _store.prepend(
      _store.dailyReports,
      DailyReport(
        id: id,
        date: date,
        content: content,
        staffName: _store.requireUser.fullName,
        submittedAt: DateTime.now(),
      ),
    );
    _store.audit(
      module: 'reports',
      action: 'create',
      targetCollection: 'daily_reports',
      targetId: id,
      newValue: {'date': date},
    );
    return const Success(null);
  }
}

// ---------------------------------------------------------------------------
// Guidance
// ---------------------------------------------------------------------------

class DemoGuidanceRepository implements GuidanceRepository {
  final DemoStore _store;
  DemoGuidanceRepository(this._store);

  @override
  Stream<List<GuidanceRecord>> watchGuidanceRecords(String studentId) =>
      _store.guidanceRecords.stream.map(
        (all) => all.where((g) => g.studentId == studentId).toList()
          ..sort((a, b) => b.recordedAt.compareTo(a.recordedAt)),
      );

  @override
  Future<Result<void>> createGuidanceRecord({
    required String studentId,
    required String studentName,
    required GuidanceCategory category,
    required String notes,
  }) async {
    await _latency();
    final id = _store.nextId('gui');
    _store.prepend(
      _store.guidanceRecords,
      GuidanceRecord(
        id: id,
        studentId: studentId,
        studentName: studentName,
        category: category,
        notes: notes,
        recordedByName: _store.requireUser.fullName,
        recordedAt: DateTime.now(),
      ),
    );
    _store.audit(
      module: 'guidance',
      action: 'create',
      targetCollection: 'guidance_records',
      targetId: id,
      // Deliberately no note text in the audit entry -- counseling notes
      // are confidential, and the audit log has a wider audience.
      newValue: {'studentId': studentId, 'category': category.value},
    );
    return const Success(null);
  }

  @override
  Stream<List<Summons>> watchSummons() =>
      _store.summonses.stream.map((all) => [...all]..sort((a, b) => b.createdAt.compareTo(a.createdAt)));

  @override
  Future<Result<void>> createSummons({
    required String studentId,
    required String studentName,
    required String reason,
    required DateTime scheduledDate,
  }) async {
    await _latency();
    final id = _store.nextId('sum');
    _store.prepend(
      _store.summonses,
      Summons(
        id: id,
        studentId: studentId,
        studentName: studentName,
        reason: reason,
        scheduledDate: scheduledDate,
        status: SummonsStatus.pending,
        issuedByName: _store.requireUser.fullName,
        createdAt: DateTime.now(),
      ),
    );
    _store.audit(
      module: 'guidance',
      action: 'create',
      targetCollection: 'summons',
      targetId: id,
      newValue: {'studentId': studentId, 'reason': reason},
    );
    return const Success(null);
  }

  @override
  Future<Result<void>> updateSummonsStatus({
    required String summonsId,
    required SummonsStatus status,
  }) async {
    await _latency(250);
    _store.update<Summons>(
      _store.summonses,
      (s) => s.id == summonsId,
      (s) => Summons(
        id: s.id,
        studentId: s.studentId,
        studentName: s.studentName,
        reason: s.reason,
        scheduledDate: s.scheduledDate,
        status: status,
        issuedByName: s.issuedByName,
        createdAt: s.createdAt,
      ),
    );
    _store.audit(
      module: 'guidance',
      action: 'update',
      targetCollection: 'summons',
      targetId: summonsId,
      newValue: {'status': status.value},
    );
    return const Success(null);
  }
}

// ---------------------------------------------------------------------------
// Profile
// ---------------------------------------------------------------------------

class DemoProfileRepository implements ProfileRepository {
  final DemoStore _store;
  DemoProfileRepository(this._store);

  @override
  Future<Result<void>> updateProfile({String? phone, String? photoUrl}) async {
    await _latency();
    final user = _store.currentUser.valueOrNull;
    if (user == null) return const Error(AuthFailure('no-current-user', 'Not signed in.'));
    if (photoUrl != null) _store.currentUser.add(user.copyWith(photoUrl: photoUrl));
    _store.audit(
      module: 'profile',
      action: 'update',
      targetCollection: 'users',
      targetId: user.uid,
      newValue: {if (phone != null) 'phone': phone, if (photoUrl != null) 'photoUrl': photoUrl},
    );
    return const Success(null);
  }
}

// ---------------------------------------------------------------------------
// Audit trail
// ---------------------------------------------------------------------------

class DemoAuditTrailRepository implements AuditTrailRepository {
  final DemoStore _store;
  DemoAuditTrailRepository(this._store);

  @override
  Stream<List<AuditLogEntry>> watchAuditLog({
    String? moduleFilter,
    DateTime? startDate,
    DateTime? endDate,
    String? userIdFilter,
    int limit = 100,
  }) {
    return _store.auditLog.stream.map((all) {
      var list = all.where((e) {
        if (moduleFilter != null && e.module != moduleFilter) return false;
        if (userIdFilter != null && e.userId != userIdFilter) return false;
        if (startDate != null && e.timestamp.isBefore(startDate)) return false;
        if (endDate != null && e.timestamp.isAfter(endDate)) return false;
        return true;
      }).toList();
      list.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      return list.take(limit).toList();
    });
  }
}
