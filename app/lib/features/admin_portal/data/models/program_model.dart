import '../../domain/entities/program.dart';

class ProgramModel extends Program {
  const ProgramModel({
    required super.id,
    required super.name,
    required super.code,
    required super.department,
  });

  factory ProgramModel.fromFirestore(String id, Map<String, dynamic> data) {
    return ProgramModel(
      id: id,
      name: data['name'] as String? ?? '',
      code: data['code'] as String? ?? '',
      department: data['department'] as String? ?? '',
    );
  }
}
