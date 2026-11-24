import 'package:flutter/material.dart';

/// Keeps legacy section navigation stable while intentionally showing no
/// removed book, ziyara, dua, or article text.
class EmptyTextSectionScreen extends StatelessWidget {
  const EmptyTextSectionScreen({
    super.key,
    required this.title,
    this.message = 'أُفرغ محتوى هذا القسم. بقي القسم وزر التنقل كما هما.',
  });

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.all(18),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              Text(
                title,
                style: theme.textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 18),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      Icon(Icons.inbox_rounded,
                          size: 42, color: theme.colorScheme.secondary),
                      const SizedBox(height: 12),
                      Text(message,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(height: 1.7)),
                    ],
                  ),
                ),
              ),
            ]),
          ),
        ),
      ],
    );
  }
}
