import '../../../../core/errors/result.dart';

abstract class DataProtectionRepository {
  /// Records that this person has read the privacy notice at [version].
  ///
  /// A self-assertion about themselves, so it is an ordinary write to
  /// their own user document rather than a callable -- firestore.rules
  /// permits exactly these two fields and nothing else.
  Future<Result<void>> acknowledgePrivacyNotice(int version);
}
