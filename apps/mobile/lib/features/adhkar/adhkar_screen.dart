import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../components/app_card.dart';
import '../../components/app_sheet.dart';
import '../../components/app_text.dart';
import '../../components/khazain_icon.dart';
import '../../components/state_view.dart';
import '../../design/theme_provider.dart';
import '../content/local_text_library.dart';

/// The adhkar index.
///
/// The app never paraphrases a religious text: the screen groups the
/// offline, sourced material that matches each adhkar category and links to
/// the verified collections. Every entry keeps its source and licence.
class AdhkarScreen extends ConsumerWidget {
  const AdhkarScreen({super.key, this.category});

  /// Optional deep-link category (G1).
  final String? category;

  static const List<({String id, String title, String desc, String icon})>
      _categories = <({String id, String title, String desc, String icon})>[
    (
      id: 'morning_evening',
      title: 'أذكار الصباح والمساء',
      desc: 'ما يُذكر به طرف النهار وطرف الليل',
      icon: 'adhkar',
    ),
    (
      id: 'after_salah',
      title: 'أذكار بعد الصلاة',
      desc: 'ما يُقال عقب كل صلاة مفروضة',
      icon: 'tasbih',
    ),
    (
      id: 'sleep',
      title: 'أذكار النوم',
      desc: 'ما يُذكر عند إرادة النوم',
      icon: 'ramadan',
    ),
    (
      id: 'istighfar',
      title: 'الاستغفار والتسبيح',
      desc: 'المسبحة والاستغفار وأذكار الاستفتاح',
      icon: 'misira',
    ),
    (
      id: 'hardship',
      title: 'دعاء الكرب',
      desc: 'ما يُذكر عند الشدة والهم',
      icon: 'khamat',
    ),
    (
      id: 'ruqya',
      title: 'الرقية الشرعية',
      desc: 'الذكر المشروع بالآيات والسنن',
      icon: 'quran',
    ),
  ];

  static const Map<String, List<String>> _keywords = <String, List<String>>{
    'morning_evening': <String>['صباح', 'مساء', 'ذكر'],
    'after_salah': <String>['الصلاة', 'صلاة', 'أذكار'],
    'sleep': <String>['نوم', 'ليل'],
    'istighfar': <String>['استغفار', 'تسبيح', 'تسبيح'],
    'hardship': <String>['كرب', 'هم', 'غم'],
    'ruqya': <String>['رقية', 'قرآن', 'ذِكر'],
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(uiThemeProvider);
    final entries = ref.watch(_libraryProvider);
    final selected = category;

    return Container(
      color: theme.color('bgApp'),
      child: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
          children: [
            AppText('الأذكار', token: 'display'),
            const SizedBox(height: 4),
            AppText(
              'المحتوى هنا من النصوص المحفوظة على الجهاز مع ذكر المصدر والرخصة، '
              'ولا يُعاد صياغة الأذكار ولا يُنقل نصّها دون توثيق.',
              token: 'bodyDim',
              color: theme.color('textMuted'),
            ),
            const SizedBox(height: 16),
            for (final item in _categories)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _CategoryCard(
                  id: item.id,
                  title: item.title,
                  description: item.desc,
                  iconId: item.icon,
                  highlighted: selected == item.id,
                  onTap: () => _openCategory(context, ref, item),
                ),
              ),
            const SizedBox(height: 12),
            AppText('الأدعية المحفوظة على الجهاز', token: 'h2'),
            const SizedBox(height: 10),
            entries.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (_, __) => StateView(
                icon: const Icon(Icons.cloud_off_rounded),
                message: 'تعذر تحميل المحتوى المحفوظ.',
                actionLabel: 'إعادة المحاولة',
                onAction: () => ref.invalidate(_libraryProvider),
              ),
              data: (list) {
                if (list.isEmpty) {
                  return const StateView(
                    icon: Icon(Icons.menu_book_rounded),
                    message: 'لا توجد نصوص محفوظة على الجهاز بعد.',
                  );
                }
                return Column(
                  children: [
                    for (final entry in list)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _EntryRow(entry: entry),
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

  Future<void> _openCategory(
    BuildContext context,
    WidgetRef ref,
    ({String id, String title, String desc, String icon}) item,
  ) async {
    final entries = await ref.read(_libraryProvider.future);
    final keywords = _keywords[item.id] ?? const <String>[];
    final matching = entries.where((entry) {
      final haystack =
          '${entry.title} ${entry.summary} ${entry.content}'.toLowerCase();
      return keywords.any((keyword) => haystack.contains(keyword.toLowerCase()));
    }).toList(growable: false);

    if (!context.mounted) return;
    await KzSheet.show(
      context,
      title: item.title,
      builder: (sheetContext) => matching.isEmpty
          ? StateView(
              icon: const Icon(Icons.menu_book_rounded),
              message: 'لا يوجد نص محفوظ لهذا التصنيف بعد.',
              actionLabel: 'فتح الأدعية الموثقة',
              onAction: () {
                Navigator.of(sheetContext).pop();
                context.push('/duas');
              },
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final entry in matching)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _EntryRow(entry: entry),
                  ),
              ],
            ),
    );
  }
}

class _CategoryCard extends ConsumerWidget {
  const _CategoryCard({
    required this.id,
    required this.title,
    required this.description,
    required this.iconId,
    required this.highlighted,
    required this.onTap,
  });

  final String id;
  final String title;
  final String description;
  final String iconId;
  final bool highlighted;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(uiThemeProvider);
    return KzSurface(
      level: 1,
      color: highlighted
          ? theme.color('green').withOpacity(.35)
          : theme.color('surface1'),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      onTap: onTap,
      child: Row(
        children: [
          KhazainIcon(iconId, size: 26),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppText(title, token: 'body', maxLines: 1),
                const SizedBox(height: 2),
                AppText(
                  description,
                  token: 'bodyDim',
                  color: theme.color('textMuted'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_left_rounded, color: theme.color('textMuted')),
        ],
      ),
    );
  }
}

class _EntryRow extends ConsumerWidget {
  const _EntryRow({required this.entry});

  final LocalLibraryEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(uiThemeProvider);
    return KzSurface(
      level: 1,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      onTap: () => context.push('/content/${entry.id}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppText(entry.title, token: 'body', maxLines: 1),
          const SizedBox(height: 3),
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
            color: theme.color('gold'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

final _libraryProvider = FutureProvider<List<LocalLibraryEntry>>((ref) async {
  final all = await LocalLibraryRepository.loadAll();
  return all.where((entry) => entry.category == 'dua').toList(growable: false);
});
