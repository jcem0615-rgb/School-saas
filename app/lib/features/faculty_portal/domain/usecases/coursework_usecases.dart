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
    );
  }
}
