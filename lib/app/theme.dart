import 'package:flutter/material.dart';

import '../data/settings.dart';

/// Retro-terminal palette: black background, two dark surfaces and one
/// selectable accent. Status colours (band VERDE/AMARILLO/ROJO) are
/// semantic and only used for readiness and food safety.
abstract final class HosColors {
  static const background = Color(0xFF000000);
  static const surface = Color(0xFF121212);
  static const surfaceHigh = Color(0xFF1E1E1E);
  static const phosphor = Color(0xFF39FF14);
  static const safetyOrange = Color(0xFFFF6B00);
  static const amber = Color(0xFFFFC107);
  static const alert = Color(0xFFFF4D4D);
  static const muted = Color(0xFF8A8A8A);

  static Color accent(AccentColor accent) =>
      accent == AccentColor.safetyOrange ? safetyOrange : phosphor;
}

abstract final class HosFonts {
  static const display = 'VT323';
  static const label = 'ShareTechMono';
  static const data = 'IBMPlexMono';
}

/// Minimum touch target (gloves off after the shift).
const double kTouchTarget = 56;

ThemeData buildTheme(AccentColor accentChoice) {
  final accent = HosColors.accent(accentChoice);
  final scheme = ColorScheme.dark(
    primary: accent,
    onPrimary: HosColors.background,
    secondary: accent,
    onSecondary: HosColors.background,
    surface: HosColors.surface,
    onSurface: accent,
    surfaceContainerHighest: HosColors.surfaceHigh,
    error: HosColors.alert,
    onError: HosColors.background,
    outline: accent.withValues(alpha: 0.5),
  );
  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    scaffoldBackgroundColor: HosColors.background,
    fontFamily: HosFonts.data,
  );
  TextStyle display(double size) => TextStyle(
        fontFamily: HosFonts.display,
        fontSize: size,
        color: accent,
        letterSpacing: 1.2,
        height: 1.0,
      );
  TextStyle label(double size, {FontWeight weight = FontWeight.w400}) =>
      TextStyle(
        fontFamily: HosFonts.label,
        fontSize: size,
        color: accent,
        fontWeight: weight,
        letterSpacing: 0.8,
      );
  TextStyle data(double size, {FontWeight weight = FontWeight.w400}) =>
      TextStyle(
        fontFamily: HosFonts.data,
        fontSize: size,
        color: accent,
        fontWeight: weight,
      );
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
    bodySmall: data(12).copyWith(color: accent.withValues(alpha: 0.75)),
    labelLarge: label(16),
    labelMedium: label(14),
    labelSmall: label(12),
  );
  final shape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(2),
    side: BorderSide(color: accent.withValues(alpha: 0.6)),
  );
  return base.copyWith(
    textTheme: textTheme,
    // Screens switch instantly, like a terminal: no decorative transitions.
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: _InstantTransitions(),
      TargetPlatform.linux: _InstantTransitions(),
    }),
    appBarTheme: AppBarTheme(
      backgroundColor: HosColors.background,
      foregroundColor: accent,
      elevation: 0,
      titleTextStyle: display(30),
    ),
    cardTheme: CardThemeData(
      color: HosColors.surface,
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 6),
      shape: shape,
    ),
    dividerTheme: DividerThemeData(color: accent.withValues(alpha: 0.25)),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(kTouchTarget, kTouchTarget),
        backgroundColor: accent,
        foregroundColor: HosColors.background,
        textStyle: label(17, weight: FontWeight.w700),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(2)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(kTouchTarget, kTouchTarget),
        foregroundColor: accent,
        side: BorderSide(color: accent),
        textStyle: label(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(2)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(kTouchTarget, kTouchTarget),
        foregroundColor: accent,
        textStyle: label(16),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        minimumSize: const Size(kTouchTarget, kTouchTarget),
        foregroundColor: accent,
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: HosColors.surface,
      indicatorColor: accent.withValues(alpha: 0.22),
      height: 72,
      labelTextStyle: WidgetStatePropertyAll(label(13)),
      iconTheme: WidgetStatePropertyAll(IconThemeData(color: accent)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: HosColors.surfaceHigh,
      labelStyle: label(14),
      hintStyle: data(14).copyWith(color: accent.withValues(alpha: 0.5)),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(2),
        borderSide: BorderSide(color: accent.withValues(alpha: 0.6)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(2),
        borderSide: BorderSide(color: accent.withValues(alpha: 0.6)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(2),
        borderSide: BorderSide(color: accent, width: 2),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: HosColors.surfaceHigh,
      selectedColor: accent.withValues(alpha: 0.25),
      labelStyle: label(13),
      side: BorderSide(color: accent.withValues(alpha: 0.5)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(2)),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? accent : HosColors.muted),
      trackColor: WidgetStateProperty.resolveWith((s) =>
          s.contains(WidgetState.selected)
              ? accent.withValues(alpha: 0.35)
              : HosColors.surfaceHigh),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: HosColors.surfaceHigh,
      contentTextStyle: data(14),
      behavior: SnackBarBehavior.floating,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: HosColors.surface,
      shape: shape,
      titleTextStyle: display(30),
      contentTextStyle: data(15),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: HosColors.surface,
      showDragHandle: true,
    ),
    tabBarTheme: TabBarThemeData(
      labelStyle: label(15),
      unselectedLabelStyle: label(15),
      labelColor: accent,
      unselectedLabelColor: accent.withValues(alpha: 0.55),
      indicatorColor: accent,
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
