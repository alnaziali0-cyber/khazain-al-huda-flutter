import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design/theme_provider.dart';

/// Token-driven Arabic text.
///
/// Every string in the app renders through this widget so the type scale and
/// the user font scale stay consistent, and so calligraphic text (adhkar)
/// can be rendered with an independent size and diacritics switch (G22).
class AppText extends ConsumerWidget {
  const AppText(
    this.text, {
    super.key,
    this.token = 'body',
    this.color,
    this.scale = 1,
    this.textAlign,
    this.maxLines,
    this.overflow,
    this.height,
    this.fontWeight,
    this.letterSpacing,
  });

  final String text;

  /// Key inside `UITheme.typography`.
  final String token;

  /// Overrides the token colour.
  final Color? color;

  /// Extra multiplier on top of the user font scale.
  final double scale;

  final TextAlign? textAlign;
  final int? maxLines;
  final TextOverflow? overflow;
  final double? height;
  final FontWeight? fontWeight;
  final double? letterSpacing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(uiThemeProvider);
    final spec = theme.type(token);
    return Text(
      text,
      textAlign: textAlign,
      maxLines: maxLines,
      overflow: overflow,
      style: spec.toStyle(
        color: color ?? theme.color('textPrimary'),
        scale: theme.fontScale * scale,
        familyOverride: theme.fontFamily,
      ).copyWith(
        height: height ?? spec.lineHeight,
        fontWeight: fontWeight ?? spec.fontWeight,
        letterSpacing: letterSpacing,
      ),
    );
  }
}

/// Calligraphic text for adhkar and du'a — rendered with the Amiri family,
/// an independent size multiplier and a togglable diacritics switch (G22).
class CalligraphicText extends ConsumerWidget {
  const CalligraphicText(
    this.text, {
    super.key,
    this.color,
    this.scale = 1,
    this.textAlign,
    this.maxLines,
    this.overflow,
    this.showDiacritics,
  });

  final String text;
  final Color? color;
  final double scale;
  final TextAlign? textAlign;
  final int? maxLines;
  final TextOverflow? overflow;

  /// Overrides the theme-wide diacritics switch when provided.
  final bool? showDiacritics;

  /// Removes Arabic diacritics (tashkeel) and tatweel from the string.
  static String stripDiacritics(String value) {
    final buffer = StringBuffer();
    for (final rune in value.runes) {
      // Arabic diacritics live in U+0610–U+061A, U+064B–U+065F, U+0670 and
      // U+06D6–U+06ED; the tatweel is U+0640.
      final isDiacritic = (rune >= 0x0610 && rune <= 0x061A) ||
          (rune >= 0x064B && rune <= 0x065F) ||
          rune == 0x0640 ||
          (rune >= 0x06D6 && rune <= 0x06ED);
      if (!isDiacritic) buffer.writeCharCode(rune);
    }
    return buffer.toString();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(uiThemeProvider);
    final withDiacritics = showDiacritics ?? theme.showDiacritics;
    final content = withDiacritics ? text : stripDiacritics(text);
    final spec = theme.type('body');
    return Text(
      content,
      textAlign: textAlign,
      maxLines: maxLines,
      overflow: overflow,
      style: spec.toStyle(
        color: color ?? theme.color('textPrimary'),
        scale: theme.fontScale * scale * theme.calligraphicScale,
        familyOverride: theme.calligraphicFamily,
      ).copyWith(
        height: 1.9,
        fontWeight: FontWeight.w400,
      ),
    );
  }
}

/// A dimmed caption used for helper copy under a section.
class BodyDimText extends StatelessWidget {
  const BodyDimText(this.text, {super.key, this.maxLines, this.textAlign});

  final String text;
  final int? maxLines;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) => AppText(
        text,
        token: 'bodyDim',
        color: Theme.of(context).colorScheme.onSurface.withOpacity(.72),
        maxLines: maxLines,
        textAlign: textAlign,
      );
}

/// Section title used at the top of a page or a group.
class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Expanded(
            child: AppText(text, token: 'h2'),
          ),
          if (trailing != null) trailing!,
        ],
      );
}

/// A gold caption used under a grid tile (IconLabel token).
class IconLabelText extends ConsumerWidget {
  const IconLabelText(this.text, {super.key, this.maxLines = 2, this.textAlign});

  final String text;
  final int maxLines;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(uiThemeProvider);
    return AppText(
      text,
      token: 'iconLabel',
      color: theme.color('gold'),
      maxLines: maxLines,
      textAlign: textAlign,
      overflow: TextOverflow.ellipsis,
    );
  }
}

/// The page gutter used by every screen (16dp).
const EdgeInsets kzPagePadding = EdgeInsets.symmetric(horizontal: 16);

/// The standard page padding including the vertical rhythm.
const EdgeInsets kzPageInsets = EdgeInsets.fromLTRB(16, 16, 16, 24);
