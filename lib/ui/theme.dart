import 'package:flutter/material.dart';

/// The reading face. Android maps "serif" to Noto Serif, so no font files are bundled.
const readingFont = 'serif';

class Palette {
  static const cream = Color(0xFFF6F1E7);
  static const paper = Color(0xFFFBF8F2);
  static const sand = Color(0xFFEEE6D6);
  static const ink = Color(0xFF2A2925);
  static const inkMuted = Color(0xFF6B655A);
  static const forest = Color(0xFF2F5D4E);
  static const forestSoft = Color(0xFFDCE8E0);
  static const burgundy = Color(0xFF8A3B45);
  static const line = Color(0xFFDDD3C1);

  static const night = Color(0xFF121311);
  static const nightSurface = Color(0xFF1B1C19);
  static const nightRaised = Color(0xFF252621);
  static const moon = Color(0xFFE9E4D8);
  static const moonMuted = Color(0xFFA39D90);
  static const sage = Color(0xFF94C3AD);
  static const sageDeep = Color(0xFF213A30);
  static const rose = Color(0xFFDB98A1);
  static const nightLine = Color(0xFF383934);
}

class HighlightColor {
  final String name;
  final Color light;
  final Color dark;
  const HighlightColor(this.name, this.light, this.dark);
  Color of(BuildContext context) => Theme.of(context).brightness == Brightness.dark ? dark : light;
}

const highlightColors = [
  HighlightColor('Gold', Color(0xFFF5E2A2), Color(0xFF5B4B1C)),
  HighlightColor('Sage', Color(0xFFD3E6C8), Color(0xFF2E4A2B)),
  HighlightColor('Sky', Color(0xFFCDE0EF), Color(0xFF223D53)),
  HighlightColor('Rose', Color(0xFFF2CDD3), Color(0xFF56262F)),
  HighlightColor('Lavender', Color(0xFFDFD5EE), Color(0xFF3B2F53)),
];

HighlightColor highlightColor(int i) => highlightColors[i.clamp(0, highlightColors.length - 1)];

extension ThemeX on BuildContext {
  ThemeData get theme => Theme.of(this);
  ColorScheme get colors => Theme.of(this).colorScheme;
  TextTheme get text => Theme.of(this).textTheme;
  bool get isDark => Theme.of(this).brightness == Brightness.dark;
  Color get muted => isDark ? Palette.moonMuted : Palette.inkMuted;
}

ThemeData buildTheme(Brightness b) {
  final dark = b == Brightness.dark;
  final scheme = ColorScheme(
    brightness: b,
    primary: dark ? Palette.sage : Palette.forest,
    onPrimary: dark ? const Color(0xFF0E2219) : Colors.white,
    primaryContainer: dark ? Palette.sageDeep : Palette.forestSoft,
    onPrimaryContainer: dark ? const Color(0xFFCBE7D9) : const Color(0xFF173A2E),
    secondary: dark ? Palette.rose : Palette.burgundy,
    onSecondary: dark ? const Color(0xFF3A1016) : Colors.white,
    secondaryContainer: dark ? const Color(0xFF4A2228) : const Color(0xFFF3DEE0),
    onSecondaryContainer: dark ? const Color(0xFFF6D9DD) : const Color(0xFF4A1A21),
    tertiary: dark ? const Color(0xFFD9C08A) : const Color(0xFF7A5B1E),
    onTertiary: dark ? Colors.black : Colors.white,
    error: dark ? const Color(0xFFF2A9A0) : const Color(0xFFA3352B),
    onError: dark ? Colors.black : Colors.white,
    surface: dark ? Palette.night : Palette.cream,
    onSurface: dark ? Palette.moon : Palette.ink,
    onSurfaceVariant: dark ? Palette.moonMuted : Palette.inkMuted,
    surfaceContainerLowest: dark ? const Color(0xFF0D0E0C) : Colors.white,
    surfaceContainerLow: dark ? Palette.nightSurface : Palette.paper,
    surfaceContainer: dark ? Palette.nightSurface : Palette.paper,
    surfaceContainerHigh: dark ? Palette.nightRaised : const Color(0xFFF2ECE0),
    surfaceContainerHighest: dark ? const Color(0xFF2E2F2A) : Palette.sand,
    outline: dark ? const Color(0xFF5A5B54) : const Color(0xFFB9AE9A),
    outlineVariant: dark ? Palette.nightLine : Palette.line,
    shadow: Colors.black,
    inverseSurface: dark ? Palette.moon : Palette.ink,
    onInverseSurface: dark ? Palette.ink : Palette.cream,
    inversePrimary: dark ? Palette.forest : Palette.sage,
  );
  final base = ThemeData(useMaterial3: true, colorScheme: scheme, brightness: b);
  final t = base.textTheme;
  TextStyle? serif(TextStyle? s, {FontWeight? w}) => s?.copyWith(fontFamily: readingFont, fontWeight: w);
  return base.copyWith(
    scaffoldBackgroundColor: scheme.surface,
    textTheme: t.copyWith(
      displaySmall: serif(t.displaySmall, w: FontWeight.w600),
      headlineMedium: serif(t.headlineMedium, w: FontWeight.w600),
      headlineSmall: serif(t.headlineSmall, w: FontWeight.w600),
      titleLarge: serif(t.titleLarge, w: FontWeight.w600),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0.5,
      shadowColor: Colors.black26,
      centerTitle: false,
      titleTextStyle: serif(t.titleLarge, w: FontWeight.w600)?.copyWith(color: scheme.onSurface, fontSize: 21),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: dark ? Palette.nightSurface : Palette.paper,
      indicatorColor: scheme.primaryContainer,
      surfaceTintColor: Colors.transparent,
      height: 66,
      labelTextStyle: WidgetStatePropertyAll(t.labelMedium?.copyWith(fontWeight: FontWeight.w500)),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: dark ? Palette.nightSurface : Palette.paper,
      indicatorColor: scheme.primaryContainer,
    ),
    cardTheme: CardThemeData(
      color: scheme.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: BorderSide(color: scheme.outlineVariant)),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: scheme.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: scheme.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerHigh,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: scheme.primary, width: 1.4)),
    ),
    chipTheme: base.chipTheme.copyWith(
      backgroundColor: scheme.surfaceContainerLow,
      selectedColor: scheme.primaryContainer,
      side: BorderSide(color: scheme.outlineVariant),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    dividerTheme: DividerThemeData(color: scheme.outlineVariant, thickness: 1, space: 1),
    listTileTheme: ListTileThemeData(iconColor: scheme.onSurfaceVariant),
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
    }),
  );
}
