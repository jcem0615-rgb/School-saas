import '../../../../core/constants/education_level.dart';
import '../../domain/entities/program.dart';

class ProgramModel extends Program {
  const ProgramModel({
    required super.id,
    required super.name,
    required super.code,
    required super.department,
    super.educationLevel,
  });

  factory ProgramModel.fromFirestore(String id, Map<String, dynamic> data) {
    return ProgramModel(
      id: id,
      name: data['name'] as String? ?? '',
      code: data['code'] as String? ?? '',
      department: data['department'] as String? ?? '',
      // Every program in the catalogue before Senior High existed was a
      // college program, so that is the honest default for an old doc.
      educationLevel:
          EducationLevel.fromString(data['educationLevel'] as String? ?? 'college'),
    );
  }
}
