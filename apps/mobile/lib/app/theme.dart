import 'package:flutter/material.dart';

import '../design/theme_provider.dart';
import '../design/tokens/app_tokens.dart';

/// Legacy palette kept for the few widgets that still reference the old
/// names. The values now resolve from the measured design tokens.
class KhazainPalette {
  const KhazainPalette._();

  static const green = KhazainColors.green;
  static const greenSoft = KhazainColors.greenActive;
  static const gold = KhazainColors.gold;
  static const dark = KhazainColors.bgApp;
  static const darkSurface = KhazainColors.surface1;
  static const darkElevated = KhazainColors.surface2;
  static const lightSurface = KhazainColors.lightSurface1;
  static const lightInk = KhazainColors.lightTextPrimary;
}

/// Builds the Material theme from the live design tokens.
///
/// Every colour, radius and text step resolves from [UITheme], so a change
/// made in the developer panel is reflected in Material widgets too.
ThemeData buildThemeData(UITheme theme, {required bool isDark}) {
  final scheme = ColorScheme.fromSeed(
    seedColor: theme.color('green'),
    brightness: isDark ? Brightness.dark : Brightness.light,
  ).copyWith(
    primary: theme.color('green'),
    secondary: theme.color('gold'),
    surface: theme.color('surface1'),
    error: theme.color('error'),
  );

  TextStyle style(String token) => theme
      .type(token)
      .toStyle(
        color: theme.color('textPrimary'),
        scale: theme.fontScale,
        familyOverride: theme.fontFamily,
      );

  return ThemeData(
    useMaterial3: true,
    brightness: isDark ? Brightness.dark : Brightness.light,
    fontFamily: theme.fontFamily,
    colorScheme: scheme,
    scaffoldBackgroundColor: theme.color('bgApp'),
    dividerColor: theme.color('divider'),
    splashFactory: InkSparkle.splashFactory,
    cardTheme: CardThemeData(
      color: theme.color('surface1'),
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(theme.cardRadius),
        side: BorderSide(color: theme.color('hairline')),
      ),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      foregroundColor: theme.color('textPrimary'),
      elevation: 0,
      centerTitle: false,
      titleTextStyle: style('h2'),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: theme.color('bgNav'),
      indicatorColor: theme.color('green').withOpacity(.28),
      labelTextStyle: WidgetStatePropertyAll<TextStyle>(style('label')),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: theme.color('surface3'),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(theme.fieldRadius),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(theme.fieldRadius),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(theme.fieldRadius),
        borderSide: BorderSide(color: theme.color('green'), width: 1.5),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: theme.color('surface2'),
      labelStyle: style('label'),
      side: BorderSide(color: theme.color('divider')),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(theme.chipRadius),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: theme.color('surface2'),
      contentTextStyle: style('body'),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: theme.color('surface2'),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(theme.cardRadius),
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: theme.color('surface1'),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(theme.sheetRadius),
        ),
      ),
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: theme.color('gold'),
      thumbColor: theme.color('gold'),
      inactiveTrackColor: theme.color('divider'),
    ),
    listTileTheme: ListTileThemeData(
      iconColor: theme.color('textSecondary'),
      textColor: theme.color('textPrimary'),
    ),
  );
}

/// Light theme built from the shipped tokens.
ThemeData lightTheme({String fontFamily = KhazainType.uiFamily}) {
  return buildThemeData(
    buildBaseTheme(mode: 'light', family: fontFamily),
    isDark: false,
  );
}

/// Dark theme built from the shipped tokens.
ThemeData darkTheme({String fontFamily = KhazainType.uiFamily}) {
  return buildThemeData(
    buildBaseTheme(mode: 'dark', family: fontFamily),
    isDark: true,
  );
}
