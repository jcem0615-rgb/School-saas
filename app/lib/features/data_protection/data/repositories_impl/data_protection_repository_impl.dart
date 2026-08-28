import '../../../../core/errors/app_exceptions.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/errors/result.dart';
import '../../domain/entities/data_request.dart';
import '../../domain/repositories/data_protection_repository.dart';
import '../datasources/data_protection_remote_datasource.dart';

class DataProtectionRepositoryImpl implements DataProtectionRepository {
  final DataProtectionRemoteDataSource _remote;
  const DataProtectionRepositoryImpl(this._remote);

  @override
  Stream<List<DataRequest>> watchRequests() => _remote.watchRequests();

  @override
  Stream<List<DataRequest>> watchMyRequests(String uid) => _remote.watchMyRequests(uid);

  @override
  Future<Result<String>> raiseRequest({
    required DataRequestKind kind,
    required String details,
    String? studentId,
    String? studentName,
  }) async {
    try {
      return Success(await _remote.raiseRequest(
        kind: kind,
        details: details,
        studentId: studentId,
        studentName: studentName,
      ));
    } on ServerException catch (e) {
      return Error(ServerFailure(e.message));
    } catch (_) {
      return const Error(UnknownFailure('The request could not be filed.'));
    }
  }

  @override
  Future<Result<void>> closeRequest({
    required String requestId,
    required DataRequestStatus status,
    required String outcome,
  }) async {
    try {
      await _remote.closeRequest(requestId: requestId, status: status, outcome: outcome);
      return const Success(null);
    } on ServerException catch (e) {
      return Error(ServerFailure(e.message));
    } catch (_) {
      return const Error(UnknownFailure('The request could not be updated.'));
    }
  }

  @override
  Future<Result<void>> acknowledgePrivacyNotice(int version) async {
    try {
      await _remote.acknowledgePrivacyNotice(version);
      return const Success(null);
    } on ServerException catch (e) {
      return Error(ServerFailure(e.message));
    } catch (_) {
      return const Error(UnknownFailure('That could not be recorded.'));
    }
  }
}
