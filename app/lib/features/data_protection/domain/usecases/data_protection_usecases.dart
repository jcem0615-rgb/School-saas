import '../../../../core/errors/failures.dart';
import '../../../../core/errors/result.dart';
import '../entities/data_request.dart';
import '../repositories/data_protection_repository.dart';

class WatchDataRequestsUseCase {
  final DataProtectionRepository _repository;
  const WatchDataRequestsUseCase(this._repository);

  Stream<List<DataRequest>> call() => _repository.watchRequests();
}

class WatchMyDataRequestsUseCase {
  final DataProtectionRepository _repository;
  const WatchMyDataRequestsUseCase(this._repository);

  Stream<List<DataRequest>> call(String uid) => _repository.watchMyRequests(uid);
}

/// Files a request.
///
/// The only validation is that something was actually asked for. A
/// person exercising a right should not be made to phrase it correctly
/// -- the office reads it and decides -- so this refuses an empty box
/// and nothing else.
class RaiseDataRequestUseCase {
  final DataProtectionRepository _repository;
  const RaiseDataRequestUseCase(this._repository);

  Future<Result<String>> call({
    required DataRequestKind kind,
    required String details,
    String? studentId,
    String? studentName,
  }) {
    if (details.trim().isEmpty) {
      return Future.value(
        const Error(ValidationFailure('Say what you are asking for.')),
      );
    }
    return _repository.raiseRequest(
      kind: kind,
      details: details.trim(),
      studentId: studentId,
      studentName: studentName,
    );
  }
}

/// Closes a request, done or refused.
///
/// The outcome is mandatory in both directions. A request marked done
/// with nothing said about it is the entry that makes an audit worse
/// rather than better, and a refusal with no reason is the one a
/// regulator asks about first.
class CloseDataRequestUseCase {
  final DataProtectionRepository _repository;
  const CloseDataRequestUseCase(this._repository);

  Future<Result<void>> call({
    required String requestId,
    required DataRequestStatus status,
    required String outcome,
  }) {
    if (status == DataRequestStatus.open) {
      return Future.value(
        const Error(ValidationFailure('Choose whether this was done or refused.')),
      );
    }
    if (outcome.trim().isEmpty) {
      return Future.value(
        Error(ValidationFailure(
          status == DataRequestStatus.refused
              ? 'Say why this request is being refused. The person is entitled '
                  'to be told.'
              : 'Say what was done, so the record means something later.',
        )),
      );
    }
    return _repository.closeRequest(
      requestId: requestId,
      status: status,
      outcome: outcome.trim(),
    );
  }
}

class AcknowledgePrivacyNoticeUseCase {
  final DataProtectionRepository _repository;
  const AcknowledgePrivacyNoticeUseCase(this._repository);

  Future<Result<void>> call(int version) => _repository.acknowledgePrivacyNotice(version);
}
