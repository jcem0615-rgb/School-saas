import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:school_saas/core/errors/result.dart';
import 'package:school_saas/core/push/push_registrar.dart';
import 'package:school_saas/features/auth/domain/usecases/change_password_usecase.dart';
import 'package:school_saas/features/auth/domain/usecases/forgot_password_usecase.dart';
import 'package:school_saas/features/auth/domain/usecases/login_usecase.dart';
import 'package:school_saas/features/auth/domain/usecases/logout_usecase.dart';
import 'package:school_saas/features/auth/presentation/controllers/auth_controller.dart';

class _MockLogin extends Mock implements LoginUseCase {}

class _MockLogout extends Mock implements LogoutUseCase {}

class _MockForgot extends Mock implements ForgotPasswordUseCase {}

class _MockChangePassword extends Mock implements ChangePasswordUseCase {}

class _SpyPushRegistrar implements PushRegistrar {
  int unregisterCalls = 0;
  bool throwOnUnregister = false;

  @override
  Future<bool> register() async => true;

  @override
  Future<void> unregister() async {
    unregisterCalls++;
    if (throwOnUnregister) throw StateError('token cleanup failed');
  }

  @override
  Future<bool> isRegistered() async => true;
}

/// School computers get shared. If signing out leaves the device token
/// attached to the account that just left, the next person to use that
/// browser starts receiving someone else's announcements -- including the
/// staff-only ones, on a machine a student is now sitting at.
void main() {
  late _MockLogout logout;
  late _SpyPushRegistrar push;

  AuthController build() => AuthController(
        login: _MockLogin(),
        logout: logout,
        forgotPassword: _MockForgot(),
        changePassword: _MockChangePassword(),
        pushRegistrar: push,
      );

  setUp(() {
    logout = _MockLogout();
    push = _SpyPushRegistrar();
    when(() => logout()).thenAnswer((_) async => const Success(null));
  });

  test('signing out forgets this device', () async {
    final controller = build();

    await controller.logout();

    expect(push.unregisterCalls, 1);
  });

  test('a failed token cleanup does not block the sign-out', () async {
    // Being unable to tidy up a token is not a reason to keep somebody
    // signed in on a shared machine -- that is the worse of the two
    // outcomes by a wide margin.
    push.throwOnUnregister = true;
    final controller = build();

    await expectLater(controller.logout(), completes);
    verify(() => logout()).called(1);
  });
}
