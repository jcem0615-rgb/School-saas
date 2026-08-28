import '../../../../core/errors/result.dart';
import '../entities/data_request.dart';

abstract class DataProtectionRepository {
  /// Every request the school has received, newest first.
  Stream<List<DataRequest>> watchRequests();

  /// The requests one person raised, for their own profile screen.
  Stream<List<DataRequest>> watchMyRequests(String uid);

  Future<Result<String>> raiseRequest({
    required DataRequestKind kind,
    required String details,
    String? studentId,
    String? studentName,
  });

  Future<Result<void>> closeRequest({
    required String requestId,
    required DataRequestStatus status,
    required String outcome,
  });

  /// Records that this person has read the privacy notice at [version].
  ///
  /// A self-assertion about themselves, so it is an ordinary write to
  /// their own user document rather than a callable -- firestore.rules
  /// permits exactly these two fields and nothing else.
  Future<Result<void>> acknowledgePrivacyNotice(int version);
}
