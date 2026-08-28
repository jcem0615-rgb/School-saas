import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:logicclass/core/constants/education_level.dart';
import 'package:logicclass/core/errors/result.dart';
import 'package:logicclass/demo/demo_overrides.dart';
import 'package:logicclass/demo/demo_store.dart';
import 'package:logicclass/features/owner_portal/domain/entities/school_summary.dart';
import 'package:logicclass/features/owner_portal/presentation/controllers/owner_controller.dart';

/// Schools are added by the Owner, by hand. There is no sign-up, so this
/// path is the only way one comes into existence -- and the demo has to
/// keep working, since it is what the app runs as by default.
void main() {
  late ProviderContainer container;

  setUp(() {
    container = ProviderContainer(overrides: demoOverrides());
    container.read(demoAuthRepositoryProvider).signInAs(
          DemoStore.demoAccounts.firstWhere((a) => a.email == 'owner@demo.ph'),
        );
  });
  tearDown(() => container.dispose());

  test('a new school appears in the owner list', () async {
    final repo = container.read(ownerRepositoryProvider);
    final before = container.read(demoStoreProvider).schools.value.length;

    final result = await repo.createSchool(
      name: 'Sacred Heart Academy',
      billingRatePerStudent: 65,
      educationLevels: const {
        EducationLevel.elementary,
        EducationLevel.highSchool,
        EducationLevel.seniorHigh,
      },
    );

    expect(result, isA<Success<String>>());
    final id = (result as Success<String>).value;
    // The id is derived from the name, the same way the callable derives
    // it, so the two backends agree on what a school is called.
    expect(id, 'sacred-heart-academy');

    final schools = container.read(demoStoreProvider).schools.value;
    expect(schools.length, before + 1);
    final created = schools.firstWhere((s) => s.id == id);
    expect(created.name, 'Sacred Heart Academy');
    // A school created a moment ago has no students and owes nothing.
    expect(created.status, SchoolSubscriptionStatus.active);
    expect(created.activeStudentCount, 0);
    expect(created.currentCycleAccrued, 0);
    // What the Owner picked, said back the way they would say it.
    expect(created.coverageLabel, 'Elementary to Senior High School');
  });

  test('the same id twice is refused, not silently merged', () async {
    final repo = container.read(ownerRepositoryProvider);
    const levels = {EducationLevel.college};
    await repo.createSchool(
      name: 'Twice Over',
      billingRatePerStudent: 10,
      educationLevels: levels,
    );
    final second = await repo.createSchool(
      name: 'Twice Over',
      billingRatePerStudent: 10,
      educationLevels: levels,
    );

    // Overwriting would hand a second school every record belonging to
    // the first.
    expect(second, isA<Error<String>>());
    expect(
      container.read(demoStoreProvider).schools.value
          .where((s) => s.id == 'twice-over')
          .length,
      1,
    );
  });

  test('a name with no letters or digits in it is refused', () async {
    // Punctuation slugifies to nothing, and an empty id would be a
    // Firestore path segment that cannot exist.
    final result =
        await container.read(ownerRepositoryProvider).createSchool(
              name: '!!! ???',
              billingRatePerStudent: 10,
              educationLevels: const {EducationLevel.elementary},
            );
    expect(result, isA<Error<String>>());
  });

  test('a school with no levels picked is refused', () async {
    // Which divisions a school runs is not a detail to be filled in
    // later: it decides what its own registration form can offer. The
    // callable refuses an empty list too, so the demo refusing it here
    // is the same answer, one round trip earlier.
    final result = await container.read(ownerRepositoryProvider).createSchool(
          name: 'Levels Missing Academy',
          billingRatePerStudent: 10,
          educationLevels: const {},
        );
    expect(result, isA<Error<String>>());
    expect(
      container.read(demoStoreProvider).schools.value
          .any((s) => s.id == 'levels-missing-academy'),
      isFalse,
    );
  });

  group('the coverage phrase', () {
    test('one division is named on its own', () {
      expect(educationCoverageLabel(const {EducationLevel.college}), 'College');
      expect(
        educationCoverageLabel(const {EducationLevel.highSchool}),
        'Junior High School',
      );
    });

    test('a run of divisions reads as a range', () {
      expect(
        educationCoverageLabel(const {
          EducationLevel.elementary,
          EducationLevel.highSchool,
        }),
        'Elementary to Junior High School',
      );
      expect(
        educationCoverageLabel(const {
          EducationLevel.elementary,
          EducationLevel.highSchool,
          EducationLevel.seniorHigh,
          EducationLevel.college,
        }),
        'Elementary to College',
      );
      // Tap order must not show: the phrase is built from the division
      // order, not the order they went into the set.
      expect(
        educationCoverageLabel({
          EducationLevel.seniorHigh,
          EducationLevel.highSchool,
        }),
        'Junior High to Senior High School',
      );
    });

    test('a gap is listed out rather than bridged', () {
      // The reason this is a set and not a fixed list of combinations.
      // Calling this "Elementary to College" would claim a high school
      // the school does not run.
      expect(
        educationCoverageLabel(const {
          EducationLevel.elementary,
          EducationLevel.college,
        }),
        'Elementary and College',
      );
      expect(
        educationCoverageLabel(const {
          EducationLevel.elementary,
          EducationLevel.seniorHigh,
          EducationLevel.college,
        }),
        'Elementary, Senior High School and College',
      );
    });

    test('nothing picked says so rather than inventing a range', () {
      expect(educationCoverageLabel(const {}), 'Not specified');
    });
  });

  group('reading levels back from a stored document', () {
    test('a missing field is empty, not a guess', () {
      // Every school created before this was recorded. Guessing here
      // would put a Senior High tab in front of a school that has none.
      expect(parseEducationLevels(null), isEmpty);
      expect(parseEducationLevels('elementary'), isEmpty);
    });

    test('an unrecognised division is skipped, not thrown on', () {
      expect(
        parseEducationLevels(['elementary', 'kindergarten', 7]),
        {EducationLevel.elementary},
      );
    });
  });

  test('slugify matches what the callable would produce', () {
    // Kept in step with slugify() in
    // functions/src/callable/schools/createSchool.ts -- if these drift, a
    // school gets one id in the demo and another in production.
    expect(DemoStore.slugify('St. Mary’s College'), 'st-mary-s-college');
    expect(DemoStore.slugify('  Spaces   Everywhere  '), 'spaces-everywhere');
    expect(DemoStore.slugify('ALL CAPS 123'), 'all-caps-123');
    expect(DemoStore.slugify('---leading and trailing---'),
        'leading-and-trailing');
    expect(DemoStore.slugify('!!!'), '');
    // Accents fold to the plain letter rather than becoming a separator.
    // "Muñoz Elementary" is a real school name shape here, and it used to
    // slug to "mu-oz-elementary" on this side and "mun-oz-elementary" on
    // the server -- wrong, and wrong differently.
    expect(DemoStore.slugify('Muñoz Elementary'), 'munoz-elementary');
    expect(DemoStore.slugify('Peñafrancia College'), 'penafrancia-college');
    expect(DemoStore.slugify('José Rizal High'), 'jose-rizal-high');
    expect(DemoStore.slugify('x' * 80).length, 48);
  });
}
