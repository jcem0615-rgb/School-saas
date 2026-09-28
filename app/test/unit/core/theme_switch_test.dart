import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logicclass/core/constants/user_roles.dart';
import 'package:logicclass/core/theme/theme_choice.dart';
import 'package:logicclass/core/theme/theme_controller.dart';
import 'package:logicclass/core/theme/theme_preference.dart';
import 'package:logicclass/core/theme/theme_switch.dart';
import 'package:logicclass/features/auth/domain/entities/app_user.dart';
import 'package:logicclass/features/auth/presentation/controllers/auth_controller.dart'
    show authStateProvider;
import 'package:shared_preferences/shared_preferences.dart';

/// The switch, and the thing it is supposed to switch.
///
/// Tested through a real MaterialApp rather than by reading the
/// provider back, because "the setting changed" and "the app changed
/// colour" are two different claims and only the second is the feature.
void main() {
  late StreamController<AppUser?> signedIn;

  AppUser account(String uid) => AppUser(
        uid: uid,
        schoolId: 'school-1',
        role: UserRole.faculty,
        firstName: 'Maria',
        lastName: 'Santos',
        email: '$uid@school.test',
        status: UserAccountStatus.active,
        mustChangePassword: false,
        qrCode: 'qr_$uid',
      );

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await ThemePreference.warmUp();
    signedIn = StreamController<AppUser?>.broadcast();
  });

  tearDown(() async {
    await signedIn.close();
    ThemePreference.useForTesting(null);
  });

  /// A whole app, so the brightness being asserted is the real one.
  Future<BuildContext> pumpApp(WidgetTester tester) async {
    late BuildContext captured;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authStateProvider.overrideWith((ref) => signedIn.stream),
        ],
        child: Consumer(
          builder: (context, ref, _) => MaterialApp(
            theme: ThemeData(brightness: Brightness.light),
            darkTheme: ThemeData(brightness: Brightness.dark),
            themeMode: ref.watch(themeChoiceProvider).mode,
            home: Builder(
              builder: (context) {
                captured = context;
                return const Scaffold(body: ThemeSwitch());
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return captured;
  }

  Brightness brightnessOf(WidgetTester tester) =>
      Theme.of(tester.element(find.byType(Scaffold))).brightness;

  testWidgets('turns the app dark, and back to light', (tester) async {
    await pumpApp(tester);
    expect(brightnessOf(tester), Brightness.light,
        reason: 'the test binding reports a light device');

    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();
    expect(brightnessOf(tester), Brightness.dark);

    await tester.tap(find.text('Light'));
    await tester.pumpAndSettle();
    expect(brightnessOf(tester), Brightness.light);
  });

  testWidgets('offers all three, and says what the chosen one means',
      (tester) async {
    // Three rather than one switch: "dark off" could mean light or it
    // could mean follow the device, and a switch cannot say which.
    await pumpApp(tester);

    for (final choice in ThemeChoice.values) {
      expect(find.text(choice.label), findsOneWidget);
    }
    expect(find.textContaining(ThemeChoice.system.meaning), findsOneWidget);

    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();
    expect(find.textContaining(ThemeChoice.dark.meaning), findsOneWidget);
  });

  testWidgets('remembers it for the account that chose it', (tester) async {
    await pumpApp(tester);
    signedIn.add(account('user_a'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();

    expect(ThemePreference.read('user_a'), ThemeChoice.dark);
  });

  testWidgets('swaps with the account, on a shared computer',
      (tester) async {
    // The morning receptionist likes dark. The afternoon one signs in
    // and gets the app as the school set it up.
    await ThemePreference.write('morning', ThemeChoice.dark);
    await pumpApp(tester);

    signedIn.add(account('morning'));
    await tester.pumpAndSettle();
    expect(brightnessOf(tester), Brightness.dark);

    signedIn.add(account('afternoon'));
    await tester.pumpAndSettle();
    expect(brightnessOf(tester), Brightness.light);

    signedIn.add(account('morning'));
    await tester.pumpAndSettle();
    expect(brightnessOf(tester), Brightness.dark);
  });

  testWidgets('stays where it was put when the account stream re-emits',
      (tester) async {
    // A profile edit makes the account stream emit the same person
    // again, which re-runs the provider. Re-reading storage there would
    // undo a choice made a moment earlier whose write had not yet
    // reached the disk.
    await pumpApp(tester);
    signedIn.add(account('user_a'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();
    expect(brightnessOf(tester), Brightness.dark);

    signedIn.add(account('user_a'));
    await tester.pumpAndSettle();

    expect(brightnessOf(tester), Brightness.dark);
  });

  testWidgets('applies on the first frame, without a flash of the wrong one',
      (tester) async {
    // Read synchronously from a store opened before runApp. Read a
    // frame late, a person who chose dark would watch the app open
    // white and then change its mind in front of them.
    await ThemePreference.write(null, ThemeChoice.dark);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authStateProvider.overrideWith((ref) => signedIn.stream),
        ],
        child: Consumer(
          builder: (context, ref, _) => MaterialApp(
            theme: ThemeData(brightness: Brightness.light),
            darkTheme: ThemeData(brightness: Brightness.dark),
            themeMode: ref.watch(themeChoiceProvider).mode,
            home: const Scaffold(body: SizedBox()),
          ),
        ),
      ),
    );
    // One frame. No settle, no waiting for a future.
    await tester.pump();

    expect(brightnessOf(tester), Brightness.dark);
  });

  testWidgets('the one-button version names where it has got to',
      (tester) async {
    // A button that changes something without saying what it changed to
    // leaves a person pressing it to find out.
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authStateProvider.overrideWith((ref) => signedIn.stream),
        ],
        child: const MaterialApp(home: Scaffold(body: ThemeCycleButton())),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(ThemeChoice.system.label), findsOneWidget);

    await tester.tap(find.text(ThemeChoice.system.label));
    await tester.pumpAndSettle();
    expect(find.text(ThemeChoice.light.label), findsOneWidget);

    await tester.tap(find.text(ThemeChoice.light.label));
    await tester.pumpAndSettle();
    expect(find.text(ThemeChoice.dark.label), findsOneWidget);

    // And round again, rather than stopping at the end.
    await tester.tap(find.text(ThemeChoice.dark.label));
    await tester.pumpAndSettle();
    expect(find.text(ThemeChoice.system.label), findsOneWidget);
  });

  testWidgets('a device that remembers nothing still switches', (tester) async {
    // A private window, a locked-down browser. The setting applies for
    // this session and is forgotten after it -- it must not fail to
    // apply at all.
    ThemePreference.useForTesting(null);
    await pumpApp(tester);

    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();

    expect(brightnessOf(tester), Brightness.dark);
  });

  testWidgets('the app bar button offers what is not on the screen',
      (tester) async {
    // On Automatic on a device that is itself dark, a button offering
    // dark would appear to do nothing. This one reads the brightness
    // the person is looking at, so one tap always changes something.
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authStateProvider.overrideWith((ref) => signedIn.stream),
        ],
        child: Consumer(
          builder: (context, ref, _) => MaterialApp(
            theme: ThemeData(brightness: Brightness.light),
            darkTheme: ThemeData(brightness: Brightness.dark),
            themeMode: ref.watch(themeChoiceProvider).mode,
            home: const Scaffold(
              body: Center(child: ThemeToggleButton()),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byTooltip('Switch to dark mode'), findsOneWidget);
    await tester.tap(find.byTooltip('Switch to dark mode'));
    await tester.pumpAndSettle();

    expect(brightnessOf(tester), Brightness.dark);
    // Not a one-way door.
    expect(find.byTooltip('Switch to light mode'), findsOneWidget);

    await tester.tap(find.byTooltip('Switch to light mode'));
    await tester.pumpAndSettle();
    expect(brightnessOf(tester), Brightness.light);
  });

  testWidgets('and remembers it against the account that pressed it',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authStateProvider.overrideWith((ref) => signedIn.stream),
        ],
        child: Consumer(
          builder: (context, ref, _) => MaterialApp(
            theme: ThemeData(brightness: Brightness.light),
            darkTheme: ThemeData(brightness: Brightness.dark),
            themeMode: ref.watch(themeChoiceProvider).mode,
            home: const Scaffold(body: ThemeToggleButton()),
          ),
        ),
      ),
    );
    signedIn.add(account('user_a'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Switch to dark mode'));
    await tester.pumpAndSettle();

    expect(ThemePreference.read('user_a'), ThemeChoice.dark);
  });
}
