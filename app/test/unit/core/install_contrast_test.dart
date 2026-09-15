import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:logicclass/core/install/install_app_button.dart';
import 'package:logicclass/core/install/install_prompt_factory.dart';
import 'package:logicclass/core/theme/app_palette.dart';
import 'package:logicclass/core/theme/app_theme.dart';

/// The install button has to be readable in both themes.
///
/// It was not. The sign-in screen passed `onDarkSurface: true`, which
/// pinned the foreground to white -- and this app ships a light theme and
/// a dark one with no `themeMode` set, so the device decides. In the dark
/// theme white on deep blue reads at 15.7:1. In the light theme the
/// sign-in pane is white glass over a pale sky, so it was white on white
/// at **1.02:1**: the button rendered, took up space, and was invisible.
/// A device in light mode is the common case, so that is what most
/// people got.
///
/// These pump the real widget and read the colour it actually renders.
/// An earlier version of this file asserted that `colorScheme.primary`
/// contrasts well and passed happily with `Colors.white` still hardcoded
/// in the widget -- a test of the palette rather than of the button.
void main() {
  /// Flutter's `computeLuminance` is WCAG relative luminance, so this is
  /// the WCAG contrast ratio rather than an approximation of it.
  double contrast(Color a, Color b) {
    final la = a.computeLuminance();
    final lb = b.computeLuminance();
    final hi = la > lb ? la : lb;
    final lo = la > lb ? lb : la;
    return (hi + 0.05) / (lo + 0.05);
  }

  /// A translucent colour laid over an opaque one, as the renderer
  /// composites it. Contrast against a colour with alpha is meaningless
  /// on its own: the pane is see-through, and what shows through is half
  /// the answer.
  Color over(Color front, Color back) => Color.from(
        alpha: 1,
        red: front.r * front.a + back.r * (1 - front.a),
        green: front.g * front.a + back.g * (1 - front.a),
        blue: front.b * front.a + back.b * (1 - front.a),
      );

  /// What the sign-in card actually is: the glass pane composited over
  /// the ambient wash behind it.
  Color signInPane(GlassPalette glass) => over(glass.paneFill, glass.backdropTop);

  final themes = {
    'light': (theme: AppTheme.light(), glass: GlassPalette.light),
    'dark': (theme: AppTheme.dark(), glass: GlassPalette.dark),
  };

  Future<void> pump(WidgetTester tester, ThemeData theme, InstallOffer offer) async {
    await tester.pumpWidget(MaterialApp(
      theme: theme,
      home: Scaffold(
        body: Center(child: InstallAppButton(debugPrompt: _FakePrompt(offer))),
      ),
    ));
    await tester.pump();
  }

  /// What the label is painted with, resolved the way the framework
  /// resolves it for an enabled button.
  Color buttonForeground(WidgetTester tester) {
    final button = tester.widget<TextButton>(find.byType(TextButton));
    final resolved = button.style?.foregroundColor?.resolve(<WidgetState>{});
    expect(resolved, isNotNull, reason: 'the button must set a foreground');
    return resolved!;
  }

  group('the offer to install, on the sign-in pane', () {
    for (final entry in themes.entries) {
      final name = entry.key;
      final theme = entry.value.theme;
      final pane = signInPane(entry.value.glass);

      testWidgets('reads against the $name pane', (tester) async {
        await pump(tester, theme, InstallOffer.prompt);
        // 4.5:1 is WCAG AA for body text. The label is body-sized, so it
        // is held to that rather than the 3:1 bar for large text.
        expect(
          contrast(buttonForeground(tester), pane),
          greaterThanOrEqualTo(4.5),
          reason: 'the install label must be legible on the $name sign-in pane',
        );
      });

      testWidgets('and so does the iOS line in the $name theme', (tester) async {
        // Safari gets a sentence rather than a button, because it gives
        // nothing to press. It is the only install affordance an iPhone
        // has, so an unreadable one is the feature missing there.
        await pump(tester, theme, InstallOffer.instructions);
        final text = tester.widget<Text>(find.textContaining('Add to Home Screen'));
        final colour = text.style?.color;
        expect(colour, isNotNull, reason: 'the instructions must set a colour');
        expect(
          contrast(colour!, pane),
          greaterThanOrEqualTo(4.5),
          reason: 'the instructions must be legible on the $name sign-in pane',
        );

        final icon = tester.widget<Icon>(find.byIcon(Icons.ios_share));
        expect(icon.color, isNotNull);
        // 3:1 is the WCAG bar for a non-text graphic carrying meaning.
        expect(contrast(icon.color!, pane), greaterThanOrEqualTo(3.0));
      });

      testWidgets('and on an ordinary surface too, which is Profile',
          (tester) async {
        // Profile's panes sit on the scheme's surface rather than the
        // sign-in glass. Same button, different ground.
        await pump(tester, theme, InstallOffer.prompt);
        expect(
          contrast(buttonForeground(tester), theme.colorScheme.surface),
          greaterThanOrEqualTo(4.5),
        );
      });
    }

    testWidgets('and nothing at all is offered when there is nothing to offer',
        (tester) async {
      await pump(tester, AppTheme.light(), InstallOffer.none);
      expect(find.byType(TextButton), findsNothing);
      expect(find.textContaining('Add to Home Screen'), findsNothing);
    });
  });

  test('white, which is what it used to be, fails the light pane', () {
    // The regression itself, kept so the reason the flag was removed does
    // not have to be taken on trust.
    expect(contrast(Colors.white, signInPane(GlassPalette.dark)),
        greaterThan(10.0), reason: 'fine on the dark pane, which is why it shipped');
    expect(contrast(Colors.white, signInPane(GlassPalette.light)),
        lessThan(1.1), reason: 'and the same colour as the light one');
  });
}

/// A browser that offers exactly what the test says it does.
class _FakePrompt extends InstallPrompt {
  final InstallOffer _offer;
  const _FakePrompt(this._offer);

  @override
  InstallOffer get offer => _offer;

  @override
  Future<bool> show() async => true;

  @override
  void Function() listen(void Function() onChange) => () {};
}
