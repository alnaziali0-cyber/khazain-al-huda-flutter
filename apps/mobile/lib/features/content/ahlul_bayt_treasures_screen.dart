import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../core/ahlul_bayt_treasures_repository.dart';

enum AhlulBaytTreasuresSection { duas, visits }

class AhlulBaytTreasuresScreen extends StatefulWidget {
  const AhlulBaytTreasuresScreen({
    super.key,
    required this.section,
    this.initialSearch,
    this.repository,
  });

  final AhlulBaytTreasuresSection section;
  final String? initialSearch;
  final AhlulBaytTreasuresRepository? repository;

  @override
  State<AhlulBaytTreasuresScreen> createState() =>
      _AhlulBaytTreasuresScreenState();
}

class _AhlulBaytTreasuresScreenState
    extends State<AhlulBaytTreasuresScreen> {
  late final AhlulBaytTreasuresRepository _repository =
      widget.repository ?? AhlulBaytTreasuresRepository();
  late final TextEditingController _searchController =
      TextEditingController(text: widget.initialSearch ?? '');
  late Future<List<AhlulBaytTreasuresIndexEntry>> _indexFuture =
      _repository.loadIndex();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _query = widget.initialSearch?.trim().toLowerCase() ?? '';
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String get _title => widget.section == AhlulBaytTreasuresSection.duas
      ? 'موسوعة الأدعية والمناجاة'
      : 'موسوعة الزيارات';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FutureBuilder<List<AhlulBaytTreasuresIndexEntry>>(
      future: _indexFuture,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _TreasuresStatus(
            title: _title,
            message:
                'تعذر تحميل الفهرس حالياً. تحقق من اتصال الإنترنت ثم أعد المحاولة، أو افتح المواد المحلية المحفوظة في التطبيق.',
            localLocation: widget.section == AhlulBaytTreasuresSection.duas
                ? '/duas/local'
                : '/visits/local',
            onRetry: () => setState(
              () => _indexFuture = _repository.loadIndex(refresh: true),
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final all = snapshot.data!
            .where((entry) => entry.isZiyara ==
                (widget.section == AhlulBaytTreasuresSection.visits))
            .toList(growable: false);
        final visible = all.where((entry) {
          if (_query.isEmpty) return true;
          final arabic = _arabicTitles[entry.name] ?? '';
          return '${entry.name} $arabic'.toLowerCase().contains(_query);
        }).toList(growable: false);

        return CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  Text(
                    _title,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'مجموعة نصوص من مشروع Ahlul Bayt Treasures. يُحمّل النص الكامل عند فتحه ويُحفظ على الجهاز للقراءة لاحقاً دون اتصال.',
                    style: theme.textTheme.bodyMedium?.copyWith(height: 1.65),
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _SectionChip(
                        label: 'الأدعية',
                        selected: widget.section ==
                            AhlulBaytTreasuresSection.duas,
                        onTap: () => context.go('/duas'),
                      ),
                      _SectionChip(
                        label: 'الزيارات',
                        selected: widget.section ==
                            AhlulBaytTreasuresSection.visits,
                        onTap: () => context.go('/visits'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: TextField(
                      controller: _searchController,
                      onChanged: (value) => setState(
                        () => _query = value.trim().toLowerCase(),
                      ),
                      textInputAction: TextInputAction.search,
                      decoration: InputDecoration(
                        border: InputBorder.none,
                        hintText: 'ابحث باسم الدعاء أو الزيارة',
                        prefixIcon: const Icon(Icons.search_rounded),
                        suffixIcon: _query.isEmpty
                            ? null
                            : IconButton(
                                tooltip: 'مسح البحث',
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() => _query = '');
                                },
                                icon: const Icon(Icons.close_rounded),
                              ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Icon(Icons.library_books_outlined,
                          size: 18, color: theme.colorScheme.secondary),
                      const SizedBox(width: 7),
                      Text('المواد: ${visible.length} من ${all.length}'),
                      const Spacer(),
                      const Text('المصدر: 1.0.1'),
                    ],
                  ),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: TextButton.icon(
                      onPressed: () => context.go(
                        widget.section == AhlulBaytTreasuresSection.duas
                            ? '/duas/local'
                            : '/visits/local',
                      ),
                      icon: const Icon(Icons.offline_pin_outlined),
                      label: const Text('المواد المحلية المحفوظة في خزائن الهدى'),
                    ),
                  ),
                  const SizedBox(height: 10),
                ]),
              ),
            ),
            if (visible.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      _query.isEmpty
                          ? 'لا توجد مواد في هذا القسم ضمن الفهرس.'
                          : 'لم نعثر على نتيجة مطابقة.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 28),
                sliver: SliverList.builder(
                  itemCount: visible.length,
                  itemBuilder: (context, index) {
                    final entry = visible[index];
                    final arabicTitle = _arabicTitles[entry.name];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      clipBehavior: Clip.antiAlias,
                      child: ListTile(
                        contentPadding: const EdgeInsetsDirectional.fromSTEB(
                          15, 7, 13, 7,
                        ),
                        leading: CircleAvatar(
                          backgroundColor: theme.colorScheme.secondaryContainer,
                          child: Text(
                            '${entry.id}',
                            style: TextStyle(
                              color: theme.colorScheme.onSecondaryContainer,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        title: Text(
                          arabicTitle ?? entry.name,
                          textDirection: arabicTitle == null
                              ? TextDirection.ltr
                              : TextDirection.rtl,
                          textAlign: arabicTitle == null
                              ? TextAlign.left
                              : TextAlign.right,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        subtitle: Text(
                          arabicTitle == null
                              ? 'العنوان كما ورد في فهرس المصدر'
                              : entry.name,
                          textDirection: TextDirection.ltr,
                          textAlign: TextAlign.start,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: const Icon(Icons.chevron_left_rounded),
                        onTap: () => context.push(
                          widget.section == AhlulBaytTreasuresSection.visits
                              ? '/visits/treasures/${entry.id}'
                              : '/duas/${entry.id}',
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        );
      },
    );
  }
}

class AhlulBaytTreasuresReaderScreen extends StatefulWidget {
  const AhlulBaytTreasuresReaderScreen({
    super.key,
    required this.textId,
    this.repository,
  });

  final int textId;
  final AhlulBaytTreasuresRepository? repository;

  @override
  State<AhlulBaytTreasuresReaderScreen> createState() =>
      _AhlulBaytTreasuresReaderScreenState();
}

class _AhlulBaytTreasuresReaderScreenState
    extends State<AhlulBaytTreasuresReaderScreen> {
  late final AhlulBaytTreasuresRepository _repository =
      widget.repository ?? AhlulBaytTreasuresRepository();
  late Future<AhlulBaytTreasuresText> _textFuture =
      _repository.fetchText(widget.textId);

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AhlulBaytTreasuresText>(
      future: _textFuture,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _TreasuresStatus(
            title: 'تعذر فتح النص',
            message:
                'لم نتمكن من تحميل النص المطلوب. تحقق من اتصال الإنترنت أو أعد المحاولة. النصوص التي سبق تنزيلها تبقى محفوظة على الجهاز.',
            onRetry: () => setState(
              () => _textFuture = _repository.fetchText(
                widget.textId,
                refresh: true,
              ),
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final dua = snapshot.data!;
        final title = _arabicTitles[dua.name] ?? dua.name;
        final allArabic = dua.rows
            .where((row) => row.instruction.trim().isEmpty)
            .map((row) => row.arabic.trim())
            .where((text) => text.isNotEmpty)
            .join('\n');

        return CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          textDirection: _arabicTitles.containsKey(dua.name)
                              ? TextDirection.rtl
                              : TextDirection.ltr,
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w900),
                        ),
                      ),
                      IconButton(
                        tooltip: 'نسخ النص العربي',
                        onPressed: allArabic.isEmpty
                            ? null
                            : () async {
                                await Clipboard.setData(
                                  ClipboardData(text: allArabic),
                                );
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('تم نسخ النص العربي.'),
                                    ),
                                  );
                                }
                              },
                        icon: const Icon(Icons.copy_all_outlined),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'رقم المادة: ${dua.id} · Ahlul Bayt Treasures ${AhlulBaytTreasuresRepository.version}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 14),
                  const Divider(),
                ]),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsetsDirectional.fromSTEB(18, 0, 18, 12),
              sliver: SliverList.builder(
                itemCount: dua.rows.length,
                itemBuilder: (context, index) => _DuaRowCard(
                  row: dua.rows[index],
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(18, 4, 18, 30),
              sliver: SliverToBoxAdapter(
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(15),
                    child: Text(
                      'النص معروض وفق ملف البيانات كما هو. إدراجه لا يعني إصدار حكم على صحة النسبة أو السند، ولا يغني عن مراجعة المصدر والنسخة المعتمدة.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            height: 1.7,
                          ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _DuaRowCard extends StatelessWidget {
  const _DuaRowCard({required this.row});

  final AhlulBaytTreasuresTextRow row;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasArabic = row.arabic.trim().isNotEmpty;
    final hasTranslation = row.translation.trim().isNotEmpty;
    final hasTransliteration = row.transliteration.trim().isNotEmpty;
    final hasInstruction = row.instruction.trim().isNotEmpty;
    final hasTitle = row.title.trim().isNotEmpty;

    if (!hasArabic && !hasTranslation && !hasTransliteration &&
        !hasInstruction && !hasTitle) {
      return const SizedBox.shrink();
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (hasTitle || row.showId.trim().isNotEmpty)
              Row(
                children: [
                  if (hasTitle)
                    Expanded(
                      child: Text(
                        row.title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  if (row.showId.trim().isNotEmpty)
                    Chip(
                      label: Text(row.showId),
                      visualDensity: VisualDensity.compact,
                    ),
                ],
              ),
            if (hasInstruction) ...[
              if (hasTitle || row.showId.trim().isNotEmpty)
                const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 9,
                ),
                decoration: BoxDecoration(
                  color: theme.colorScheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  row.instruction,
                  textDirection: TextDirection.ltr,
                  style: TextStyle(
                    color: theme.colorScheme.onSecondaryContainer,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
            if (hasArabic) ...[
              if (hasTitle || hasInstruction || row.showId.isNotEmpty)
                const SizedBox(height: 12),
              SelectableText(
                row.arabic,
                textDirection: TextDirection.rtl,
                textAlign: TextAlign.justify,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontFamily: 'NotoNaskhArabicUI',
                  height: 2.0,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
            if (hasTranslation) ...[
              const SizedBox(height: 14),
              Text('الترجمة',
                  style: theme.textTheme.labelLarge
                      ?.copyWith(fontWeight: FontWeight.w900)),
              const SizedBox(height: 5),
              SelectableText(
                row.translation,
                textDirection: TextDirection.ltr,
                style: theme.textTheme.bodyMedium?.copyWith(height: 1.7),
              ),
            ],
            if (hasTransliteration) ...[
              const SizedBox(height: 10),
              Text('النقل الصوتي',
                  style: theme.textTheme.labelLarge
                      ?.copyWith(fontWeight: FontWeight.w900)),
              const SizedBox(height: 4),
              SelectableText(
                row.transliteration,
                textDirection: TextDirection.ltr,
                style: theme.textTheme.bodySmall?.copyWith(height: 1.6),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SectionChip extends StatelessWidget {
  const _SectionChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
    );
  }
}

class _TreasuresStatus extends StatelessWidget {
  const _TreasuresStatus({
    required this.title,
    required this.message,
    required this.onRetry,
    this.localLocation,
  });

  final String title;
  final String message;
  final VoidCallback onRetry;
  final String? localLocation;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.cloud_download_outlined,
                    size: 38, color: theme.colorScheme.secondary),
                const SizedBox(height: 12),
                Text(title,
                    style: theme.textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w900)),
                const SizedBox(height: 9),
                Text(message,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(height: 1.6)),
                const SizedBox(height: 15),
                FilledButton.tonalIcon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('إعادة المحاولة'),
                ),
                if (localLocation != null) ...[
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: () => context.go(localLocation!),
                    icon: const Icon(Icons.offline_pin_outlined),
                    label: const Text('فتح المحتوى المحلي'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

const Map<String, String> _arabicTitles = {
  'Dua Kumayl': 'دعاء كميل',
  'Dua Tawassul': 'دعاء التوسل',
  'Dua Ahad': 'دعاء العهد',
  'Dua Sabah': 'دعاء الصباح',
  'Dua Simaat': 'دعاء السمات',
  'Dua Nudba': 'دعاء الندبة',
  'Ziarat Waritha': 'زيارة وارث',
  'Hadith e Kisa': 'حديث الكساء',
  'Dua Faraj': 'دعاء الفرج',
  'Dua Mashlool': 'دعاء المشلول',
  'Dua Adeelah': 'دعاء العديلة',
  'Dua Yastashir': 'دعاء يستشير',
  'Ziarat Jamia Kabeera': 'الزيارة الجامعة الكبيرة',
  'Ziarat Ale Yasin': 'زيارة آل ياسين',
  'Ziarat Ashura': 'زيارة عاشوراء',
  'Ziarat Jamia Sagheera': 'الزيارة الجامعة الصغيرة',
  'Dua Mujeer': 'دعاء المجير',
  'Dua Sahar': 'دعاء السحر',
  'Dua Makarimul Akhlaq': 'دعاء مكارم الأخلاق',
  'Dua Abu Hamza Thumali': 'دعاء أبي حمزة الثمالي',
  'Dua Jawshan Kabeer': 'دعاء الجوشن الكبير',
  'Ziarat Arbaeen': 'زيارة الأربعين',
  'Ziarat Ameenullah': 'زيارة أمين الله',
  'Dua Arafah - Imam Hussain': 'دعاء عرفة للإمام الحسين',
  'Dua Alqama': 'دعاء علقمة',
  'Salawaat': 'الصلوات',
  'Munajat Shabaniya': 'المناجاة الشعبانية',
  'Dua Umm Dawood': 'دعاء أم داود',
  'Ziarat Nahiya': 'زيارة الناحية المقدسة',
  'Ziarat Taziya': 'زيارة التعزية',
};
