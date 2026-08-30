import 'dart:async';

import 'package:intl/intl.dart';
import '../core/location/location_probe.dart';
import '../core/constants/education_level.dart';
import '../core/constants/user_roles.dart';
import '../core/errors/failures.dart';
import 'dart:convert';
import 'dart:typed_data';

import '../core/errors/result.dart';
import '../features/admin_portal/domain/entities/employee_summary.dart';
import '../features/admin_portal/domain/entities/program.dart';
import '../features/admin_portal/domain/entities/school_branding.dart';
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
import '../features/emergency/domain/entities/emergency_alert.dart';
import '../features/emergency/domain/entities/emergency_contact.dart';
import '../features/emergency/domain/repositories/emergency_repository.dart';
import '../features/faculty_portal/domain/entities/answer_key.dart';
import '../features/faculty_portal/domain/entities/coursework_submission.dart';
import '../features/faculty_portal/domain/entities/grade.dart';
import '../core/storage/upload_repository.dart';
import '../features/faculty_portal/domain/repositories/faculty_repository.dart';
import '../features/guidance_portal/domain/entities/guidance_record.dart';
import '../features/guidance_portal/domain/entities/summons.dart';
import '../features/guidance_portal/domain/repositories/guidance_repository.dart';
import '../features/reports/domain/entities/report_kind.dart';
import '../features/reports/domain/entities/report_period.dart';
import '../features/reports/domain/repositories/reports_repository.dart';
import '../features/schedules/domain/entities/schedule_block.dart';
import '../features/schedules/domain/repositories/schedule_repository.dart';
import '../features/data_protection/domain/entities/data_request.dart';
import '../features/data_protection/domain/repositories/data_protection_repository.dart';
import '../features/system_check/domain/entities/system_check.dart';
import '../features/system_check/domain/repositories/system_check_repository.dart';
// See the note in demo_store.dart: unqualified PaymentMethod is the
// student-payments enum; the platform-billing one is `billing.PaymentMethod`.
import '../features/owner_portal/domain/entities/invoice.dart' hide PaymentMethod;
import '../features/owner_portal/domain/entities/invoice.dart' as billing;
import '../features/owner_portal/domain/entities/revenue_summary.dart';
import '../features/owner_portal/domain/entities/school_summary.dart';
import '../features/owner_portal/domain/repositories/owner_repository.dart';
import '../features/parent_portal/domain/repositories/parent_repository.dart';
import '../features/payments/domain/entities/assessment.dart';
import '../features/payments/domain/entities/fee_structure.dart';
import '../features/payments/domain/entities/payment.dart';
import '../features/payments/domain/entities/payment_settings.dart';
import '../features/payments/domain/entities/payment_submission.dart';
import '../features/payments/domain/repositories/payment_repository.dart';
import '../features/profile/domain/repositories/profile_repository.dart';
import '../features/qr_attendance/domain/entities/attendance_record.dart';
import '../features/qr_attendance/domain/entities/qr_scan_result.dart';
import '../features/qr_attendance/domain/repositories/qr_attendance_repository.dart';
import '../features/registrar_portal/domain/entities/document_release.dart';
import '../features/registrar_portal/domain/entities/student_summary.dart';
import '../features/registrar_portal/domain/repositories/registrar_repository.dart';
import '../features/staff_portal/domain/entities/checklist_item.dart';
import '../features/notifications/domain/entities/app_notification.dart';
import '../features/notifications/domain/repositories/notifications_repository.dart';
import '../features/school_totals/domain/entities/school_totals.dart';
import '../features/school_totals/domain/repositories/school_totals_repository.dart';
import '../features/terms/domain/repositories/terms_repository.dart';
import '../features/staff_portal/domain/entities/daily_report.dart';
import '../features/staff_portal/domain/repositories/staff_repository.dart';
import '../features/student_portal/domain/repositories/student_repository.dart';
import 'demo_session.dart';
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
/// Money is stored to the centavo. Without this a few assessments and a
/// payment leave a balance like 23999.999999999996, which is a real
/// difference on a printed statement.
double _round2(double value) => (value * 100).round() / 100;

Future<void> _latency([int ms = 350]) => Future<void>.delayed(Duration(milliseconds: ms));

/// How a summons date reads in a notification. Matches what
/// formatSummonsWhen() produces server-side.
final _summonsWhen = DateFormat('EEE d MMM, h:mm a');

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

    _store.currentUser.add(_store.withAcknowledgement(match));
    // Not awaited: signing in must not wait on a disk write, and a failed
    // one costs a re-login after a reload rather than anything visible.
    unawaited(DemoSession.remember(match));
    _store.audit(
      module: 'users',
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
    // Awaited, unlike remembering: a sign-out that leaves the session on
    // disk would put the next visitor straight back into the previous
    // one's portal.
    await DemoSession.remember(null);
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
      module: 'users',
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
  ///
  /// Remembered like an ordinary sign-in, so a reload comes back as
  /// whichever role you were last looking at rather than as whoever you
  /// typed a password for.
  void signInAs(AppUser user) {
    // Carry back whether this account already read the privacy notice
    // this run. The demo accounts are const, so without this the gate
    // would reappear every time somebody switched roles and back --
    // demonstrating the gate rather than the app behind it.
    _store.currentUser.add(_store.withAcknowledgement(user));
    unawaited(DemoSession.remember(user));
  }
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
  Future<Result<String>> createSchool({
    required String name,
    required double billingRatePerStudent,
    required Set<EducationLevel> educationLevels,
    String? schoolId,
    String? addressLine,
    String? contactEmail,
    String? contactPhone,
  }) async {
    await _latency();
    // Mirrors the callable: the id is slugified from the name when the
    // caller does not choose one, and a duplicate is refused rather than
    // silently overwriting a school that already exists.
    final id = (schoolId?.trim().isNotEmpty ?? false)
        ? schoolId!.trim()
        : DemoStore.slugify(name);
    if (id.isEmpty) {
      return const Error(ValidationFailure('That name has no usable id in it.'));
    }
    if (_store.schools.value.any((s) => s.id == id)) {
      return Error(ValidationFailure('A school with the id "$id" already exists.'));
    }
    if (educationLevels.isEmpty) {
      // The callable refuses this too. Which divisions a school runs is
      // not a detail to be filled in later: it decides what the
      // registration form offers on the day after this one.
      return const Error(
        ValidationFailure('Pick at least one level the school offers.'),
      );
    }

    _store.prepend(
      _store.schools,
      SchoolSummary(
        id: id,
        name: name.trim(),
        // Active with nothing accrued: a school created a moment ago has
        // no students and has not been billed for any.
        status: SchoolSubscriptionStatus.active,
        activeStudentCount: 0,
        currentCycleAccrued: 0,
        educationLevels: educationLevels,
      ),
    );
    return Success(id);
  }

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
        // Carried forward, not defaulted: pausing a school does not
        // change which divisions it runs.
        educationLevels: s.educationLevels,
        suspendedAt: DateTime.now(),
      ),
    );
    _store.audit(
      module: 'platformSchools',
      action: 'suspend',
      targetCollection: 'platformSchools',
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
        // Carried forward, not defaulted: pausing a school does not
        // change which divisions it runs.
        educationLevels: s.educationLevels,
      ),
    );
    _store.audit(
      module: 'platformSchools',
      action: 'resume',
      targetCollection: 'platformSchools',
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
      module: 'platformInvoices',
      action: 'payment',
      targetCollection: 'platformInvoices',
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
    // Students only. The faculty scan is in the same collection, and
    // counting it toward a rate whose denominator is the enrolled student
    // count made the figure drift up by one person every morning.
    final todays = _store.attendance.value
        .where((a) =>
            a.date == today && a.subjectType == AttendanceSubjectType.student)
        .toList();
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
        createdBy: _store.requireUser.uid,
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
        createdBy: a.createdBy,
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
      action: 'soft_delete',
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
      action: 'soft_delete',
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
        decidedByUid: _store.requireUser.uid,
        decidedByName: _store.requireUser.fullName,
        decidedByRole: _store.requireUser.role.value,
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
      action: 'soft_delete',
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
    bool isAdviser = false,
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
        isAdviser: isAdviser,
      ),
    );
    _store.audit(
      module: 'teacherAssignments',
      action: 'create',
      targetCollection: 'teacherAssignments',
      targetId: id,
      newValue: {'subject': subject, 'section': section},
    );
    return const Success(null);
  }

  @override
  Future<Result<void>> updateTeacherAssignment({
    required String assignmentId,
    required String teacherId,
    required String teacherName,
    required String subject,
    required String section,
    required String schoolYear,
    bool isAdviser = false,
  }) async {
    await _latency();
    _store.update<TeacherAssignment>(
      _store.assignments,
      (a) => a.id == assignmentId,
      (a) => TeacherAssignment(
        id: a.id,
        teacherId: teacherId,
        teacherName: teacherName,
        subject: subject,
        section: section,
        schoolYear: schoolYear,
        isAdviser: isAdviser,
      ),
    );
    _store.audit(
      module: 'teacherAssignments',
      action: 'update',
      targetCollection: 'teacherAssignments',
      targetId: assignmentId,
      newValue: {'subject': subject, 'section': section},
    );
    return const Success(null);
  }

  @override
  Future<Result<void>> deleteTeacherAssignment(String assignmentId) async {
    await _latency();
    _store.softDelete(_store.assignments, (a) => a.id == assignmentId);
    _store.audit(
      module: 'teacherAssignments',
      action: 'soft_delete',
      targetCollection: 'teacherAssignments',
      targetId: assignmentId,
      remarks: 'Soft deleted',
    );
    return const Success(null);
  }

  @override
  Stream<List<Program>> watchPrograms() => _store.programs.stream;

  @override
  Future<Result<void>> createProgram({
    required EducationLevel educationLevel,
    required String name,
    required String code,
    required String department,
  }) async {
    await _latency();
    final id = _store.nextId('prog');
    _store.prepend(
      _store.programs,
      Program(
        id: id,
        name: name,
        code: code,
        department: department,
        educationLevel: educationLevel,
      ),
    );
    _store.audit(
      module: 'programs',
      action: 'create',
      targetCollection: 'programs',
      targetId: id,
      newValue: {'name': name, 'code': code},
    );
    return const Success(null);
  }

  @override
  Future<Result<void>> updateProgram({
    required String programId,
    required String name,
    required String code,
    required String department,
  }) async {
    await _latency();
    _store.update<Program>(
      _store.programs,
      (p) => p.id == programId,
      // The division is fixed at creation: moving a strand into the
      // college catalogue (or the reverse) would silently reclassify every
      // student already enrolled in it.
      (p) => Program(
            id: p.id,
            name: name,
            code: code,
            department: department,
            educationLevel: p.educationLevel,
          ),
    );
    _store.audit(
      module: 'programs',
      action: 'update',
      targetCollection: 'programs',
      targetId: programId,
      newValue: {'name': name, 'code': code},
    );
    return const Success(null);
  }

  @override
  Future<Result<void>> deleteProgram(String programId) async {
    await _latency();
    _store.softDelete(_store.programs, (p) => p.id == programId);
    _store.audit(
      module: 'programs',
      action: 'soft_delete',
      targetCollection: 'programs',
      targetId: programId,
      remarks: 'Soft deleted',
    );
    return const Success(null);
  }

  @override
  Stream<SchoolBranding> watchBranding() => _store.branding.stream;

  @override
  Future<Result<void>> updateBranding({
    String? logoUrl,
    String? logoFileName,
    String? schoolName,
    String? addressLine,
    String? principalName,
    String? principalSignatureUrl,
    String? directorSignatureUrl,
    String? directorName,
    String? schoolYear,
    String? dpoName,
    String? dpoEmail,
    String? dpoPhone,
  }) async {
    await _latency();
    final current = _store.branding.value;
    _store.branding.add(SchoolBranding(
      // Null means "not being changed" -- saving the name must not clear
      // a previously uploaded logo.
      logoUrl: logoUrl ?? current.logoUrl,
      logoFileName: logoFileName ?? current.logoFileName,
      schoolName: schoolName ?? current.schoolName,
      addressLine: addressLine ?? current.addressLine,
      principalName: principalName ?? current.principalName,
      principalSignatureUrl: principalSignatureUrl ?? current.principalSignatureUrl,
      directorSignatureUrl: directorSignatureUrl ?? current.directorSignatureUrl,
      directorName: directorName ?? current.directorName,
      schoolYear: schoolYear ?? current.schoolYear,
      dpoName: dpoName ?? current.dpoName,
      dpoEmail: dpoEmail ?? current.dpoEmail,
      dpoPhone: dpoPhone ?? current.dpoPhone,
      updatedAt: DateTime.now(),
      updatedByName: _store.requireUser.fullName,
    ));
    _store.audit(
      module: 'branding',
      action: 'update',
      targetCollection: 'settings',
      targetId: 'branding',
      newValue: {if (logoFileName != null) 'logoFileName': logoFileName},
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
  Stream<List<StudentSummary>> watchStudents({int? limit, EducationLevel? educationLevel}) =>
      _store.students.stream.map((all) {
        final rows = all
            .where((s) => educationLevel == null || s.educationLevel == educationLevel)
            .toList()
          ..sort((a, b) => a.lastName.compareTo(b.lastName));
        // The truncation is the point: the demo has to page the same way
        // the real thing does, or the Load more button is decoration.
        return limit == null || rows.length <= limit ? rows : rows.sublist(0, limit);
      });

  @override
  Future<Result<void>> setStudentPhoto({
    required String studentId,
    required String photoUrl,
  }) async {
    await _latency(300);
    _store.update<StudentSummary>(
      _store.students,
      (s) => s.id == studentId,
      (s) => _copyStudent(s, photoUrl: photoUrl),
    );
    _store.audit(
      module: 'students',
      action: 'set_photo',
      targetCollection: 'students',
      targetId: studentId,
      newValue: {'photoUrl': 'set'},
    );
    return const Success(null);
  }

  @override
  Future<List<StudentSummary>> fetchAllStudents() async {
    await _latency(300);
    return [..._store.students.value]..sort((a, b) => a.lastName.compareTo(b.lastName));
  }

  @override
  Stream<List<Grade>> watchStudentGrades(String studentId) => _store.grades.stream.map(
        (all) => all.where((g) => g.studentId == studentId).toList()
          ..sort((a, b) => b.submittedAt.compareTo(a.submittedAt)),
      );

  @override
  Stream<List<DocumentRelease>> watchDocumentReleases(String studentId) =>
      _store.documentReleases.stream.map(
        (all) => all.where((r) => r.studentId == studentId).toList()
          ..sort((a, b) => b.releasedAt.compareTo(a.releasedAt)),
      );

  @override
  Future<Result<void>> recordDocumentRelease({
    required String studentId,
    required String studentName,
    required SchoolDocument document,
    required int copies,
    required String purpose,
    required String releasedToName,
    String? releasedToRelation,
    String? remarks,
  }) async {
    await _latency(400);
    _store.prepend(
      _store.documentReleases,
      DocumentRelease(
        id: _store.nextId('rel'),
        studentId: studentId,
        studentName: studentName,
        document: document,
        copies: copies,
        purpose: purpose,
        releasedToName: releasedToName,
        releasedToRelation: releasedToRelation,
        releasedByName: _store.requireUser.fullName,
        releasedAt: DateTime.now(),
        remarks: remarks,
      ),
    );
    _store.audit(
      module: 'students',
      action: 'release_document',
      targetCollection: 'documentReleases',
      targetId: studentId,
      newValue: {'document': document.value, 'copies': copies},
      remarks: 'Released to $releasedToName — $purpose',
    );
    return const Success(null);
  }

  @override
  Future<Result<RegisterStudentOutcome>> registerStudent({
    required String firstName,
    required String lastName,
    String? middleName,
    required EducationLevel educationLevel,
    required String gradeLevel,
    required String section,
    String? programId,
    DateTime? birthDate,
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
        birthDate: birthDate,
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
    DateTime? birthDate,
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
        birthDate: birthDate,
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
  Future<Result<void>> setStudentBalance({
    required String studentId,
    required double balance,
    required String remarks,
  }) async {
    await _latency();
    _store.update<StudentSummary>(
      _store.students,
      (s) => s.id == studentId,
      (s) => _copyStudent(s, balance: balance),
    );
    _store.audit(
      module: 'students',
      action: 'update',
      targetCollection: 'students',
      targetId: studentId,
      newValue: {'balance': balance},
      remarks: remarks,
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
  DateTime? birthDate,
  String? photoUrl,
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
    photoUrl: photoUrl ?? s.photoUrl,
    enrollmentDate: s.enrollmentDate,
    birthDate: birthDate ?? s.birthDate,
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
  Stream<List<CourseworkSubmission>> watchSubmissionsFor(String courseworkId) =>
      _store.courseworkSubmissions.stream.map((all) => all
          .where((sub) => sub.courseworkId == courseworkId)
          .toList()
        ..sort((a, b) => a.studentName.compareTo(b.studentName)));

  @override
  Stream<AnswerKey?> watchAnswerKey(String courseworkId) => _store.answerKeys.stream
      .map((all) => all.where((k) => k.courseworkId == courseworkId).firstOrNull);

  @override
  Future<Result<void>> saveAnswerKey({
    required String courseworkId,
    required List<String> answers,
    required double pointsPerQuestion,
  }) async {
    await _latency();
    final key = AnswerKey(
      courseworkId: courseworkId,
      answers: answers,
      pointsPerQuestion: pointsPerQuestion,
      updatedByName: _store.requireUser.fullName,
      updatedAt: DateTime.now(),
    );
    final existing =
        _store.answerKeys.value.where((k) => k.courseworkId == courseworkId).firstOrNull;
    if (existing == null) {
      _store.prepend(_store.answerKeys, key);
    } else {
      _store.update<AnswerKey>(
          _store.answerKeys, (k) => k.courseworkId == courseworkId, (_) => key);
    }

    // Mirrors what the real datasource does: the question count lives on
    // the item so the student form can size itself without the key.
    _store.update<CourseworkItem>(
      _store.coursework,
      (c) => c.id == courseworkId,
      (c) => _copyCoursework(c, questionCount: answers.length),
    );

    // Demo mode has no Cloud Functions, so the re-marking the trigger
    // would do on the server happens here instead. Same arithmetic, same
    // AnswerKey.scoreFor -- what differs is only who runs it.
    for (final sub in _store.courseworkSubmissions.value
        .where((s) => s.courseworkId == courseworkId)
        .toList()) {
      _store.update<CourseworkSubmission>(
        _store.courseworkSubmissions,
        (s) => s.id == sub.id,
        (s) => _copySubmission(s,
            autoScore: key.scoreFor(s.answers), correctCount: key.correctCount(s.answers)),
      );
    }
    return const Success(null);
  }

  @override
  Future<Result<void>> gradeSubmission({
    required String submissionId,
    required double score,
    String? feedback,
  }) async {
    await _latency();
    _store.update<CourseworkSubmission>(
      _store.courseworkSubmissions,
      (s) => s.id == submissionId,
      (s) => _copySubmission(s,
          score: score,
          feedback: feedback,
          gradedByName: _store.requireUser.fullName,
          gradedAt: DateTime.now()),
    );
    _store.audit(
      module: 'courseworkSubmissions',
      action: 'grade',
      targetCollection: 'courseworkSubmissions',
      targetId: submissionId,
      newValue: {'score': score},
    );
    return const Success(null);
  }

  @override
  Future<Result<void>> createCourseworkItem({
    required CourseworkType type,
    required CourseworkDelivery delivery,
    required String title,
    required String description,
    required String subject,
    required String section,
    DateTime? dueDate,
    double? totalPoints,
    required bool published,
    String? attachmentUrl,
    String? attachmentName,
  }) async {
    await _latency();
    final user = _store.requireUser;
    final id = _store.nextId('cw');
    _store.prepend(
      _store.coursework,
      CourseworkItem(
        id: id,
        type: type,
        delivery: delivery,
        title: title,
        description: description,
        subject: subject,
        section: section,
        teacherId: user.uid,
        teacherName: user.fullName,
        dueDate: dueDate,
        totalPoints: totalPoints,
        attachmentUrl: attachmentUrl,
        attachmentName: attachmentName,
        published: published,
        createdAt: DateTime.now(),
      ),
    );
    _store.audit(
      module: 'courseworkItems',
      action: 'create',
      targetCollection: 'courseworkItems',
      targetId: id,
      newValue: {'type': type.value, 'title': title, 'published': published},
    );
    return const Success(null);
  }

  @override
  Future<Result<void>> updateCourseworkItem({
    required String itemId,
    required CourseworkType type,
    required CourseworkDelivery delivery,
    required String title,
    required String description,
    required String subject,
    required String section,
    DateTime? dueDate,
    double? totalPoints,
    required bool published,
    String? attachmentUrl,
    String? attachmentName,
  }) async {
    await _latency();
    _store.update<CourseworkItem>(
      _store.coursework,
      (c) => c.id == itemId,
      (c) => CourseworkItem(
        id: c.id,
        type: type,
        delivery: delivery,
        title: title,
        description: description,
        subject: subject,
        section: section,
        // teacherId/teacherName are never reassigned by an edit; the
        // rules reject any update that changes teacherId.
        teacherId: c.teacherId,
        teacherName: c.teacherName,
        dueDate: dueDate,
        totalPoints: totalPoints,
        attachmentUrl: attachmentUrl,
        attachmentName: attachmentName,
        published: published,
        createdAt: c.createdAt,
      ),
    );
    _store.audit(
      module: 'courseworkItems',
      action: 'update',
      targetCollection: 'courseworkItems',
      targetId: itemId,
      newValue: {'title': title, 'published': published},
    );
    return const Success(null);
  }

  @override
  Future<Result<void>> deleteCourseworkItem(String itemId) async {
    await _latency();
    _store.softDelete(_store.coursework, (c) => c.id == itemId);
    _store.audit(
      module: 'courseworkItems',
      action: 'soft_delete',
      targetCollection: 'courseworkItems',
      targetId: itemId,
      remarks: 'Soft deleted',
    );
    return const Success(null);
  }

  @override
  Stream<List<StudentSummary>> watchStudentsInSection(String section) {
    return _store.students.stream.map(
      (all) => all.where((s) => s.section == section).toList()
        ..sort((a, b) => a.lastName.compareTo(b.lastName)),
    );
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
// Attachments
// ---------------------------------------------------------------------------

/// Stands in for Firebase Storage.
///
/// Encodes the file as a data URI rather than uploading anywhere, so a
/// receipt or attachment picked in demo mode is genuinely viewable on the
/// same device -- the flow can be exercised end to end with no bucket, and
/// nothing leaves the browser.
class DemoUploadRepository implements UploadRepository {
  final DemoStore _store;
  DemoUploadRepository(this._store);

  @override
  Future<Result<UploadedFile>> upload({
    required UploadFolder folder,
    required String fileName,
    required Uint8List bytes,
    required String contentType,
  }) async {
    await _latency(700);

    // Same 10MB ceiling storage.rules enforces, so demo mode rejects what
    // the real backend would reject rather than silently accepting more.
    const maxBytes = 10 * 1024 * 1024;
    if (bytes.lengthInBytes > maxBytes) {
      return const Error(ValidationFailure('Files are limited to 10MB.'));
    }

    _store.audit(
      module: folder.folder,
      action: 'upload',
      targetCollection: folder.folder,
      targetId: fileName,
      newValue: {'fileName': fileName, 'sizeBytes': bytes.lengthInBytes},
    );

    return Success(UploadedFile(
      fileName: fileName,
      url: 'data:$contentType;base64,${base64Encode(bytes)}',
      sizeBytes: bytes.lengthInBytes,
    ));
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
  @override
  Stream<List<CourseworkSubmission>> watchMySubmissions(String studentId) =>
      _store.courseworkSubmissions.stream
          .map((all) => all.where((sub) => sub.studentId == studentId).toList());

  @override
  Future<Result<void>> submitCoursework({
    String? submissionId,
    required CourseworkItem item,
    required String studentId,
    required String studentName,
    required String section,
    required String answer,
    List<String> answers = const [],
    String? attachmentUrl,
    String? attachmentName,
  }) async {
    await _latency();
    // The same deterministic key the real datasource uses, so tapping
    // Submit twice replaces the answer instead of leaving a teacher two
    // documents to reconcile.
    final id = '${item.id}_$studentId';
    final existing =
        _store.courseworkSubmissions.value.where((sub) => sub.id == id).firstOrNull;

    // Demo mode has no Cloud Functions, so the marking that
    // onCourseworkSubmissionWritten does on the server happens here.
    // Same arithmetic via AnswerKey.scoreFor -- what differs is only who
    // runs it, and in the real app the student's device never sees the
    // key at all.
    final key = _store.answerKeys.value
        .where((k) => k.courseworkId == item.id)
        .firstOrNull;

    final record = CourseworkSubmission(
      id: id,
      courseworkId: item.id,
      courseworkTitle: item.title,
      studentId: studentId,
      studentName: studentName,
      section: section,
      userId: _store.requireUser.uid,
      answer: answer,
      answers: answers,
      autoScore: key?.scoreFor(answers),
      correctCount: key?.correctCount(answers),
      // A teacher's mark survives a resubmission: they marked the work,
      // and silently dropping that because the student edited a typo
      // would be worse than leaving a stale score for them to revisit.
      score: existing?.score,
      feedback: existing?.feedback,
      gradedByName: existing?.gradedByName,
      gradedAt: existing?.gradedAt,
      attachmentUrl: attachmentUrl,
      attachmentName: attachmentName,
      // A first submission stamps submittedAt; a revision keeps the
      // original time and records separately that it changed, so a
      // teacher can tell a rewrite from a late arrival.
      submittedAt: existing?.submittedAt ?? DateTime.now(),
      updatedAt: existing == null ? null : DateTime.now(),
    );

    if (existing == null) {
      _store.prepend(_store.courseworkSubmissions, record);
    } else {
      _store.update<CourseworkSubmission>(
        _store.courseworkSubmissions,
        (sub) => sub.id == id,
        (_) => record,
      );
    }
    _store.audit(
      module: 'courseworkSubmissions',
      action: existing == null ? 'create' : 'update',
      targetCollection: 'courseworkSubmissions',
      targetId: id,
      newValue: {'courseworkId': item.id, 'studentId': studentId},
    );
    return const Success(null);
  }

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

  // -------------------------------------------------------------------
  // Fee assessment
  // -------------------------------------------------------------------

  @override
  Stream<List<FeeStructure>> watchFeeStructures() => _store.feeStructures.stream
      .map((all) => [...all]..sort((a, b) => a.name.compareTo(b.name)));

  @override
  Future<Result<void>> saveFeeStructure({
    String? structureId,
    required String name,
    required EducationLevel educationLevel,
    String? gradeLevel,
    required String schoolYear,
    required List<FeeItem> items,
    required bool isActive,
  }) async {
    await _latency(400);
    final saved = FeeStructure(
      id: structureId ?? _store.nextId('fee'),
      name: name,
      educationLevel: educationLevel,
      gradeLevel: gradeLevel?.trim().isEmpty ?? true ? null : gradeLevel!.trim(),
      schoolYear: schoolYear,
      items: items,
      isActive: isActive,
      updatedAt: DateTime.now(),
      updatedByName: _store.requireUser.fullName,
    );
    if (structureId == null) {
      _store.prepend(_store.feeStructures, saved);
    } else {
      _store.update<FeeStructure>(
          _store.feeStructures, (f) => f.id == structureId, (_) => saved);
    }
    _store.audit(
      module: 'payments',
      action: structureId == null ? 'create_fee_structure' : 'update_fee_structure',
      targetCollection: 'feeStructures',
      targetId: saved.id,
      newValue: {'name': name, 'total': saved.total},
    );
    return const Success(null);
  }

  @override
  Stream<List<Assessment>> watchAssessments(String studentId) => _store.assessments.stream.map(
        (all) => all.where((a) => a.studentId == studentId).toList()
          ..sort((a, b) => b.assessedAt.compareTo(a.assessedAt)),
      );

  @override
  Future<Result<AssessmentOutcome>> assessStudentFees({
    required String studentId,
    required String schoolYear,
    required List<FeeItem> items,
    String? sourceStructureId,
    String? sourceStructureName,
    String? remarks,
  }) async {
    await _latency(700);
    final student = _store.students.value.where((s) => s.id == studentId).firstOrNull;
    if (student == null) return const Error(ValidationFailure('Student record not found.'));

    // Mirrors the duplicate check in assessStudentFees.ts. Charging the
    // same schedule twice for one year is two clicks away, and it
    // silently doubles what a family owes.
    if (sourceStructureId != null &&
        _store.assessments.value.any((a) =>
            a.studentId == studentId &&
            a.sourceStructureId == sourceStructureId &&
            a.schoolYear == schoolYear &&
            !a.isVoided)) {
      return Error(ValidationFailure(
        'This student has already been assessed under that schedule for '
        '$schoolYear. Void the existing assessment first if it needs to change.',
      ));
    }

    final total = items.fold<double>(0, (sum, i) => sum + i.amount);
    final id = _store.nextId('asmt');
    _store.prepend(
      _store.assessments,
      Assessment(
        id: id,
        studentId: studentId,
        studentName: student.fullName,
        schoolYear: schoolYear,
        sourceStructureId: sourceStructureId,
        sourceStructureName: sourceStructureName,
        items: items,
        assessedByName: _store.requireUser.fullName,
        assessedAt: DateTime.now(),
        remarks: remarks,
      ),
    );

    // The balance and the record move together, the way the server
    // transaction makes them.
    final newBalance = _round2(student.balance + total);
    _store.update<StudentSummary>(
      _store.students,
      (s) => s.id == studentId,
      (s) => _copyStudent(s, balance: newBalance),
    );
    _store.audit(
      module: 'payments',
      action: 'assess_fees',
      targetCollection: 'assessments',
      targetId: id,
      newValue: {'total': total, 'balance': newBalance},
      remarks: sourceStructureName ?? 'Ad-hoc assessment',
    );
    return Success(AssessmentOutcome(assessmentId: id, total: total, newBalance: newBalance));
  }

  @override
  Future<Result<void>> voidAssessment({
    required String assessmentId,
    required String reason,
  }) async {
    await _latency(500);
    final assessment =
        _store.assessments.value.where((a) => a.id == assessmentId).firstOrNull;
    if (assessment == null) return const Error(ValidationFailure('Assessment not found.'));
    if (assessment.isVoided) {
      return const Error(ValidationFailure('That assessment has already been voided.'));
    }

    _store.update<Assessment>(
      _store.assessments,
      (a) => a.id == assessmentId,
      (a) => Assessment(
        id: a.id,
        studentId: a.studentId,
        studentName: a.studentName,
        schoolYear: a.schoolYear,
        sourceStructureId: a.sourceStructureId,
        sourceStructureName: a.sourceStructureName,
        items: a.items,
        assessedByName: a.assessedByName,
        assessedAt: a.assessedAt,
        remarks: a.remarks,
        voidedAt: DateTime.now(),
        voidedByName: _store.requireUser.fullName,
        voidReason: reason,
      ),
    );

    final student =
        _store.students.value.where((s) => s.id == assessment.studentId).firstOrNull;
    if (student != null) {
      _store.update<StudentSummary>(
        _store.students,
        (s) => s.id == assessment.studentId,
        (s) => _copyStudent(s, balance: _round2(s.balance - assessment.total)),
      );
    }
    _store.audit(
      module: 'payments',
      action: 'void_assessment',
      targetCollection: 'assessments',
      targetId: assessmentId,
      newValue: {'reversed': assessment.total},
      remarks: reason,
    );
    return const Success(null);
  }

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
    // The student is looked up before anything is written, because
    // _store.update silently matches nothing when the id is wrong -- so
    // without this a payment against a mistyped id produced a receipt,
    // an audit entry and no deduction anywhere. That is exactly what a
    // cashier reports as "the balance is not deducting": the money was
    // recorded, just not against this student. The real callable refuses
    // it with not-found; this refuses it too.
    final student =
        _store.students.value.where((s) => s.id == studentId).firstOrNull;
    if (student == null) {
      return const Error(
        ValidationFailure('No student has that ID. Check it and try again.'),
      );
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
        newBalance = _round2(s.balance - amount);
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

  // ---- Online payment submissions ----

  @override
  Stream<List<PaymentSubmission>> watchSubmissionsForStudent(String studentId) =>
      _store.paymentSubmissions.stream.map(
        (all) => all.where((s) => s.studentId == studentId).toList()
          ..sort((a, b) => b.submittedAt.compareTo(a.submittedAt)),
      );

  @override
  Stream<List<PaymentSubmission>> watchSubmissions({bool pendingOnly = true}) =>
      _store.paymentSubmissions.stream.map(
        (all) => all.where((s) => !pendingOnly || s.isPending).toList()
          ..sort((a, b) => b.submittedAt.compareTo(a.submittedAt)),
      );

  @override
  Future<Result<void>> submitOnlinePayment({
    required String studentId,
    required String studentName,
    required double amount,
    required PaymentMethod method,
    required PaymentPurpose purpose,
    required String referenceNumber,
    String? receiptUrl,
    String? receiptFileName,
  }) async {
    await _latency(600);
    final user = _store.requireUser;
    final id = _store.nextId('sub');

    // Deliberately does NOT touch the balance. That only happens when a
    // registrar approves, which is the whole point of the review step.
    _store.prepend(
      _store.paymentSubmissions,
      PaymentSubmission(
        id: id,
        studentId: studentId,
        studentName: studentName,
        submittedByName: user.fullName,
        submittedByRole: user.role.value,
        amount: amount,
        method: method,
        purpose: purpose,
        referenceNumber: referenceNumber,
        receiptUrl: receiptUrl,
        receiptFileName: receiptFileName,
        status: SubmissionStatus.pending,
        submittedAt: DateTime.now(),
      ),
    );
    _store.audit(
      module: 'paymentSubmissions',
      action: 'create',
      targetCollection: 'paymentSubmissions',
      targetId: id,
      newValue: {
        'studentId': studentId,
        'amount': amount,
        'referenceNumber': referenceNumber,
      },
    );
    return const Success(null);
  }

  @override
  Future<Result<void>> decideSubmission({
    required String submissionId,
    required bool approve,
    String? remarks,
  }) async {
    await _latency(600);
    final submission =
        _store.paymentSubmissions.value.where((s) => s.id == submissionId).firstOrNull;
    if (submission == null) {
      return const Error(ValidationFailure('Submission not found.'));
    }
    if (!submission.isPending) {
      return const Error(ValidationFailure('That submission has already been decided.'));
    }

    final reviewer = _store.requireUser;
    String? paymentId;

    if (approve) {
      // Approval is what turns a claim into money: it creates the Payment
      // and moves the balance, using the same receipt-numbering the
      // counter flow uses so the two are indistinguishable afterwards.
      paymentId = _store.nextId('pay');
      final receiptNumber =
          'OR-${DateTime.now().year}-${(_store.payments.value.length + 1).toString().padLeft(6, '0')}';
      _store.prepend(
        _store.payments,
        Payment(
          id: paymentId,
          studentId: submission.studentId,
          amount: submission.amount,
          method: submission.method,
          referenceNumber: submission.referenceNumber,
          receiptNumber: receiptNumber,
          collectedByName: reviewer.fullName,
          purpose: submission.purpose,
          status: PaymentStatus.completed,
          createdAt: DateTime.now(),
        ),
      );
      _store.update<StudentSummary>(
        _store.students,
        (s) => s.id == submission.studentId,
        (s) => _copyStudent(s, balance: _round2(s.balance - submission.amount)),
      );
    }

    _store.update<PaymentSubmission>(
      _store.paymentSubmissions,
      (s) => s.id == submissionId,
      (s) => PaymentSubmission(
        id: s.id,
        studentId: s.studentId,
        studentName: s.studentName,
        submittedByName: s.submittedByName,
        submittedByRole: s.submittedByRole,
        amount: s.amount,
        method: s.method,
        purpose: s.purpose,
        referenceNumber: s.referenceNumber,
        receiptUrl: s.receiptUrl,
        receiptFileName: s.receiptFileName,
        status: approve ? SubmissionStatus.approved : SubmissionStatus.rejected,
        reviewedByName: reviewer.fullName,
        reviewedAt: DateTime.now(),
        decisionRemarks: remarks,
        resultingPaymentId: paymentId,
        submittedAt: s.submittedAt,
      ),
    );

    _store.audit(
      module: 'paymentSubmissions',
      action: approve ? 'approve' : 'reject',
      targetCollection: 'paymentSubmissions',
      targetId: submissionId,
      newValue: {if (paymentId != null) 'resultingPaymentId': paymentId},
      remarks: remarks,
    );
    return const Success(null);
  }

  // ---- Payment settings ----

  @override
  Stream<PaymentSettings> watchPaymentSettings() => _store.paymentSettings.stream;

  @override
  Future<Result<void>> updatePaymentSettings({
    String? qrCodeUrl,
    String? qrCodeFileName,
    String? accountName,
    String? accountNumber,
    String? instructions,
  }) async {
    await _latency();
    final current = _store.paymentSettings.value;
    _store.paymentSettings.add(PaymentSettings(
      // Null means "not being changed" -- saving account details must not
      // wipe a previously uploaded QR.
      qrCodeUrl: qrCodeUrl ?? current.qrCodeUrl,
      qrCodeFileName: qrCodeFileName ?? current.qrCodeFileName,
      accountName: accountName ?? current.accountName,
      accountNumber: accountNumber ?? current.accountNumber,
      instructions: instructions ?? current.instructions,
      updatedAt: DateTime.now(),
      updatedByName: _store.requireUser.fullName,
    ));
    _store.audit(
      module: 'paymentSettings',
      action: 'update',
      targetCollection: 'settings',
      targetId: 'payments',
      newValue: {if (qrCodeFileName != null) 'qrCodeFileName': qrCodeFileName},
    );
    return const Success(null);
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
      (s) => _copyStudent(s, balance: _round2(s.balance + original.amount)),
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
      module: 'checklistItems',
      action: 'create',
      targetCollection: 'checklistItems',
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
  Future<Result<void>> updateChecklistItem({required String itemId, required String task}) async {
    await _latency(250);
    _store.update<ChecklistItem>(
      _store.checklist,
      (c) => c.id == itemId,
      (c) => ChecklistItem(
        id: c.id,
        task: task,
        date: c.date,
        completed: c.completed,
        completedAt: c.completedAt,
        notes: c.notes,
      ),
    );
    _store.audit(
      module: 'checklistItems',
      action: 'update',
      targetCollection: 'checklistItems',
      targetId: itemId,
      newValue: {'task': task},
    );
    return const Success(null);
  }

  @override
  Future<Result<void>> deleteChecklistItem(String itemId) async {
    await _latency(250);
    _store.softDelete(_store.checklist, (c) => c.id == itemId);
    _store.audit(
      module: 'checklistItems',
      action: 'soft_delete',
      targetCollection: 'checklistItems',
      targetId: itemId,
      remarks: 'Soft deleted',
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
      module: 'dailyReports',
      action: 'create',
      targetCollection: 'dailyReports',
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
  Stream<List<GuidanceRecord>> watchSectionRecords(String section) {
    return _store.guidanceRecords.stream.map(
      (all) => all.where((g) => g.studentId == null && g.section == section).toList()
        ..sort((a, b) => b.recordedAt.compareTo(a.recordedAt)),
    );
  }

  @override
  Future<Result<void>> createGuidanceRecord({
    String? studentId,
    String? studentName,
    required String section,
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
        section: section,
        category: category,
        notes: notes,
        recordedByName: _store.requireUser.fullName,
        recordedAt: DateTime.now(),
      ),
    );
    _store.audit(
      module: 'guidanceRecords',
      action: 'create',
      targetCollection: 'guidanceRecords',
      targetId: id,
      // Deliberately no note text in the audit entry -- counseling notes
      // are confidential, and the audit log has a wider audience.
      newValue: {'studentId': studentId, 'section': section, 'category': category.value},
    );
    return const Success(null);
  }

  @override
  Future<Result<void>> updateGuidanceRecord({
    required String recordId,
    required GuidanceCategory category,
    required String notes,
  }) async {
    await _latency();
    _store.update<GuidanceRecord>(
      _store.guidanceRecords,
      (g) => g.id == recordId,
      (g) => GuidanceRecord(
        id: g.id,
        // studentId never moves -- the rules reject an update that
        // reassigns a counseling note to a different student.
        studentId: g.studentId,
        studentName: g.studentName,
        section: g.section,
        category: category,
        notes: notes,
        recordedByName: g.recordedByName,
        recordedAt: g.recordedAt,
      ),
    );
    _store.audit(
      module: 'guidanceRecords',
      action: 'update',
      targetCollection: 'guidanceRecords',
      targetId: recordId,
      // Still no note text in the audit entry -- counseling notes are
      // confidential and the audit log has a wider audience.
      newValue: {'category': category.value},
    );
    return const Success(null);
  }

  @override
  Future<Result<void>> deleteGuidanceRecord(String recordId) async {
    await _latency();
    _store.softDelete(_store.guidanceRecords, (g) => g.id == recordId);
    _store.audit(
      module: 'guidanceRecords',
      action: 'soft_delete',
      targetCollection: 'guidanceRecords',
      targetId: recordId,
      remarks: 'Soft deleted',
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
      module: 'guidanceRecords',
      action: 'create',
      targetCollection: 'summons',
      targetId: id,
      newValue: {'studentId': studentId, 'reason': reason},
    );
    // What onSummonsWritten.ts does server-side. Issued here rather than
    // left to the guidance screen, so it happens however the summons was
    // created -- a notification that depends on which button was pressed
    // is one that will eventually not be sent.
    _store.notify(
      recipientUids: _store.familyOf(studentId),
      kind: NotificationKind.summons,
      title: 'Guidance office appointment',
      body: '$studentName is asked to come to the guidance office on '
          '${_summonsWhen.format(scheduledDate)}. Reason: $reason',
      sourceId: id,
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
      module: 'guidanceRecords',
      action: 'update',
      targetCollection: 'summons',
      targetId: summonsId,
      newValue: {'status': status.value},
    );
    // Cancelling matters more than issuing: a family that rearranged a
    // working day around an appointment should not turn up to one that
    // is off. Completing is silent -- the student was there.
    if (status == SummonsStatus.cancelled) {
      final summons =
          _store.summonses.value.where((s) => s.id == summonsId).firstOrNull;
      if (summons != null) {
        _store.notify(
          recipientUids: _store.familyOf(summons.studentId),
          kind: NotificationKind.summons,
          title: 'Guidance appointment cancelled',
          body: 'The guidance office has cancelled the appointment for '
              '${summons.studentName} on '
              '${_summonsWhen.format(summons.scheduledDate)}. There is '
              'nothing to attend.',
          sourceId: '$summonsId:cancelled',
        );
      }
    }
    return const Success(null);
  }
  @override
  Future<Result<void>> updateSummons({
    required String summonsId,
    required String reason,
    required DateTime scheduledDate,
  }) async {
    await _latency();
    _store.update<Summons>(
      _store.summonses,
      (s) => s.id == summonsId,
      (s) => Summons(
        id: s.id,
        studentId: s.studentId,
        studentName: s.studentName,
        reason: reason,
        scheduledDate: scheduledDate,
        status: s.status,
        issuedByName: s.issuedByName,
        createdAt: s.createdAt,
      ),
    );
    _store.audit(
      module: 'guidanceRecords',
      action: 'update',
      targetCollection: 'summons',
      targetId: summonsId,
      newValue: {'reason': reason},
    );
    return const Success(null);
  }

  @override
  Future<Result<void>> deleteSummons(String summonsId) async {
    await _latency();
    _store.softDelete(_store.summonses, (s) => s.id == summonsId);
    _store.audit(
      module: 'guidanceRecords',
      action: 'soft_delete',
      targetCollection: 'summons',
      targetId: summonsId,
      remarks: 'Soft deleted',
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
      module: 'users',
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

/// Copies a submission with the marking fields replaced. Demo mode has no
/// Cloud Function, so these are set locally by the same code paths that
/// would otherwise be server writes.
CourseworkSubmission _copySubmission(
  CourseworkSubmission s, {
  double? autoScore,
  int? correctCount,
  double? score,
  String? feedback,
  String? gradedByName,
  DateTime? gradedAt,
}) {
  return CourseworkSubmission(
    id: s.id,
    courseworkId: s.courseworkId,
    courseworkTitle: s.courseworkTitle,
    studentId: s.studentId,
    studentName: s.studentName,
    section: s.section,
    userId: s.userId,
    answer: s.answer,
    answers: s.answers,
    attachmentUrl: s.attachmentUrl,
    attachmentName: s.attachmentName,
    submittedAt: s.submittedAt,
    updatedAt: s.updatedAt,
    autoScore: autoScore ?? s.autoScore,
    correctCount: correctCount ?? s.correctCount,
    score: score ?? s.score,
    feedback: feedback ?? s.feedback,
    gradedByName: gradedByName ?? s.gradedByName,
    gradedAt: gradedAt ?? s.gradedAt,
  );
}

CourseworkItem _copyCoursework(CourseworkItem c, {int? questionCount}) {
  return CourseworkItem(
    id: c.id,
    type: c.type,
    delivery: c.delivery,
    title: c.title,
    description: c.description,
    subject: c.subject,
    section: c.section,
    teacherId: c.teacherId,
    teacherName: c.teacherName,
    dueDate: c.dueDate,
    totalPoints: c.totalPoints,
    attachmentUrl: c.attachmentUrl,
    attachmentName: c.attachmentName,
    published: c.published,
    questionCount: questionCount ?? c.questionCount,
    createdAt: c.createdAt,
  );
}

// ---------------------------------------------------------------------------
// Emergency
// ---------------------------------------------------------------------------

class DemoEmergencyRepository implements EmergencyRepository {
  final DemoStore _store;
  DemoEmergencyRepository(this._store);

  @override
  Stream<List<EmergencyContact>> watchContacts() => _store.emergencyContacts.stream
      .map((all) => [...all]..sort((a, b) => a.sortOrder.compareTo(b.sortOrder)));

  @override
  Stream<List<EmergencyAlert>> watchAlerts() => _store.emergencyAlerts.stream
      .map((all) => [...all]..sort((a, b) => b.raisedAt.compareTo(a.raisedAt)));

  @override
  Stream<List<EmergencyAlert>> watchAlertsForStudent(String studentId) =>
      _store.emergencyAlerts.stream.map((all) => all
          .where((a) => a.studentId == studentId)
          .toList()
        ..sort((a, b) => b.raisedAt.compareTo(a.raisedAt)));

  @override
  Future<Result<void>> saveContact({
    String? contactId,
    required String label,
    required String phone,
    String? notes,
    required int sortOrder,
  }) async {
    await _latency();
    final id = contactId ?? _store.nextId('emg');
    final contact = EmergencyContact(
      id: id,
      label: label,
      phone: phone,
      notes: notes,
      sortOrder: sortOrder,
      updatedAt: DateTime.now(),
      updatedByName: _store.requireUser.fullName,
    );
    final exists = _store.emergencyContacts.value.any((c) => c.id == id);
    if (exists) {
      _store.update<EmergencyContact>(
          _store.emergencyContacts, (c) => c.id == id, (_) => contact);
    } else {
      _store.prepend(_store.emergencyContacts, contact);
    }
    _store.audit(
      module: 'emergencyContacts',
      action: exists ? 'update' : 'create',
      targetCollection: 'emergencyContacts',
      targetId: id,
      newValue: {'label': label},
    );
    return const Success(null);
  }

  @override
  Future<Result<void>> deleteContact(String contactId) async {
    await _latency();
    _store.softDelete<EmergencyContact>(_store.emergencyContacts, (c) => c.id == contactId);
    _store.audit(
      module: 'emergencyContacts',
      action: 'delete',
      targetCollection: 'emergencyContacts',
      targetId: contactId,
    );
    return const Success(null);
  }

  @override
  Future<Result<void>> raiseAlert({
    required String studentId,
    required String studentName,
    required String section,
    String? message,
    LocationResult? location,
  }) async {
    await _latency();
    final id = _store.nextId('alert');
    final fix = location?.fix;
    _store.prepend(
      _store.emergencyAlerts,
      EmergencyAlert(
        id: id,
        studentId: studentId,
        studentName: studentName,
        section: section,
        userId: _store.requireUser.uid,
        message: message,
        raisedAt: DateTime.now(),
        latitude: fix?.latitude,
        longitude: fix?.longitude,
        locationAccuracyMeters: fix?.accuracyMeters,
        locationFailure: location?.failure,
      ),
    );
    _store.audit(
      module: 'emergencyAlerts',
      action: 'create',
      targetCollection: 'emergencyAlerts',
      targetId: id,
      newValue: {
        'studentId': studentId,
        'section': section,
        'hasLocation': fix != null,
      },
    );
    return const Success(null);
  }

  @override
  Future<Result<void>> acknowledgeAlert(String alertId) async {
    await _latency();
    _store.update<EmergencyAlert>(
      _store.emergencyAlerts,
      (a) => a.id == alertId,
      (a) => _copyAlert(a,
          acknowledgedByName: _store.requireUser.fullName, acknowledgedAt: DateTime.now()),
    );
    return const Success(null);
  }

  @override
  Future<Result<void>> resolveAlert({required String alertId, String? note}) async {
    await _latency();
    _store.update<EmergencyAlert>(
      _store.emergencyAlerts,
      (a) => a.id == alertId,
      (a) => _copyAlert(a, resolvedAt: DateTime.now(), resolutionNote: note),
    );
    return const Success(null);
  }
}

EmergencyAlert _copyAlert(
  EmergencyAlert a, {
  String? acknowledgedByName,
  DateTime? acknowledgedAt,
  DateTime? resolvedAt,
  String? resolutionNote,
}) {
  return EmergencyAlert(
    id: a.id,
    studentId: a.studentId,
    studentName: a.studentName,
    section: a.section,
    userId: a.userId,
    message: a.message,
    raisedAt: a.raisedAt,
    acknowledgedByName: acknowledgedByName ?? a.acknowledgedByName,
    acknowledgedAt: acknowledgedAt ?? a.acknowledgedAt,
    resolvedAt: resolvedAt ?? a.resolvedAt,
    resolutionNote: resolutionNote ?? a.resolutionNote,
  );
}


// ---------------------------------------------------------------------------
// Reports
// ---------------------------------------------------------------------------

/// The in-memory twin of the reports read.
///
/// It filters by date the same way the Firestore queries do rather than
/// handing every seeded row to the builders. That is the point of having
/// it: if a builder were quietly relying on being given the whole
/// collection, demo mode would keep working while the real app returned
/// a differently-shaped answer, and nothing would say so.
class DemoReportsRepository implements ReportsRepository {
  final DemoStore _store;
  DemoReportsRepository(this._store);

  @override
  Future<Result<ReportData>> fetch({
    required ReportKind kind,
    required ReportPeriod period,
  }) async {
    return Success(ReportData(
      students: kind.needsStudents ? _store.students.value : const [],
      payments: kind.needsPayments
          ? _store.payments.value.where((p) => period.contains(p.createdAt)).toList()
          : const [],
      assessments: kind.needsAssessments
          ? _store.assessments.value.where((a) => period.contains(a.assessedAt)).toList()
          : const [],
      attendance: kind.needsAttendance
          ? _store.attendance.value.where((record) {
              final day = DateTime.tryParse(record.date);
              return day != null && period.contains(day);
            }).toList()
          : const [],
      grades: kind.needsGrades
          ? _store.grades.value.where((g) => period.contains(g.submittedAt)).toList()
          : const [],
    ));
  }
}


// ---------------------------------------------------------------------------
// Timetable
// ---------------------------------------------------------------------------

/// The in-memory twin of the schedule callables.
///
/// It runs the same clash check the server runs, rather than accepting
/// whatever the screen sends. The check is the feature, and a demo that
/// cheerfully books two classes into one room would be demonstrating
/// something the real app refuses.
class DemoScheduleRepository implements ScheduleRepository {
  final DemoStore _store;
  DemoScheduleRepository(this._store);

  @override
  Stream<List<ScheduleBlock>> watchSchedule(String schoolYear) =>
      _store.scheduleBlocks.stream.map(
        (all) => all.where((b) => b.schoolYear == schoolYear).toList()
          ..sort((a, b) {
            final byDay = a.dayOfWeek.compareTo(b.dayOfWeek);
            return byDay != 0 ? byDay : a.startMinute.compareTo(b.startMinute);
          }),
      );

  @override
  Future<Result<String>> saveScheduleBlock({
    String? blockId,
    required String subject,
    required String section,
    required String teacherId,
    required String teacherName,
    String? room,
    required int dayOfWeek,
    required int startMinute,
    required int endMinute,
    required String schoolYear,
    String? term,
  }) async {
    final id = blockId ?? 'sched_${DateTime.now().microsecondsSinceEpoch}';
    final candidate = ScheduleBlock(
      id: id,
      subject: subject.trim(),
      section: section.trim(),
      teacherId: teacherId,
      teacherName: teacherName,
      room: room?.trim().isEmpty ?? true ? null : room!.trim(),
      dayOfWeek: dayOfWeek,
      startMinute: startMinute,
      endMinute: endMinute,
      schoolYear: schoolYear,
      term: term,
    );

    final conflicts = findConflicts(
      candidate,
      _store.scheduleBlocks.value.where((b) => b.id != id),
    );
    if (conflicts.isNotEmpty) {
      return Error(ServerFailure(conflicts.map((c) => c.message).join(' ')));
    }

    final all = [..._store.scheduleBlocks.value];
    final index = all.indexWhere((b) => b.id == id);
    if (index >= 0) {
      all[index] = candidate;
    } else {
      all.add(candidate);
    }
    _store.scheduleBlocks.add(all);
    return Success(id);
  }

  @override
  Future<Result<void>> deleteScheduleBlock(String blockId) async {
    _store.scheduleBlocks.add(
      _store.scheduleBlocks.value.where((b) => b.id != blockId).toList(),
    );
    return const Success(null);
  }
}


// ---------------------------------------------------------------------------
// Data protection
// ---------------------------------------------------------------------------

/// The in-memory twin of the data-request collection and the privacy
/// acknowledgement.
///
/// The acknowledgement writes back onto the signed-in user, which is
/// what makes the demo behave like the real thing: the router's gate
/// watches auth state, so the person is let through only once the record
/// actually changed rather than because a screen popped itself.
class DemoDataProtectionRepository implements DataProtectionRepository {
  final DemoStore _store;
  DemoDataProtectionRepository(this._store);

  @override
  Stream<List<DataRequest>> watchRequests() => _store.dataRequests.stream.map(
        (all) => [...all]..sort((a, b) => b.requestedAt.compareTo(a.requestedAt)),
      );

  @override
  Stream<List<DataRequest>> watchMyRequests(String uid) => _store.dataRequests.stream.map(
        (all) => all.where((r) => r.requestedByUid == uid).toList()
          ..sort((a, b) => b.requestedAt.compareTo(a.requestedAt)),
      );

  @override
  Future<Result<String>> raiseRequest({
    required DataRequestKind kind,
    required String details,
    String? studentId,
    String? studentName,
  }) async {
    await _latency();
    final user = _store.requireUser;
    final id = 'dsr_${DateTime.now().microsecondsSinceEpoch}';
    _store.dataRequests.add([
      DataRequest(
        id: id,
        requestedByUid: user.uid,
        requestedByName: user.fullName,
        kind: kind,
        details: details,
        requestedAt: DateTime.now(),
        studentId: studentId,
        studentName: studentName,
      ),
      ..._store.dataRequests.value,
    ]);
    return Success(id);
  }

  @override
  Future<Result<void>> closeRequest({
    required String requestId,
    required DataRequestStatus status,
    required String outcome,
  }) async {
    await _latency();
    final user = _store.requireUser;
    _store.dataRequests.add([
      for (final request in _store.dataRequests.value)
        if (request.id == requestId)
          DataRequest(
            id: request.id,
            requestedByUid: request.requestedByUid,
            requestedByName: request.requestedByName,
            kind: request.kind,
            details: request.details,
            requestedAt: request.requestedAt,
            studentId: request.studentId,
            studentName: request.studentName,
            status: status,
            handledByName: user.fullName,
            handledAt: DateTime.now(),
            outcome: outcome,
          )
        else
          request,
    ]);
    return const Success(null);
  }

  @override
  Future<Result<void>> acknowledgePrivacyNotice(int version) async {
    await _latency();
    final user = _store.currentUser.value;
    if (user == null) return const Error(AuthFailure('no-user', 'Nobody is signed in.'));
    _store.currentUser.add(user.copyWith(privacyNoticeVersion: version));
    // Remembered per account for the life of the process, so switching
    // roles and coming back does not ask the same person twice.
    _store.acknowledgedPrivacy.add({..._store.acknowledgedPrivacy.value, user.uid});
    return const Success(null);
  }
}


// ---------------------------------------------------------------------------
// System check
// ---------------------------------------------------------------------------

/// Reports that nothing was checked.
///
/// The one demo repository that deliberately does not simulate its real
/// counterpart. Every other fake exists so the demo behaves like the
/// app; this one exists so it does not. A preflight that goes green
/// against an in-memory store is a green light that means nothing, shown
/// to the one person who most needs it to mean something -- so demo mode
/// says so and checks nothing at all.
// ---------------------------------------------------------------------------
// Terms of use
// ---------------------------------------------------------------------------

class DemoTermsRepository implements TermsRepository {
  final DemoStore _store;
  DemoTermsRepository(this._store);

  @override
  Future<Result<void>> acceptTerms(int version) async {
    await _latency();
    final user = _store.currentUser.value;
    if (user == null) return const Error(AuthFailure('no-user', 'Nobody is signed in.'));
    _store.currentUser.add(user.copyWith(termsVersion: version));
    // Remembered per account for the life of the process, the same way
    // the privacy acknowledgement is, so switching roles and coming back
    // does not put the page in front of the same person twice.
    _store.acceptedTerms.add({..._store.acceptedTerms.value, user.uid});
    return const Success(null);
  }
}

// ---------------------------------------------------------------------------
// Notifications
// ---------------------------------------------------------------------------

/// The signed-in demo account's own inbox.
///
/// Scoped to whoever is signed in, and re-scoped when the demo switcher
/// changes role, because the whole point of the collection is that one
/// person's notifications are not another's. Switching from the parent
/// to the registrar and seeing the parent's summons would demonstrate
/// the opposite of what the design does.
class DemoNotificationsRepository implements NotificationsRepository {
  final DemoStore _store;
  DemoNotificationsRepository(this._store);

  String? get _uid => _store.currentUser.valueOrNull?.uid;

  @override
  Stream<List<AppNotification>> watch() {
    return _store.notifications.stream.map((inboxes) {
      final uid = _uid;
      if (uid == null) return const <AppNotification>[];
      final mine = [...(inboxes[uid] ?? const <AppNotification>[])];
      mine.sort((a, b) {
        if (a.createdAt == null && b.createdAt == null) return 0;
        if (a.createdAt == null) return -1;
        if (b.createdAt == null) return 1;
        return b.createdAt!.compareTo(a.createdAt!);
      });
      return mine;
    });
  }

  @override
  Future<Result<void>> markRead(String notificationId) async {
    _rewrite((item) => item.id == notificationId ? item.copyWith(isRead: true) : item);
    return const Success(null);
  }

  @override
  Future<Result<void>> markAllRead() async {
    await _latency(150);
    _rewrite((item) => item.copyWith(isRead: true));
    return const Success(null);
  }

  /// Applies [change] to this account's inbox and nobody else's.
  void _rewrite(AppNotification Function(AppNotification) change) {
    final uid = _uid;
    if (uid == null) return;
    final inboxes = {..._store.notifications.value};
    final mine = inboxes[uid];
    if (mine == null) return;
    inboxes[uid] = mine.map(change).toList();
    _store.notifications.add(inboxes);
  }
}

// ---------------------------------------------------------------------------
// School totals
// ---------------------------------------------------------------------------

class DemoSchoolTotalsRepository implements SchoolTotalsRepository {
  final DemoStore _store;
  DemoSchoolTotalsRepository(this._store);

  /// The same list the real datasource uses. A Principal is division
  /// oversight and does not see money, here as there -- a demo that
  /// showed them a balance would be demonstrating a boundary the real
  /// app does not have.
  static const _moneyRoles = {UserRole.director, UserRole.admin, UserRole.registrar};

  @override
  Future<Result<SchoolTotals>> fetch() async {
    await _latency(400);
    final user = _store.requireUser;

    // The demo store has no per-account division scope, so every reader
    // sees the whole school. Said in the entity rather than faked: a
    // division field invented here would demonstrate scoping that this
    // store cannot actually apply.
    final students = _store.students.value;
    final active =
        students.where((s) => s.status == StudentStatus.enrolled).length;

    if (!_moneyRoles.contains(user.role)) {
      return Success(SchoolTotals(activeStudents: active));
    }

    final owing = students.where((s) => s.balance > 0).toList();
    final monthStart = DateTime(_store.now.year, _store.now.month);
    final collected = _store.payments.value
        .where((p) => !p.createdAt.isBefore(monthStart))
        .fold<double>(0, (sum, p) => sum + p.amount);

    return Success(SchoolTotals(
      activeStudents: active,
      outstanding: _round2(owing.fold<double>(0, (sum, s) => sum + s.balance)),
      studentsOwing: owing.length,
      collectedThisMonth: _round2(collected),
    ));
  }
}

class DemoSystemCheckRepository implements SystemCheckRepository {
  DemoSystemCheckRepository();

  @override
  Future<SystemCheckReport> run() async {
    await _latency(400);
    return SystemCheckReport(checks: const [], ranAt: DateTime.now(), demoMode: true);
  }
}
