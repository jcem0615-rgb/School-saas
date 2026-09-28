import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'theme_choice.dart';
import 'theme_controller.dart';

/// Light, dark, or whatever the device is set to.
///
/// Three buttons rather than one switch, because two of the three
/// answers are not opposites. "Dark" off could mean "light" or it could
/// mean "follow my phone", and a switch cannot say which -- so a person
/// who turns dark off on a phone that is itself dark gets a result
/// nobody chose. Three named choices have no such gap.
///
/// It applies the moment it is pressed. There is no Save: a setting you
/// can see the result of does not need confirming, and a theme that
/// waited for a button would be a theme somebody pressed twice.
class ThemeSwitch extends ConsumerWidget {
  const ThemeSwitch({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final chosen = ref.watch(themeChoiceProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text(
            'Appearance',
            style: theme.textTheme.titleMedium,
          ),
        ),
        // Wrapped and scrollable-free: at phone width with a large text
        // scale three segments and their labels do not fit across, and
        // a segmented button that overflows throws rather than wrapping.
        LayoutBuilder(
          builder: (context, box) {
            final tight = box.maxWidth <
                320 * MediaQuery.textScalerOf(context).scale(1);
            if (tight) {
              return Column(
                children: [
                  for (final choice in ThemeChoice.values)
                    RadioTileFor(
                      choice: choice,
                      chosen: chosen,
                      onChosen: (next) =>
                          ref.read(themeChoiceProvider.notifier).choose(next),
                    ),
                ],
              );
            }
            return SegmentedButton<ThemeChoice>(
              segments: [
                for (final choice in ThemeChoice.values)
                  ButtonSegment<ThemeChoice>(
                    value: choice,
                    icon: Icon(choice.icon, size: 18),
                    label: Text(choice.label),
                  ),
              ],
              selected: {chosen},
              showSelectedIcon: false,
              onSelectionChanged: (picked) => ref
                  .read(themeChoiceProvider.notifier)
                  .choose(picked.first),
            );
          },
        ),
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            '${chosen.meaning}. This is yours — it follows your account, '
            'not the computer.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ),
      ],
    );
  }
}

/// One choice, as a row. Used where three across would not fit.
class RadioTileFor extends StatelessWidget {
  final ThemeChoice choice;
  final ThemeChoice chosen;
  final ValueChanged<ThemeChoice> onChosen;

  const RadioTileFor({
    super.key,
    required this.choice,
    required this.chosen,
    required this.onChosen,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selected = choice == chosen;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      onTap: () => onChosen(choice),
      leading: Icon(
        selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
        color:
            selected ? theme.colorScheme.primary : theme.colorScheme.outline,
      ),
      title: Text(choice.label),
      subtitle: Text(choice.meaning),
      trailing: Icon(choice.icon, color: theme.colorScheme.onSurfaceVariant),
    );
  }
}

/// The same choice as a single button, for a screen with no room.
///
/// It cycles automatic to light to dark and round again, and says which
/// it landed on, because a button that changes something without naming
/// the new state leaves a person pressing it to find out.
///
/// On the sign-in screen it writes to the signed-out slot -- somebody
/// reading a login page at night should be able to turn the lights down
/// before they have an account to remember it against.
class ThemeCycleButton extends ConsumerWidget {
  const ThemeCycleButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chosen = ref.watch(themeChoiceProvider);
    final next = ThemeChoice
        .values[(chosen.index + 1) % ThemeChoice.values.length];

    return TextButton.icon(
      onPressed: () => ref.read(themeChoiceProvider.notifier).choose(next),
      icon: Icon(chosen.icon, size: 18),
      label: Text(chosen.label),
    );
  }
}

/// The one-tap switch that lives in a portal's app bar.
///
/// It reads the brightness that is actually on the screen rather than
/// the setting behind it, which is what makes one tap always do
/// something visible. On Automatic on a phone that is itself dark, a
/// button offering "dark" would appear to do nothing; this one offers
/// light, because light is what is not currently there.
///
/// Tapping therefore leaves Automatic, which is correct: somebody
/// reaching for this has an opinion about right now. Automatic is still
/// one tap away in Profile, which is where a setting that means
/// "decide for me" belongs.
class ThemeToggleButton extends ConsumerWidget {
  const ThemeToggleButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Theme.of, not the provider: this is the brightness the person is
    // looking at, and depending on it is also what rebuilds the button
    // the moment it changes.
    final dark = Theme.of(context).brightness == Brightness.dark;
    final next = dark ? ThemeChoice.light : ThemeChoice.dark;

    return IconButton(
      icon: Icon(dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined),
      tooltip: dark ? 'Switch to light mode' : 'Switch to dark mode',
      onPressed: () => ref.read(themeChoiceProvider.notifier).choose(next),
    );
  }
}
