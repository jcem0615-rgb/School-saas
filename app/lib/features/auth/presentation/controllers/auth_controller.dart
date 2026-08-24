import '../../../../core/push/push_providers.dart';
import '../../../../core/push/push_registrar.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/result.dart';
import '../../data/datasources/auth_remote_datasource.dart';
import '../../data/repositories_impl/auth_repository_impl.dart';
import '../../domain/entities/app_user.dart';
import '../../domain/repositories/auth_repository.dart';
import '../../domain/usecases/change_password_usecase.dart';
import '../../domain/usecases/forgot_password_usecase.dart';
import '../../domain/usecases/login_usecase.dart';
import '../../domain/usecases/logout_usecase.dart';
import '../../domain/usecases/watch_auth_state_usecase.dart';

// ---------------------------------------------------------------------------
// Firebase SDK instance providers. Centralized here (not scattered as
// FirebaseAuth.instance calls) so tests can override them with fakes.
// ---------------------------------------------------------------------------

final firebaseAuthProvider = Provider<fb_auth.FirebaseAuth>((ref) {
  return fb_auth.FirebaseAuth.instance;
});

final firestoreProvider = Provider<FirebaseFirestore>((ref) {
  return FirebaseFirestore.instance;
});

final firebaseFunctionsProvider = Provider<FirebaseFunctions>((ref) {
  // asia-southeast1 keeps latency low for a PH-based user base and is the
  // region all callable/scheduled functions in this project deploy to.
  return FirebaseFunctions.instanceFor(region: 'asia-southeast1');
});

// ---------------------------------------------------------------------------
// Dependency injection chain: datasource -> repository -> usecases.
// ---------------------------------------------------------------------------

final authRemoteDataSourceProvider = Provider<AuthRemoteDataSource>((ref) {
  return AuthRemoteDataSource(
    auth: ref.watch(firebaseAuthProvider),
    firestore: ref.watch(firestoreProvider),
    functions: ref.watch(firebaseFunctionsProvider),
  );
});

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepositoryImpl(ref.watch(authRemoteDataSourceProvider));
});

final loginUseCaseProvider = Provider((ref) => LoginUseCase(ref.watch(authRepositoryProvider)));
final logoutUseCaseProvider = Provider((ref) => LogoutUseCase(ref.watch(authRepositoryProvider)));
final forgotPasswordUseCaseProvider =
    Provider((ref) => ForgotPasswordUseCase(ref.watch(authRepositoryProvider)));
final changePasswordUseCaseProvider =
    Provider((ref) => ChangePasswordUseCase(ref.watch(authRepositoryProvider)));
final watchAuthStateUseCaseProvider =
    Provider((ref) => WatchAuthStateUseCase(ref.watch(authRepositoryProvider)));

// ---------------------------------------------------------------------------
// App-wide auth state stream. The router (app_router.dart) watches this to
// decide login / force-password-change / role-home redirects.
// ---------------------------------------------------------------------------

final authStateProvider = StreamProvider<AppUser?>((ref) {
  return ref.watch(watchAuthStateUseCaseProvider)();
});

// ---------------------------------------------------------------------------
// AuthController: drives the login / forgot-password / change-password
// screens. Exposes an AsyncValue<void> so screens can show loading/error
// state without each screen re-implementing try/catch around the usecases.
// ---------------------------------------------------------------------------

class AuthController extends StateNotifier<AsyncValue<void>> {
  // `mounted` guards below: these action controllers are autoDispose, and
  // the repositories they depend on rebuild whenever authStateProvider
  // emits. If that lands while a write is in flight the notifier is gone
  // by the time the result returns, and assigning `state` then throws
  // "used after dispose" -- which surfaces as an action that silently does
  // nothing even though the write succeeded.
  final LoginUseCase _login;
  final LogoutUseCase _logout;
  final ForgotPasswordUseCase _forgotPassword;
  final ChangePasswordUseCase _changePassword;
  final PushRegistrar _pushRegistrar;

  AuthController({
    required LoginUseCase login,
    required LogoutUseCase logout,
    required ForgotPasswordUseCase forgotPassword,
    required ChangePasswordUseCase changePassword,
    required PushRegistrar pushRegistrar,
  })  : _login = login,
        _logout = logout,
        _forgotPassword = forgotPassword,
        _changePassword = changePassword,
        _pushRegistrar = pushRegistrar,
        super(const AsyncData(null));

  /// Returns true on success so the screen can navigate; the router will
  /// also react to authStateProvider, but returning a bool lets the screen
  /// show an immediate transition without waiting an extra stream tick.
  Future<bool> login({required String email, required String password}) async {
    if (mounted) state = const AsyncLoading();
    final result = await _login(email: email, password: password);
    return switch (result) {
      Success() => _succeed(),
      Error(:final failure) => _fail(failure.message),
    };
  }

  Future<bool> logout() async {
    if (mounted) state = const AsyncLoading();
    // Before the sign-out, while the registrar is still scoped to this
    // user: school computers get shared, and the next person to sign in
    // must not keep receiving the last person's announcements.
    //
    // Guarded here rather than relying on the implementation to swallow
    // its own errors. Failing to tidy up a token is not a reason to leave
    // somebody signed in on a shared machine -- that is the worse of the
    // two outcomes by a wide margin.
    try {
      await _pushRegistrar.unregister();
    } catch (_) {
      // Deliberately ignored; see above.
    }
    final result = await _logout();
    return switch (result) {
      Success() => _succeed(),
      Error(:final failure) => _fail(failure.message),
    };
  }

  Future<bool> sendPasswordResetEmail(String email) async {
    if (mounted) state = const AsyncLoading();
    final result = await _forgotPassword(email);
    return switch (result) {
      Success() => _succeed(),
      Error(:final failure) => _fail(failure.message),
    };
  }

  Future<bool> changePassword({
    required String currentPassword,
    required String newPassword,
    required String confirmPassword,
  }) async {
    if (mounted) state = const AsyncLoading();
    final result = await _changePassword(
      currentPassword: currentPassword,
      newPassword: newPassword,
      confirmPassword: confirmPassword,
    );
    return switch (result) {
      Success() => _succeed(),
      Error(:final failure) => _fail(failure.message),
    };
  }

  bool _succeed() {
    if (mounted) state = const AsyncData(null);
    return true;
  }

  bool _fail(String message) {
    if (mounted) state = AsyncError(message, StackTrace.current);
    return false;
  }
}

final authControllerProvider = StateNotifierProvider<AuthController, AsyncValue<void>>((ref) {
  return AuthController(
    login: ref.watch(loginUseCaseProvider),
    logout: ref.watch(logoutUseCaseProvider),
    forgotPassword: ref.watch(forgotPasswordUseCaseProvider),
    changePassword: ref.watch(changePasswordUseCaseProvider),
    pushRegistrar: ref.watch(pushRegistrarProvider),
  );
});
