import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logicclass/demo/demo_overrides.dart';
import 'package:logicclass/demo/demo_switcher.dart';
import 'package:logicclass/demo/demo_store.dart';
import 'package:logicclass/main.dart';

/// The demo role switcher is layered over every screen, so a build error in
/// it takes the whole app down -- and in a release web build that shows up
/// as a frozen grey overlay with nothing in the console. This opens the
/// panel so any such error surfaces here instead.
void main() {
  testWidgets('the demo switcher panel opens without throwing', (tester) async {
    await tester.pumpWidget(
      ProviderScope(overrides: demoOverrides(), child: const LogicClassApp()),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(demoSwitcherButtonKey));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Demo mode'), findsOneWidget);
    // The role list is scrollable, so only the visible tiles are built --
    // assert the panel rendered its list rather than every row. That each
    // role actually reaches its portal is covered in demo_app_boot_test.
    expect(find.text(DemoStore.demoAccounts.first.role.displayName), findsWidgets);
    expect(find.byType(ListTile), findsWidgets);
  });

  testWidgets('the switcher does not sit on top of a screen FAB', (tester) async {
    // 15 screens put their primary action in the default bottom-right FAB
    // slot. The switcher must stay clear of it, or those buttons become
    // unreachable -- which is exactly what happened when it was anchored
    // bottom-right.
    await tester.pumpWidget(
      ProviderScope(overrides: demoOverrides(), child: const LogicClassApp()),
    );
    await tester.pumpAndSettle();

    final screenSize = tester.view.physicalSize / tester.view.devicePixelRatio;
    final switcher = tester.getCenter(find.byKey(demoSwitcherButtonKey));

    expect(
      switcher.dx,
      lessThan(screenSize.width / 2),
      reason: 'switcher must stay on the left half, away from the FAB slot',
    );
  });
}
