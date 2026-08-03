import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/push/push_providers.dart';
import '../core/push/push_registrar.dart';
import '../core/router/app_router.dart';
import '../core/storage/upload_providers.dart';
import '../features/auth/domain/entities/app_user.dart';
import '../features/admin_portal/presentation/controllers/admin_controller.dart';
import '../features/audit_trail/presentation/controllers/audit_trail_controller.dart';
import '../features/auth/presentation/controllers/auth_controller.dart';
import '../features/director_portal/presentation/controllers/director_controller.dart';
import '../features/faculty_portal/presentation/controllers/faculty_controller.dart';
import '../features/guidance_portal/presentation/controllers/guidance_controller.dart';
import '../features/owner_portal/presentation/controllers/owner_controller.dart';
import '../features/parent_portal/presentation/controllers/parent_controller.dart';
import '../features/payments/presentation/controllers/payment_controller.dart';
import '../features/profile/presentation/controllers/profile_controller.dart';
import '../features/qr_attendance/presentation/controllers/qr_attendance_controller.dart';
import '../features/registrar_portal/presentation/controllers/registrar_controller.dart';
import '../features/staff_portal/presentation/controllers/staff_controller.dart';
import '../features/student_portal/presentation/controllers/student_controller.dart';
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
List<Override> demoOverrides() {
  return [
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
    registrarRepositoryProvider.overrideWith((ref) {
      ref.watch(authStateProvider);
      return DemoRegistrarRepository(ref.watch(demoStoreProvider));
    }),
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
    studentRepositoryProvider.overrideWith((ref) {
      ref.watch(authStateProvider);
      return DemoStudentRepository(ref.watch(demoStoreProvider));
    }),
    parentRepositoryProvider.overrideWith((ref) {
      ref.watch(authStateProvider);
      return DemoParentRepository(ref.watch(demoStoreProvider));
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
