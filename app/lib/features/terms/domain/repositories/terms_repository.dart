import '../../../../core/errors/result.dart';

abstract class TermsRepository {
  /// Records that this account accepted [version], and when.
  ///
  /// Two fields on the account's own user document, which is why there is
  /// no callable behind it: firestore.rules lets a person write these on
  /// themselves and nowhere else, the same way the privacy
  /// acknowledgement works.
  Future<Result<void>> acceptTerms(int version);
}
