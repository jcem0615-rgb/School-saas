import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/result.dart';
import '../../../auth/presentation/controllers/auth_controller.dart' show authStateProvider, firestoreProvider;
import '../../data/datasources/faculty_remote_datasource.dart';
import '../../data/repositories_impl/faculty_repository_impl.dart';
import '../../domain/entities/coursework_item.dart';
import '../../domain/entities/grade.dart';
import '../../domain/repositories/faculty_repository.dart';
import '../../domain/usecases/coursework_usecases.dart';
import '../../domain/usecases/grade_usecases.dart';

final facultyRemoteDataSourceProvider = Provider<FacultyRemoteDataSource>((ref) {
  final user = ref.watch(authStateProvider).valueOrNull;
  if (user == null || user.schoolId == null) {
    throw StateError('FacultyRemoteDataSource requires a signed-in, school-scoped user.');
  }
  return FacultyRemoteDataSource(
    firestore: ref.watch(firestoreProvider),
    actingUser: ActingFaculty(uid: user.uid, schoolId: user.schoolId!, name: user.fullName),
  );
});

final facultyRepositoryProvider = Provider<FacultyRepository>((ref) {
  return FacultyRepositoryImpl(ref.watch(facultyRemoteDataSourceProvider));
});

final myCourseworkStreamProvider = StreamProvider.autoDispose<List<CourseworkItem>>((ref) {
  return WatchMyCourseworkItemsUseCase(ref.watch(facultyRepositoryProvider))();
});

class GradeQuery {
  final String subject;
  final String section;
  const GradeQuery({required this.subject, required this.section});

  @override
  bool operator ==(Object other) =>
      other is GradeQuery && other.subject == subject && other.section == section;

  @override
  int get hashCode => Object.hash(subject, section);
}

final gradesStreamProvider = StreamProvider.autoDispose.family<List<Grade>, GradeQuery>((ref, query) {
  return WatchGradesUseCase(ref.watch(facultyRepositoryProvider))(subject: query.subject, section: query.section);
});

class FacultyActionController extends StateNotifier<AsyncValue<void>> {
  final CreateCourseworkItemUseCase _createCourseworkItem;
  final SubmitGradeUseCase _submitGrade;

  FacultyActionController({
    required CreateCourseworkItemUseCase createCourseworkItem,
    required SubmitGradeUseCase submitGrade,
  })  : _createCourseworkItem = createCourseworkItem,
        _submitGrade = submitGrade,
        super(const AsyncData(null));

  Future<bool> createCourseworkItem({
    required CourseworkType type,
    required String title,
    required String description,
    required String subject,
    required String section,
    DateTime? dueDate,
    double? totalPoints,
    bool published = true,
  }) => _run(() => _createCourseworkItem(
        type: type,
        title: title,
        description: description,
        subject: subject,
        section: section,
        dueDate: dueDate,
        totalPoints: totalPoints,
        published: published,
      ));

  Future<bool> submitGrade({
    required String studentId,
    required String studentName,
    required String subject,
    required String section,
    required String term,
    required double score,
    required double maxScore,
    String? courseworkItemId,
    String? remarks,
  }) => _run(() => _submitGrade(
        studentId: studentId,
        studentName: studentName,
        subject: subject,
        section: section,
        term: term,
        score: score,
        maxScore: maxScore,
        courseworkItemId: courseworkItemId,
        remarks: remarks,
      ));

  Future<bool> _run(Future<dynamic> Function() action) async {
    state = const AsyncLoading();
    final result = await action();
    if (result case Success()) {
      state = const AsyncData(null);
      return true;
    } else if (result case Error(:final failure)) {
      state = AsyncError(failure.message, StackTrace.current);
    }
    return false;
  }
}

final facultyActionControllerProvider =
    StateNotifierProvider.autoDispose<FacultyActionController, AsyncValue<void>>((ref) {
  final repo = ref.watch(facultyRepositoryProvider);
  return FacultyActionController(
    createCourseworkItem: CreateCourseworkItemUseCase(repo),
    submitGrade: SubmitGradeUseCase(repo),
  );
});
