import '../../../../core/errors/failures.dart';
import '../../../../core/errors/result.dart';
import '../../../../core/utils/validators.dart';
import '../entities/meeting.dart';
import '../repositories/director_repository.dart';

class WatchMeetingsUseCase {
  final DirectorRepository _repository;
  const WatchMeetingsUseCase(this._repository);

  Stream<List<Meeting>> call() => _repository.watchMeetings();
}

class CreateMeetingUseCase {
  final DirectorRepository _repository;
  const CreateMeetingUseCase(this._repository);

  Future<Result<void>> call({
    required String title,
    String? description,
    required DateTime startTime,
    required DateTime endTime,
    String? location,
    required List<String> attendeeRoles,
  }) {
    final titleError = Validators.required(title, fieldName: 'Title');
    if (titleError != null) return Future.value(Error(ValidationFailure(titleError)));

    if (!endTime.isAfter(startTime)) {
      return Future.value(
        const Error(ValidationFailure('End time must be after the start time.')),
      );
    }
    if (attendeeRoles.isEmpty) {
      return Future.value(
        const Error(ValidationFailure('Select at least one attendee group.')),
      );
    }

    return _repository.createMeeting(
      title: title.trim(),
      description: description?.trim(),
      startTime: startTime,
      endTime: endTime,
      location: location?.trim(),
      attendeeRoles: attendeeRoles,
    );
  }
}

class CancelMeetingUseCase {
  final DirectorRepository _repository;
  const CancelMeetingUseCase(this._repository);

  Future<Result<void>> call(String meetingId) => _repository.cancelMeeting(meetingId);
}
