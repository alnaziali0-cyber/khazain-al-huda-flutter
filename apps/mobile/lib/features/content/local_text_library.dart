import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../components/app_text.dart';
import '../../core/app_preferences.dart';
import '../../design/theme_provider.dart';
import '../fada/fada_store.dart';

/// Offline text catalogue. Every entry is loaded from a local UTF-8 TXT asset.
class LocalLibraryEntry {
  const LocalLibraryEntry({
    required this.id,
    required this.category,
    required this.title,
    required this.summary,
    required this.author,
    required this.sourceName,
    required this.licenseId,
    required this.contentKind,
    required this.content,
    required this.reviewNote,
  });

  final String id;
  final String category;
  final String title;
  final String summary;
  final String author;
  final String sourceName;
  final String licenseId;
  final String contentKind;
  final String content;
  final String reviewNote;

  bool get isSourcedExcerpt => contentKind == 'sourced_excerpt';
  bool get isStory => category == 'story';

  String get kindLabel => switch (contentKind) {
        'sourced_excerpt' => 'مقتطف من مصدر',
        'editorial_reference' => 'بطاقة مرجعية',
        _ => isStory ? 'قصة خيالية' : 'مادة تحريرية',
      };

  String get licenseLabel => switch (licenseId) {
        'CC-BY-SA-4.0' => 'CC BY-SA 4.0 · الإسناد والمشاركة بالمثل',
        'CC-BY-4.0' => 'CC BY 4.0 · الإسناد',
        _ => licenseId,
      };

  factory LocalLibraryEntry.fromJson(
    Map<String, dynamic> json,
    String content,
  ) {
    String value(String key) => json[key]?.toString() ?? '';
    return LocalLibraryEntry(
      id: value('id'),
      category: value('category'),
      title: value('title'),
      summary: value('summary'),
      author: value('author'),
      sourceName: value('source_name'),
      licenseId: value('license_id'),
      contentKind: value('content_kind'),
      content: content,
      reviewNote: value('review_note'),
    );
  }
}

class LocalLibraryRepository {
  LocalLibraryRepository._();

  static Future<List<LocalLibraryEntry>>? _cache;

  static Future<List<LocalLibraryEntry>> loadAll() {
    _cache ??= _load();
    return _cache!;
  }

  static Future<List<LocalLibraryEntry>> _load() async {
    final raw = await rootBundle.loadString(
      'assets/data/library/index.json',
    );
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic> || decoded['items'] is! List) {
      throw const FormatException('فهرس المكتبة المحلية غير صالح.');
    }

    final records = decoded['items'] as List;
    final entries = <LocalLibraryEntry>[];
    final identifiers = <String>{};
    for (final record in records) {
      if (record is! Map<String, dynamic>) continue;
      final id = record['id']?.toString() ?? '';
      final category = record['category']?.toString() ?? '';
      final contentFile = record['content_file']?.toString() ?? '';
      final license = record['license_id']?.toString() ?? '';
      if (id.isEmpty || !identifiers.add(id)) {
        throw FormatException('معرّف مادة مفقود أو مكرر: $id');
      }
      if (!const {'book', 'hadith', 'dua', 'visit', 'ethics', 'story'}
          .contains(category)) {
        throw FormatException('قسم غير مسموح للمادة: $category');
      }
      if (!const {'CC-BY-4.0', 'CC-BY-SA-4.0'}.contains(license)) {
        throw FormatException('ترخيص غير معروف للمادة: $id');
      }
      if (!contentFile.endsWith('.txt') ||
          !contentFile.startsWith(_folderFor(category)) ||
          contentFile.contains('..') || contentFile.startsWith('/')) {
        throw FormatException('مسار نص غير صالح للمادة: $id');
      }
      final body = await rootBundle.loadString(
        'assets/data/library/$contentFile',
      );
      if (body.trim().isEmpty) {
        throw FormatException('ملف نص فارغ: $id');
      }
      entries.add(LocalLibraryEntry.fromJson(record, body));
    }
    entries.sort((a, b) => a.title.compareTo(b.title));
    return List.unmodifiable(entries);
  }

  static String _folderFor(String category) => switch (category) {
        'book' => 'books/',
        'hadith' => 'hadith/',
        'dua' => 'duas/',
        'visit' => 'visits/',
        'ethics' => 'ethics/',
        'story' => 'stories/',
        _ => 'invalid/',
      };

  static Future<LocalLibraryEntry?> findById(String id) async {
    final entries = await loadAll();
    for (final entry in entries) {
      if (entry.id == id) return entry;
    }
    return null;
  }
}

class LocalTextLibraryScreen extends StatefulWidget {
  const LocalTextLibraryScreen({
    super.key,
    required this.category,
    required this.title,
    this.initialSearch,
  });

  final String category;
  final String title;
  final String? initialSearch;

  @override
  State<LocalTextLibraryScreen> createState() => _LocalTextLibraryScreenState();
}

class _LocalTextLibraryScreenState extends State<LocalTextLibraryScreen> {
  late final TextEditingController _searchController = TextEditingController(
    text: widget.initialSearch ?? '',
  );
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FutureBuilder<List<LocalLibraryEntry>>(
      future: LocalLibraryRepository.loadAll(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _LocalLibraryMessage(
            title: widget.title,
            message: 'تعذر قراءة ملفات المكتبة المحلية: ${snapshot.error}',
            icon: Icons.error_outline_rounded,
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final all = snapshot.data!
            .where((entry) => entry.category == widget.category)
            .toList(growable: false);
        final visible = all.where((entry) {
          if (_query.isEmpty) return true;
          final searchText =
              '${entry.title} ${entry.summary} ${entry.content}'.toLowerCase();
          return searchText.contains(_query);
        }).toList(growable: false);

        return CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  Text(
                    widget.title,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    'مكتبة نصية محفوظة داخل التطبيق، تعمل دون روابط أو ملفات PDF.',
                    style: theme.textTheme.bodyMedium?.copyWith(height: 1.55),
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
                        hintText: 'ابحث في العناوين والنصوص',
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
                      Icon(
                        Icons.offline_pin_outlined,
                        size: 18,
                        color: theme.colorScheme.secondary,
                      ),
                      const SizedBox(width: 7),
                      Text('المواد: ${visible.length} من ${all.length}'),
                      const Spacer(),
                      const Text('قراءة نصية'),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (visible.isEmpty)
                    _LocalLibraryMessage(
                      title: 'لا توجد نتائج',
                      message: _query.isEmpty
                          ? 'سيظهر المحتوى هنا عند إضافته إلى الفهرس المحلي.'
                          : 'لم نعثر على مادة تطابق عبارة البحث.',
                      icon: Icons.search_off_rounded,
                    ),
                  ...visible.map(
                    (entry) => Padding(
                      padding: const EdgeInsets.only(bottom: 9),
                      child: Card(
                        clipBehavior: Clip.antiAlias,
                        child: ListTile(
                          contentPadding: const EdgeInsetsDirectional.fromSTEB(
                            15,
                            9,
                            12,
                            9,
                          ),
                          leading: CircleAvatar(
                            backgroundColor:
                                theme.colorScheme.secondaryContainer,
                            child: Icon(
                              _iconFor(entry.category),
                              color: theme.colorScheme.onSecondaryContainer,
                            ),
                          ),
                          title: Text(
                            entry.title,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 5),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  entry.summary,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(height: 1.45),
                                ),
                                const SizedBox(height: 7),
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 4,
                                  children: [
                                    _Tag(text: entry.kindLabel),
                                    _Tag(text: entry.licenseId),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          trailing: const Icon(Icons.chevron_left_rounded),
                          onTap: () => context.push('/content/${entry.id}'),
                        ),
                      ),
                    ),
                  ),
                ]),
              ),
            ),
          ],
        );
      },
    );
  }

  static IconData _iconFor(String category) => switch (category) {
        'book' => Icons.menu_book_outlined,
        'hadith' => Icons.auto_stories_outlined,
        'dua' => Icons.volunteer_activism_outlined,
        'visit' => Icons.place_outlined,
        'ethics' => Icons.school_outlined,
        'story' => Icons.auto_stories_rounded,
        _ => Icons.article_outlined,
      };
}

class LocalTextReaderScreen extends ConsumerStatefulWidget {
  const LocalTextReaderScreen({super.key, required this.entryId});

  final String entryId;

  @override
  ConsumerState<LocalTextReaderScreen> createState() =>
      _LocalTextReaderScreenState();
}

class _LocalTextReaderScreenState extends ConsumerState<LocalTextReaderScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _recordHistory());
  }

  /// Keeps the entry in the "what is left" list so the user can continue it.
  void _recordHistory() {
    if (!mounted) return;
    final entry = LocalLibraryRepository.findById(widget.entryId);
    entry.then((value) {
      if (!mounted || value == null) return;
      ref.read(fadaStoreProvider.notifier).record(FadaItem(
            id: 'local:${value.id}',
            kind: value.category,
            title: value.title,
            subtitle: value.sourceName,
            route: '/content/${value.id}',
            category: _fadaCategoryFor(value.category),
            lastViewedMillis: DateTime.now().millisecondsSinceEpoch,
          ));
    }).catchError((_) {
      // The history is optional; a failure must not break the reader.
    });
  }

  static String _fadaCategoryFor(String category) => switch (category) {
        'quran' => 'quran',
        'dua' => 'duas',
        'visit' => 'visits',
        'hadith' => 'amal',
        _ => 'other',
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final uiTheme = ref.watch(uiThemeProvider);
    final showDiacritics = ref.watch(
      appPreferencesProvider.select((prefs) => prefs.showDiacritics),
    );
    return FutureBuilder<LocalLibraryEntry?>(
      future: LocalLibraryRepository.findById(widget.entryId),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _LocalLibraryMessage(
            title: 'تعذر فتح المادة',
            message: 'حدث خطأ أثناء قراءة الملف النصي المحلي.',
            icon: Icons.error_outline_rounded,
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final entry = snapshot.data;
        final content = entry == null
            ? ''
            : showDiacritics
                ? entry.content
                : CalligraphicText.stripDiacritics(entry.content);
        if (entry == null) {
          return _LocalLibraryMessage(
            title: 'المادة غير موجودة',
            message: 'قد يكون هذا رابطاً قديماً لمجلد لم يعد ضمن الحزمة. ارجع إلى فهرس القسم لاختيار مادة متاحة.',
            icon: Icons.find_in_page_outlined,
          );
        }

        return CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 30),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  Row(
                    children: [
                      IconButton(
                        tooltip: 'رجوع',
                        onPressed: () {
                          if (context.canPop()) {
                            context.pop();
                          } else {
                            context.go(_categoryRoute(entry.category));
                          }
                        },
                        icon: const Icon(Icons.arrow_forward_rounded),
                      ),
                      Expanded(
                        child: Text(
                          _categoryTitle(entry.category),
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    entry.title,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(entry.summary, style: const TextStyle(height: 1.6)),
                  const SizedBox(height: 12),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    value: showDiacritics,
                    onChanged: (value) => ref
                        .read(appPreferencesProvider.notifier)
                        .setShowDiacritics(value),
                    title: const Text('إظهار التشكيل'),
                    subtitle: const Text(
                        'يمكن إخفاء علامات الضبط دون تغيير حجم الخط'),
                  ),
                  const SizedBox(height: 8),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: SelectableText(
                        content,
                        textDirection: TextDirection.rtl,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          height: 2.0,
                          fontSize: 17 * uiTheme.calligraphicScale,
                          fontFamily: uiTheme.calligraphicFamily,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(15),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'المصدر وحقوق الاستخدام',
                            style: TextStyle(fontWeight: FontWeight.w900),
                          ),
                          const SizedBox(height: 8),
                          _MetadataRow(label: 'المؤلف/النسبة', value: entry.author),
                          _MetadataRow(label: 'المصدر', value: entry.sourceName),
                          _MetadataRow(label: 'الرخصة', value: entry.licenseLabel),
                          const SizedBox(height: 8),
                          Text(
                            entry.reviewNote,
                            style: theme.textTheme.bodySmall?.copyWith(
                              height: 1.6,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'تفاصيل الترخيص محفوظة في مجلد المكتبة داخل ملفات التطبيق.',
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ),
                ]),
              ),
            ),
          ],
        );
      },
    );
  }

  static String _categoryTitle(String category) => switch (category) {
        'book' => 'المكتبة الإسلامية',
        'hadith' => 'الروايات والأحاديث',
        'dua' => 'الأدعية والمناجاة',
        'visit' => 'الزيارات',
        'ethics' => 'الأخلاق والتربية',
        'story' => 'القصص التربوية',
        _ => 'المكتبة',
      };

  static String _categoryRoute(String category) => switch (category) {
        'book' => '/library',
        'hadith' => '/hadith',
        'dua' => '/duas',
        'visit' => '/visits',
        'ethics' => '/ethics',
        'story' => '/stories',
        _ => '/library',
      };
}

class _Tag extends StatelessWidget {
  const _Tag({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(text, style: theme.textTheme.labelSmall),
    );
  }
}

class _MetadataRow extends StatelessWidget {
  const _MetadataRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 5),
        child: Text('$label: $value', style: const TextStyle(height: 1.5)),
      );
}

class _LocalLibraryMessage extends StatelessWidget {
  const _LocalLibraryMessage({
    required this.title,
    required this.message,
    required this.icon,
  });

  final String title;
  final String message;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 38, color: theme.colorScheme.secondary),
                const SizedBox(height: 10),
                Text(title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
                const SizedBox(height: 8),
                Text(message, textAlign: TextAlign.center, style: const TextStyle(height: 1.65)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
