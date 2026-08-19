import '../../../../core/errors/failures.dart';
import '../../../../core/errors/result.dart';
import '../../../../core/utils/validators.dart';
import '../entities/announcement.dart';
import '../repositories/director_repository.dart';

class WatchAnnouncementsUseCase {
  final DirectorRepository _repository;
  const WatchAnnouncementsUseCase(this._repository);

  Stream<List<Announcement>> call() => _repository.watchAnnouncements();
}

class CreateAnnouncementUseCase {
  final DirectorRepository _repository;
  const CreateAnnouncementUseCase(this._repository);

  Future<Result<void>> call({
    required String title,
    required String body,
    required AnnouncementAudience audience,
    bool pinned = false,
  }) {
    final titleError = Validators.required(title, fieldName: 'Title');
    if (titleError != null) return Future.value(Error(ValidationFailure(titleError)));

    final bodyError = Validators.required(body, fieldName: 'Message');
    if (bodyError != null) return Future.value(Error(ValidationFailure(bodyError)));

    return _repository.createAnnouncement(
      title: title.trim(),
      body: body.trim(),
      audience: audience,
      pinned: pinned,
    );
  }
}
