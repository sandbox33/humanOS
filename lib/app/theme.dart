import 'package:flutter/material.dart';

import '../data/settings.dart';

/// Retro-terminal palette (WASTELAND): black background, two dark surfaces,
/// the chosen accent and the other one as secondary.
abstract final class HosColors {
  static const background = Color(0xFF000000);
  static const surface = Color(0xFF121212);
  static const surfaceHigh = Color(0xFF1E1E1E);
  static const phosphor = Color(0xFF39FF14);
  static const safetyOrange = Color(0xFFFF6B00);
  static const amber = Color(0xFFFFC107);
  static const alert = Color(0xFFFF4D4D);
  static const muted = Color(0xFF8A8A8A);

  static Color accent(AccentColor accent) => accent == AccentColor.safetyOrange ? safetyOrange : phosphor;
}

/// Parchment, leather and ink (GRIMORIO). Original colours.
abstract final class GrimoireColors {
  static const parchment = Color(0xFFF2E6C9);
  static const vellum = Color(0xFFE8D7AE);
  static const vellumDeep = Color(0xFFDCC690);
  static const ink = Color(0xFF2B1B0E);
  static const fadedInk = Color(0xFF5A4630);
  static const leather = Color(0xFF4A2E1A);
  static const oxblood = Color(0xFF7A1F1F);
  static const verdigris = Color(0xFF27523A);
  static const ochre = Color(0xFF6B4400);
  static const rubric = Color(0xFF8B1A1A);
}

abstract final class HosFonts {
  static const display = 'VT323';
  static const label = 'ShareTechMono';
  static const data = 'IBMPlexMono';
  static const grimoireDisplay = 'Cinzel';
  static const grimoireText = 'IMFellEnglish';
}

/// Theme-dependent colours and fonts that Material does not cover: status
/// bands (readiness, food safety), the deepest surface and whether headers
/// are a terminal (scanlines) or a book (rune rule).
@immutable
class HosLook extends ThemeExtension<HosLook> {
  const HosLook({
    required this.ok,
    required this.warn,
    required this.danger,
    required this.surfaceHigh,
    required this.displayFont,
    required this.terminal,
  });

  final Color ok;
  final Color warn;
  final Color danger;
  final Color surfaceHigh;
  final String displayFont;
  final bool terminal;

  @override
  HosLook copyWith({Color? ok, Color? warn, Color? danger, Color? surfaceHigh, String? displayFont, bool? terminal}) =>
      HosLook(
        ok: ok ?? this.ok,
        warn: warn ?? this.warn,
        danger: danger ?? this.danger,
        surfaceHigh: surfaceHigh ?? this.surfaceHigh,
        displayFont: displayFont ?? this.displayFont,
        terminal: terminal ?? this.terminal,
      );

  /// A status word (band, food safety) in the theme's display font.
  TextStyle statusStyle(double size, Color color) =>
      TextStyle(fontFamily: displayFont, fontSize: terminal ? size : size * 0.8, color: color);

  // Themes switch instantly: no decorative transition.
  @override
  HosLook lerp(HosLook? other, double t) => other == null || t < 0.5 ? this : other;
}

extension HosLookOf on BuildContext {
  HosLook get look => Theme.of(this).extension<HosLook>()!;
}

/// Minimum touch target (gloves off after work).
const double kTouchTarget = 56;

class _Palette {
  const _Palette({
    required this.brightness,
    required this.background,
    required this.surface,
    required this.surfaceHigh,
    required this.bar,
    required this.onBar,
    required this.primary,
    required this.onPrimary,
    required this.secondary,
    required this.text,
    required this.muted,
    required this.error,
    required this.look,
    required this.displayFont,
    required this.labelFont,
    required this.dataFont,
    required this.radius,
  });

  final Brightness brightness;
  final Color background;
  final Color surface;
  final Color surfaceHigh;
  final Color bar;
  final Color onBar;
  final Color primary;
  final Color onPrimary;
  final Color secondary;
  final Color text;
  final Color muted;
  final Color error;
  final HosLook look;
  final String displayFont;
  final String labelFont;
  final String dataFont;
  final double radius;
}

_Palette _wasteland(AccentColor choice) {
  final accent = HosColors.accent(choice);
  final other = choice == AccentColor.safetyOrange ? HosColors.phosphor : HosColors.safetyOrange;
  return _Palette(
    brightness: Brightness.dark,
    background: HosColors.background,
    surface: HosColors.surface,
    surfaceHigh: HosColors.surfaceHigh,
    bar: HosColors.surface,
    onBar: accent,
    primary: accent,
    onPrimary: HosColors.background,
    secondary: other,
    text: accent,
    muted: HosColors.muted,
    error: HosColors.alert,
    look: const HosLook(
      ok: HosColors.phosphor,
      warn: HosColors.amber,
      danger: HosColors.alert,
      surfaceHigh: HosColors.surfaceHigh,
      displayFont: HosFonts.display,
      terminal: true,
    ),
    displayFont: HosFonts.display,
    labelFont: HosFonts.label,
    dataFont: HosFonts.data,
    radius: 2,
  );
}

const _grimorio = _Palette(
  brightness: Brightness.light,
  background: GrimoireColors.parchment,
  surface: GrimoireColors.vellum,
  surfaceHigh: GrimoireColors.vellumDeep,
  bar: GrimoireColors.leather,
  onBar: GrimoireColors.parchment,
  primary: GrimoireColors.oxblood,
  onPrimary: GrimoireColors.parchment,
  secondary: GrimoireColors.verdigris,
  text: GrimoireColors.ink,
  muted: GrimoireColors.fadedInk,
  error: GrimoireColors.rubric,
  look: HosLook(
    ok: GrimoireColors.verdigris,
    warn: GrimoireColors.ochre,
    danger: GrimoireColors.rubric,
    surfaceHigh: GrimoireColors.vellumDeep,
    displayFont: HosFonts.grimoireDisplay,
    terminal: false,
  ),
  displayFont: HosFonts.grimoireDisplay,
  labelFont: HosFonts.grimoireText,
  dataFont: HosFonts.data,
  radius: 6,
);

/// One theme: its Material theme, its fonts and whether the user's accent
/// applies. A later avatar, voice or assistant wording is added here per
/// theme, never as a global switch.
class HosThemeSpec {
  const HosThemeSpec({required this.id, required this.fonts, required this.usesAccent});

  final HosThemeId id;

  /// Font families the theme draws with (all OFL, in `assets/fonts/`).
  final List<String> fonts;

  /// WASTELAND lets the user pick green or orange; GRIMORIO has its own ink.
  final bool usesAccent;

  ThemeData build(AccentColor accent) =>
      _build(id == HosThemeId.grimorio ? _grimorio : _wasteland(accent));
}

abstract final class ThemeRegistry {
  static const all = [
    HosThemeSpec(
      id: HosThemeId.wasteland,
      fonts: [HosFonts.display, HosFonts.label, HosFonts.data],
      usesAccent: true,
    ),
    HosThemeSpec(
      id: HosThemeId.grimorio,
      fonts: [HosFonts.grimoireDisplay, HosFonts.grimoireText, HosFonts.data],
      usesAccent: false,
    ),
  ];

  static HosThemeSpec of(HosThemeId id) => all.firstWhere((t) => t.id == id);
}

/// The theme [theme] (with [accent] where the theme uses it).
ThemeData buildTheme(AccentColor accent, {HosThemeId theme = HosThemeId.wasteland}) =>
    ThemeRegistry.of(theme).build(accent);

ThemeData _build(_Palette p) {
  final scheme = ColorScheme(
    brightness: p.brightness,
    primary: p.primary,
    onPrimary: p.onPrimary,
    secondary: p.secondary,
    onSecondary: p.onPrimary,
    surface: p.surface,
    onSurface: p.text,
    surfaceContainerHighest: p.surfaceHigh,
    error: p.error,
    onError: p.onPrimary,
    outline: p.primary.withValues(alpha: 0.5),
  );
  final base = ThemeData(
    useMaterial3: true,
    brightness: p.brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: p.background,
    fontFamily: p.dataFont,
    extensions: [p.look],
  );
  TextStyle display(double size) => TextStyle(
        fontFamily: p.displayFont,
        fontSize: p.displayFont == HosFonts.grimoireDisplay ? size * 0.8 : size,
        color: p.text,
        letterSpacing: 1.2,
        height: 1.0,
      );
  TextStyle label(double size, {FontWeight weight = FontWeight.w400, Color? color}) => TextStyle(
        fontFamily: p.labelFont,
        fontSize: size,
        color: color ?? p.text,
        fontWeight: weight,
        letterSpacing: 0.8,
      );
  TextStyle data(double size, {FontWeight weight = FontWeight.w400}) =>
      TextStyle(fontFamily: p.dataFont, fontSize: size, color: p.text, fontWeight: weight);
  final textTheme = TextTheme(
    displayLarge: display(72),
    displayMedium: display(56),
    displaySmall: display(44),
    headlineLarge: display(38),
    headlineMedium: display(32),
    headlineSmall: display(28),
    titleLarge: label(20),
    titleMedium: label(17),
    titleSmall: label(15),
    bodyLarge: data(16),
    bodyMedium: data(14),
    bodySmall: data(12).copyWith(color: p.muted),
    labelLarge: label(16),
    labelMedium: label(14),
    labelSmall: label(12),
  );
  final corners = BorderRadius.circular(p.radius);
  final shape = RoundedRectangleBorder(
    borderRadius: corners,
    side: BorderSide(color: p.primary.withValues(alpha: 0.6)),
  );
  return base.copyWith(
    textTheme: textTheme,
    // Screens switch instantly: no decorative transitions.
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: _InstantTransitions(),
      TargetPlatform.linux: _InstantTransitions(),
    }),
    appBarTheme: AppBarTheme(
      backgroundColor: p.bar,
      foregroundColor: p.onBar,
      elevation: 0,
      titleTextStyle: display(30).copyWith(color: p.onBar),
    ),
    cardTheme: CardThemeData(
      color: p.surface,
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 6),
      shape: shape,
    ),
    dividerTheme: DividerThemeData(color: p.primary.withValues(alpha: 0.25)),
    iconTheme: IconThemeData(color: p.text),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(kTouchTarget, kTouchTarget),
        backgroundColor: p.primary,
        foregroundColor: p.onPrimary,
        textStyle: label(17, weight: FontWeight.w700),
        shape: RoundedRectangleBorder(borderRadius: corners),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(kTouchTarget, kTouchTarget),
        foregroundColor: p.primary,
        side: BorderSide(color: p.primary),
        textStyle: label(16),
        shape: RoundedRectangleBorder(borderRadius: corners),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(kTouchTarget, kTouchTarget),
        foregroundColor: p.primary,
        textStyle: label(16),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        minimumSize: const Size(kTouchTarget, kTouchTarget),
        foregroundColor: p.text,
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: p.bar,
      indicatorColor: p.onBar.withValues(alpha: 0.22),
      height: 72,
      labelTextStyle: WidgetStatePropertyAll(label(13, color: p.onBar)),
      iconTheme: WidgetStatePropertyAll(IconThemeData(color: p.onBar)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: p.surfaceHigh,
      labelStyle: label(14),
      hintStyle: data(14).copyWith(color: p.muted),
      border: OutlineInputBorder(borderRadius: corners, borderSide: BorderSide(color: p.primary.withValues(alpha: 0.6))),
      enabledBorder:
          OutlineInputBorder(borderRadius: corners, borderSide: BorderSide(color: p.primary.withValues(alpha: 0.6))),
      focusedBorder: OutlineInputBorder(borderRadius: corners, borderSide: BorderSide(color: p.primary, width: 2)),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: p.surfaceHigh,
      selectedColor: p.primary.withValues(alpha: 0.25),
      labelStyle: label(13),
      side: BorderSide(color: p.primary.withValues(alpha: 0.5)),
      shape: RoundedRectangleBorder(borderRadius: corners),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? p.primary : p.muted),
      trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? p.primary.withValues(alpha: 0.35) : p.surfaceHigh),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: p.bar,
      contentTextStyle: data(14).copyWith(color: p.onBar),
      behavior: SnackBarBehavior.floating,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: p.surface,
      shape: shape,
      titleTextStyle: display(30),
      contentTextStyle: data(15),
    ),
    bottomSheetTheme: BottomSheetThemeData(backgroundColor: p.surface, showDragHandle: true),
    tabBarTheme: TabBarThemeData(
      labelStyle: label(15),
      unselectedLabelStyle: label(15),
      labelColor: p.primary,
      unselectedLabelColor: p.muted,
      indicatorColor: p.primary,
    ),
  );
}

class _InstantTransitions extends PageTransitionsBuilder {
  const _InstantTransitions();

  @override
  Duration get transitionDuration => Duration.zero;

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) =>
      child;
}
