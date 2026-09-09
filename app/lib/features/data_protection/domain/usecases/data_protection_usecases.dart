import '../../../../core/errors/result.dart';
import '../repositories/data_protection_repository.dart';

class AcknowledgePrivacyNoticeUseCase {
  final DataProtectionRepository _repository;
  const AcknowledgePrivacyNoticeUseCase(this._repository);

  Future<Result<void>> call(int version) => _repository.acknowledgePrivacyNotice(version);
}
