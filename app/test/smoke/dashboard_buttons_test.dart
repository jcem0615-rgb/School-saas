import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:school_saas/core/constants/user_roles.dart';
import 'package:school_saas/demo/demo_overrides.dart';
import 'package:school_saas/demo/demo_store.dart';
import 'package:school_saas/main.dart' as app;

/// Every dashboard tile, for every role, actually goes somewhere.
///
/// The portals are mostly a grid of navigation tiles, and a tile whose
/// onTap pushes nothing -- or pushes a screen that throws on build -- looks
/// identical to a working one until you press it. This walks all ten
/// dashboards, presses every tile, and asserts the press both left the
/// dashboard and raised no exception.
Future<ProviderContainer> pumpAs(WidgetTester tester, UserRole role) async {
  tester.view.physicalSize = const Size(1280, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final c = ProviderContainer(overrides: demoOverrides());
  addTearDown(c.dispose);
  c.read(demoAuthRepositoryProvider).signInAs(
      DemoStore.demoAccounts.firstWhere((a) => a.role == role));

  await tester.pumpWidget(
      UncontrolledProviderScope(container: c, child: const app.SchoolSaasApp()));
  await tester.pumpAndSettle();
  return c;
}

/// Labels of every enabled, tappable tile currently on screen.
List<String> tileLabels(WidgetTester tester) {
  final out = <String>[];
  for (final element in find.byType(InkWell).evaluate()) {
    final inkWell = element.widget as InkWell;
    if (inkWell.onTap == null) continue;
    final texts = find
        .descendant(of: find.byWidget(inkWell), matching: find.byType(Text))
        .evaluate()
        .map((e) => (e.widget as Text).data)
        .whereType<String>()
        .where((s) => s.trim().isNotEmpty)
        .toList();
    if (texts.isNotEmpty && !out.contains(texts.first)) out.add(texts.first);
  }
  return out;
}

String currentTitle(WidgetTester tester) {
  final appBars = find.byType(AppBar).evaluate();
  if (appBars.isEmpty) return '(no app bar)';
  final title = find
      .descendant(of: find.byWidget(appBars.first.widget), matching: find.byType(Text))
      .evaluate();
  return title.isEmpty ? '(untitled)' : ((title.first.widget as Text).data ?? '');
}

/// Pops whatever the tile opened -- a pushed route or a dialog -- so the
/// next tile is pressed from the dashboard again.
Future<void> popBack(WidgetTester tester) async {
  final navigators = find.byType(Navigator).evaluate().toList();
  if (navigators.isEmpty) return;
  for (final element in navigators.reversed) {
    final nav = (element as StatefulElement).state as NavigatorState;
    if (nav.canPop()) {
      nav.pop();
      await tester.pumpAndSettle();
      return;
    }
  }
}

void main() {
  for (final role in UserRole.values) {
    testWidgets('${role.value} \u00b7 every dashboard tile responds', (tester) async {
      await pumpAs(tester, role);
      final home = currentTitle(tester);
      final labels = tileLabels(tester);

      expect(labels, isNotEmpty,
          reason: '${role.value} dashboard exposes no tappable tiles at all');

      final broken = <String>[];
      final inert = <String>[];

      for (final label in labels) {
        final target = find.text(label);
        if (target.evaluate().isEmpty) continue;
        await tester.ensureVisible(target.first);
        await tester.pumpAndSettle();
        await tester.tap(target.first, warnIfMissed: false);
        await tester.pumpAndSettle();

        final err = tester.takeException();
        if (err != null) {
          broken.add('$label -> ${err.toString().split('\n').first}');
          await popBack(tester);
          continue;
        }
        // A tile has done something if it changed the app bar title or put a
        // dialog on screen.
        final movedTo = currentTitle(tester);
        final openedDialog = find.byType(Dialog).evaluate().isNotEmpty ||
            find.byType(AlertDialog).evaluate().isNotEmpty ||
            find.byType(BottomSheet).evaluate().isNotEmpty;
        if (movedTo == home && !openedDialog) inert.add(label);

        await popBack(tester);
      }

      expect(broken, isEmpty, reason: '${role.value}: tiles that threw on open');
      expect(inert, isEmpty,
          reason: '${role.value}: tiles that did nothing (still on "$home")');
    });
  }
}
