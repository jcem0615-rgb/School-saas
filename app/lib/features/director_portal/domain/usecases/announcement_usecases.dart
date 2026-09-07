import '../../../../core/constants/user_roles.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/errors/result.dart';
import '../../../../core/utils/validators.dart';
import '../entities/announcement.dart';
import '../repositories/director_repository.dart';

class WatchAnnouncementsUseCase {
  final DirectorRepository _repository;
  const WatchAnnouncementsUseCase(this._repository);

  /// Announcements the given [role] is actually addressed by.
  ///
  /// The filter lives here rather than on a screen because every portal
  /// -- staff, student and parent alike -- opens the same
  /// AnnouncementsScreen. Filtering per screen would mean filtering it
  /// nine times and forgetting once, which is how a student ended up
  /// reading the payroll cut-off notice.
  ///
  /// See AnnouncementAudience: this is relevance, not secrecy. The
  /// collection is readable tenant-wide, because Firestore rules reject
  /// queries rather than filtering them.
  ///
  /// [viewerSections] are the classes this viewer belongs to, which is
  /// how a teacher's notice for one section finds its students, their
  /// parents and the section's other teachers.
  Stream<List<Announcement>> call(
    UserRole role, {
    Iterable<String> viewerSections = const [],
  }) =>
      _repository.watchAnnouncements().map((all) => all
          .where((a) => a.audience.includes(role, viewerSections: viewerSections))
          .toList());

  /// Everything posted, for the roles that manage announcements. Separate
  /// from [call] so that reading unfiltered is a deliberate choice at the
  /// call site rather than a default someone forgets to narrow.
  Stream<List<Announcement>> unfiltered() => _repository.watchAnnouncements();
}

/// Refuses an audience nobody is in.
///
/// The editor disables Post in this state, and the notification trigger
/// declines to fan out from it -- but the entity has carried
/// [AnnouncementAudience.reachesNobody] since sections existed, described
/// as "the state the editor must not let somebody post from", and until
/// now nothing outside a test called it. A notice addressed to no one is
/// not a draft: it is a row in the school's announcements that reads as
/// posted and reaches nobody, and an import or a script would have
/// written one without a word.
Failure? _audienceProblem(AnnouncementAudience audience) {
  if (!audience.reachesNobody) return null;
  return const ValidationFailure(
    'Choose who this is for -- everyone, some roles, or a class.',
  );
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

    final audienceProblem = _audienceProblem(audience);
    if (audienceProblem != null) return Future.value(Error(audienceProblem));

    return _repository.createAnnouncement(
      title: title.trim(),
      body: body.trim(),
      audience: audience,
      pinned: pinned,
    );
  }
}

/// Edits apply the same validation as creation -- an edit that blanks a
/// required field is exactly as invalid as a create that never filled it.
class UpdateAnnouncementUseCase {
  final DirectorRepository _repository;
  const UpdateAnnouncementUseCase(this._repository);

  Future<Result<void>> call({
    required String announcementId,
    required String title,
    required String body,
    required AnnouncementAudience audience,
    bool pinned = false,
  }) {
    if (announcementId.trim().isEmpty) {
      return Future.value(const Error(ValidationFailure('Missing announcement.')));
    }

    final titleError = Validators.required(title, fieldName: 'Title');
    if (titleError != null) return Future.value(Error(ValidationFailure(titleError)));

    final bodyError = Validators.required(body, fieldName: 'Message');
    if (bodyError != null) return Future.value(Error(ValidationFailure(bodyError)));

    // An edit that empties the audience is exactly as invalid as a
    // create that never filled it -- and worse in one way: the notice is
    // already on the board, and it would stay there addressed to no one.
    final audienceProblem = _audienceProblem(audience);
    if (audienceProblem != null) return Future.value(Error(audienceProblem));

    return _repository.updateAnnouncement(
      announcementId: announcementId,
      title: title.trim(),
      body: body.trim(),
      audience: audience,
      pinned: pinned,
    );
  }
}

class DeleteAnnouncementUseCase {
  final DirectorRepository _repository;
  const DeleteAnnouncementUseCase(this._repository);

  Future<Result<void>> call(String announcementId) {
    if (announcementId.trim().isEmpty) {
      return Future.value(const Error(ValidationFailure('Missing announcement.')));
    }
    return _repository.deleteAnnouncement(announcementId);
  }
}
