import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/app_preferences.dart';
import '../core/providers.dart';
import '../devpanel/store.dart' as dev_store;
import 'tokens/app_tokens.dart';

/// A single typography entry — mirrors the developer-panel schema
/// `{size, weight, lineHeight, family}`.
@immutable
class TypographySpec {
  const TypographySpec({
    required this.size,
    required this.weight,
    required this.lineHeight,
    required this.family,
  });

  final double size;
  final int weight;
  final double lineHeight;
  final String family;

  FontWeight get fontWeight => FontWeight.values.firstWhere(
        (value) => value.index == weight,
        orElse: () => FontWeight.w400,
      );

  TextStyle toStyle({
    Color? color,
    double scale = 1,
    String? familyOverride,
  }) =>
      TextStyle(
        fontSize: size * scale,
        fontWeight: fontWeight,
        height: lineHeight,
        fontFamily: familyOverride ?? family,
        color: color,
      );

  TypographySpec copyWith({
    double? size,
    int? weight,
    double? lineHeight,
    String? family,
  }) =>
      TypographySpec(
        size: size ?? this.size,
        weight: weight ?? this.weight,
        lineHeight: lineHeight ?? this.lineHeight,
        family: family ?? this.family,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'size': size,
        'weight': weight,
        'lineHeight': lineHeight,
        'family': family,
      };

  factory TypographySpec.fromJson(Map<String, dynamic> json) =>
      TypographySpec(
        size: (json['size'] as num?)?.toDouble() ?? 15,
        weight: (json['weight'] as num?)?.toInt() ?? 400,
        lineHeight: (json['lineHeight'] as num?)?.toDouble() ?? 1.4,
        family: json['family'] as String? ?? KhazainType.uiFamily,
      );

  @override
  bool operator ==(Object other) =>
      other is TypographySpec &&
      other.size == size &&
      other.weight == weight &&
      other.lineHeight == lineHeight &&
      other.family == family;

  @override
  int get hashCode => Object.hash(size, weight, lineHeight, family);
}

/// The live theme contract. It is fully serialisable so the developer panel
/// can edit, export and re-import it.
@immutable
class UITheme {
  const UITheme({
    required this.colors,
    required this.typography,
    required this.radius,
    required this.spacing,
    required this.grid,
    this.mode = 'dark',
    this.fontScale = 1,
    this.direction = 'rtl',
    this.fontFamily = KhazainType.uiFamily,
    this.calligraphicFamily = KhazainType.calligraphicFamily,
    this.showDiacritics = true,
    this.calligraphicScale = 1,
  });

  final Map<String, String> colors;
  final Map<String, TypographySpec> typography;
  final Map<String, double> radius;
  final Map<String, double> spacing;
  final Map<String, double> grid;

  /// `dark` | `light` | `system`
  final String mode;

  /// 0.85 / 1.0 / 1.15 / 1.3
  final double fontScale;

  /// `rtl` | `ltr`
  final String direction;

  final String fontFamily;
  final String calligraphicFamily;
  final bool showDiacritics;
  final double calligraphicScale;

  bool get isLight => mode == 'light';

  Color color(String key) {
    final raw = colors[key];
    if (raw == null) return KhazainColors.textPrimary;
    final value = raw.replaceAll('#', '');
    final parsed = int.tryParse(value, radix: 16);
    if (parsed == null) return KhazainColors.textPrimary;
    return Color(0xFF000000 | parsed);
  }

  double get cardRadius => radius['card'] ?? KhazainRadius.card;
  double get tileRadius => radius['tile'] ?? KhazainRadius.tile;
  double get chipRadius => radius['chip'] ?? KhazainRadius.chip;
  double get sheetRadius => radius['sheet'] ?? KhazainRadius.sheet;
  double get fieldRadius => radius['field'] ?? KhazainRadius.field;

  TypographySpec type(String key) =>
      typography[key] ??
      TypographySpec(
        size: KhazainType.body,
        weight: 400,
        lineHeight: KhazainType.bodyLineHeight,
        family: fontFamily,
      );

  UITheme copyWith({
    Map<String, String>? colors,
    Map<String, TypographySpec>? typography,
    Map<String, double>? radius,
    Map<String, double>? spacing,
    Map<String, double>? grid,
    String? mode,
    double? fontScale,
    String? direction,
    String? fontFamily,
    String? calligraphicFamily,
    bool? showDiacritics,
    double? calligraphicScale,
  }) =>
      UITheme(
        colors: colors ?? this.colors,
        typography: typography ?? this.typography,
        radius: radius ?? this.radius,
        spacing: spacing ?? this.spacing,
        grid: grid ?? this.grid,
        mode: mode ?? this.mode,
        fontScale: fontScale ?? this.fontScale,
        direction: direction ?? this.direction,
        fontFamily: fontFamily ?? this.fontFamily,
        calligraphicFamily: calligraphicFamily ?? this.calligraphicFamily,
        showDiacritics: showDiacritics ?? this.showDiacritics,
        calligraphicScale: calligraphicScale ?? this.calligraphicScale,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'colors': colors,
        'typography': typography.map((key, value) => MapEntry(key, value.toJson())),
        'radius': radius,
        'spacing': spacing,
        'grid': grid,
        'mode': mode,
        'fontScale': fontScale,
        'direction': direction,
        'fontFamily': fontFamily,
        'calligraphicFamily': calligraphicFamily,
        'showDiacritics': showDiacritics,
        'calligraphicScale': calligraphicScale,
      };

  factory UITheme.fromJson(Map<String, dynamic> json) {
    final rawColors = (json['colors'] as Map?)?.cast<String, dynamic>() ?? {};
    final rawType = (json['typography'] as Map?)?.cast<String, dynamic>() ?? {};
    final rawRadius = (json['radius'] as Map?)?.cast<String, dynamic>() ?? {};
    final rawSpacing = (json['spacing'] as Map?)?.cast<String, dynamic>() ?? {};
    final rawGrid = (json['grid'] as Map?)?.cast<String, dynamic>() ?? {};
    return UITheme(
      colors: rawColors.map((key, value) => MapEntry(key, value.toString())),
      typography: rawType.map(
        (key, value) => MapEntry(
          key,
          TypographySpec.fromJson(
              (value as Map?)?.cast<String, dynamic>() ?? const {}),
        ),
      ),
      radius: rawRadius.map((key, value) => MapEntry(key, (value as num).toDouble())),
      spacing:
          rawSpacing.map((key, value) => MapEntry(key, (value as num).toDouble())),
      grid: rawGrid.map((key, value) => MapEntry(key, (value as num).toDouble())),
      mode: json['mode'] as String? ?? 'dark',
      fontScale: (json['fontScale'] as num?)?.toDouble() ?? 1,
      direction: json['direction'] as String? ?? 'rtl',
      fontFamily: json['fontFamily'] as String? ?? KhazainType.uiFamily,
      calligraphicFamily:
          json['calligraphicFamily'] as String? ?? KhazainType.calligraphicFamily,
      showDiacritics: json['showDiacritics'] as bool? ?? true,
      calligraphicScale: (json['calligraphicScale'] as num?)?.toDouble() ?? 1,
    );
  }

  String encode() => const JsonEncoder.withIndent('  ').convert(toJson());
}

/// The built-in dark palette: ink navy, mineral patina and fired clay.
const Map<String, String> kDarkPalette = <String, String>{
  'bgApp': '#111722',
  'surface1': '#1B2633',
  'surface2': '#263543',
  'surface3': '#151F2B',
  'bgNav': '#111722',
  'hairline': '#35414A',
  'divider': '#47565B',
  'tileBg': '#F2EBDD',
  'green': '#376E6A',
  'greenDark': '#244B4F',
  'greenActive': '#8DB9AE',
  'tealSurface': '#263D43',
  'skyTop': '#141D2B',
  'skyBottom': '#394F68',
  'scrim': '#99000000',
  'gold': '#C77A57',
  'goldBright': '#E6A27C',
  'glassSlate': '#768C94',
  'textPrimary': '#F4F1E9',
  'textSecondary': '#D8E0DC',
  'textMuted': '#A4B0B1',
  'textOnTile': '#1A2B36',
  'error': '#DC6C72',
  'success': '#76A78E',
};

/// The light fallback palette.
const Map<String, String> kLightPalette = <String, String>{
  'bgApp': '#F4F0E8',
  'surface1': '#FFFCF6',
  'surface2': '#EBE4D8',
  'surface3': '#F8F3E9',
  'bgNav': '#FFFCF6',
  'hairline': '#DED4C6',
  'divider': '#D4C9B9',
  'tileBg': '#FFFCF6',
  'green': '#376E6A',
  'greenDark': '#244B4F',
  'greenActive': '#3D8077',
  'tealSurface': '#E4EEEA',
  'skyTop': '#141D2B',
  'skyBottom': '#394F68',
  'scrim': '#99000000',
  'gold': '#B76548',
  'goldBright': '#BB6A4D',
  'glassSlate': '#768C94',
  'textPrimary': '#202632',
  'textSecondary': '#37545A',
  'textMuted': '#69777A',
  'textOnTile': '#202632',
  'error': '#B94D58',
  'success': '#37765C',
};

/// Built-in typography steps keyed by their token name.
Map<String, TypographySpec> buildBaseTypography(String family) =>
    <String, TypographySpec>{
      'display': TypographySpec(
          size: KhazainType.display,
          weight: 700,
          lineHeight: 1.25,
          family: family),
      'h1': TypographySpec(
          size: KhazainType.h1, weight: 700, lineHeight: 1.3, family: family),
      'h2': TypographySpec(
          size: KhazainType.h2, weight: 700, lineHeight: 1.35, family: family),
      'body': TypographySpec(
          size: KhazainType.body,
          weight: 400,
          lineHeight: KhazainType.bodyLineHeight,
          family: family),
      'bodyDim': TypographySpec(
          size: KhazainType.bodyDim,
          weight: 400,
          lineHeight: 1.5,
          family: family),
      'label': TypographySpec(
          size: KhazainType.label, weight: 500, lineHeight: 1.35, family: family),
      'iconLabel': TypographySpec(
          size: KhazainType.iconLabel,
          weight: 600,
          lineHeight: 1.25,
          family: family),
    };

Map<String, double> buildBaseRadius() => <String, double>{
      'card': KhazainRadius.card,
      'tile': KhazainRadius.tile,
      'chip': KhazainRadius.chip,
      'sheet': KhazainRadius.sheet,
      'field': KhazainRadius.field,
    };

Map<String, double> buildBaseSpacing() => <String, double>{
      'xs': KhazainSpacing.xs,
      'sm': KhazainSpacing.sm,
      'md': KhazainSpacing.md,
      'lg': KhazainSpacing.lg,
      'xl': KhazainSpacing.xl,
      'xxl': KhazainSpacing.xxl,
    };

Map<String, double> buildBaseGrid() => <String, double>{
      'columns': KhazainGrid.wideColumns.toDouble(),
      'gutter': KhazainGrid.gutterRatio,
      'sidePadding': KhazainGrid.sidePadding,
      'tileAspect': KhazainGrid.sectionsTileAspect,
    };

/// The theme seed used before any developer-panel override is applied.
UITheme buildBaseTheme({String mode = 'dark', String family = KhazainType.uiFamily}) =>
    UITheme(
      colors: Map<String, String>.from(
          mode == 'light' ? kLightPalette : kDarkPalette),
      typography: buildBaseTypography(family),
      radius: buildBaseRadius(),
      spacing: buildBaseSpacing(),
      grid: buildBaseGrid(),
      mode: mode,
      fontFamily: family,
    );

/// Resolves the effective theme: base tokens → developer overrides → user
/// preferences (font scale / family).
final uiThemeProvider = Provider<UITheme>((ref) {
  final mode = ref.watch(themeModeProvider);
  final prefs = ref.watch(appPreferencesProvider);
  final overrides = ref.watch(devThemeOverridesProvider);

  final resolvedMode = switch (mode) {
    ThemeMode.dark => 'dark',
    ThemeMode.light => 'light',
    ThemeMode.system => 'system',
  };
  final paletteMode = resolvedMode == 'system' ? 'dark' : resolvedMode;
  final base = buildBaseTheme(
    mode: paletteMode,
    family: prefs.appFontFamily.themeFamily,
  );

  final colors = Map<String, String>.from(base.colors)
    ..addAll(overrides[paletteMode] ?? const <String, String>{});

  final typography = buildBaseTypography(prefs.appFontFamily.themeFamily);
  final rawTypography =
      (overrides['typography'] as Map?)?.cast<String, dynamic>() ?? const {};
  rawTypography.forEach((key, value) {
    if (value is Map) {
      typography[key] =
          TypographySpec.fromJson(value.cast<String, dynamic>());
    }
  });

  final radius = buildBaseRadius()
    ..addAll((overrides['radius'] as Map?)?.cast<String, double>() ??
        const <String, double>{});
  final spacing = buildBaseSpacing()
    ..addAll((overrides['spacing'] as Map?)?.cast<String, double>() ??
        const <String, double>{});
  final grid = buildBaseGrid()
    ..addAll((overrides['grid'] as Map?)?.cast<String, double>() ??
        const <String, double>{});

  return base.copyWith(
    colors: colors,
    typography: typography,
    radius: radius,
    spacing: spacing,
    grid: grid,
    mode: resolvedMode,
    fontScale: prefs.textSize.factor,
    fontFamily: prefs.appFontFamily.themeFamily,
    direction: (overrides['direction'] as String?) ?? 'rtl',
    showDiacritics: prefs.showDiacritics,
    calligraphicScale: prefs.calligraphicScale,
  );
});

/// Developer-panel colour/typography/radius/spacing/grid overrides.
final devThemeOverridesProvider = dev_store.devThemeOverridesProvider;