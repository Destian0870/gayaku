import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Colour tokens for one mode.
///
/// One `const` instance per mode, carried on the theme as a [ThemeExtension] and
/// read through [AppColors.of]. The palette rides on the theme instead of being
/// looked up from `Theme.brightness`, because both modes are dark grounds:
/// brightness can no longer say which navy you are standing on.
///
/// Measured WCAG contrast for every pair the design leans on:
///
/// - [light]: ink/canvas 14.85, ink/card 12.25, inkMuted/canvas 7.84,
///   action/canvas 3.15, onAction/action 4.55, accent/canvas 8.36,
///   actionInk/card 4.95, nav pill/card 1.73.
/// - [dark]: ink/canvas 15.78, ink/card 14.05, inkMuted/canvas 7.13,
///   action/canvas 3.43, onAction/action 4.55, accent/canvas 9.38,
///   actionInk/card 6.00, nav pill/card 1.70.
@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.canvas,
    required this.surface,
    required this.surfaceMuted,
    required this.sheet,
    required this.accentTint,
    required this.ink,
    required this.inkMuted,
    required this.action,
    required this.onAction,
    required this.accent,
    required this.accentInk,
    required this.onAccent,
    required this.actionInk,
  });

  /// Screen background.
  final Color canvas;

  /// Cards, panels and the bottom nav.
  final Color surface;

  /// Image and scanner areas.
  final Color surfaceMuted;

  /// Bottom sheets, dialogs, text fields.
  final Color sheet;

  /// Selected chips, and the pill behind the selected bottom-nav item.
  final Color accentTint;

  /// Primary text. 14.85 on canvas in [light], 15.78 in [dark].
  final Color ink;

  /// Secondary text. Never reach for opacity instead of this.
  final Color inkMuted;

  /// Primary action fill. A deep red, so at 3.15 on canvas in [light] it reads
  /// as a button but not as text: reach for [actionInk] to draw with it.
  final Color action;

  /// Label on [action].
  final Color onAction;

  /// Accent fill.
  final Color accent;

  /// The accent used as ink, for icons, borders and small marks. The light blue
  /// clears 8.36 on canvas, so both modes read it straight.
  final Color accentInk;

  /// Label on [accent].
  final Color onAccent;

  /// The action colour used as ink, for text, borders and marks. Mirrors
  /// [accentInk]: a red dark enough to fill a button is too dark to read on a
  /// navy ground, so the ink role lifts to 4.95 on a card.
  final Color actionInk;

  /// Midnight. The default ground: navy canvas, maroon action, light blue mark.
  static const light = AppPalette(
    canvas: Color(0xFF101F3C),
    surface: Color(0xFF1A2E52),
    surfaceMuted: Color(0xFF223C66),
    sheet: Color(0xFF16294B),
    accentTint: Color(0xFF3A5472),
    ink: Color(0xFFF1F4FA),
    inkMuted: Color(0xFFA8B4CB),
    action: Color(0xFFC63A2E),
    onAction: Color(0xFFFBEDEC),
    accent: Color(0xFF96C0CE),
    accentInk: Color(0xFF96C0CE),
    onAccent: Color(0xFF0C1A31),
    actionInk: Color(0xFFE2836F),
  );

  /// Midnight Deep. The same roles one step down, for a dark system setting.
  static const dark = AppPalette(
    canvas: Color(0xFF0A1428),
    surface: Color(0xFF131F3A),
    surfaceMuted: Color(0xFF1B2C4E),
    sheet: Color(0xFF0E1A31),
    accentTint: Color(0xFF2A4763),
    ink: Color(0xFFE9EEF8),
    inkMuted: Color(0xFF93A2BE),
    action: Color(0xFFC63A2E),
    onAction: Color(0xFFFBEDEC),
    accent: Color(0xFF96C0CE),
    accentInk: Color(0xFF96C0CE),
    onAccent: Color(0xFF0A1428),
    actionInk: Color(0xFFE2836F),
  );

  /// Palettes swap whole. Blending two of them would invent colours that belong
  /// to neither, so a theme change cuts at the midpoint.
  @override
  AppPalette copyWith() => this;

  @override
  AppPalette lerp(covariant AppPalette? other, double t) =>
      t < 0.5 ? this : (other ?? this);
}

/// Reads the active palette.
abstract final class AppColors {
  /// Falls back to [AppPalette.light] so a bare `MaterialApp`, such as a widget
  /// test harness or a scratch preview, renders instead of throwing.
  static AppPalette of(BuildContext context) =>
      Theme.of(context).extension<AppPalette>() ?? AppPalette.light;
}

abstract final class AppDecorations {
  /// Both grounds are dark, so the shadow is black. The old navy-tinted `0x14`
  /// shadow disappeared the moment the canvas turned navy.
  static const cardShadow = BoxShadow(
    color: Color(0x59000000),
    blurRadius: 18,
    offset: Offset(0, 8),
  );

  static const panelShadow = BoxShadow(
    color: Color(0x40000000),
    blurRadius: 16,
    offset: Offset(0, 7),
  );
}

/// App themes. Bricolage Grotesque for display, Inter for body, both served from
/// `assets/google_fonts/` so nothing is fetched at runtime.
abstract final class AppTheme {
  static ThemeData get light => _build(AppPalette.light);

  static ThemeData get dark => _build(AppPalette.dark);

  static ThemeData _build(AppPalette palette) {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: palette.action,
        brightness: Brightness.dark,
        surface: palette.canvas,
        onSurface: palette.ink,
        primary: palette.action,
        onPrimary: palette.onAction,
        secondary: palette.accent,
        onSecondary: palette.onAccent,
        error: palette.actionInk,
        onError: palette.canvas,
      ),
    );
    final text = base.textTheme.copyWith(
      displayLarge: GoogleFonts.bricolageGrotesque(
        textStyle: base.textTheme.displayLarge,
      ),
      displayMedium: GoogleFonts.bricolageGrotesque(
        textStyle: base.textTheme.displayMedium,
      ),
      displaySmall: GoogleFonts.bricolageGrotesque(
        textStyle: base.textTheme.displaySmall,
      ),
      headlineLarge: GoogleFonts.bricolageGrotesque(
        textStyle: base.textTheme.headlineLarge,
      ),
      headlineMedium: GoogleFonts.bricolageGrotesque(
        textStyle: base.textTheme.headlineMedium,
      ),
      headlineSmall: GoogleFonts.bricolageGrotesque(
        textStyle: base.textTheme.headlineSmall,
      ),
      bodyLarge: GoogleFonts.inter(textStyle: base.textTheme.bodyLarge),
      bodyMedium: GoogleFonts.inter(textStyle: base.textTheme.bodyMedium),
      bodySmall: GoogleFonts.inter(textStyle: base.textTheme.bodySmall),
      labelLarge: GoogleFonts.inter(textStyle: base.textTheme.labelLarge),
      labelMedium: GoogleFonts.inter(textStyle: base.textTheme.labelMedium),
      labelSmall: GoogleFonts.inter(textStyle: base.textTheme.labelSmall),
    );
    return base.copyWith(
      extensions: [palette],
      scaffoldBackgroundColor: palette.canvas,
      textTheme: text.apply(displayColor: palette.ink, bodyColor: palette.ink),
      appBarTheme: AppBarTheme(
        backgroundColor: palette.canvas,
        foregroundColor: palette.ink,
        elevation: 0,
      ),
      cardTheme: CardThemeData(
        color: palette.surface,
        elevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(32)),
        ),
      ),
    );
  }
}

abstract final class AppRadius {
  /// Chips, small controls, inline inputs.
  static const chip = BorderRadius.all(Radius.circular(12));

  /// List rows, inner cards, text fields.
  static const field = BorderRadius.all(Radius.circular(16));

  /// Panels, sheets, dialogs, medium cards.
  static const panel = BorderRadius.all(Radius.circular(24));

  /// Hero cards, search bar, bottom nav.
  static const hero = BorderRadius.all(Radius.circular(32));

  /// Style tags, avatars.
  static const pill = BorderRadius.all(Radius.circular(999));

  /// Bottom sheets and dialogs: rounded top corners only.
  static const sheet = BorderRadius.vertical(top: Radius.circular(24));
}

/// The three motion durations, and nothing else. No animation may run longer
/// than [hero].
abstract final class AppMotion {
  /// State changes: a chip, a toggle.
  static const state = Duration(milliseconds: 150);

  /// Routes and sheets.
  static const route = Duration(milliseconds: 250);

  /// Entrance of a hero element.
  static const hero = Duration(milliseconds: 350);
}
