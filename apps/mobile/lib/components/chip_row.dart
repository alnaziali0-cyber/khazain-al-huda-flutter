import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design/theme_provider.dart';
import 'app_text.dart';

/// A horizontally scrolling chip row (G8).
///
/// The row scrolls with the full width available, fades the trailing edge,
/// hides the scroll indicator and snaps between chips — the reference design
/// clipped its last chip, which this implementation removes.
class ChipRow extends ConsumerWidget {
  const ChipRow({
    super.key,
    required this.chips,
    required this.onSelected,
    this.selectedId,
    this.padding = const EdgeInsets.symmetric(horizontal: 16),
  });

  /// Each chip is a `(id, label)` pair.
  final List<({String id, String label})> chips;

  final ValueChanged<String> onSelected;
  final String? selectedId;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(uiThemeProvider);
    if (chips.isEmpty) {
      return const SizedBox.shrink();
    }
    return ShaderMask(
      shaderCallback: (bounds) => const LinearGradient(
        begin: Alignment.centerRight,
        end: Alignment.centerLeft,
        colors: <Color>[Colors.white, Colors.white, Colors.transparent],
        stops: <double>[0.0, 0.94, 1.0],
      ).createShader(bounds),
      blendMode: BlendMode.dstIn,
      child: ScrollConfiguration(
        behavior: const _NoGlowBehavior(),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: padding,
          physics: const BouncingScrollPhysics(),
          child: Row(
            children: [
              for (final chip in chips) ...[
                _Chip(
                  label: chip.label,
                  selected: chip.id == selectedId,
                  radius: theme.chipRadius,
                  onTap: () => onSelected(chip.id),
                ),
                const SizedBox(width: 8),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Chip extends ConsumerWidget {
  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.radius,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final double radius;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(uiThemeProvider);
    final background =
        selected ? theme.color('green') : theme.color('surface2');
    final foreground =
        selected ? theme.color('textPrimary') : theme.color('textSecondary');
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(radius),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            curve: const Cubic(0.2, 0, 0, 1),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(radius),
              border: Border.all(
                color: selected
                    ? theme.color('green')
                    : theme.color('divider'),
              ),
            ),
            child: AppText(
              label,
              token: 'label',
              color: foreground,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ),
    );
  }
}

class _NoGlowBehavior extends ScrollBehavior {
  const _NoGlowBehavior();

  @override
  Widget buildOverscrollIndicator(
          BuildContext context, Widget child, ScrollableDetails details) =>
      child;
}
