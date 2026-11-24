import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../components/app_sheet.dart';
import '../../components/app_text.dart';
import '../../components/khazain_icon.dart';
import '../../design/theme_provider.dart';
import '../../design/tokens/app_tokens.dart';
import '../content/local_text_library.dart';
import 'mukhalafat_store.dart';

/// The leftovers screen (S3).
///
/// The reference design showed five blank white tiles and one broken tile.
/// Every cell here is a real card: six adhkar categories, the offline
/// library entries and the entries the user adds with the floating action
/// button (G1, G2, G3).
class MukhalafatScreen extends ConsumerWidget {
  const MukhalafatScreen({super.key});

  /// The six adhkar categories required by G1.
  static const List<({String id, String title, String desc, String icon})>
      _adhkarCategories = <({String id, String title, String desc, String icon})>[
    (
      id: 'morning_evening',
      title: 'أذكار الصباح والمساء',
      desc: 'حصن اليوم والذكر مع مصدره',
      icon: 'adhkar',
    ),
    (
      id: 'after_salah',
      title: 'أذكار بعد الصلاة',
      desc: 'ما يُقال عقب كل فرض',
      icon: 'tasbih',
    ),
    (
      id: 'sleep',
      title: 'أذكار النوم',
      desc: 'الذكر قبل النوم',
      icon: 'ramadan',
    ),
    (
      id: 'istighfar',
      title: 'الاستغفار والتسبيح',
      desc: 'المسبحة والاستغفار',
      icon: 'misira',
    ),
    (
      id: 'hardship',
      title: 'دعاء الكرب',
      desc: 'الذكر عند الشدة',
      icon: 'khamat',
    ),
    (
      id: 'ruqya',
      title: 'الرقية الشرعية',
      desc: 'الذكر المشروع بالآيات',
      icon: 'quran',
    ),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(uiThemeProvider);
    final custom = ref.watch(mukhalafatStoreProvider);
    final library = ref.watch(_libraryProvider);

    return Scaffold(
      backgroundColor: theme.color('bgApp'),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openAddSheet(context, ref),
        backgroundColor: theme.color('green'),
        foregroundColor: theme.color('textPrimary'),
        icon: const Icon(Icons.add_rounded, size: 20),
        label: AppText('إضافة ذكر أو ورد', token: 'label'),
      ),
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              sliver: SliverToBoxAdapter(
                child: Row(
                  children: [
                    Expanded(
                      child: AppText('مساحتي', token: 'display'),
                    ),
                    AppText(
                      '${_adhkarCategories.length + custom.length + (library.valueOrNull?.length ?? 0)} عنصر',
                      token: 'bodyDim',
                      color: theme.color('textMuted'),
                    ),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _MukhalafatGrid(
                      adhkarCards: _adhkarCategories
                          .map((item) => _CardData(
                                title: item.title,
                                description: item.desc,
                                iconId: item.icon,
                                route: '/adhkar?category=${item.id}',
                              ))
                          .toList(growable: false),
                      customCards: custom
                          .map((entry) => _CardData(
                                title: entry.title,
                                description: entry.note.isEmpty
                                    ? 'عنصر أضفته إلى مساحتي'
                                    : entry.note,
                                iconId: 'mukhalafat',
                                route: '',
                                onDelete: () => ref
                                    .read(mukhalafatStoreProvider.notifier)
                                    .remove(entry.id),
                              ))
                          .toList(growable: false),
                      libraryCards: (library.valueOrNull ?? const [])
                          .map((entry) => _CardData(
                                title: entry.title,
                                description: entry.summary,
                                iconId: 'taqiyat',
                                route: '/content/${entry.id}',
                              ))
                          .toList(growable: false),
                    ),
                    const SizedBox(height: 10),
                    library.when(
                      loading: () => const Padding(
                        padding: EdgeInsets.symmetric(vertical: 18),
                        child: Center(child: CircularProgressIndicator()),
                      ),
                      error: (_, __) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: AppText(
                          'تعذر تحميل المواد المحفوظة على الجهاز. الأقسام الأساسية ما زالت متاحة.',
                          token: 'bodyDim',
                          color: theme.color('textMuted'),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      data: (_) => const SizedBox.shrink(),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openAddSheet(BuildContext context, WidgetRef ref) async {
    await KzSheet.show(
      context,
      title: 'إضافة ذكر أو ورد',
      builder: (sheetContext) => _AddPurposeSheet(
        onSave: (title, note) {
          ref
              .read(mukhalafatStoreProvider.notifier)
              .add(title: title, note: note);
        },
      ),
    );
  }
}

/// The form of the "add a purpose" sheet.
///
/// It owns its text controllers so they are disposed with the sheet instead
/// of while its closing animation is still running.
class _AddPurposeSheet extends StatefulWidget {
  const _AddPurposeSheet({required this.onSave});

  final void Function(String title, String note) onSave;

  @override
  State<_AddPurposeSheet> createState() => _AddPurposeSheetState();
}

class _AddPurposeSheetState extends State<_AddPurposeSheet> {
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _noteController = TextEditingController();

  @override
  void dispose() {
    _titleController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  void _save(BuildContext context) {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('اكتب عنواناً للمقصد.')),
      );
      return;
    }
    widget.onSave(title, _noteController.text);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _titleController,
          textInputAction: TextInputAction.next,
          decoration: const InputDecoration(
            labelText: 'العنوان',
            hintText: 'مثال: ورد الصبح',
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _noteController,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'ملاحظة',
            hintText: 'تفاصيل قصيرة',
          ),
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: () => _save(context),
          child: const Text('حفظ'),
        ),
      ],
    );
  }
}

class _CardData {
  const _CardData({
    required this.title,
    required this.description,
    required this.iconId,
    required this.route,
    this.onDelete,
  });

  final String title;
  final String description;
  final String iconId;
  final String route;
  final VoidCallback? onDelete;
}

class _MukhalafatGrid extends StatelessWidget {
  const _MukhalafatGrid({
    required this.adhkarCards,
    required this.customCards,
    required this.libraryCards,
  });

  final List<_CardData> adhkarCards;
  final List<_CardData> customCards;
  final List<_CardData> libraryCards;

  @override
  Widget build(BuildContext context) {
    final cards = <_CardData>[
      ...adhkarCards,
      ...customCards,
      ...libraryCards,
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        const columns = KhazainGrid.mukhalafatColumns;
        const gutter = KhazainGrid.mukhalafatGutter;
        const sidePadding = KhazainGrid.sidePadding;
        final tileWidth =
            (constraints.maxWidth - (sidePadding * 2) - (gutter * (columns - 1))) /
                columns;
        final tileHeight = tileWidth * KhazainGrid.mukhalafatTileAspect;
        return Wrap(
          spacing: gutter,
          runSpacing: gutter,
          children: [
            for (final card in cards)
              SizedBox(
                width: tileWidth,
                height: tileHeight,
                child: _MukhalafatCard(card: card),
              ),
          ],
        );
      },
    );
  }
}

class _MukhalafatCard extends ConsumerWidget {
  const _MukhalafatCard({required this.card});

  final _CardData card;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(uiThemeProvider);
    final tile = Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.color('tileBg'),
        borderRadius: BorderRadius.circular(theme.tileRadius),
        border: Border.all(color: theme.color('hairline')),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              KhazainIcon(card.iconId, size: 26),
              const Spacer(),
              if (card.onDelete != null)
                GestureDetector(
                  onTap: card.onDelete,
                  child: Icon(
                    Icons.close_rounded,
                    size: 18,
                    color: theme.color('textMuted'),
                  ),
                ),
            ],
          ),
          const Spacer(),
          AppText(
            card.title,
            token: 'body',
            color: theme.color('textOnTile'),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          AppText(
            card.description,
            token: 'bodyDim',
            color: theme.color('textMuted'),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );

    if (card.route.isEmpty) return tile;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => context.push(card.route),
        borderRadius: BorderRadius.circular(theme.tileRadius),
        child: tile,
      ),
    );
  }
}

/// The offline library entries surfaced in the leftovers grid.
final _libraryProvider = FutureProvider<List<LocalLibraryEntry>>((ref) async {
  final all = await LocalLibraryRepository.loadAll();
  final duas = all.where((entry) => entry.category == 'dua').toList();
  final visits = all.where((entry) => entry.category == 'visit').toList();
  return <LocalLibraryEntry>[...duas, ...visits];
});
