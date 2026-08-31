import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/location/location_providers.dart';
import '../core/push/push_providers.dart';
import '../core/push/push_registrar.dart';
import '../core/router/app_router.dart';
import '../core/session/session_guard.dart';
import '../core/session/session_providers.dart';
import '../core/storage/upload_providers.dart';
import '../features/auth/domain/entities/app_user.dart';
import '../features/admin_portal/presentation/controllers/admin_controller.dart';
import '../features/audit_trail/presentation/controllers/audit_trail_controller.dart';
import '../features/auth/presentation/controllers/auth_controller.dart';
import '../features/director_portal/presentation/controllers/director_controller.dart';
import '../features/emergency/presentation/controllers/emergency_controller.dart';
import '../features/faculty_portal/presentation/controllers/faculty_controller.dart';
import '../features/guidance_portal/presentation/controllers/guidance_controller.dart';
import '../features/owner_portal/presentation/controllers/owner_controller.dart';
import '../features/parent_portal/presentation/controllers/parent_controller.dart';
import '../features/payments/presentation/controllers/payment_controller.dart';
import '../features/profile/presentation/controllers/profile_controller.dart';
import '../features/qr_attendance/presentation/controllers/qr_attendance_controller.dart';
import '../features/admissions/presentation/controllers/admissions_controller.dart';
import '../features/payroll/presentation/controllers/payroll_controller.dart';
import '../features/registrar_portal/presentation/controllers/registrar_controller.dart';
import '../features/reports/presentation/controllers/reports_controller.dart';
import '../features/schedules/presentation/controllers/schedule_controller.dart';
import '../features/data_protection/presentation/controllers/data_protection_controller.dart';
import '../features/system_check/presentation/controllers/system_check_controller.dart';
import '../features/class_sessions/presentation/controllers/class_session_controller.dart';
import '../features/auth/data/phone/phone_verifier_impl.dart' show DemoPhoneVerifier;
import '../features/auth/presentation/controllers/phone_reset_controller.dart';
import '../features/messaging/presentation/controllers/messaging_controller.dart';
import '../features/notifications/presentation/controllers/notifications_controller.dart';
import '../features/school_totals/presentation/controllers/school_totals_controller.dart';
import '../features/timekeeping/presentation/controllers/timekeeping_controller.dart';
import '../features/staff_portal/presentation/controllers/staff_controller.dart';
import '../features/terms/presentation/controllers/terms_controller.dart';
import '../features/student_portal/presentation/controllers/student_controller.dart';
import 'demo_location_probe.dart';
import 'demo_session.dart';
import 'demo_repositories.dart';
import 'demo_store.dart';

/// The one live [DemoStore] for the process. Exposed as a provider so demo
/// UI (the role switcher) can reach it, and so a widget test could swap it
/// for a differently-seeded one.
final demoStoreProvider = Provider<DemoStore>((ref) {
  final store = DemoStore();
  ref.onDispose(store.dispose);
  return store;
});

final demoAuthRepositoryProvider = Provider<DemoAuthRepository>((ref) {
  return DemoAuthRepository(ref.watch(demoStoreProvider));
});

/// Switches the session to [user] and moves to that role's portal home.
///
/// The navigation is not optional. The router's redirect only routes you
/// to your portal home from an auth screen, because in the real app that
/// is the only way a user ever changes: you log out, then log in. Swapping
/// the signed-in user underneath a live portal route is something only
/// demo mode does, and without the explicit `go` the new role keeps
/// looking at the previous role's dashboard.
void demoSignInAs(DemoAuthRepository auth, GoRouter router, AppUser user) {
  auth.signInAs(user);
  router.go(AppRoutes.homeFor(user.role));
}

/// Swaps every Firestore-backed repository for its in-memory twin.
///
/// Only the repository layer is replaced. Everything above it -- usecases,
/// controllers, routing, and all 200-odd widget files -- runs exactly as it
/// does against real Firebase, which is the point: what you click through
/// in demo mode is the real app, not a mock-up of it. Because nothing ever
/// watches the datasource providers, `Firebase.initializeApp` is never
/// called and no `firebase_options.dart` is needed.
/// [signedInAs] is a session restored from a previous run -- see
/// [DemoSession]. Passed in rather than read here so the store is seeded
/// synchronously: an async restore would render the login screen first
/// and then jump, which looks like being signed out and immediately
/// signed back in.
List<Override> demoOverrides({AppUser? signedInAs}) {
  return [
    if (signedInAs != null)
      demoStoreProvider.overrideWith((ref) {
        final store = DemoStore(signedInAs: signedInAs);
        ref.onDispose(store.dispose);
        return store;
      }),
    authRepositoryProvider.overrideWith((ref) => ref.watch(demoAuthRepositoryProvider)),

    // The real versions of these are rebuilt whenever the signed-in user
    // changes (they stamp the acting user onto every write). The fakes
    // watch authStateProvider for the same reason: it forces every
    // dependent stream provider to re-subscribe on a role switch, so no
    // screen is left showing the previous user's data.
    ownerRepositoryProvider.overrideWith((ref) {
      ref.watch(authStateProvider);
      return DemoOwnerRepository(ref.watch(demoStoreProvider));
    }),
    directorRepositoryProvider.overrideWith((ref) {
      ref.watch(authStateProvider);
      return DemoDirectorRepository(ref.watch(demoStoreProvider));
    }),
    adminRepositoryProvider.overrideWith((ref) {
      ref.watch(authStateProvider);
      return DemoAdminRepository(ref.watch(demoStoreProvider));
    }),
    payrollRepositoryProvider.overrideWith((ref) {
      ref.watch(authStateProvider);
      return DemoPayrollRepository(ref.watch(demoStoreProvider));
    }),
    admissionsRepositoryProvider.overrideWith((ref) {
      ref.watch(authStateProvider);
      return DemoAdmissionsRepository(ref.watch(demoStoreProvider));
    }),
    registrarRepositoryProvider.overrideWith((ref) {
      ref.watch(authStateProvider);
      return DemoRegistrarRepository(ref.watch(demoStoreProvider));
    }),
    // Four, not twenty. The demo school has nine students, and a page
    // size they never reach would leave Load more permanently hidden --
    // paging you cannot see is paging nobody can check.
    studentPageSizeProvider.overrideWith((ref) => 4),
    facultyRepositoryProvider.overrideWith((ref) {
      ref.watch(authStateProvider);
      return DemoFacultyRepository(ref.watch(demoStoreProvider));
    }),
    uploadRepositoryProvider.overrideWith((ref) {
      ref.watch(authStateProvider);
      return DemoUploadRepository(ref.watch(demoStoreProvider));
    }),
    // Demo mode never initialises Firebase, and prompting a stranger's
    // browser for notification permission to look at a demo would be
    // rude even if it worked.
    pushRegistrarProvider.overrideWith((ref) => const NoOpPushRegistrar()),
    // Nothing to enforce: the demo has no Firebase to hold the claim,
    // and one browser tab cannot take a session from itself. Overridden
    // explicitly rather than left to fall through, so switching demo
    // roles never trips the displacement path.
    sessionGuardProvider.overrideWith((ref) => const NoOpSessionGuard()),
    // Never asks the browser for the real thing -- see DemoLocationProbe.
    locationProbeProvider.overrideWith((ref) => const DemoLocationProbe()),
    emergencyRepositoryProvider.overrideWith((ref) {
      ref.watch(authStateProvider);
      return DemoEmergencyRepository(ref.watch(demoStoreProvider));
    }),
    studentRepositoryProvider.overrideWith((ref) {
      ref.watch(authStateProvider);
      return DemoStudentRepository(ref.watch(demoStoreProvider));
    }),
    parentRepositoryProvider.overrideWith((ref) {
      ref.watch(authStateProvider);
      return DemoParentRepository(ref.watch(demoStoreProvider));
    }),
    // Not a simulation of the real one -- see DemoSystemCheckRepository.
    systemCheckRepositoryProvider.overrideWith((ref) => DemoSystemCheckRepository()),
    schoolTotalsRepositoryProvider
        .overrideWith((ref) => DemoSchoolTotalsRepository(ref.watch(demoStoreProvider))),
    // Watches auth as well as the store, so switching demo role re-reads
    // the inbox: notifications belong to a person, and the switcher
    // changes which person this is.
    classSessionRepositoryProvider.overrideWith((ref) {
      ref.watch(authStateProvider);
      return DemoClassSessionRepository(ref.watch(demoStoreProvider));
    }),
    timekeepingRepositoryProvider.overrideWith((ref) {
      ref.watch(authStateProvider);
      return DemoTimekeepingRepository(ref.watch(demoStoreProvider));
    }),
    // No SMS, no Firebase, and the screen says so: a demo that asked
    // for a code nobody can receive is a dead end.
    phoneVerifierProvider.overrideWith((ref) => const DemoPhoneVerifier()),
    messagingRepositoryProvider.overrideWith((ref) {
      ref.watch(authStateProvider);
      return DemoMessagingRepository(ref.watch(demoStoreProvider));
    }),
    notificationsRepositoryProvider.overrideWith((ref) {
      ref.watch(authStateProvider);
      return DemoNotificationsRepository(ref.watch(demoStoreProvider));
    }),
    termsRepositoryProvider
        .overrideWith((ref) => DemoTermsRepository(ref.watch(demoStoreProvider))),
    dataProtectionRepositoryProvider.overrideWith((ref) {
      ref.watch(authStateProvider);
      return DemoDataProtectionRepository(ref.watch(demoStoreProvider));
    }),
    scheduleRepositoryProvider.overrideWith((ref) {
      ref.watch(authStateProvider);
      return DemoScheduleRepository(ref.watch(demoStoreProvider));
    }),
    reportsRepositoryProvider.overrideWith((ref) {
      ref.watch(authStateProvider);
      return DemoReportsRepository(ref.watch(demoStoreProvider));
    }),
    paymentRepositoryProvider.overrideWith((ref) {
      ref.watch(authStateProvider);
      return DemoPaymentRepository(ref.watch(demoStoreProvider));
    }),
    qrAttendanceRepositoryProvider.overrideWith((ref) {
      ref.watch(authStateProvider);
      return DemoQrAttendanceRepository(ref.watch(demoStoreProvider));
    }),
    staffRepositoryProvider.overrideWith((ref) {
      ref.watch(authStateProvider);
      return DemoStaffRepository(ref.watch(demoStoreProvider));
    }),
    guidanceRepositoryProvider.overrideWith((ref) {
      ref.watch(authStateProvider);
      return DemoGuidanceRepository(ref.watch(demoStoreProvider));
    }),
    profileRepositoryProvider.overrideWith((ref) {
      ref.watch(authStateProvider);
      return DemoProfileRepository(ref.watch(demoStoreProvider));
    }),
    auditTrailRepositoryProvider.overrideWith((ref) {
      ref.watch(authStateProvider);
      return DemoAuditTrailRepository(ref.watch(demoStoreProvider));
    }),
  ];
}
