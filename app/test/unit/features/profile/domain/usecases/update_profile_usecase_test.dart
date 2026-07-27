import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:school_saas/core/errors/result.dart';
import 'package:school_saas/features/profile/domain/repositories/profile_repository.dart';
import 'package:school_saas/features/profile/domain/usecases/update_profile_usecase.dart';

class MockProfileRepository extends Mock implements ProfileRepository {}

void main() {
  test('UpdateProfileUseCase delegates phone/photoUrl to the repository unchanged', () async {
    final repository = MockProfileRepository();
    when(() => repository.updateProfile(phone: '0900000000', photoUrl: null))
        .thenAnswer((_) async => const Success(null));

    final useCase = UpdateProfileUseCase(repository);
    final result = await useCase(phone: '0900000000');

    expect(result, isA<Success<void>>());
    verify(() => repository.updateProfile(phone: '0900000000', photoUrl: null)).called(1);
  });
}
