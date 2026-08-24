import '../../../../core/errors/result.dart';
import '../entities/school_branding.dart';
import '../repositories/admin_repository.dart';

class WatchBrandingUseCase {
  final AdminRepository _repository;
  const WatchBrandingUseCase(this._repository);

  Stream<SchoolBranding> call() => _repository.watchBranding();
}

class UpdateBrandingUseCase {
  final AdminRepository _repository;
  const UpdateBrandingUseCase(this._repository);

  /// Every field is optional: uploading a logo and renaming the school are
  /// separate actions, and neither should clear the other.
  Future<Result<void>> call({
    String? logoUrl,
    String? logoFileName,
    String? schoolName,
    String? addressLine,
    String? principalName,
    String? principalSignatureUrl,
    String? directorSignatureUrl,
    String? directorName,
    String? schoolYear,
  }) {
    return _repository.updateBranding(
      logoUrl: logoUrl,
      logoFileName: logoFileName,
      schoolName: schoolName?.trim(),
      addressLine: addressLine?.trim(),
      principalName: principalName?.trim(),
      principalSignatureUrl: principalSignatureUrl,
      directorSignatureUrl: directorSignatureUrl,
      directorName: directorName?.trim(),
      schoolYear: schoolYear?.trim(),
    );
  }
}
