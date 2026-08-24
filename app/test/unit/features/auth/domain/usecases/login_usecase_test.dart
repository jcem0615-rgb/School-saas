import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:logicclass/core/constants/user_roles.dart';
import 'package:logicclass/core/errors/failures.dart';
import 'package:logicclass/core/errors/result.dart';
import 'package:logicclass/features/auth/domain/entities/app_user.dart';
import 'package:logicclass/features/auth/domain/repositories/auth_repository.dart';
import 'package:logicclass/features/auth/domain/usecases/login_usecase.dart';

class MockAuthRepository extends Mock implements AuthRepository {}

void main() {
  late MockAuthRepository repository;
  late LoginUseCase useCase;

  final testUser = AppUser(
    uid: 'uid_1',
    schoolId: 'school_1',
    role: UserRole.registrar,
    firstName: 'Jane',
    lastName: 'Cruz',
    email: 'jane@school.edu.ph',
    status: UserAccountStatus.active,
    mustChangePassword: false,
    qrCode: 'qr_token_abc',
  );

  setUp(() {
    repository = MockAuthRepository();
    useCase = LoginUseCase(repository);
  });

  group('LoginUseCase', () {
    test('returns ValidationFailure without hitting the repository when email is invalid',
        () async {
      final result = await useCase(email: 'not-an-email', password: 'somepassword1');

      expect(result, isA<Error<AppUser>>());
      expect((result as Error<AppUser>).failure, isA<ValidationFailure>());
      verifyNever(() => repository.login(email: any(named: 'email'), password: any(named: 'password')));
    });

    test('returns ValidationFailure when password is empty', () async {
      final result = await useCase(email: 'jane@school.edu.ph', password: '');

      expect(result, isA<Error<AppUser>>());
      expect((result as Error<AppUser>).failure, isA<ValidationFailure>());
      verifyNever(() => repository.login(email: any(named: 'email'), password: any(named: 'password')));
    });

    test('trims email and delegates to repository.login on valid input', () async {
      when(() => repository.login(email: 'jane@school.edu.ph', password: 'somepassword1'))
          .thenAnswer((_) async => Success(testUser));

      final result = await useCase(email: '  jane@school.edu.ph  ', password: 'somepassword1');

      expect(result, isA<Success<AppUser>>());
      expect((result as Success<AppUser>).value, testUser);
      verify(() => repository.login(email: 'jane@school.edu.ph', password: 'somepassword1')).called(1);
    });

    test('propagates AuthFailure from the repository unchanged', () async {
      when(() => repository.login(email: any(named: 'email'), password: any(named: 'password')))
          .thenAnswer((_) async => const Error(AuthFailure('wrong-password', 'Incorrect email or password.')));

      final result = await useCase(email: 'jane@school.edu.ph', password: 'wrongpass1');

      expect(result, isA<Error<AppUser>>());
      expect((result as Error<AppUser>).failure, isA<AuthFailure>());
    });
  });
}
