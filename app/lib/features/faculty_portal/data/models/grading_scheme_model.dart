import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/entities/grading_scheme.dart';

/// The school's grading scheme as it is stored.
///
/// A missing document is not an error and not an empty scheme: it is a
/// school that has not been to the grading settings screen yet, and it
/// reads back as the DepEd defaults with [GradingScheme.confirmedBySchool]
/// false. That is exactly the state the confirmation step exists for --
/// grades compute and show on screen, marked provisional, and the report
/// card will not print until somebody has said the weights are right.
class GradingSchemeModel extends GradingScheme {
  const GradingSchemeModel({
    required super.weights,
    super.transmutation,
    super.confirmedBySchool,
    super.confirmedByName,
    super.confirmedAt,
  });

  factory GradingSchemeModel.fromFirestore(Map<String, dynamic>? data) {
    if (data == null) {
      return const GradingSchemeModel(
        weights: GradingScheme.depEdBasicEducationDefaults,
      );
    }

    final rawWeights = data['weights'] as List<dynamic>? ?? const [];
    final weights = [
      for (final entry in rawWeights)
        if (entry is Map<String, dynamic>) SubjectWeights.fromMap(entry),
    ];

    final rawBands = data['transmutation'] as List<dynamic>? ?? const [];

    return GradingSchemeModel(
      // A document that exists but has no weights in it is the same
      // situation as no document: seed rather than leave every subject on
      // the visibly-wrong even split.
      weights: weights.isEmpty ? GradingScheme.depEdBasicEducationDefaults : weights,
      transmutation: [
        for (final band in rawBands)
          if (band is Map<String, dynamic>) TransmutationBand.fromMap(band),
      ],
      confirmedBySchool: data['confirmedBySchool'] as bool? ?? false,
      confirmedByName: data['confirmedByName'] as String?,
      confirmedAt: (data['confirmedAt'] as Timestamp?)?.toDate(),
    );
  }

  static Map<String, dynamic> toMap(GradingScheme scheme) => {
        'weights': [for (final group in scheme.weights) group.toMap()],
        'transmutation': [for (final band in scheme.transmutation) band.toMap()],
      };
}
