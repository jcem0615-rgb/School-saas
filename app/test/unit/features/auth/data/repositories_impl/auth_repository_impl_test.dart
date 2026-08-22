import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:logicclass/core/constants/user_roles.dart';
import 'package:logicclass/core/errors/app_exceptions.dart';
import 'package:logicclass/core/errors/failures.dart';
import 'package:logicclass/core/errors/result.dart';
import 'package:logicclass/features/auth/data/datasources/auth_remote_datasource.dart';
import 'package:logicclass/features/auth/data/models/app_user_model.dart';
import 'package:logicclass/features/auth/data/repositories_impl/auth_repository_impl.dart';

class MockAuthRemoteDataSource extends Mock implements AuthRemoteDataSource {}

void main() {
  late MockAuthRemoteDataSource dataSource;
  late AuthRepositoryImpl repository;

  final testModel = AppUserModel(
    uid: 'uid_1',
    schoolId: 'school_1',
    role: UserRole.faculty,
    firstName: 'Mark',
    lastName: 'Santos',
    email: 'mark@school.edu.ph',
    status: UserAccountStatus.active,
    mustChangePassword: false,
    qrCode: 'qr_token_xyz',
  );

  setUp(() {
    dataSource = MockAuthRemoteDataSource();
    repository = AuthRepositoryImpl(dataSource);
  });

  group('login', () {
    test('maps AuthException to AuthFailure carrying the original code', () async {
      when(() => dataSource.login(email: any(named: 'email'), password: any(named: 'password')))
          .thenThrow(const AuthException('wrong-password', 'Incorrect email or password.'));

      final result = await repository.login(email: 'mark@school.edu.ph', password: 'badpass1');

      expect(result, isA<Error>());
      final failure = (result as Error).failure;
      expect(failure, isA<AuthFailure>());
      expect((failure as AuthFailure).code, 'wrong-password');
    });

    test('maps NotFoundException to ServerFailure', () async {
      when(() => dataSource.login(email: any(named: 'email'), password: any(named: 'password')))
          .thenThrow(const NotFoundException('User profile not found.'));

      final result = await repository.login(email: 'mark@school.edu.ph', password: 'somepass1');

      expect((result as Error).failure, isA<ServerFailure>());
    });

    test('maps unexpected exceptions to UnknownFailure rather than rethrowing', () async {
      when(() => dataSource.login(email: any(named: 'email'), password: any(named: 'password')))
          .thenThrow(StateError('unexpected'));

      final result = await repository.login(email: 'mark@school.edu.ph', password: 'somepass1');

      expect((result as Error).failure, isA<UnknownFailure>());
    });

    test('returns Success with the mapped user on the happy path', () async {
      when(() => dataSource.login(email: any(named: 'email'), password: any(named: 'password')))
          .thenAnswer((_) async => testModel);

      final result = await repository.login(email: 'mark@school.edu.ph', password: 'goodpass1');

      expect(result, isA<Success>());
      expect((result as Success).value, testModel);
    });
  });

  group('clearForcePasswordChangeFlag', () {
    test('maps ServerException to ServerFailure', () async {
      when(() => dataSource.clearForcePasswordChangeFlag())
          .thenThrow(const ServerException('Internal error.'));

      final result = await repository.clearForcePasswordChangeFlag();

      expect((result as Error).failure, isA<ServerFailure>());
    });
  });
}
