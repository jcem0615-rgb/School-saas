import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/entities/school_branding.dart';

class SchoolBrandingModel extends SchoolBranding {
  const SchoolBrandingModel({
    super.logoUrl,
    super.logoFileName,
    super.schoolName,
    super.addressLine,
    super.principalName,
    super.directorName,
    super.schoolYear,
    super.updatedAt,
    super.updatedByName,
  });

  /// [data] is null until an admin saves branding, which is the normal
  /// state for a new school -- callers show a default rather than assuming
  /// a logo exists.
  factory SchoolBrandingModel.fromFirestore(Map<String, dynamic>? data) {
    if (data == null) return const SchoolBrandingModel();
    return SchoolBrandingModel(
      logoUrl: data['logoUrl'] as String?,
      logoFileName: data['logoFileName'] as String?,
      schoolName: data['schoolName'] as String?,
      addressLine: data['addressLine'] as String?,
      principalName: data['principalName'] as String?,
      directorName: data['directorName'] as String?,
      schoolYear: data['schoolYear'] as String?,
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
      updatedByName: data['updatedByName'] as String?,
    );
  }
}
