import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:logicclass/demo/demo_overrides.dart';
import 'package:logicclass/features/auth/data/remembered_email.dart';
import 'package:logicclass/features/auth/presentation/screens/login_screen.dart';

/// Remember me fills the email in next time and never touches the
/// password. The second half is the part worth pinning down: a school's
/// front desk is a shared computer, and a remembered password there is
/// everybody's password.
Future<void> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(900, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final c = ProviderContainer(overrides: demoOverrides());
  addTearDown(c.dispose);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: c,
    child: const MaterialApp(home: LoginScreen()),
  ));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('unticked by default, with nothing remembered', (tester) async {
    await _pump(tester);
    final box = tester.widget<Checkbox>(find.byType(Checkbox));
    expect(box.value, isFalse);
    expect(await RememberedEmail.read(), isNull);
  });

  testWidgets('signing in with it ticked remembers the email', (tester) async {
    await _pump(tester);

    await tester.enterText(
        find.widgetWithText(TextFormField, 'Email'), 'registrar@demo.ph');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Password'), 'demo1234');
    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pumpAndSettle(const Duration(seconds: 1));

    expect(await RememberedEmail.read(), 'registrar@demo.ph');
  });

  testWidgets('the password is never written anywhere', (tester) async {
    await _pump(tester);

    await tester.enterText(
        find.widgetWithText(TextFormField, 'Email'), 'registrar@demo.ph');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Password'), 'demo1234');
    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pumpAndSettle(const Duration(seconds: 1));

    // Every stored value, not just the key this feature owns: the point
    // is that nothing anywhere in preferences holds the password.
    final prefs = await SharedPreferences.getInstance();
    for (final key in prefs.getKeys()) {
      expect(prefs.get(key).toString(), isNot(contains('demo1234')));
    }
  });

  testWidgets('a remembered email comes back ticked and filled in',
      (tester) async {
    await RememberedEmail.write('faculty@demo.ph');
    await _pump(tester);

    expect(find.text('faculty@demo.ph'), findsOneWidget);
    expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isTrue);
  });

  testWidgets('unticking it forgets, which is how a shared computer is cleared',
      (tester) async {
    await RememberedEmail.write('faculty@demo.ph');
    await _pump(tester);

    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Password'), 'demo1234');
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pumpAndSettle(const Duration(seconds: 1));

    expect(await RememberedEmail.read(), isNull);
  });

  testWidgets('the password field has a show-password toggle', (tester) async {
    await _pump(tester);
    expect(find.byTooltip('Show password'), findsOneWidget);

    await tester.tap(find.byTooltip('Show password'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Hide password'), findsOneWidget);
  });
}
