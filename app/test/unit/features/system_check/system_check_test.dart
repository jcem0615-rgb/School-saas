import 'package:flutter_test/flutter_test.dart';

import 'package:logicclass/features/system_check/domain/entities/system_check.dart';

/// The report's own arithmetic, which is what the screen and the person
/// reading it both act on.
SystemCheck pass(String id) =>
    SystemCheck.pass(id: id, title: id, detail: 'fine');

SystemCheck fail(String id) =>
    SystemCheck.fail(id: id, title: id, detail: 'broken', remedy: 'fix it');

SystemCheck warn(String id) => SystemCheck.warn(id: id, title: id, detail: 'look');

SystemCheckReport report(List<SystemCheck> checks, {bool demoMode = false}) =>
    SystemCheckReport(checks: checks, ranAt: DateTime(2026, 8, 28), demoMode: demoMode);

void main() {
  test('all green is ready', () {
    final r = report([pass('a'), pass('b')]);
    expect(r.isReady, isTrue);
    expect(r.headline, 'Ready');
  });

  test('a warning does not block, and says how many to look at', () {
    final r = report([pass('a'), warn('b'), warn('c')]);
    expect(r.isReady, isTrue, reason: 'a missing logo is not a broken deployment');
    expect(r.warnings, 2);
    expect(r.headline, 'Ready, with 2 to look at');
  });

  test('a failure blocks and is counted', () {
    final r = report([pass('a'), fail('b')]);
    expect(r.isReady, isFalse);
    expect(r.failures, 1);
    expect(r.headline, '1 check failed');
  });

  test('the headline counts plurally', () {
    expect(report([fail('a'), fail('b')]).headline, '2 checks failed');
  });

  // The whole point of the demo flag. A preflight that goes green
  // against an in-memory store is a green light that means nothing.
  test('demo mode is never ready, however green it looks', () {
    final r = report([pass('a'), pass('b')], demoMode: true);
    expect(r.isReady, isFalse);
    expect(r.headline, 'Nothing was checked');
  });

  test('an empty demo report is still not ready', () {
    expect(report(const [], demoMode: true).isReady, isFalse);
  });

  group('every failing check names a remedy', () {
    // A red light with no next step is a red light somebody clicks past.
    test('the constructor requires one', () {
      final failing = fail('rules');
      expect(failing.remedy, isNotNull);
      expect(failing.remedy!.trim(), isNotEmpty);
    });

    test('a passing check has nothing to do', () {
      expect(pass('rules').remedy, isNull);
    });
  });
}
