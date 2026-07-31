import '../../../../core/errors/failures.dart';
import '../../../../core/errors/result.dart';
import '../../../../core/utils/validators.dart';
import '../entities/coursework_item.dart';
import '../repositories/faculty_repository.dart';

class WatchMyCourseworkItemsUseCase {
  final FacultyRepository _repository;
  const WatchMyCourseworkItemsUseCase(this._repository);

  Stream<List<CourseworkItem>> call() => _repository.watchMyCourseworkItems();
}

class CreateCourseworkItemUseCase {
  final FacultyRepository _repository;
  const CreateCourseworkItemUseCase(this._repository);

  Future<Result<void>> call({
    required CourseworkType type,
    required String title,
    required String description,
    required String subject,
    required String section,
    DateTime? dueDate,
    double? totalPoints,
    bool published = true,
    String? attachmentUrl,
    String? attachmentName,
  }) {
    final titleError = Validators.required(title, fieldName: 'Title');
    if (titleError != null) return Future.value(Error(ValidationFailure(titleError)));

    final subjectError = Validators.required(subject, fieldName: 'Subject');
    if (subjectError != null) return Future.value(Error(ValidationFailure(subjectError)));

    final sectionError = Validators.required(section, fieldName: 'Section');
    if (sectionError != null) return Future.value(Error(ValidationFailure(sectionError)));

    if (type.isGradable && dueDate == null) {
      return Future.value(
        Error(ValidationFailure('A due date is required for a ${type.displayLabel.toLowerCase()}.')),
      );
    }

    return _repository.createCourseworkItem(
      type: type,
      title: title.trim(),
      description: description.trim(),
      subject: subject.trim(),
      section: section.trim(),
      dueDate: dueDate,
      totalPoints: totalPoints,
      published: published,
      attachmentUrl: attachmentUrl,
      attachmentName: attachmentName,
    );
  }
}

/// Edits re-run creation's validation -- an edit that blanks the title is
/// exactly as invalid as a create that never set one.
class UpdateCourseworkItemUseCase {
  final FacultyRepository _repository;
  const UpdateCourseworkItemUseCase(this._repository);

  Future<Result<void>> call({
    required String itemId,
    required CourseworkType type,
    required String title,
    required String description,
    required String subject,
    required String section,
    DateTime? dueDate,
    double? totalPoints,
    bool published = true,
    String? attachmentUrl,
    String? attachmentName,
  }) {
    if (itemId.trim().isEmpty) {
      return Future.value(const Error(ValidationFailure('Missing coursework item.')));
    }
    final titleError = Validators.required(title, fieldName: 'Title');
    if (titleError != null) return Future.value(Error(ValidationFailure(titleError)));

    final subjectError = Validators.required(subject, fieldName: 'Subject');
    if (subjectError != null) return Future.value(Error(ValidationFailure(subjectError)));

    final sectionError = Validators.required(section, fieldName: 'Section');
    if (sectionError != null) return Future.value(Error(ValidationFailure(sectionError)));

    if (type.isGradable && (totalPoints == null || totalPoints <= 0)) {
      return Future.value(
        const Error(ValidationFailure('Total points must be greater than zero for graded work.')),
      );
    }

    return _repository.updateCourseworkItem(
      itemId: itemId,
      type: type,
      title: title.trim(),
      description: description.trim(),
      subject: subject.trim(),
      section: section.trim(),
      dueDate: dueDate,
      totalPoints: totalPoints,
      published: published,
      attachmentUrl: attachmentUrl,
      attachmentName: attachmentName,
    );
  }
}

class DeleteCourseworkItemUseCase {
  final FacultyRepository _repository;
  const DeleteCourseworkItemUseCase(this._repository);

  Future<Result<void>> call(String itemId) {
    if (itemId.trim().isEmpty) {
      return Future.value(const Error(ValidationFailure('Missing coursework item.')));
    }
    return _repository.deleteCourseworkItem(itemId);
  }
}
