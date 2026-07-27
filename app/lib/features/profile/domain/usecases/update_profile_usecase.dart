import '../../../../core/errors/result.dart';
import '../repositories/profile_repository.dart';

class UpdateProfileUseCase {
  final ProfileRepository _repository;
  const UpdateProfileUseCase(this._repository);

  Future<Result<void>> call({String? phone, String? photoUrl}) =>
      _repository.updateProfile(phone: phone, photoUrl: photoUrl);
}
