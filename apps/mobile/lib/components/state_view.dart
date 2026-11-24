import 'package:flutter/material.dart';

import '../design/tokens/app_tokens.dart';
import 'app_text.dart';

/// The unified empty / error / offline state used across every screen (G9).
///
/// It always renders an icon, one line of copy and an optional action — never
/// a blank tile.
class StateView extends StatelessWidget {
  const StateView({
    super.key,
    required this.icon,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.tone = StateViewTone.neutral,
    this.compact = false,
  });

  /// Icon glyph drawn above the message.
  final Widget icon;

  /// A single line of copy.
  final String message;

  final String? actionLabel;
  final VoidCallback? onAction;

  final StateViewTone tone;

  /// Renders a smaller variant for use inside a card.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = switch (tone) {
      StateViewTone.error => theme.colorScheme.error,
      StateViewTone.success => KhazainColors.success,
      StateViewTone.neutral => theme.colorScheme.onSurface.withOpacity(.55),
    };
    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: 24,
          vertical: compact ? 16 : 28,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: compact ? 44 : 64,
              height: compact ? 44 : 64,
              child: IconTheme(
                data: IconThemeData(color: color, size: compact ? 34 : 52),
                child: icon,
              ),
            ),
            SizedBox(height: compact ? 10 : 14),
            AppText(
              message,
              token: compact ? 'bodyDim' : 'body',
              color: theme.colorScheme.onSurface.withOpacity(.78),
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            if (actionLabel != null && onAction != null) ...[
              SizedBox(height: compact ? 8 : 16),
              FilledButton.tonal(
                onPressed: onAction,
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 44),
                  padding: const EdgeInsets.symmetric(horizontal: 22),
                ),
                child: AppText(actionLabel!, token: 'label'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

enum StateViewTone { neutral, error, success }
