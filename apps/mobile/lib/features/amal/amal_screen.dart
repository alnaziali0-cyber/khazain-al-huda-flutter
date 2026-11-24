import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../components/app_card.dart';
import '../../components/app_text.dart';
import '../../components/state_view.dart';
import '../../design/theme_provider.dart';
import '../content/local_text_library.dart';

/// "الأعمال" — the deeds of the heart and the tongue.
///
/// The screen gathers the offline, editorial material that deals with
/// conduct, character and education, with the source and licence of every
/// entry shown underneath.
class AmalScreen extends ConsumerWidget {
  const AmalScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(uiThemeProvider);
    final entries = ref.watch(_amalProvider);

    return Container(
      color: theme.color('bgApp'),
      child: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
          children: [
            AppText('الأعمال', token: 'display'),
            const SizedBox(height: 4),
            AppText(
              'دروس أخلاقية وقصص تربوية وكتب محفوظة على الجهاز، '
              'كل مادة منها موثّقة برخصتها ومصدرها.',
              token: 'bodyDim',
              color: theme.color('textMuted'),
            ),
            const SizedBox(height: 16),
            entries.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (_, __) => StateView(
                icon: const Icon(Icons.cloud_off_rounded),
                message: 'تعذر تحميل المحتوى المحفوظ على الجهاز.',
                actionLabel: 'إعادة المحاولة',
                onAction: () => ref.invalidate(_amalProvider),
              ),
              data: (list) {
                if (list.isEmpty) {
                  return const StateView(
                    icon: Icon(Icons.handshake_rounded),
                    message: 'لا توجد مواد محفوظة بعد.',
                  );
                }
                return Column(
                  children: [
                    for (final entry in list)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _AmalCard(entry: entry),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _AmalCard extends ConsumerWidget {
  const _AmalCard({required this.entry});

  final LocalLibraryEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(uiThemeProvider);
    return KzSurface(
      level: 1,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      onTap: () => context.push('/content/${entry.id}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: AppText(
                  entry.title,
                  token: 'body',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: theme.color('gold').withOpacity(.18),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: AppText(
                  entry.kindLabel,
                  token: 'label',
                  color: theme.color('gold'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          AppText(
            entry.summary,
            token: 'bodyDim',
            color: theme.color('textMuted'),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 6),
          AppText(
            '${entry.sourceName} · ${entry.licenseLabel}',
            token: 'label',
            color: theme.color('textMuted'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

final _amalProvider = FutureProvider<List<LocalLibraryEntry>>((ref) async {
  final all = await LocalLibraryRepository.loadAll();
  return all
      .where((entry) =>
          entry.category == 'ethics' ||
          entry.category == 'story' ||
          entry.category == 'book')
      .toList(growable: false);
});
