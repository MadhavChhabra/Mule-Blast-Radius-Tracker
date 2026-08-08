import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// The BlipRadius design system, transcribed from the approved comp.
///
/// One committed dark world: a near-black canvas the estate map lives on, glass panels docked over
/// it, IBM Plex for everything, and colour reserved almost entirely for meaning. The only decorative
/// hue is the violet accent — every red, amber and green on screen is load-bearing.
class AppColors {
  /// The estate canvas. Everything else sits above this.
  static const canvas = Color(0xFF08090D);

  /// Framed surfaces (API hub, Sources, Changelog) sit a hair lighter than the canvas.
  static const shell = Color(0xFF0A0B10);

  /// Top bar and inset wells.
  static const bar = Color(0xFF0C0E14);

  /// Solid card inside a framed surface.
  static const card = Color(0xFF111319);

  /// Glass docked over the canvas — always paired with blur(14).
  static const glass = Color(0xDB0E1016);
  static const glassStrong = Color(0xF00E1016);

  /// Node plates on the map: .9 focused, .75 at rest, .5 when off the blast path.
  static const node = Color(0xE6141620);
  static const nodeQuiet = Color(0xBF141620);
  static const nodeOffPath = Color(0x80141620);

  static const hairline = Color(0x12FFFFFF);
  static const hairlineSoft = Color(0x0DFFFFFF);
  static const hairlineStrong = Color(0x1FFFFFFF);

  /// List-row background.
  static const fillSubtle = Color(0x09FFFFFF);

  static const text = Color(0xFFEDEDF2);
  static const textSecondary = Color(0xFFB9BCC9);
  static const textMuted = Color(0xFF8B8E9E);
  static const textFaint = Color(0xFF868A9C);
  static const textDim = Color(0xFF9296A8);
  static const textGhost = Color(0xFF3A3D4B);

  /// The one decorative hue. Never used to mean anything.
  static const accent = Color(0xFF8B7BFF);
  static const accentSoft = Color(0xFFB7ACFF);
  static const onAccent = Color(0xFF0C0D12);
  static const accentGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF8B7BFF), Color(0xFF4C8DF6)],
  );

  // Semantic — these carry meaning and may not be traded for aesthetics.
  static const breaking = Color(0xFFFF5C61);
  static const breakingText = Color(0xFFFF7B7F);
  static const additive = Color(0xFF3DD68C);

  /// "We cannot prove this either way" — distinct from both safe and breaking.
  static const warning = Color(0xFFF5A623);
  static const safe = warning;
  static const neutral = Color(0xFF868A9C);

  // API-led layers.
  static const app = Color(0xFFF5A623);
  static const experience = Color(0xFF4C8DF6);
  static const process = Color(0xFFA78BFA);
  static const system = Color(0xFF2DD4BF);
  static const backend = Color(0xFF7E8CA3);

  static Color forLayer(String layer) => switch (layer) {
        'EXPERIENCE' => experience,
        'PROCESS' => process,
        'SYSTEM' => system,
        'BACKEND' => backend,
        'APP' => app,
        _ => neutral,
      };

  static String layerLabel(String layer) => switch (layer) {
        'EXPERIENCE' => 'Experience API',
        'PROCESS' => 'Process API',
        'SYSTEM' => 'System API',
        'BACKEND' => 'System of record',
        'APP' => 'Consumer app',
        _ => 'API',
      };

  static String layerBand(String layer) => switch (layer) {
        'EXPERIENCE' => 'EXPERIENCE',
        'PROCESS' => 'PROCESS',
        'SYSTEM' => 'SYSTEM',
        'BACKEND' => 'SYSTEMS OF RECORD',
        'APP' => 'CONSUMER APPS',
        _ => 'UNCLASSIFIED',
      };

  static Color forClassification(String c) => switch (c.toUpperCase()) {
        'BREAKING' => breaking,
        'ADDITIVE' => additive,
        'NON_BREAKING' => warning,
        _ => neutral,
      };

  static Color forRisk(String risk) => switch (risk) {
        'breaking' => breaking,
        'safe' => additive,
        _ => neutral,
      };
}

String classificationLabel(String c) =>
    c.toUpperCase() == 'NON_BREAKING' ? 'SAFE' : c.toUpperCase();

class AppRadius {
  static const panel = 13.0;
  static const card = 14.0;

  /// Map node cards.
  static const tile = 11.0;
  static const field = 9.0;
  static const button = 9.0;
  static const chip = 7.0;
  static const pill = 20.0;
}

/// Statistics are Light 300 and never bold — the weight contrast is the design's signature.
TextStyle statStyle(double size, {Color? color}) => TextStyle(
      fontFamily: kSans,
      fontSize: size,
      fontWeight: FontWeight.w300,
      height: 1.0,
      letterSpacing: size >= 36 ? -1.5 : -0.6,
      color: color ?? AppColors.text,
    );

class AppSpacing {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
  static const xxl = 32.0;
}

/// Motion durations. The comp animates edges, path tracing and node arrivals; everything else
/// stays still so movement always means something.
class AppMotion {
  static const fast = Duration(milliseconds: 160);
  static const base = Duration(milliseconds: 240);
  static const slow = Duration(milliseconds: 420);
  static const edgeFlow = Duration(seconds: 6);
  static const trace = Duration(milliseconds: 500);
  static const curve = Curves.easeOutCubic;
}

const String kSans = 'IBMPlexSans';
const String kMono = 'IBMPlexMono';

/// Uppercase mono label — the comp's recurring section marker.
TextStyle monoLabel({Color? color, double size = 10}) => TextStyle(
      fontFamily: kMono,
      fontSize: size,
      fontWeight: FontWeight.w500,
      letterSpacing: size * 0.14,
      color: color ?? AppColors.textFaint,
    );

TextStyle monoData({Color? color, double size = 10.5, FontWeight? weight}) => TextStyle(
      fontFamily: kMono,
      fontSize: size,
      fontWeight: weight ?? FontWeight.w400,
      color: color ?? AppColors.textFaint,
    );

ThemeData buildTheme(Brightness brightness) {
  // The comp commits to one world. A light rendition would be a different design, not an
  // inversion, so both slots resolve to the same theme rather than shipping a broken half.
  final scheme = const ColorScheme.dark(
    primary: AppColors.accent,
    onPrimary: AppColors.onAccent,
    secondary: AppColors.accentSoft,
    onSecondary: AppColors.onAccent,
    surface: AppColors.shell,
    onSurface: AppColors.text,
    error: AppColors.breaking,
    onError: AppColors.onAccent,
  ).copyWith(
    surfaceContainerHighest: AppColors.card,
    surfaceContainerHigh: AppColors.card,
    surfaceContainerLowest: AppColors.canvas,
    onSurfaceVariant: AppColors.textMuted,
    outline: AppColors.hairlineStrong,
    outlineVariant: AppColors.hairline,
    primaryContainer: const Color(0x2B8B7BFF),
    onPrimaryContainer: AppColors.accentSoft,
  );

  TextStyle sans(double size, FontWeight weight, {double? spacing, Color? color, double? height}) =>
      TextStyle(
        fontFamily: kSans,
        fontSize: size,
        fontWeight: weight,
        letterSpacing: spacing,
        height: height,
        color: color ?? AppColors.text,
      );

  final textTheme = TextTheme(
    displaySmall: sans(30, FontWeight.w600, spacing: -0.7),
    headlineMedium: sans(26, FontWeight.w600, spacing: -0.6),
    headlineSmall: sans(22, FontWeight.w600, spacing: -0.4),
    titleLarge: sans(19, FontWeight.w600, spacing: -0.3),
    titleMedium: sans(15, FontWeight.w600, spacing: -0.1),
    titleSmall: sans(13.5, FontWeight.w600),
    bodyLarge: sans(14, FontWeight.w400, height: 1.55),
    bodyMedium: sans(13, FontWeight.w400, height: 1.55, color: AppColors.textSecondary),
    bodySmall: sans(12.5, FontWeight.w400, height: 1.5, color: AppColors.textMuted),
    labelLarge: sans(12.5, FontWeight.w600),
    labelMedium: sans(12, FontWeight.w500, color: AppColors.textMuted),
    labelSmall: monoLabel(),
  );

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    fontFamily: kSans,
    textTheme: textTheme,
    scaffoldBackgroundColor: AppColors.shell,
    canvasColor: AppColors.shell,
    dividerColor: AppColors.hairline,
    dividerTheme: const DividerThemeData(color: AppColors.hairline, thickness: 1, space: 1),
    cardTheme: CardTheme(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: AppColors.card,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.panel),
        side: const BorderSide(color: AppColors.hairline),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      isDense: true,
      filled: true,
      fillColor: AppColors.bar,
      contentPadding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
      hintStyle: const TextStyle(fontFamily: kMono, fontSize: 12, color: AppColors.textFaint),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.field),
        borderSide: const BorderSide(color: AppColors.hairlineStrong),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.field),
        borderSide: const BorderSide(color: AppColors.hairlineStrong),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.field),
        borderSide: const BorderSide(color: AppColors.accent, width: 1.4),
      ),
    ),
    tooltipTheme: TooltipThemeData(
      waitDuration: const Duration(milliseconds: 350),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xF01A1D26),
        borderRadius: BorderRadius.circular(AppRadius.chip),
        border: Border.all(color: AppColors.hairlineStrong),
      ),
      textStyle: const TextStyle(
          fontFamily: kSans, color: AppColors.text, fontSize: 12, height: 1.35),
    ),
    chipTheme: ChipThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.pill)),
      side: const BorderSide(color: AppColors.hairlineStrong),
      backgroundColor: Colors.transparent,
      labelStyle: const TextStyle(fontFamily: kSans, fontSize: 11.5),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppColors.card,
      contentTextStyle: const TextStyle(fontFamily: kSans, color: AppColors.text, fontSize: 13),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.field),
        side: const BorderSide(color: AppColors.hairlineStrong),
      ),
    ),
    tabBarTheme: TabBarTheme(
      labelStyle: const TextStyle(fontFamily: kSans, fontSize: 13, fontWeight: FontWeight.w600),
      unselectedLabelStyle: const TextStyle(fontFamily: kSans, fontSize: 13),
      labelColor: AppColors.text,
      unselectedLabelColor: AppColors.textMuted,
      indicatorSize: TabBarIndicatorSize.label,
      indicator: const UnderlineTabIndicator(
        borderSide: BorderSide(color: AppColors.accent, width: 2),
      ),
      dividerColor: AppColors.hairline,
      overlayColor: WidgetStatePropertyAll(AppColors.accent.withOpacity(0.06)),
    ),
    listTileTheme: const ListTileThemeData(dense: true, iconColor: AppColors.textMuted),
    iconTheme: const IconThemeData(color: AppColors.textSecondary, size: 18),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.accent,
        foregroundColor: AppColors.onAccent,
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
        textStyle: const TextStyle(fontFamily: kSans, fontSize: 12.5, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.button)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.text,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        textStyle: const TextStyle(fontFamily: kSans, fontSize: 12.5, fontWeight: FontWeight.w500),
        side: const BorderSide(color: AppColors.hairlineStrong),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.button)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.accentSoft,
        textStyle: const TextStyle(fontFamily: kSans, fontSize: 12.5, fontWeight: FontWeight.w500),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.chip)),
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? AppColors.accent : AppColors.textMuted),
      trackColor: WidgetStateProperty.resolveWith((s) =>
          s.contains(WidgetState.selected) ? AppColors.accent.withOpacity(0.3) : AppColors.hairline),
      trackOutlineColor: const WidgetStatePropertyAll(AppColors.hairlineStrong),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: AppColors.accent,
      linearTrackColor: AppColors.hairline,
      circularTrackColor: AppColors.hairline,
    ),
    scrollbarTheme: ScrollbarThemeData(
      thumbColor: WidgetStatePropertyAll(AppColors.textGhost.withOpacity(0.7)),
      thickness: const WidgetStatePropertyAll(7),
      radius: const Radius.circular(4),
    ),
  );
}

/// A docked glass panel — the comp's primary container over the canvas.
class GlassPanel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final Color? border;
  final bool strong;
  const GlassPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.radius = AppRadius.panel,
    this.border,
    this.strong = false,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: strong ? AppColors.glassStrong : AppColors.glass,
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: border ?? AppColors.hairline),
          ),
          child: child,
        ),
      ),
    );
  }
}

/// A solid panel inside a framed surface (hub, sources, changelog).
class SolidPanel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? border;
  final Color? fill;
  final double radius;
  const SolidPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.border,
    this.fill,
    this.radius = AppRadius.panel,
  });

  @override
  Widget build(BuildContext context) => Container(
        padding: padding,
        decoration: BoxDecoration(
          color: fill ?? AppColors.card,
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: border ?? AppColors.hairline),
        ),
        child: child,
      );
}

/// The comp's small mono status pill: a tinted ground, a matching border, uppercase mono.
class StatusPill extends StatelessWidget {
  final String label;
  final Color color;
  final bool bordered;
  const StatusPill(this.label, this.color, {super.key, this.bordered = false});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
        decoration: BoxDecoration(
          color: color.withOpacity(0.15),
          borderRadius: BorderRadius.circular(5),
          border: bordered ? Border.all(color: color.withOpacity(0.32)) : null,
        ),
        child: Text(label.toUpperCase(),
            style: TextStyle(
                fontFamily: kMono, fontSize: 9.5, fontWeight: FontWeight.w500, color: color)),
      );
}

class RiskChip extends StatelessWidget {
  final String classification;
  const RiskChip(this.classification, {super.key});

  @override
  Widget build(BuildContext context) =>
      StatusPill(classificationLabel(classification), AppColors.forClassification(classification),
          bordered: true);
}

/// The 6px rounded square that marks a layer throughout the comp.
class LayerDot extends StatelessWidget {
  final String layer;
  final double size;
  const LayerDot(this.layer, {super.key, this.size = 6});

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: AppColors.forLayer(layer),
          borderRadius: BorderRadius.circular(size / 2),
        ),
      );
}

/// The BlipRadius mark: the accent gradient square used in every top bar.
class BrandMark extends StatelessWidget {
  final double size;
  const BrandMark({super.key, this.size = 20});

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          gradient: AppColors.accentGradient,
          borderRadius: BorderRadius.circular(size * 0.3),
        ),
      );
}
