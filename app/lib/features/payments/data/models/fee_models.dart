import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../../core/constants/education_level.dart';
import '../../domain/entities/assessment.dart';
import '../../domain/entities/fee_structure.dart';
import '../../domain/entities/installment.dart';

/// Reads a payment plan out of a stored document.
///
/// Due dates are written as ISO strings rather than Timestamps. Nothing
/// queries on them -- Firestore cannot filter on a field inside an array
/// element anyway -- so a Timestamp would buy nothing and cost a type
/// that has to be converted on both sides of every read. A
/// hand-corrected document carrying a Timestamp is still accepted,
/// because the alternative is a plan that silently reads as empty.
List<Installment> _installmentsFrom(dynamic raw) {
  if (raw is! List) return const [];
  final parsed = <Installment>[];
  for (final entry in raw) {
    if (entry is! Map) continue;
    final map = Map<String, dynamic>.from(entry);
    final stored = map['dueDate'];
    final dueDate = stored is Timestamp ? stored.toDate() : null;
    final installment = Installment.fromMap(map, dueDate: dueDate);
    // A line with no money on it is not a payment date, and a family
    // shown "0.00 due 5 Oct" would reasonably think something is broken.
    if (installment.amount > 0) parsed.add(installment);
  }
  return parsed;
}

class FeeStructureModel extends FeeStructure {
  const FeeStructureModel({
    required super.id,
    required super.name,
    required super.educationLevel,
    required super.schoolYear,
    required super.items,
    required super.updatedAt,
    required super.updatedByName,
    super.gradeLevel,
    super.installments,
    super.isActive,
  });

  factory FeeStructureModel.fromFirestore(String id, Map<String, dynamic> data) {
    return FeeStructureModel(
      id: id,
      name: data['name'] as String? ?? '',
      educationLevel: EducationLevel.fromString(data['educationLevel'] as String? ?? 'elementary'),
      // Empty string and null both mean "the whole division". Stored as
      // null, but a hand-edited document may carry either.
      gradeLevel: (data['gradeLevel'] as String?)?.trim().isEmpty ?? true
          ? null
          : (data['gradeLevel'] as String).trim(),
      schoolYear: data['schoolYear'] as String? ?? '',
      items: (data['items'] as List<dynamic>? ?? [])
          .map((e) => FeeItem.fromMap(Map<String, dynamic>.from(e as Map)))
          .toList(),
      installments: _installmentsFrom(data['installments']),
      // Missing means active: a schedule written before the flag existed
      // is one the school is still using.
      isActive: data['isActive'] as bool? ?? true,
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedByName: data['updatedByName'] as String? ?? 'Unknown',
    );
  }

  static Map<String, dynamic> toFirestore({
    required String name,
    required EducationLevel educationLevel,
    required String? gradeLevel,
    required String schoolYear,
    required List<FeeItem> items,
    required List<Installment> installments,
    required bool isActive,
  }) =>
      {
        'name': name.trim(),
        'educationLevel': educationLevel.value,
        'gradeLevel': gradeLevel?.trim().isEmpty ?? true ? null : gradeLevel!.trim(),
        'schoolYear': schoolYear.trim(),
        'items': items.map((i) => i.toMap()).toList(),
        'installments': installments.map((i) => i.toMap()).toList(),
        // Denormalised so a list screen can show the total without
        // summing every document's items client-side, and so a report
        // can group on it.
        'total': items.fold<double>(0, (running, i) => running + i.amount),
        'isActive': isActive,
      };
}

class AssessmentModel extends Assessment {
  const AssessmentModel({
    required super.id,
    required super.studentId,
    required super.studentName,
    required super.schoolYear,
    required super.items,
    required super.assessedByName,
    required super.assessedAt,
    super.installments,
    super.sourceStructureId,
    super.sourceStructureName,
    super.remarks,
    super.voidedAt,
    super.voidedByName,
    super.voidReason,
  });

  factory AssessmentModel.fromFirestore(String id, Map<String, dynamic> data) {
    return AssessmentModel(
      id: id,
      studentId: data['studentId'] as String? ?? '',
      studentName: data['studentName'] as String? ?? '',
      schoolYear: data['schoolYear'] as String? ?? '',
      sourceStructureId: data['sourceStructureId'] as String?,
      sourceStructureName: data['sourceStructureName'] as String?,
      items: (data['items'] as List<dynamic>? ?? [])
          .map((e) => FeeItem.fromMap(Map<String, dynamic>.from(e as Map)))
          .toList(),
      installments: _installmentsFrom(data['installments']),
      assessedByName: data['assessedByName'] as String? ?? 'Unknown',
      // The write sets this from the server clock, so it is null in the
      // local echo of a document that has not round-tripped yet.
      assessedAt: (data['assessedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      remarks: data['remarks'] as String?,
      voidedAt: (data['voidedAt'] as Timestamp?)?.toDate(),
      voidedByName: data['voidedByName'] as String?,
      voidReason: data['voidReason'] as String?,
    );
  }
}
