import 'package:flutter_test/flutter_test.dart';

import 'package:logicclass/features/faculty_portal/data/models/grading_scheme_model.dart';
import 'package:logicclass/features/faculty_portal/domain/entities/grading_scheme.dart';

/// The scheme is the one piece of this feature that is configuration
/// rather than arithmetic, and configuration is where the quiet failures
/// live: weights that do not add up produce grades that look entirely
/// plausible and are wrong for a whole school year.
void main() {
  group('a school that has never opened the settings screen', () {
    test('reads back the DepEd defaults, unconfirmed', () {
      final scheme = GradingSchemeModel.fromFirestore(null);

      expect(scheme.weights, GradingScheme.depEdBasicEducationDefaults);
      // The half that matters. Defaults are a starting point transcribed
      // from a public order, not this software's assertion about what a
      // school's grades should be, and the report card refuses while this
      // is false.
      expect(scheme.confirmedBySchool, isFalse);
      expect(scheme.confirmedByName, isNull);
    });

    test('a document with no weights in it is the same situation', () {
      final scheme = GradingSchemeModel.fromFirestore(<String, dynamic>{
        'confirmedBySchool': true,
      });
      expect(scheme.weights, GradingScheme.depEdBasicEducationDefaults);
    });
  });

  group('what a school stored', () {
    final stored = <String, dynamic>{
      'weights': [
        {
          'label': 'Core subjects',
          'subjects': ['Mathematics', 'Science'],
          'writtenWork': 25,
          'performanceTask': 45,
          'quarterlyAssessment': 30,
        },
      ],
      'transmutation': [
        {'from': 0, 'to': 60, 'transmuted': 60},
        {'from': 60.01, 'to': 100, 'transmuted': 90},
      ],
      'confirmedBySchool': true,
      'confirmedByName': 'Grace Mendoza',
    };

    test('comes back as it was written', () {
      final scheme = GradingSchemeModel.fromFirestore(stored);
      expect(scheme.weights.single.label, 'Core subjects');
      expect(scheme.weightsFor('Science').performanceTask, 45);
      expect(scheme.transmutation.length, 2);
      expect(scheme.confirmedByName, 'Grace Mendoza');
    });

    test('survives a round trip through the map it is stored as', () {
      final scheme = GradingSchemeModel.fromFirestore(stored);
      final again = GradingSchemeModel.fromFirestore({
        ...GradingSchemeModel.toMap(scheme),
        'confirmedBySchool': true,
      });
      expect(again.weightsFor('Mathematics').writtenWork, 25);
      expect(again.transmutation.last.transmuted, 90);
    });

    test('the confirmation is not part of what toMap writes', () {
      // Saving revokes it, so the map that saving writes must not carry
      // it -- otherwise an edit would silently keep a confirmation
      // nobody gave for the new numbers.
      expect(GradingSchemeModel.toMap(GradingSchemeModel.fromFirestore(stored)),
          isNot(contains('confirmedBySchool')));
    });
  });

  group('a scheme with nothing configured', () {
    test('still returns weights rather than crashing a report card', () {
      const empty = GradingScheme(weights: []);
      final weights = empty.weightsFor('Mathematics');

      // Visibly not anybody's policy, which is the point: a grade
      // computed on an even split looks wrong and gets fixed.
      expect(weights.label, 'Unconfigured');
      expect(weights.balances, isTrue);
    });
  });

  test('a group that does not add up to a hundred is named', () {
    const scheme = GradingScheme(weights: [
      SubjectWeights(
        label: 'Science and Mathematics',
        subjects: ['Science'],
        writtenWork: 40,
        performanceTask: 40,
        quarterlyAssessment: 30,
      ),
      SubjectWeights(
        label: 'Everything else',
        writtenWork: 30,
        performanceTask: 50,
        quarterlyAssessment: 20,
      ),
    ]);

    expect(scheme.unbalanced.map((w) => w.label), ['Science and Mathematics']);
  });

  test('a subject matches the first group naming it, not the fallback', () {
    const scheme = GradingScheme(weights: [
      SubjectWeights(
        label: 'Everything else',
        writtenWork: 30,
        performanceTask: 50,
        quarterlyAssessment: 20,
      ),
      SubjectWeights(
        label: 'Science and Mathematics',
        subjects: ['Science'],
        writtenWork: 40,
        performanceTask: 40,
        quarterlyAssessment: 20,
      ),
    ]);

    // The fallback is listed first here on purpose: matching has to be by
    // what a group names, not by where it sits in the list, or a school
    // that reorders its groups silently regrades its school.
    expect(scheme.weightsFor('Science').label, 'Science and Mathematics');
    expect(scheme.weightsFor('Robotics').label, 'Everything else');
  });
}
