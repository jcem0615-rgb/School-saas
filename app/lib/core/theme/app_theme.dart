import 'package:flutter/material.dart';

import 'app_palette.dart';

/// App-wide Material 3 theme.
///
/// One seed colour drives both brightness variants so every portal shares
/// the same palette -- roles differ in what they can see, not in how the
/// app looks. Card, input, and app-bar defaults are set here rather than
/// per screen, since the portal screens were written against Material
/// defaults and pick these up automatically.
///
/// The surfaces are glass: translucent panes over an [AmbientBackground]
/// installed above the router. That is why the scaffold, app bar and cards
/// are all transparent here -- an opaque scaffold would cover the wash and
/// leave the panes floating on nothing. The two things that stay dense are
/// dialogs and menus, where legibility of small text beats the effect.
class AppTheme {
  AppTheme._();

  /// Azure rather than the older institutional navy: at low opacity over a
  /// light backdrop navy goes grey and stops reading as a colour at all,
  /// which is most of a glass UI's surface area. Still cool and sober
  /// enough for a records system, and it holds its identity in both
  /// brightnesses.
  static const _seed = Color(0xFF2E5FD9);

  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isLight = brightness == Brightness.light;
    final scheme = ColorScheme.fromSeed(seedColor: _seed, brightness: brightness);
    final glass = isLight ? GlassPalette.light : GlassPalette.dark;

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      extensions: [glass],
      // The ambient wash paints the ground; anything opaque here would
      // cover it.
      scaffoldBackgroundColor: Colors.transparent,
      canvasColor: Colors.transparent,
      textTheme: _textTheme(scheme),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: scheme.onSurface,
          fontSize: 21,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.2,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: glass.paneFill,
        surfaceTintColor: Colors.transparent,
        shadowColor: glass.paneShadow,
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: glass.paneBorder),
        ),
        clipBehavior: Clip.antiAlias,
      ),
      // Fields are recessed, not raised. Every other surface in this theme
      // stands proud of the backdrop; a field has to read as somewhere you
      // put something *into*, which on a white pane means a tinted well
      // and a border you can actually see rather than white-on-white.
      //
      // Every border state is named, not just `border`. InputDecoration
      // resolves the enabled, focused, disabled and error states from
      // their own slots first and only falls back to `border`, so setting
      // one and not the others is how a form ends up with one field styled
      // and the next one not. This is now the only place any of them is
      // set: the inline overrides the screens used to carry were stripped
      // once they became inert, so there is nothing left to drift.
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: glass.fieldFill,
        border: _inputBorder(glass.fieldBorder),
        enabledBorder: _inputBorder(glass.fieldBorder),
        disabledBorder: _inputBorder(glass.paneBorder),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: scheme.primary, width: 1.6),
        ),
        errorBorder: _inputBorder(scheme.error),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: scheme.error, width: 1.6),
        ),
        // Multi-line fields put the label and hint against the first line
        // rather than floating them in the middle of an empty box.
        alignLabelWithHint: true,
        hintStyle: TextStyle(color: scheme.onSurfaceVariant),
        prefixIconColor: scheme.onSurfaceVariant,
        suffixIconColor: scheme.onSurfaceVariant,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          side: BorderSide(color: glass.paneBorder),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: glass.paneFill,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        side: BorderSide(color: glass.paneBorder),
      ),
      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      ),
      dividerTheme: DividerThemeData(color: glass.paneBorder, space: 1, thickness: 1),
      // Dense, not translucent. A dialog sits over whatever the user was
      // reading, and frosted small text over an arbitrary background is
      // the point where the effect starts costing legibility.
      dialogTheme: DialogThemeData(
        backgroundColor: glass.paneFillStrong,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: glass.paneBorder),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: glass.paneFillStrong,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: glass.paneBorder),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: glass.paneFillStrong,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: scheme.primary),
    );
  }

  static OutlineInputBorder _inputBorder(Color colour) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: colour),
      );

  /// Tightened rather than replaced.
  ///
  /// No web font: the app has to start on a school's connection and, in
  /// demo mode, with no network at all, and a display face that arrives
  /// late reflows the first screen a student sees. The character comes from
  /// weight and spacing instead -- heavy, slightly tightened headings
  /// against normal-width body text.
  static TextTheme _textTheme(ColorScheme scheme) {
    return TextTheme(
      headlineSmall: TextStyle(
        fontWeight: FontWeight.w700,
        letterSpacing: -0.4,
        color: scheme.onSurface,
      ),
      titleLarge: TextStyle(
        fontSize: 19,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.2,
        color: scheme.onSurface,
      ),
      titleMedium: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: scheme.onSurface,
      ),
      titleSmall: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: scheme.onSurface,
      ),
      bodyMedium: TextStyle(fontSize: 14, height: 1.45, color: scheme.onSurface),
      bodySmall: TextStyle(
        fontSize: 12.5,
        height: 1.4,
        color: scheme.onSurfaceVariant,
      ),
      labelLarge: const TextStyle(fontWeight: FontWeight.w600),
    );
  }
}
