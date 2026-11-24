import 'package:flutter/material.dart';

/// Signature design tokens for «خزائن الهدى» — the original Ink / Patina / Clay identity.
///
/// This palette combines ink navy, limestone, mineral patina and fired-clay
/// accents. It is the single source of truth for the app's visual language.
class KhazainColors {
  const KhazainColors._();

  // Surfaces
  static const Color bgApp = Color(0xFF111722);
  static const Color surface1 = Color(0xFF1B2633);
  static const Color surface2 = Color(0xFF263543);
  static const Color surface3 = Color(0xFF151F2B);
  static const Color bgNav = Color(0xFF111722);
  static const Color hairline = Color(0xFF35414A);
  static const Color divider = Color(0xFF47565B);
  static const Color tileBg = Color(0xFFF2EBDD);

  // Brand
  static const Color green = Color(0xFF376E6A);
  static const Color greenDark = Color(0xFF244B4F);
  static const Color greenActive = Color(0xFF8DB9AE);
  static const Color tealSurface = Color(0xFF263D43);

  // Sky gradient (home header)
  static const Color skyTop = Color(0xFF141D2B);
  static const Color skyBottom = Color(0xFF394F68);
  static const Color scrim = Color(0x99000000);

  // Accents
  static const Color gold = Color(0xFFC77A57);
  static const Color goldBright = Color(0xFFE6A27C);
  static const Color glassSlate = Color(0xFF768C94);

  // Text
  static const Color textPrimary = Color(0xFFF4F1E9);
  static const Color textSecondary = Color(0xFFD8E0DC);
  static const Color textMuted = Color(0xFFA4B0B1);
  static const Color textOnTile = Color(0xFF1A2B36);

  // Status (errors / success only)
  static const Color error = Color(0xFFDC6C72);
  static const Color success = Color(0xFF76A78E);

  /// Light-mode counterparts. The app ships dark-first; light is a debug and
  /// accessibility fallback exposed through the developer panel.
  static const Color lightBgApp = Color(0xFFF4F0E8);
  static const Color lightSurface1 = Color(0xFFFFFCF6);
  static const Color lightSurface2 = Color(0xFFEBE4D8);
  static const Color lightSurface3 = Color(0xFFF8F3E9);
  static const Color lightTextPrimary = Color(0xFF202632);
  static const Color lightTextSecondary = Color(0xFF37545A);
  static const Color lightTextMuted = Color(0xFF69777A);
}

/// Type scale. Sizes are logical pixels before the user font scale is
/// applied by the theme provider.
class KhazainType {
  const KhazainType._();

  static const double display = 28;
  static const double h1 = 24;
  static const double h2 = 20;
  static const double body = 16;
  static const double bodyDim = 14;
  static const double label = 13;
  static const double iconLabel = 13;

  static const double bodyLineHeight = 1.65;

  static const FontWeight regular = FontWeight.w400;
  static const FontWeight medium = FontWeight.w500;
  static const FontWeight semiBold = FontWeight.w600;
  static const FontWeight bold = FontWeight.w700;

  /// Calligraphic families used for adhkar (G22).
  static const String calligraphicFamily = 'AmiriQuran';
  static const String uiFamily = 'IBMPlexSansArabic';
}

/// Spacing scale — base unit 4.
class KhazainSpacing {
  const KhazainSpacing._();

  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double xxxl = 32;
  static const double huge = 40;

  /// Page gutter.
  static const double pagePadding = 16;

  /// Vertical gap between grouped blocks.
  static const double groupGap = 24;

  /// Standard list row height.
  static const double rowHeight = 56;
}

/// Corner radii.
class KhazainRadius {
  const KhazainRadius._();

  static const double card = 20;
  static const double tile = 24;
  static const double chip = 18;
  static const double sheet = 28;
  static const double field = 16;
}

/// Grid geometry for the sections screen (S5) and the leftovers screen (S3).
class KhazainGrid {
  const KhazainGrid._();

  /// Columns at ≥600dp.
  static const int wideColumns = 4;

  /// Columns between 360dp and 599dp.
  static const int compactColumns = 3;

  /// Gutter expressed as a fraction of the tile edge.
  static const double gutterRatio = 0.35;

  /// Side padding in logical pixels.
  static const double sidePadding = 16;

  /// Sections tile aspect ratio (1:1).
  static const double sectionsTileAspect = 1;

  /// Leftovers grid (S3): two columns, 16dp gutter, 1:1.35 tiles.
  static const int mukhalafatColumns = 2;
  static const double mukhalafatGutter = 16;
  static const double mukhalafatTileAspect = 1.35;

  /// Number of columns resolved for a given viewport width.
  static int columnsFor(double width) {
    if (width >= 600) return wideColumns;
    if (width >= 360) return compactColumns;
    return 2;
  }

  /// Edge length of a square tile that fits [width] using [columns] columns.
  static double tileSizeFor(double width, int columns) {
    final available = width - (sidePadding * 2);
    final unit = columns + ((columns - 1) * gutterRatio);
    if (unit <= 0) return available;
    return available / unit;
  }
}

/// Motion tokens (160 / 240 / 320ms).
class KhazainMotion {
  const KhazainMotion._();

  static const Duration fast = Duration(milliseconds: 160);
  static const Duration normal = Duration(milliseconds: 240);
  static const Duration slow = Duration(milliseconds: 320);

  /// Material-style emphasized-decelerate curve used across the app.
  static const Curve curve = Cubic(0.2, 0, 0, 1);
}

/// Icon geometry: 24px grid, 2px stroke, round caps, two-tone.
class KhazainIconGrid {
  const KhazainIconGrid._();

  static const double canvas = 24;
  static const double stroke = 2;
  static const double minRenderSize = 16;
}
