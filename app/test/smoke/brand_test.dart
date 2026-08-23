import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:logicclass/core/theme/app_theme.dart';
import 'package:logicclass/core/widgets/brand.dart';

/// The brand marks are files loaded by name, which is the kind of thing
/// that breaks silently: a renamed asset, or one added but never declared
/// in pubspec, shows an empty box rather than throwing.
void main() {
  Widget wrap(Widget child, {required Brightness brightness}) => MaterialApp(
        theme: brightness == Brightness.dark ? AppTheme.dark() : AppTheme.light(),
        home: Scaffold(body: Center(child: child)),
      );

  test('every brand asset the app names is actually on disk', () {
    // The dark logo went missing once because it existed but nothing
    // carried it. Naming the files here means a rename has to be
    // deliberate.
    for (final name in const [
      'logicclass-logo.svg',
      'logicclass-logo-dark.svg',
      'logicclass-icon.svg',
      'logicgrid-logo.svg',
    ]) {
      expect(File('assets/brand/$name').existsSync(), isTrue,
          reason: '$name is referenced but not present');
    }
  });

  test('pubspec declares the brand folder', () {
    // Present on disk but undeclared is the same as absent at runtime.
    expect(File('pubspec.yaml').readAsStringSync(), contains('assets/brand/'));
  });

  testWidgets('the mark renders in both themes', (tester) async {
    for (final brightness in Brightness.values) {
      await tester.pumpWidget(
        wrap(const LogicClassMark(size: 64), brightness: brightness),
      );
      expect(find.byType(LogicClassMark), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('the credit names LogicGrid and reads as one label',
      (tester) async {
    await tester.pumpWidget(
      wrap(const PoweredByLogicGrid(), brightness: Brightness.light),
    );

    expect(find.textContaining('LogicGrid', findRichText: true), findsOneWidget);
    // The row is a mark plus two text spans; a screen reader should hear
    // the sentence once, not the logo and the words as separate stops.
    expect(
      tester.getSemantics(find.byType(PoweredByLogicGrid)).label,
      contains('Powered by LogicGrid'),
    );
  });
}
