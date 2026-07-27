import '../../../registrar_portal/domain/entities/student_summary.dart';
import '../repositories/parent_repository.dart';

class WatchChildrenUseCase {
  final ParentRepository _repository;
  const WatchChildrenUseCase(this._repository);

  Stream<List<StudentSummary>> call(List<String> linkedStudentIds) =>
      _repository.watchChildren(linkedStudentIds);
}
