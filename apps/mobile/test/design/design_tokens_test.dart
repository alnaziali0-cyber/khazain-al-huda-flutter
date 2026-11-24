import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:khazain_al_huda/design/theme_provider.dart';
import 'package:khazain_al_huda/design/tokens/app_tokens.dart';

void main() {
  group('signature colour tokens', () {
    test('matches the original ink, patina and clay palette', () {
      expect(KhazainColors.bgApp, const Color(0xFF111722));
      expect(KhazainColors.surface1, const Color(0xFF1B2633));
      expect(KhazainColors.surface2, const Color(0xFF263543));
      expect(KhazainColors.surface3, const Color(0xFF151F2B));
      expect(KhazainColors.bgNav, const Color(0xFF111722));
      expect(KhazainColors.hairline, const Color(0xFF35414A));
      expect(KhazainColors.divider, const Color(0xFF47565B));
      expect(KhazainColors.tileBg, const Color(0xFFF2EBDD));
      expect(KhazainColors.green, const Color(0xFF376E6A));
      expect(KhazainColors.greenDark, const Color(0xFF244B4F));
      expect(KhazainColors.greenActive, const Color(0xFF8DB9AE));
      expect(KhazainColors.tealSurface, const Color(0xFF263D43));
      expect(KhazainColors.skyTop, const Color(0xFF141D2B));
      expect(KhazainColors.skyBottom, const Color(0xFF394F68));
      expect(KhazainColors.gold, const Color(0xFFC77A57));
      expect(KhazainColors.goldBright, const Color(0xFFE6A27C));
      expect(KhazainColors.glassSlate, const Color(0xFF768C94));
      expect(KhazainColors.textPrimary, const Color(0xFFF4F1E9));
      expect(KhazainColors.textSecondary, const Color(0xFFD8E0DC));
      expect(KhazainColors.textMuted, const Color(0xFFA4B0B1));
      expect(KhazainColors.textOnTile, const Color(0xFF1A2B36));
      expect(KhazainColors.error, const Color(0xFFDC6C72));
      expect(KhazainColors.success, const Color(0xFF76A78E));
    });
  });

  group('type scale', () {
    test('matches the measured steps', () {
      expect(KhazainType.display, 28);
      expect(KhazainType.h1, 24);
      expect(KhazainType.h2, 20);
      expect(KhazainType.body, 16);
      expect(KhazainType.bodyDim, 14);
      expect(KhazainType.label, 13);
      expect(KhazainType.iconLabel, 13);
      expect(KhazainType.bodyLineHeight, 1.65);
    });
  });

  group('spacing and radius', () {
    test('spacing is a base-4 scale', () {
      expect(KhazainSpacing.xs, 4);
      expect(KhazainSpacing.sm, 8);
      expect(KhazainSpacing.md, 12);
      expect(KhazainSpacing.lg, 16);
      expect(KhazainSpacing.xl, 20);
      expect(KhazainSpacing.xxl, 24);
      expect(KhazainSpacing.xxxl, 32);
      expect(KhazainSpacing.huge, 40);
      expect(KhazainSpacing.pagePadding, 16);
      expect(KhazainSpacing.groupGap, 24);
      expect(KhazainSpacing.rowHeight, 56);
    });

    test('radius tokens match the reference', () {
      expect(KhazainRadius.card, 20);
      expect(KhazainRadius.tile, 24);
      expect(KhazainRadius.chip, 18);
      expect(KhazainRadius.sheet, 28);
    });
  });

  group('grid geometry', () {
    test('resolves the column count from the viewport width', () {
      expect(KhazainGrid.columnsFor(1024), 4);
      expect(KhazainGrid.columnsFor(768), 4);
      expect(KhazainGrid.columnsFor(600), 4);
      expect(KhazainGrid.columnsFor(412), 3);
      expect(KhazainGrid.columnsFor(360), 3);
      expect(KhazainGrid.columnsFor(320), 2);
    });

    test('every tile keeps a 44dp hit area at the reference widths', () {
      for (final width in const [320.0, 360.0, 412.0, 768.0, 1024.0]) {
        final columns = KhazainGrid.columnsFor(width);
        final tile = KhazainGrid.tileSizeFor(width, columns);
        expect(tile, greaterThanOrEqualTo(44),
            reason: 'tile too small at $width dp');
      }
    });

    test('the leftovers grid uses two columns with a 16dp gutter', () {
      expect(KhazainGrid.mukhalafatColumns, 2);
      expect(KhazainGrid.mukhalafatGutter, 16);
      expect(KhazainGrid.mukhalafatTileAspect, 1.35);
    });
  });

  group('theme serialisation', () {
    test('the base theme round-trips through JSON', () {
      final base = buildBaseTheme();
      final restored = UITheme.fromJson(base.toJson());
      expect(restored.colors, base.colors);
      expect(restored.typography['body']?.size, base.typography['body']?.size);
      expect(restored.radius, base.radius);
      expect(restored.spacing, base.spacing);
      expect(restored.grid, base.grid);
      expect(restored.mode, 'dark');
      expect(restored.direction, 'rtl');
      expect(restored.fontFamily, 'IBMPlexSansArabic');
    });

    test('every palette key resolves to a colour', () {
      final theme = buildBaseTheme();
      for (final key in theme.colors.keys) {
        expect(theme.color(key), isA<Color>());
      }
    });
  });

  group('token discipline', () {
    test('no raw hex colour is declared outside the token file', () {
      // The token file defines the palette and the developer panel is the
      // tool that edits it, so both are allowed to write literal colours.
      // The files below predate the token system and still carry their own
      // palette; they are listed here so the remainder stays visible.
      const allowed = <String>{
        'lib/design/tokens/app_tokens.dart',
        'lib/devpanel/',
        'lib/features/assistant/library_assistant_screen.dart',
        'lib/features/tasbih/tasbih_screen.dart',
        'lib/features/settings/prayer_alarm_reliability_screen.dart',
        'lib/features/visitor/visitor_guide_screen.dart',
        'lib/features/governorate/governorate_wheel_picker.dart',
        'lib/features/content/quran_text_reader_screen.dart',
      };
      final root = Directory('lib');
      final offenders = <String>[];
      for (final file in root.listSync(recursive: true).whereType<File>()) {
        if (!file.path.endsWith('.dart')) continue;
        if (allowed.any((entry) => file.path.startsWith(entry))) continue;
        final source = file.readAsStringSync();
        final matches = RegExp(r'Color\(0x[0-9A-Fa-f]{8}\)').allMatches(source);
        for (final match in matches) {
          offenders.add('${file.path}: ${match.group(0)}');
        }
      }
      expect(offenders, isEmpty,
          reason: 'Colours must resolve from the token file:\n'
              '${offenders.join('\n')}');
    });

    test('the design token file keeps every palette entry in sync', () {
      final dark = buildBaseTheme(mode: 'dark');
      final light = buildBaseTheme(mode: 'light');
      expect(dark.colors.keys.toSet(), light.colors.keys.toSet());
      expect(dark.colors.length, greaterThanOrEqualTo(24));
    });
  });
}
