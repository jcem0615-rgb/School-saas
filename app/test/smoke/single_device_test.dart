import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:logicclass/core/constants/user_roles.dart';
import 'package:logicclass/core/session/device_identity.dart';
import 'package:logicclass/core/session/session_guard.dart';
import 'package:logicclass/core/session/session_providers.dart';
import 'package:logicclass/core/session/single_device_session.dart';
import 'package:logicclass/core/theme/app_theme.dart';
import 'package:logicclass/demo/demo_overrides.dart';
import 'package:logicclass/demo/demo_store.dart';
import 'package:logicclass/features/auth/presentation/controllers/auth_controller.dart';
import 'package:logicclass/features/profile/presentation/screens/profile_screen.dart';

/// One account, one device -- and a sign-out button a person can find.
///
/// The two belong in one file because they are the same story from two
/// ends: the deliberate way out of a session, and the involuntary one.
class _FakeGuard implements SessionGuard {
  final _claims = StreamController<DeviceClaim?>.broadcast();
  final claimed = <DeviceClaim>[];

  @override
  Future<void> claim(DeviceClaim claim) async => claimed.add(claim);

  @override
  Stream<DeviceClaim?> watch() => _claims.stream;

  void somebodyElseSignedIn(String deviceId, {String label = 'an Android device'}) =>
      _claims.add(DeviceClaim(deviceId: deviceId, deviceLabel: label));

  void dispose() => _claims.close();
}

/// A guard whose claim always fails, standing in for being offline or
/// for rules saying no.
class _RefusingGuard extends _FakeGuard {
  @override
  Future<void> claim(DeviceClaim claim) async => throw StateError('offline');
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('the verdict a device reaches', () {
    test('nobody has claimed the account, so claim it', () {
      expect(
        verdictFor(myDeviceId: 'me', claim: null),
        SessionVerdict.unclaimed,
      );
    });

    test('this device holds it, so carry on', () {
      expect(
        verdictFor(
          myDeviceId: 'me',
          claim: const DeviceClaim(deviceId: 'me', deviceLabel: 'a web browser'),
        ),
        SessionVerdict.hold,
      );
    });

    test('somebody else holds it, so sign out', () {
      expect(
        verdictFor(
          myDeviceId: 'me',
          claim: const DeviceClaim(deviceId: 'them', deviceLabel: 'a Mac'),
        ),
        SessionVerdict.displaced,
      );
    });
  });

  group('this installation', () {
    test('keeps the same id across restarts', () async {
      final first = await StoredDeviceIdentity().id();
      final second = await StoredDeviceIdentity().id();

      expect(first, isNotNull);
      expect(second, first,
          reason: 'a new id per launch would displace the account every launch');
    });

    test('is not the same as another installation', () async {
      final mine = await StoredDeviceIdentity().id();
      SharedPreferences.setMockInitialValues({});
      final theirs = await StoredDeviceIdentity().id();

      expect(theirs, isNot(mine));
    });

    test('says nothing rather than guessing when it cannot remember', () async {
      // Storage that accepts a write and keeps nothing -- a private
      // window, or a browser with site data blocked. The id has to come
      // back null so the rule switches itself off, rather than minting a
      // fresh one that reads as a new device every single launch.
      final identity = StoredDeviceIdentity(preloaded: () => _AmnesiacPrefs());
      expect(await identity.id(), isNull);
    });
  });

  group('a second sign-in elsewhere', () {
    Future<(ProviderContainer, _FakeGuard)> signedIn(
      WidgetTester tester, {
      _FakeGuard? guard,
      String? deviceId = 'device_a',
    }) async {
      final fake = guard ?? _FakeGuard();
      addTearDown(fake.dispose);

      final container = ProviderContainer(overrides: [
        ...demoOverrides(),
        deviceIdentityProvider.overrideWithValue(FixedDeviceIdentity(deviceId)),
        sessionGuardProvider.overrideWithValue(fake),
      ]);
      addTearDown(container.dispose);

      container.read(demoAuthRepositoryProvider).signInAs(
            DemoStore.demoAccounts.firstWhere((a) => a.role == UserRole.faculty),
          );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const SingleDeviceSession(child: Text('the portal')),
          ),
        ),
      );
      // The claim runs in a post-frame callback and then awaits twice --
      // the device id, then the write. Pumped rather than settled: there
      // is nothing animating, and pumpAndSettle would only hide how many
      // frames this actually takes.
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      return (container, fake);
    }

    testWidgets('this device claims the account on sign-in', (tester) async {
      final (container, fake) = await signedIn(tester);

      expect(fake.claimed.single.deviceId, 'device_a');
      expect(container.read(authStateProvider).valueOrNull, isNotNull);
    });

    testWidgets('signs this one out', (tester) async {
      final (container, fake) = await signedIn(tester);
      expect(container.read(authStateProvider).valueOrNull, isNotNull);

      fake.somebodyElseSignedIn('device_b');
      // The demo repository puts 200ms of pretend latency on a sign-out.
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(container.read(authStateProvider).valueOrNull, isNull,
          reason: 'the device that lost the claim has to let go of the session');
    });

    testWidgets('leaves this one alone when the claim is its own', (tester) async {
      // The device re-announcing itself -- a reconnect, a token refresh,
      // the write this device just made echoing back. Signing out on that
      // would make the app unusable for one device as surely as for two.
      final (container, fake) = await signedIn(tester);

      fake.somebodyElseSignedIn('device_a');
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(container.read(authStateProvider).valueOrNull, isNotNull);
    });

    testWidgets('cannot displace a device that could not be identified',
        (tester) async {
      final (container, fake) = await signedIn(tester, deviceId: null);

      expect(fake.claimed, isEmpty,
          reason: 'nothing to claim with, so nothing is claimed');

      fake.somebodyElseSignedIn('device_b');
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(container.read(authStateProvider).valueOrNull, isNotNull,
          reason: 'a browser that cannot remember an id must still be usable');
    });

    testWidgets('does not act on a claim it never managed to make',
        (tester) async {
      // Offline at sign-in. The document on the server may hold an older
      // claim by another device; acting on it would sign this person out
      // of an account nobody else is actually using.
      final (container, _) = await signedIn(tester, guard: _RefusingGuard());

      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(container.read(authStateProvider).valueOrNull, isNotNull);
    });
  });

  group('signing out on purpose', () {
    Future<ProviderContainer> openProfile(WidgetTester tester) async {
      final container = ProviderContainer(overrides: demoOverrides());
      addTearDown(container.dispose);
      container.read(demoAuthRepositoryProvider).signInAs(
            DemoStore.demoAccounts.firstWhere((a) => a.role == UserRole.parent),
          );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(theme: AppTheme.light(), home: const ProfileScreen()),
        ),
      );
      await tester.pumpAndSettle();
      return container;
    }

    /// The button is the last thing on a long screen, so nothing has
    /// built it yet -- a ListView only builds what is on screen. Scrolled
    /// into view rather than moved somewhere shallower: the bottom is
    /// where a settings screen's sign-out belongs, and a test that had to
    /// move it would be testing a layout nobody ships.
    final signOutTile = find.widgetWithText(ListTile, 'Sign out');

    Future<void> scrollToSignOut(WidgetTester tester) async {
      await tester.scrollUntilVisible(signOutTile, 300,
          scrollable: find.byType(Scrollable).first);
      await tester.pumpAndSettle();
    }

    testWidgets('is a labelled button, not only an icon', (tester) async {
      await openProfile(tester);
      await scrollToSignOut(tester);

      // The icon in the app bar was the whole of it, and people asked
      // where sign-out was while looking straight at it.
      expect(signOutTile, findsOneWidget);
    });

    testWidgets('asks first, and backing out keeps the session', (tester) async {
      final container = await openProfile(tester);
      await scrollToSignOut(tester);

      await tester.tap(signOutTile);
      await tester.pumpAndSettle();
      expect(find.text('Sign out?'), findsOneWidget);

      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('Sign out?'), findsNothing);
      expect(container.read(authStateProvider).valueOrNull, isNotNull);
    });

    testWidgets('names the account being signed out', (tester) async {
      // A school computer is shared. "Sign out?" on its own does not tell
      // the person at the keyboard whose session they are about to end.
      await openProfile(tester);
      await scrollToSignOut(tester);
      final parent =
          DemoStore.demoAccounts.firstWhere((a) => a.role == UserRole.parent);

      await tester.tap(signOutTile);
      await tester.pumpAndSettle();

      expect(find.textContaining(parent.email), findsOneWidget);
    });

    testWidgets('confirming ends the session', (tester) async {
      final container = await openProfile(tester);
      await scrollToSignOut(tester);

      await tester.tap(signOutTile);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Sign out'));
      // Not settled: the screen falls back to a spinner once there is no
      // user, and pumpAndSettle never returns with one of those on it.
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(container.read(authStateProvider).valueOrNull, isNull);
    });
  });
}

/// Storage that takes a write and forgets it.
class _AmnesiacPrefs implements SharedPreferences {
  @override
  String? getString(String key) => null;

  @override
  Future<bool> setString(String key, String value) async => true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
