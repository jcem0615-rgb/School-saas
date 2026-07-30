import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:school_saas/core/constants/user_roles.dart';
import 'package:school_saas/core/theme/app_theme.dart';
import 'package:school_saas/demo/demo_overrides.dart';
import 'package:school_saas/demo/demo_store.dart';
import 'package:school_saas/features/director_portal/presentation/screens/expenses_screen.dart';

void main() {
  testWidgets('diagnose expenses overflow', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final onError = FlutterError.onError;
    FlutterError.onError = (details) {
      // ignore: avoid_print
      print('>>> OVERFLOW DETAILS:\n${details.exception}\nCONTEXT: ${details.context}\nLIBRARY: ${details.library}\n${details.informationCollector?.call().map((n) => n.toString()).join('\n') ?? ''}');
      onError?.call(details);
    };
    addTearDown(() => FlutterError.onError = onError);

    final c = ProviderContainer(overrides: demoOverrides());
    addTearDown(c.dispose);
    c.read(demoAuthRepositoryProvider).signInAs(
        DemoStore.demoAccounts.firstWhere((a) => a.role == UserRole.director));

    await tester.pumpWidget(UncontrolledProviderScope(
        container: c,
        child: MaterialApp(theme: AppTheme.light(), home: const ExpensesScreen())));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    tester.takeException();
  });
}
