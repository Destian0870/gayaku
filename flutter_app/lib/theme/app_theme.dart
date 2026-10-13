import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Colour tokens for one mode.
///
/// Values and their verified contrast ratios live in `design.md`. A flat
/// `static const` cannot be two different colours in two modes, so each mode is
/// one `const` instance of this class, read through [AppColors.of].
@immutable
class AppPalette {
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
  });

  /// Screen background.
  final Color canvas;

  /// Cards and panels.
  final Color surface;

  /// Image and scanner areas.
  final Color surfaceMuted;

  /// Bottom sheets, dialogs, text fields.
  final Color sheet;

  /// Selected chips and subtle highlights.
  final Color accentTint;

  /// Primary text. 9.21 on canvas in light, 12.91 in dark.
  final Color ink;

  /// Secondary text. Never reach for opacity instead of this.
  final Color inkMuted;

  /// Primary action fill. 9.01 as ink on canvas in light, 8.52 in dark.
  final Color action;

  /// Label on [action].
  final Color onAction;

  /// Accent fill. Not an ink in light mode, where it is 1.61 on canvas.
  final Color accent;

  /// The accent used as ink, for icons, borders and small marks. In light mode
  /// this darkens toward the ink, because Light blue cannot carry meaning on a
  /// light ground. In dark mode it stays Light blue, at 8.02 on canvas.
  final Color accentInk;

  /// Label on [accent].
  final Color onAccent;

  static const light = AppPalette(
    canvas: Color(0xFFEFE8DF),
    surface: Color(0xFFD8BA98),
    surfaceMuted: Color(0xFFE2CFB8),
    sheet: Color(0xFFF7F4EF),
    accentTint: Color(0xFFD6DDDA),
    ink: Color(0xFF0F414A),
    inkMuted: Color(0xFF275053),
    action: Color(0xFF7F0303),
    onAction: Color(0xFFEFE8DF),
    accent: Color(0xFF96C0CE),
    accentInk: Color(0xFF1E4F59),
    onAccent: Color(0xFF0F414A),
  );

  static const dark = AppPalette(
    canvas: Color(0xFF09272C),
    surface: Color(0xFF0C353D),
    surfaceMuted: Color(0xFF204E57),
    sheet: Color(0xFF0A2E34),
    accentTint: Color(0xFF25464C),
    ink: Color(0xFFEFE8DF),
    inkMuted: Color(0xFF989F9B),
    action: Color(0xFFD8BA98),
    onAction: Color(0xFF0F414A),
    accent: Color(0xFF96C0CE),
    accentInk: Color(0xFF96C0CE),
    onAccent: Color(0xFF0F414A),
  );
}

/// Reads the active palette.
abstract final class AppColors {
  static AppPalette of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
      ? AppPalette.dark
      : AppPalette.light;
}

abstract final class AppDecorations {
  static const cardShadow = BoxShadow(
    color: Color(0x140F414A),
    blurRadius: 18,
    offset: Offset(0, 8),
  );

  static const panelShadow = BoxShadow(
    color: Color(0x120F414A),
    blurRadius: 16,
    offset: Offset(0, 7),
  );
}

/// App themes. Bricolage Grotesque for display, Inter for body, both served from
/// `assets/google_fonts/` so nothing is fetched at runtime.
abstract final class AppTheme {
  static ThemeData get light => _build(AppPalette.light, Brightness.light);

  static ThemeData get dark => _build(AppPalette.dark, Brightness.dark);

  static ThemeData _build(AppPalette palette, Brightness brightness) {
    final base = ThemeData(useMaterial3: true, brightness: brightness);
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
      scaffoldBackgroundColor: palette.canvas,
      colorScheme: ColorScheme.fromSeed(
        seedColor: palette.action,
        brightness: brightness,
        surface: palette.canvas,
      ),
      textTheme: text.apply(
        displayColor: palette.ink,
        bodyColor: palette.ink,
      ),
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

/// The three `design.md` motion durations, and nothing else. No animation may
/// run longer than [hero].
abstract final class AppMotion {
  /// State changes: a chip, a toggle.
  static const state = Duration(milliseconds: 150);

  /// Routes and sheets.
  static const route = Duration(milliseconds: 250);

  /// Entrance of a hero element.
  static const hero = Duration(milliseconds: 350);
}