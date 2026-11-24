import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../design/tokens/app_tokens.dart';
import '../design/theme_provider.dart';
import '../devpanel/models.dart';
import '../devpanel/store.dart';
import '../icons/khazain_icons.dart';

/// Renders one of the 18 two-tone icons.
///
/// The glyph is described as SVG path data on a 24px canvas with a 2px
/// stroke. When the developer panel overrides an icon, the override wins so
/// the Icon Manager tab has a live effect without a rebuild of the app.
class KhazainIcon extends ConsumerWidget {
  const KhazainIcon(
    this.iconId, {
    super.key,
    this.size = 24,
    this.primary,
    this.secondary,
    this.stroke,
  });

  final String iconId;
  final double size;
  final String? primary;
  final String? secondary;
  final double? stroke;

  /// Builds the SVG document for a definition.
  static String buildSvg({
    required List<String> primaryPaths,
    required List<String> accentPaths,
    required String primaryColor,
    required String accentColor,
    required double strokeWidth,
  }) {
    final buffer = StringBuffer()
      ..write('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" '
          'fill="none" stroke-linecap="round" stroke-linejoin="round">');
    for (final path in primaryPaths) {
      buffer.write('<path d="$path" stroke="$primaryColor" '
          'stroke-width="$strokeWidth"/>');
    }
    for (final path in accentPaths) {
      buffer.write('<path d="$path" stroke="$accentColor" '
          'stroke-width="$strokeWidth"/>');
    }
    buffer.write('</svg>');
    return buffer.toString();
  }

  static String _hex(Color color) {
    final argb = color.toARGB32().toRadixString(16).padLeft(8, '0');
    return '#${argb.substring(2).toUpperCase()}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(uiThemeProvider);
    final primaryColor = _hex(theme.color('green'));
    final accentColor = _hex(theme.color('gold'));
    final overrides = ref.watch(
      devStoreProvider.select((state) => state.icons),
    );

    IconDef? override;
    for (final icon in overrides) {
      if (icon.id == iconId) override = icon;
    }

    if (override != null) {
      final svg = buildSvg(
        primaryPaths: override.primaryPaths,
        accentPaths: override.accentPaths,
        primaryColor: primary ??
            (override.primary == '#174940' ? primaryColor : override.primary),
        accentColor: secondary ??
            (override.secondary == '#BC9551'
                ? accentColor
                : override.secondary ?? override.primary),
        strokeWidth: stroke ?? override.stroke,
      );
      return SvgPicture.string(
        svg,
        width: size,
        height: size,
        semanticsLabel: iconId,
      );
    }

    final definition = khazainIconById(iconId);
    if (definition == null) {
      // Never render a blank box: fall back to a neutral glyph so a missing
      // icon is visible during the audit instead of silently disappearing.
      return SizedBox(
        width: size,
        height: size,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(color: KhazainColors.textMuted, width: 1.5),
            borderRadius: BorderRadius.circular(size / 6),
          ),
        ),
      );
    }

    final svg = buildSvg(
      primaryPaths: definition.paths,
      accentPaths: definition.accentPaths,
      primaryColor: primary ?? primaryColor,
      accentColor: secondary ?? accentColor,
      strokeWidth: stroke ?? definition.stroke,
    );
    return SvgPicture.string(
      svg,
      width: size,
      height: size,
      semanticsLabel: definition.label,
    );
  }
}
