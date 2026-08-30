import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/domain/entities/app_user.dart';
import '../../features/auth/presentation/controllers/auth_controller.dart';
import '../../features/auth/presentation/screens/force_password_change_screen.dart';
import '../../features/auth/presentation/screens/login_screen.dart';
import '../../features/admin_portal/presentation/screens/admin_dashboard_screen.dart';
import '../../features/audit_trail/presentation/screens/audit_trail_screen.dart';
import '../../features/audit_trail/presentation/screens/my_activity_screen.dart';
import '../../features/data_protection/presentation/controllers/data_protection_controller.dart'
    show needsPrivacyAcknowledgementProvider;
import '../../features/data_protection/presentation/screens/acknowledge_privacy_screen.dart';
import '../../features/terms/presentation/controllers/terms_controller.dart';
import '../../features/terms/presentation/screens/accept_terms_screen.dart';
import '../../features/data_protection/presentation/screens/privacy_notice_screen.dart';
import '../../features/director_portal/presentation/screens/director_dashboard_screen.dart';
import '../../features/faculty_portal/presentation/screens/faculty_dashboard_screen.dart';
import '../../features/guidance_portal/presentation/screens/guidance_dashboard_screen.dart';
import '../../features/owner_portal/presentation/screens/owner_dashboard_screen.dart';
import '../../features/owner_portal/presentation/screens/school_detail_screen.dart';
import '../../features/parent_portal/presentation/screens/parent_dashboard_screen.dart';
import '../../features/payments/presentation/screens/payment_history_screen.dart';
import '../../features/payments/presentation/screens/record_payment_screen.dart';
import '../../features/principal_portal/presentation/screens/principal_dashboard_screen.dart';
import '../../features/notifications/presentation/screens/notifications_screen.dart';
import '../../features/profile/presentation/screens/profile_screen.dart';
import '../../features/qr_attendance/presentation/screens/attendance_history_screen.dart';
import '../../features/qr_attendance/presentation/screens/e_id_screen.dart';
import '../../features/qr_attendance/presentation/screens/qr_scanner_screen.dart';
import '../../features/registrar_portal/presentation/screens/registrar_dashboard_screen.dart';
import '../../features/reports/presentation/screens/reports_screen.dart';
import '../../features/staff_portal/presentation/screens/staff_dashboard_screen.dart';
import '../../features/system_check/presentation/screens/system_check_screen.dart';
import '../../features/student_portal/presentation/screens/student_dashboard_screen.dart';
import '../constants/user_roles.dart';

/// Central route table + auth guard. Every portal module registers its
/// routes here (added incrementally as each portal module is built);
/// this file owns only the auth-gating logic that applies to all of them.
class AppRoutes {
  static const login = '/login';
  static const forcePasswordChange = '/force-password-change';
  static const myQrId = '/qr-id';
  static const scanAttendance = '/scan-attendance';
  static const myAttendance = '/my-attendance';
  static const myActivity = '/my-activity';
  static const auditTrail = '/audit-trail';
  static const reports = '/reports';
  static const privacy = '/privacy';
  static const systemCheck = '/system-check';
  static const acknowledgePrivacy = '/privacy/acknowledge';
  static const acceptTerms = '/terms/accept';
  static const profile = '/profile';
  static const notifications = '/notifications';
  static const recordPayment = '/payments/record';
  static const paymentHistory = '/payments/history';
  static const ownerHome = '/owner';
  static const directorHome = '/director';
  static const principalHome = '/principal';
  static const adminHome = '/admin';
  static const registrarHome = '/registrar';
  static const facultyHome = '/faculty';
  static const staffHome = '/staff';
  static const guidanceHome = '/guidance';
  static const studentHome = '/student';
  static const parentHome = '/parent';

  /// Maps each role to its portal's landing route. Used both by the
  /// redirect logic below and by any "go home" action elsewhere in the app.
  static String homeFor(UserRole role) => switch (role) {
        UserRole.owner => ownerHome,
        UserRole.director => directorHome,
        UserRole.principal => principalHome,
        UserRole.admin => adminHome,
        UserRole.registrar => registrarHome,
        UserRole.faculty => facultyHome,
        UserRole.staff => staffHome,
        UserRole.guidance => guidanceHome,
        UserRole.student => studentHome,
        UserRole.parent => parentHome,
      };
}

final goRouterProvider = Provider<GoRouter>((ref) {
  // Re-evaluate redirects any time auth state changes, not just on
  // navigation -- otherwise a background sign-out wouldn't kick the user
  // back to /login until they next tapped something.
  final authStateStream = ref.watch(authStateProvider.stream);
  final refreshListenable = GoRouterRefreshStream(authStateStream);
  ref.onDispose(refreshListenable.dispose);

  return GoRouter(
    initialLocation: AppRoutes.login,
    refreshListenable: refreshListenable,
    redirect: (context, state) {
      final authState = ref.read(authStateProvider);

      // Auth state still resolving (app just launched) -- stay put, the
      // splash/loading UI is handled by whatever widget wraps MaterialApp.
      if (authState.isLoading) return null;

      final AppUser? user = authState.valueOrNull;
      final loggingIn = state.matchedLocation == AppRoutes.login;

      if (user == null) {
        return loggingIn ? null : AppRoutes.login;
      }

      // Signed in but must change password: lock to that screen until done.
      if (user.mustChangePassword) {
        return state.matchedLocation == AppRoutes.forcePasswordChange
            ? null
            : AppRoutes.forcePasswordChange;
      }

      // Signed in, password OK, but has not been shown the current
      // privacy notice. Gated in the same place as the password change
      // and for the same reason: a notice somebody could navigate past
      // is one the school cannot say was given.
      //
      // Owner is exempt. They are the platform operator rather than
      // somebody whose personal data the school processes, and there is
      // no school branding to name a Data Protection Officer from.
      if (user.role != UserRole.owner && ref.read(needsPrivacyAcknowledgementProvider)) {
        return state.matchedLocation == AppRoutes.acknowledgePrivacy
            ? null
            : AppRoutes.acknowledgePrivacy;
      }

      // Then the terms, in that order. The notice explains what is held
      // about them; the terms ask them to agree to something. Being told
      // before being asked is the only sequence that makes sense, and it
      // is also the one where the terms can point at the notice as
      // already read.
      //
      // Owner is exempt for the same reason: these are terms a school
      // issues to its people, and the platform operator is not one of
      // them.
      if (user.role != UserRole.owner && ref.read(needsTermsAcceptanceProvider)) {
        return state.matchedLocation == AppRoutes.acceptTerms
            ? null
            : AppRoutes.acceptTerms;
      }

      // Signed in, password OK, but sitting on an auth screen -- send them
      // to their portal home.
      if (loggingIn ||
          state.matchedLocation == AppRoutes.forcePasswordChange ||
          state.matchedLocation == AppRoutes.acknowledgePrivacy ||
          state.matchedLocation == AppRoutes.acceptTerms) {
        return AppRoutes.homeFor(user.role);
      }

      // Two Director/Admin surfaces. Reports is on this list for a
      // rules reason rather than a product one: those are the only roles
      // with an unconditional read on students, payments, grades and
      // attendance, and a school-wide list query from any other account
      // is refused per document. Every other role still has
      // /my-activity, which is scoped to their own uid.
      if ((state.matchedLocation == AppRoutes.auditTrail ||
              state.matchedLocation == AppRoutes.reports ||
              state.matchedLocation == AppRoutes.systemCheck) &&
          user.role != UserRole.director &&
          user.role != UserRole.admin) {
        return AppRoutes.homeFor(user.role);
      }

      return null; // no redirect needed
    },
    routes: [
      GoRoute(path: AppRoutes.login, builder: (context, state) => const LoginScreen()),
      GoRoute(
        path: AppRoutes.forcePasswordChange,
        builder: (context, state) => const ForcePasswordChangeScreen(),
      ),
      // Shared across every role -- spec requires a QR ID and attendance
      // history for every user type. The scanner route is reachable by
      // any signed-in user at the routing layer; actual authorization is
      // enforced server-side in markAttendance.ts (defense in depth: the
      // route existing is not the same as the action being permitted).
      GoRoute(path: AppRoutes.myQrId, builder: (context, state) => const EIdScreen()),
      GoRoute(path: AppRoutes.scanAttendance, builder: (context, state) => const QrScannerScreen()),
      GoRoute(path: AppRoutes.myActivity, builder: (context, state) => const MyActivityScreen()),
      // School-wide audit trail. firestore.rules lets owner/director/admin
      // read the log, but Owner is platform-level with no schoolId, and
      // this screen is tenant-scoped -- so Director/Admin only, and the
      // redirect below sends anyone else back to their own portal rather
      // than rendering a screen whose queries would be denied.
      GoRoute(path: AppRoutes.auditTrail, builder: (context, state) => const AuditTrailScreen()),
      GoRoute(path: AppRoutes.profile, builder: (context, state) => const ProfileScreen()),
      // Reachable from the bell in every portal's app bar, and from a
      // tapped push notification -- deliver.ts sends every one of them
      // here, because a link to a screen that only exists for one role
      // is a link that breaks for everybody else.
      GoRoute(
        path: AppRoutes.notifications,
        builder: (context, state) => const NotificationsScreen(),
      ),
      GoRoute(path: AppRoutes.reports, builder: (context, state) => const ReportsScreen()),
      GoRoute(path: AppRoutes.privacy, builder: (context, state) => const PrivacyNoticeScreen()),
      GoRoute(
        path: AppRoutes.systemCheck,
        builder: (context, state) => const SystemCheckScreen(),
      ),
      GoRoute(
        path: AppRoutes.acknowledgePrivacy,
        builder: (context, state) => const AcknowledgePrivacyScreen(),
      ),
      GoRoute(
        path: AppRoutes.acceptTerms,
        builder: (context, state) => const AcceptTermsScreen(),
      ),
      GoRoute(
        path: AppRoutes.myAttendance,
        builder: (context, state) {
          final uid = ref.read(authStateProvider).valueOrNull?.uid ?? '';
          return AttendanceHistoryScreen(personId: uid, title: 'My Attendance');
        },
      ),
      GoRoute(
        path: AppRoutes.recordPayment,
        builder: (context, state) => const RecordPaymentScreen(),
      ),
      GoRoute(
        path: '${AppRoutes.paymentHistory}/:studentId',
        builder: (context, state) {
          final user = ref.read(authStateProvider).valueOrNull;
          // Only collector/refund-capable roles see the refund action;
          // everyone else (Student viewing their own, Parent viewing a
          // child's) gets a read-only history -- Firestore rules are the
          // real enforcement boundary, this only controls whether the
          // button renders.
          final allowRefunds = user != null &&
              (user.role == UserRole.director || user.role == UserRole.admin);
          return PaymentHistoryScreen(
            studentId: state.pathParameters['studentId']!,
            allowRefunds: allowRefunds,
          );
        },
      ),
      // Portal home routes (placeholder builders) are registered here as
      // each portal module is implemented. Each portal module also nests
      // its own sub-routes under its home path.
      GoRoute(
        path: AppRoutes.ownerHome,
        builder: (context, state) => const OwnerDashboardScreen(),
        routes: [
          GoRoute(
            path: 'schools/:schoolId',
            builder: (context, state) =>
                SchoolDetailScreen(schoolId: state.pathParameters['schoolId']!),
          ),
        ],
      ),
      GoRoute(
        path: AppRoutes.directorHome,
        builder: (context, state) => const DirectorDashboardScreen(),
      ),
      GoRoute(
        path: AppRoutes.principalHome,
        builder: (context, state) => const PrincipalDashboardScreen(),
      ),
      GoRoute(
        path: AppRoutes.adminHome,
        builder: (context, state) => const AdminDashboardScreen(),
      ),
      GoRoute(
        path: AppRoutes.registrarHome,
        builder: (context, state) => const RegistrarDashboardScreen(),
      ),
      GoRoute(
        path: AppRoutes.staffHome,
        builder: (context, state) => const StaffDashboardScreen(),
      ),
      GoRoute(
        path: AppRoutes.facultyHome,
        builder: (context, state) => const FacultyDashboardScreen(),
      ),
      GoRoute(
        path: AppRoutes.guidanceHome,
        builder: (context, state) => const GuidanceDashboardScreen(),
      ),
      GoRoute(
        path: AppRoutes.studentHome,
        builder: (context, state) => const StudentDashboardScreen(),
      ),
      GoRoute(
        path: AppRoutes.parentHome,
        builder: (context, state) => const ParentDashboardScreen(),
      ),
    ],
  );
});

/// Bridges a Riverpod stream to go_router's Listenable-based refresh API.
class GoRouterRefreshStream extends ChangeNotifier {
  late final Stream<dynamic> _subscriptionSource;
  GoRouterRefreshStream(Stream<dynamic> stream) {
    _subscriptionSource = stream.asBroadcastStream();
    _subscriptionSource.listen((_) => notifyListeners());
  }
}
