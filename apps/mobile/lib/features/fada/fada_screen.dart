import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../components/app_card.dart';
import '../../components/app_text.dart';
import '../../components/chip_row.dart';
import '../../components/state_view.dart';
import '../../design/theme_provider.dart';
import 'fada_store.dart';

/// The leftovers screen (S4).
///
/// A horizontal chip row filters what the user opened but has not finished.
/// The row scrolls properly with an edge fade and no scrollbar, so the last
/// chip is never clipped (G8). With nothing to continue the screen shows a
/// real empty state (G9).
class FadaScreen extends ConsumerStatefulWidget {
  const FadaScreen({super.key});

  @override
  ConsumerState<FadaScreen> createState() => _FadaScreenState();
}

class _FadaScreenState extends ConsumerState<FadaScreen> {
  String _filter = 'all';

  static const List<({String id, String label})> _chips =
      <({String id, String label})>[
    (id: 'all', label: 'الكل'),
    (id: 'amal', label: 'الأعمال'),
    (id: 'quran', label: 'القرآن'),
    (id: 'duas', label: 'الأدعية'),
    (id: 'visits', label: 'الزيارات'),
    (id: 'other', label: 'الأخرى'),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(uiThemeProvider);
    final items = ref.watch(fadaStoreProvider);
    final pending = items.where((item) => !item.done).toList(growable: false);
    final visible = _filter == 'all'
        ? pending
        : pending.where((item) => item.category == _filter).toList(growable: false);

    return Container(
      color: theme.color('bgApp'),
      child: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
              child: Row(
                children: [
                  Expanded(child: AppText('متابعتي', token: 'display')),
                  if (pending.isNotEmpty)
                    AppText(
                      '${pending.length} عنصر للمتابعة',
                      token: 'bodyDim',
                      color: theme.color('textMuted'),
                    ),
                ],
              ),
            ),
            if (pending.isNotEmpty) ...[
              ChipRow(
                chips: _chips,
                selectedId: _filter,
                onSelected: (id) => setState(() => _filter = id),
              ),
              const SizedBox(height: 12),
            ],
            Expanded(
              child: visible.isEmpty
                  ? StateView(
                      icon: const Icon(Icons.bookmark_border_rounded),
                      message: pending.isEmpty
                          ? 'لا توجد عناصر للمتابعة بعد. افتح أي نص لتتابع قراءته من هنا.'
                          : 'لا توجد عناصر في هذا التصنيف.',
                      actionLabel: pending.isEmpty ? 'تصفّح الأقسام' : null,
                      onAction: pending.isEmpty
                          ? () => context.go('/sections')
                          : null,
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                      itemCount: visible.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, index) =>
                          _FadaRow(item: visible[index]),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FadaRow extends ConsumerWidget {
  const _FadaRow({required this.item});

  final FadaItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(uiThemeProvider);
    final icon = switch (item.category) {
      'quran' => Icons.menu_book_rounded,
      'duas' => Icons.volunteer_activism_rounded,
      'visits' => Icons.mosque_rounded,
      'amal' => Icons.handshake_rounded,
      _ => Icons.article_rounded,
    };
    return KzSurface(
      level: 1,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      onTap: () => context.push(item.route),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: theme.color('green').withOpacity(.22),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 19, color: theme.color('gold')),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppText(
                  item.title,
                  token: 'body',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                AppText(
                  item.subtitle,
                  token: 'bodyDim',
                  color: theme.color('textMuted'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'إنهاء',
            onPressed: () =>
                ref.read(fadaStoreProvider.notifier).markDone(item.id),
            icon: Icon(
              Icons.check_circle_outline_rounded,
              size: 20,
              color: theme.color('textMuted'),
            ),
          ),
        ],
      ),
    );
  }
}
