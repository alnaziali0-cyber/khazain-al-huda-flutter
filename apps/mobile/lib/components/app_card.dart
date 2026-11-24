import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design/theme_provider.dart';
import 'app_text.dart';
import 'khazain_icon.dart';

/// A rounded surface container resolved from the token set.
class KzSurface extends ConsumerWidget {
  const KzSurface({
    super.key,
    required this.child,
    this.level = 1,
    this.radiusToken = 'card',
    this.padding = EdgeInsets.zero,
    this.onTap,
    this.color,
  });

  /// 1 → surface-1, 2 → surface-2, 3 → surface-3.
  final int level;
  final String radiusToken;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? color;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(uiThemeProvider);
    final surface = switch (level) {
      2 => theme.color('surface2'),
      3 => theme.color('surface3'),
      _ => theme.color('surface1'),
    };
    final radius = switch (radiusToken) {
      'tile' => theme.tileRadius,
      'chip' => theme.chipRadius,
      'sheet' => theme.sheetRadius,
      'field' => theme.fieldRadius,
      _ => theme.cardRadius,
    };
    final content = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? surface,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: theme.color('hairline')),
      ),
      child: child,
    );

    if (onTap == null) return content;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(radius),
        child: content,
      ),
    );
  }
}

/// A grouped settings block: a rounded surface holding 56dp rows separated
/// by hairline dividers (matches the reference settings screen).
class KzGroupCard extends ConsumerWidget {
  const KzGroupCard({
    super.key,
    required this.children,
    this.level = 2,
    this.padding = EdgeInsets.zero,
  });

  final List<Widget> children;
  final int level;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(uiThemeProvider);
    final rows = <Widget>[];
    for (var index = 0; index < children.length; index++) {
      rows.add(children[index]);
      if (index != children.length - 1) {
        rows.add(Divider(
          height: 1,
          thickness: 1,
          color: theme.color('divider'),
          indent: 16,
          endIndent: 16,
        ));
      }
    }
    return KzSurface(
      level: level,
      padding: padding,
      child: Column(mainAxisSize: MainAxisSize.min, children: rows),
    );
  }
}

/// One 56dp row inside a [KzGroupCard].
class KzRow extends ConsumerWidget {
  const KzRow({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.onTap,
    this.titleColor,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;
  final Color? titleColor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(uiThemeProvider);
    final content = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 56),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            if (leading != null) ...[
              leading!,
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppText(
                    title,
                    token: 'body',
                    color: titleColor,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    AppText(
                      subtitle!,
                      token: 'bodyDim',
                      color: theme.color('textMuted'),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: 12),
              trailing!,
            ],
          ],
        ),
      ),
    );

    if (onTap == null) return content;
    return Material(
      color: Colors.transparent,
      child: InkWell(onTap: onTap, child: content),
    );
  }
}

/// A square tile used by the sections grid (S5).
class KzTile extends ConsumerWidget {
  const KzTile({
    super.key,
    required this.iconId,
    required this.label,
    this.description = '',
    this.onTap,
    this.selected = false,
    this.dashed = false,
    this.iconSize,
  });

  final String iconId;
  final String label;
  final String description;
  final VoidCallback? onTap;
  final bool selected;

  /// Renders the "add section" affordance with a dashed outline.
  final bool dashed;
  final double? iconSize;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(uiThemeProvider);
    final glyphSize = (iconSize ?? 28).clamp(22, 30).toDouble();
    final tile = Container(
      decoration: BoxDecoration(
        color: theme.color('tileBg'),
        borderRadius: BorderRadius.circular(theme.tileRadius),
        border: Border.all(
          color: dashed ? theme.color('gold') : theme.color('hairline'),
          width: dashed ? 1.4 : 1,
        ),
        boxShadow: dashed
            ? const <BoxShadow>[]
            : <BoxShadow>[
                BoxShadow(
                  color: Colors.black.withOpacity(.10),
                  blurRadius: 12,
                  offset: const Offset(0, 5),
                ),
              ],
      ),
      child: Stack(
        children: [
          if (dashed)
            Positioned.fill(
              child: CustomPaint(
                painter: _DashedBorderPainter(color: theme.color('gold')),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: theme.color('green').withOpacity(.13),
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: Center(
                        child: iconId.isEmpty
                            ? Icon(
                                Icons.add_rounded,
                                size: 27,
                                color: theme.color('gold'),
                              )
                            : IconTileGlyph(iconId: iconId, size: glyphSize),
                      ),
                    ),
                    const Spacer(),
                    if (!dashed)
                      Icon(
                        Icons.arrow_outward_rounded,
                        size: 16,
                        color: theme.color('textOnTile').withOpacity(.48),
                      ),
                  ],
                ),
                const Spacer(),
                AppText(
                  label,
                  token: 'body',
                  color: theme.color('textOnTile'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (description.trim().isNotEmpty) ...[
                  const SizedBox(height: 3),
                  AppText(
                    description,
                    token: 'label',
                    color: theme.color('textOnTile').withOpacity(.68),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );

    if (onTap == null) return tile;
    return Semantics(
      button: true,
      label: description.isEmpty ? label : '$label، $description',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(theme.tileRadius),
          child: tile,
        ),
      ),
    );
  }
}

/// The green-and-gold glyph inside a [KzTile].
class IconTileGlyph extends StatelessWidget {
  const IconTileGlyph({super.key, required this.iconId, this.size});

  final String iconId;
  final double? size;

  @override
  Widget build(BuildContext context) => KhazainIcon(
        iconId,
        size: size ?? 28,
      );
}

class _DashedBorderPainter extends CustomPainter {
  _DashedBorderPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final rect = Offset.zero & size;
    final path = Path()..addRRect(RRect.fromRectAndRadius(
          rect.deflate(0.75),
          const Radius.circular(23),
        ));
    const dash = 6.0;
    const gap = 5.0;
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final next = (distance + dash).clamp(0.0, metric.length);
        canvas.drawPath(metric.extractPath(distance, next), paint);
        distance = next + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedBorderPainter oldDelegate) =>
      oldDelegate.color != color;
}
