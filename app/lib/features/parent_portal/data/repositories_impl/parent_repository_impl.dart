import '../../../registrar_portal/domain/entities/student_summary.dart';
import '../../domain/repositories/parent_repository.dart';
import '../datasources/parent_remote_datasource.dart';

class ParentRepositoryImpl implements ParentRepository {
  final ParentRemoteDataSource _remote;
  const ParentRepositoryImpl(this._remote);

  @override
  Stream<List<StudentSummary>> watchChildren(List<String> linkedStudentIds) =>
      _remote.watchChildren(linkedStudentIds);
}
