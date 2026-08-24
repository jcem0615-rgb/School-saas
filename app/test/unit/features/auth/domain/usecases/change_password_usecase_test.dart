import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:logicclass/core/errors/failures.dart';
import 'package:logicclass/core/errors/result.dart';
import 'package:logicclass/features/auth/domain/repositories/auth_repository.dart';
import 'package:logicclass/features/auth/domain/usecases/change_password_usecase.dart';

class MockAuthRepository extends Mock implements AuthRepository {}

void main() {
  late MockAuthRepository repository;
  late ChangePasswordUseCase useCase;

  setUp(() {
    repository = MockAuthRepository();
    useCase = ChangePasswordUseCase(repository);
  });

  group('ChangePasswordUseCase', () {
    test('rejects weak passwords before calling the repository', () async {
      final result = await useCase(
        currentPassword: 'oldpass1',
        newPassword: 'weak',
        confirmPassword: 'weak',
      );

      expect(result, isA<Error<void>>());
      expect((result as Error<void>).failure, isA<ValidationFailure>());
      verifyNever(() => repository.changePassword(
          currentPassword: any(named: 'currentPassword'), newPassword: any(named: 'newPassword')));
    });

    test('rejects mismatched confirmation', () async {
      final result = await useCase(
        currentPassword: 'oldpass1',
        newPassword: 'newpassword1',
        confirmPassword: 'different1',
      );

      expect(result, isA<Error<void>>());
      expect((result as Error<void>).failure, isA<ValidationFailure>());
    });

    test('rejects new password identical to current password', () async {
      final result = await useCase(
        currentPassword: 'samepassword1',
        newPassword: 'samepassword1',
        confirmPassword: 'samepassword1',
      );

      expect(result, isA<Error<void>>());
      expect((result as Error<void>).failure, isA<ValidationFailure>());
    });

    test('on success, calls changePassword then clearForcePasswordChangeFlag in order', () async {
      when(() => repository.changePassword(
            currentPassword: 'oldpassword1',
            newPassword: 'newpassword1',
          )).thenAnswer((_) async => const Success(null));
      when(() => repository.clearForcePasswordChangeFlag())
          .thenAnswer((_) async => const Success(null));

      final result = await useCase(
        currentPassword: 'oldpassword1',
        newPassword: 'newpassword1',
        confirmPassword: 'newpassword1',
      );

      expect(result, isA<Success<void>>());
      verifyInOrder([
        () => repository.changePassword(currentPassword: 'oldpassword1', newPassword: 'newpassword1'),
        () => repository.clearForcePasswordChangeFlag(),
      ]);
    });

    test('does NOT call clearForcePasswordChangeFlag if changePassword itself fails', () async {
      when(() => repository.changePassword(
            currentPassword: any(named: 'currentPassword'),
            newPassword: any(named: 'newPassword'),
          )).thenAnswer((_) async => const Error(AuthFailure('requires-recent-login', 'Please sign in again.')));

      final result = await useCase(
        currentPassword: 'oldpassword1',
        newPassword: 'newpassword1',
        confirmPassword: 'newpassword1',
      );

      expect(result, isA<Error<void>>());
      verifyNever(() => repository.clearForcePasswordChangeFlag());
    });
  });
}
