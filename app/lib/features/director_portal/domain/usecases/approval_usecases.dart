import '../../../../core/errors/failures.dart';
import '../../../../core/errors/result.dart';
import '../../../../core/utils/validators.dart';
import '../entities/approval_request.dart';
import '../repositories/director_repository.dart';

class WatchApprovalsUseCase {
  final DirectorRepository _repository;
  const WatchApprovalsUseCase(this._repository);

  Stream<List<ApprovalRequest>> call({ApprovalStatus? statusFilter, String? requestedByUid}) =>
      _repository.watchApprovals(statusFilter: statusFilter, requestedByUid: requestedByUid);
}

/// Files a new request (e.g. Faculty's Material Requests). Kept generic
/// on [type] so any future module can reuse this same inbox instead of
/// building its own approval collection + screen.
class CreateApprovalRequestUseCase {
  final DirectorRepository _repository;
  const CreateApprovalRequestUseCase(this._repository);

  Future<Result<void>> call({
    required String type,
    required String title,
    String? description,
    Map<String, dynamic> details = const {},
  }) {
    final titleError = Validators.required(title, fieldName: 'Title');
    if (titleError != null) return Future.value(Error(ValidationFailure(titleError)));

    return _repository.createApprovalRequest(
      type: type,
      title: title.trim(),
      description: description?.trim(),
      details: details,
    );
  }
}

/// Approve or reject a pending request. A rejection must carry remarks
/// explaining why (enforced here, not just as a UI nicety) since the
/// requester has no other way to find out what to fix and resubmit.
class DecideApprovalUseCase {
  final DirectorRepository _repository;
  const DecideApprovalUseCase(this._repository);

  Future<Result<void>> call({
    required String approvalId,
    required bool approve,
    String? remarks,
  }) {
    if (!approve && (remarks == null || remarks.trim().isEmpty)) {
      return Future.value(
        const Error(ValidationFailure('Please provide a reason for rejecting this request.')),
      );
    }
    return _repository.decideApproval(
      approvalId: approvalId,
      approve: approve,
      remarks: remarks?.trim(),
    );
  }
}
