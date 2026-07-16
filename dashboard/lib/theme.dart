import 'package:flutter/material.dart';

class AppColors {
  static const seed = Color(0xFF6D5AE6);

  static const breaking = Color(0xFFE5484D);
  static const safe = Color(0xFFF5A623);
  static const warning = safe;
  static const additive = Color(0xFF30A46C);
  static const neutral = Color(0xFF8B8D98);

  static Color forClassification(String c) {
    switch (c.toUpperCase()) {
      case 'BREAKING':
        return breaking;
      case 'ADDITIVE':
        return additive;
      case 'NON_BREAKING':
        return safe;
      default:
        return neutral;
    }
  }

  static Color forRisk(String risk) {
    switch (risk) {
      case 'breaking':
        return breaking;
      case 'safe':
        return additive;
      default:
        return neutral;
    }
  }

  static const experience = Color(0xFF3B82F6);
  static const process = Color(0xFF8B5CF6);
  static const system = Color(0xFF14B8A6);
  static const backend = Color(0xFF64748B);
  static const app = Color(0xFFF59E0B);

  static Color forLayer(String layer) {
    switch (layer) {
      case 'EXPERIENCE':
        return experience;
      case 'PROCESS':
        return process;
      case 'SYSTEM':
        return system;
      case 'BACKEND':
        return backend;
      case 'APP':
        return app;
      default:
        return neutral;
    }
  }

  static String layerLabel(String layer) {
    switch (layer) {
      case 'EXPERIENCE':
        return 'Experience API';
      case 'PROCESS':
        return 'Process API';
      case 'SYSTEM':
        return 'System API';
      case 'BACKEND':
        return 'System of record';
      case 'APP':
        return 'Consumer app';
      default:
        return 'API';
    }
  }
}

String classificationLabel(String c) {
  switch (c.toUpperCase()) {
    case 'NON_BREAKING':
      return 'SAFE';
    default:
      return c.toUpperCase();
  }
}

/// One rounding scale for the whole app, so corners stay consistent.
class AppRadius {
  static const card = 16.0;
  static const tile = 14.0;
  static const field = 12.0;
  static const button = 12.0;
  static const chip = 24.0;
}

/// One spacing scale (a 4px rhythm) to keep gaps and padding coherent.
class AppSpacing {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
  static const xxl = 32.0;
}

ThemeData buildTheme(Brightness brightness) {
  final scheme = ColorScheme.fromSeed(seedColor: AppColors.seed, brightness: brightness);
  final dark = brightness == Brightness.dark;

  // Surface hierarchy: a tinted scaffold with panels that sit visibly above it.
  // In dark mode cards must be lighter than the scaffold (both were `surface`
  // before, so panels were invisible); in light mode white cards lift off a
  // cool-grey backdrop.
  final scaffold = dark ? scheme.surface : const Color(0xFFF4F5F8);
  final panel = dark ? scheme.surfaceContainerHigh : Colors.white;
  final hairline = dark ? scheme.outlineVariant.withOpacity(0.55) : const Color(0xFFE4E7EC);
  final fieldFill = dark ? scheme.surfaceContainerHighest : Colors.white;

  final baseText = dark ? Typography.material2021().white : Typography.material2021().black;
  final textTheme = baseText.copyWith(
    headlineMedium: baseText.headlineMedium?.copyWith(letterSpacing: -0.5, fontWeight: FontWeight.w800),
    headlineSmall: baseText.headlineSmall?.copyWith(letterSpacing: -0.3, fontWeight: FontWeight.w800),
    titleLarge: baseText.titleLarge?.copyWith(letterSpacing: -0.2, fontWeight: FontWeight.w700),
    titleMedium: baseText.titleMedium?.copyWith(letterSpacing: -0.1),
  );

  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    fontFamily: 'Roboto',
    textTheme: textTheme,
    scaffoldBackgroundColor: scaffold,
    cardTheme: CardTheme(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: panel,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.card),
        side: BorderSide(color: hairline),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      isDense: true,
      filled: true,
      fillColor: fieldFill,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.field),
        borderSide: BorderSide(color: hairline),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.field),
        borderSide: BorderSide(color: hairline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.field),
        borderSide: BorderSide(color: scheme.primary, width: 1.6),
      ),
      hintStyle: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant.withOpacity(0.7)),
    ),
    tooltipTheme: TooltipThemeData(
      waitDuration: const Duration(milliseconds: 350),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF3A3D4D) : const Color(0xFF23252F),
        borderRadius: BorderRadius.circular(8),
      ),
      textStyle: const TextStyle(color: Colors.white, fontSize: 12, height: 1.35),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: panel,
      indicatorColor: scheme.primaryContainer,
      indicatorShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      selectedIconTheme: IconThemeData(color: scheme.onPrimaryContainer, size: 24),
      unselectedIconTheme: IconThemeData(color: scheme.onSurfaceVariant, size: 24),
      selectedLabelTextStyle: TextStyle(
          fontSize: 12, fontWeight: FontWeight.w700, color: scheme.primary),
      unselectedLabelTextStyle: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
    ),
    chipTheme: ChipThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.chip)),
      side: BorderSide(color: hairline),
      backgroundColor: panel,
      labelStyle: const TextStyle(fontSize: 12),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.field)),
    ),
    dividerTheme: DividerThemeData(color: hairline, thickness: 1, space: 1),
    tabBarTheme: TabBarTheme(
      labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
      unselectedLabelStyle: const TextStyle(fontSize: 13),
      indicatorSize: TabBarIndicatorSize.label,
      dividerColor: hairline,
      overlayColor: WidgetStatePropertyAll(scheme.primary.withOpacity(0.06)),
    ),
    listTileTheme: const ListTileThemeData(dense: true),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.button)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        side: BorderSide(color: hairline),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.button)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    ),
  );
}

class RiskChip extends StatelessWidget {
  final String classification;
  const RiskChip(this.classification, {super.key});

  @override
  Widget build(BuildContext context) {
    final color = AppColors.forClassification(classification);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.14),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Text(
        classificationLabel(classification),
        style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 11, letterSpacing: 0.4),
      ),
    );
  }
}
