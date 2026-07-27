import '../entities/app_user.dart';
import '../repositories/auth_repository.dart';

class WatchAuthStateUseCase {
  final AuthRepository _repository;
  const WatchAuthStateUseCase(this._repository);

  Stream<AppUser?> call() => _repository.watchAuthState();
}
