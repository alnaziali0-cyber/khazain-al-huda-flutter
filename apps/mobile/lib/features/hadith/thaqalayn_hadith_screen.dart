import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/providers.dart';
import '../../core/thaqalayn_repository.dart';

class ThaqalaynHadithScreen extends ConsumerStatefulWidget {
  const ThaqalaynHadithScreen({super.key});

  @override
  ConsumerState<ThaqalaynHadithScreen> createState() =>
      _ThaqalaynHadithScreenState();
}

class _ThaqalaynHadithScreenState
    extends ConsumerState<ThaqalaynHadithScreen> {
  late final ThaqalaynRepository _repository;
  final _searchController = TextEditingController();
  List<ThaqalaynBook> _books = const [];
  List<ThaqalaynHadith> _results = const [];
  String? _selectedBookId;
  String? _selectedBookName;
  ThaqalaynBook? _readingBook;
  int? _readingHadithId;
  String? _error;
  bool _loadingBooks = true;
  bool _loadingResults = false;
  bool _searched = false;
  bool _showingCachedResults = false;

  @override
  void initState() {
    super.initState();
    _repository = ThaqalaynRepository(
      preferences: ref.read(sharedPreferencesProvider),
    );
    _loadBooks();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String _friendlyServiceError(Object error, String fallback) {
    if (error is DioException && error.response?.statusCode == 429) {
      return 'وصلت الخدمة إلى حد الطلبات المؤقت. انتظر قليلاً ثم أعد المحاولة.';
    }
    if (error is DioException && error.response?.statusCode == 404) {
      return 'لم يُعثر على هذا السجل في فهرس المصدر.';
    }
    return fallback;
  }

  Future<void> _loadBooks() async {
    setState(() {
      _loadingBooks = true;
      _error = null;
    });
    try {
      final books = await _repository.fetchBooks();
      if (!mounted) return;
      setState(() {
        _books = books;
        _loadingBooks = false;
      });
    } catch (error) {
      if (!mounted) return;
      final cached = await _repository.readLastCachedHadiths();
      if (!mounted) return;
      setState(() {
        _loadingBooks = false;
        _error = _friendlyServiceError(
          error,
          'تعذر تحميل فهرس الكتب من خدمة الثقلين. تحقق من الاتصال ثم أعد المحاولة.',
        );
        if (_results.isEmpty && cached.isNotEmpty) _results = cached;
      });
    }
  }

  Future<void> _search() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) {
      _showMessage('اكتب كلمة أو عبارة للبحث في الروايات.');
      return;
    }
    setState(() {
      _loadingResults = true;
      _error = null;
      _searched = true;
      _results = const [];
      _readingBook = null;
      _readingHadithId = null;
      _showingCachedResults = false;
    });
    try {
      final results = await _repository.search(
        query: query,
        bookId: _selectedBookId,
      );
      if (!mounted) return;
      setState(() {
        _results = results;
        _loadingResults = false;
        _showingCachedResults = false;
      });
    } catch (error) {
      if (!mounted) return;
      final cached = await _repository.readLastCachedHadiths();
      if (!mounted) return;
      setState(() {
        _results = cached;
        _loadingResults = false;
        _showingCachedResults = cached.isNotEmpty;
        _error = _friendlyServiceError(
          error,
          'تعذر تنفيذ البحث حالياً. تحقق من اتصال الإنترنت ثم أعد المحاولة.',
        );
      });
    }
  }

  Future<void> _randomHadith() async {
    setState(() {
      _loadingResults = true;
      _error = null;
      _searched = true;
      _results = const [];
      _readingBook = null;
      _readingHadithId = null;
      _showingCachedResults = false;
    });
    try {
      final result = await _repository.random(bookId: _selectedBookId);
      if (!mounted) return;
      setState(() {
        _results = [result];
        _loadingResults = false;
        _showingCachedResults = false;
      });
    } catch (error) {
      if (!mounted) return;
      final cached = await _repository.readLastCachedHadiths();
      if (!mounted) return;
      setState(() {
        _results = cached;
        _loadingResults = false;
        _showingCachedResults = cached.isNotEmpty;
        _error = _friendlyServiceError(
          error,
          'تعذر جلب حديث عشوائي حالياً. حاول مرة أخرى عند توفر الإنترنت.',
        );
      });
    }
  }

  Future<void> _openBook(ThaqalaynBook book) async {
    setState(() {
      _selectedBookId = book.id;
      _selectedBookName = book.name;
      _readingBook = book;
      _readingHadithId = book.minimumId;
      _loadingResults = true;
      _searched = true;
      _results = const [];
      _error = null;
      _showingCachedResults = false;
    });
    try {
      final result = await _repository.fetchHadith(
        bookId: book.id,
        hadithId: book.minimumId,
      );
      if (!mounted) return;
      setState(() {
        _results = [result];
        _loadingResults = false;
        _showingCachedResults = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadingResults = false;
        _error = 'تعذر فتح بداية هذا الكتاب. يمكنك البحث داخله أو المحاولة لاحقاً.';
      });
    }
  }

  Future<void> _moveInBook(int offset) async {
    final book = _readingBook;
    final currentId = _readingHadithId;
    if (book == null || currentId == null) return;
    final nextId = currentId + offset;
    if (nextId < book.minimumId || nextId > book.maximumId) {
      _showMessage('وصلت إلى حدود فهرس هذا المجلد.');
      return;
    }
    setState(() {
      _loadingResults = true;
      _error = null;
    });
    try {
      final item = await _repository.fetchHadith(bookId: book.id, hadithId: nextId);
      if (!mounted) return;
      setState(() {
        _readingHadithId = nextId;
        _results = [item];
        _loadingResults = false;
        _showingCachedResults = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadingResults = false;
        _error = 'تعذر فتح الرواية التالية من هذا المجلد.';
      });
    }
  }

  void _clearBookFilter() {
    setState(() {
      _selectedBookId = null;
      _selectedBookName = null;
      _readingBook = null;
      _readingHadithId = null;
      _results = const [];
      _searched = false;
      _error = null;
      _showingCachedResults = false;
    });
  }

  Future<void> _openDocumentation() async {
    final uri = Uri.parse('https://www.thaqalayn-api.net/api-docs/');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _openHadithSource(ThaqalaynHadith item) async {
    final uri = item.sourceUri;
    if (uri == null) return;
    try {
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened && mounted) _showMessage('تعذر فتح صفحة الرواية الأصلية.');
    } catch (_) {
      if (mounted) _showMessage('تعذر فتح صفحة الرواية الأصلية.');
    }
  }

  Future<void> _copyHadith(ThaqalaynHadith item) async {
    final text = [
      item.arabicText,
      if (item.englishText.isNotEmpty) item.englishText,
      if (item.reference.isNotEmpty) 'المرجع: ${item.reference}',
      for (final entry in item.metadata) '${entry.key}: ${entry.value}',
      if (item.sourceUri != null) 'الرابط الأصلي: ${item.sourceUri}',
      'المصدر التقني: Thaqalayn API',
    ].where((part) => part.trim().isNotEmpty).join('\n\n');
    await Clipboard.setData(ClipboardData(text: text));
    _showMessage('تم نسخ الرواية وبياناتها المتاحة مع إسناد المصدر.');
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 34),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'الروايات والأحاديث',
                style: theme.textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w900),
              ),
            ),
            IconButton.filledTonal(
              tooltip: 'توثيق الخدمة',
              onPressed: _openDocumentation,
              icon: const Icon(Icons.open_in_new_rounded),
            ),
          ],
        ),
        const SizedBox(height: 5),
        Text(
          'بحث مباشر في كتب حديثية شيعية من خدمة الثقلين.',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 14),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _searchController,
                  textDirection: TextDirection.rtl,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _search(),
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: 'ابحث بكلمة عربية أو إنجليزية',
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: _searchController.text.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'مسح البحث',
                            onPressed: () {
                              _searchController.clear();
                              setState(() {
                                _results = const [];
                                _searched = false;
                              });
                            },
                            icon: const Icon(Icons.close_rounded),
                          ),
                  ),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String?>(
                  value: _selectedBookId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'تصفية حسب الكتاب',
                    prefixIcon: Icon(Icons.menu_book_rounded),
                  ),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('جميع الكتب'),
                    ),
                    ..._books.map((book) => DropdownMenuItem<String?>(
                          value: book.id,
                          child: Text(
                            '${book.name}${book.volume == null ? '' : ' – ${book.volume}'}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        )),
                  ],
                  onChanged: (value) {
                    final selected = _books.where((book) => book.id == value);
                    setState(() {
                      _selectedBookId = value;
                      _selectedBookName = selected.isEmpty
                          ? null
                          : selected.first.name;
                      _results = const [];
                      _readingBook = null;
                      _readingHadithId = null;
                      _searched = false;
                      _showingCachedResults = false;
                    });
                  },
                ),
                if (_selectedBookName != null) ...[
                  const SizedBox(height: 7),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: TextButton.icon(
                      onPressed: _clearBookFilter,
                      icon: const Icon(Icons.filter_alt_off_rounded, size: 17),
                      label: Text('إلغاء تصفية $_selectedBookName'),
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _loadingResults ? null : _search,
                        icon: const Icon(Icons.search_rounded),
                        label: const Text('بحث'),
                      ),
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _loadingResults ? null : _randomHadith,
                        icon: const Icon(Icons.shuffle_rounded),
                        label: const Text('حديث عشوائي'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          color: theme.colorScheme.secondaryContainer.withOpacity(.42),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline_rounded,
                    color: theme.colorScheme.primary),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    'تُعرض الرواية مع بيانات المصدر المتاحة لدى الخدمة. وجود النص في قاعدة البيانات لا يعني الحكم بصحته؛ لم يضف التطبيق تصحيحاً أو تضعيفاً من عنده.',
                    style: theme.textTheme.bodySmall?.copyWith(height: 1.5),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 10),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(13),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(_error!, style: theme.textTheme.bodyMedium),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () => _loadBooks(),
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('إعادة المحاولة'),
                  ),
                  TextButton.icon(
                    onPressed: () => context.push('/hadith/local'),
                    icon: const Icon(Icons.offline_pin_rounded),
                    label: const Text('فتح النصوص المحفوظة دون إنترنت'),
                  ),
                ],
              ),
            ),
          ),
        ],
        if (_loadingBooks || _loadingResults) ...[
          const SizedBox(height: 20),
          const Center(child: CircularProgressIndicator()),
          const SizedBox(height: 20),
        ],
        if (_showingCachedResults)
          const Padding(
            padding: EdgeInsets.only(top: 10),
            child: Text('تُعرض آخر روايات محفوظة من اتصال سابق؛ قد لا تطابق البحث الحالي.', style: TextStyle(fontSize: 12)),
          ),
        if (_results.isNotEmpty) ...[
          const SizedBox(height: 12),
          if (_readingBook != null && _readingHadithId != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: 'الرواية السابقة',
                      onPressed: _loadingResults ? null : () => _moveInBook(-1),
                      icon: const Icon(Icons.chevron_right_rounded),
                    ),
                    Expanded(
                      child: Text('قراءة ${_readingBook!.name} · ${_readingHadithId!} / ${_readingBook!.maximumId}', textAlign: TextAlign.center, style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800)),
                    ),
                    IconButton(
                      tooltip: 'الرواية التالية',
                      onPressed: _loadingResults ? null : () => _moveInBook(1),
                      icon: const Icon(Icons.chevron_left_rounded),
                    ),
                  ],
                ),
              ),
            ),
          Row(
            children: [
              Text('نتائج الروايات',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w900)),
              const Spacer(),
              Text('${_results.length} نتيجة',
                  style: theme.textTheme.bodySmall),
            ],
          ),
          const SizedBox(height: 8),
          for (final item in _results)
            _HadithResultCard(
              item: item,
              onCopy: () => _copyHadith(item),
              onOpenSource: item.sourceUri == null
                  ? null
                  : () => _openHadithSource(item),
            ),
        ] else if (_searched && !_loadingResults && _error == null) ...[
          const SizedBox(height: 18),
          const _EmptyHadithResult(),
        ] else if (!_loadingResults && _results.isEmpty) ...[
          const SizedBox(height: 18),
          Row(
            children: [
              Text('فهرس الكتب المتاحة',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w900)),
              const Spacer(),
              Text('${_books.length} كتاباً',
                  style: theme.textTheme.bodySmall),
            ],
          ),
          const SizedBox(height: 8),
          if (_books.isEmpty && !_loadingBooks)
            const _EmptyHadithResult(message: 'لا يتوفر فهرس الكتب حالياً.')
          else
            for (final book in _books)
              _BookTile(book: book, onTap: () => _openBook(book)),
        ],
        const SizedBox(height: 12),
        Center(
          child: TextButton.icon(
            onPressed: () => context.push('/hadith/local'),
            icon: const Icon(Icons.offline_pin_rounded),
            label: const Text('النصوص المحفوظة دون إنترنت'),
          ),
        ),
        Center(
          child: Text(
            'المصدر: Thaqalayn API · https://www.thaqalayn-api.net/',
            textAlign: TextAlign.center,
            style: theme.textTheme.labelSmall?.copyWith(color: theme.hintColor),
          ),
        ),
      ],
    );
  }
}

class _BookTile extends StatelessWidget {
  const _BookTile({required this.book, required this.onTap});
  final ThaqalaynBook book;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(
          backgroundColor: theme.colorScheme.primary.withOpacity(.1),
          child: Icon(Icons.menu_book_rounded,
              color: theme.colorScheme.primary),
        ),
        title: Text(book.name,
            style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Text(
          book.subtitle.isEmpty ? book.id : book.subtitle,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: const Icon(Icons.chevron_left_rounded),
      ),
    );
  }
}

class _HadithResultCard extends StatelessWidget {
  const _HadithResultCard({
    required this.item,
    required this.onCopy,
    this.onOpenSource,
  });
  final ThaqalaynHadith item;
  final VoidCallback onCopy;
  final VoidCallback? onOpenSource;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final arabic = item.arabicText;
    final english = item.englishText;
    final metadata = item.metadata;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.format_quote_rounded,
                    color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    item.reference.isEmpty
                        ? 'رواية من قاعدة الثقلين'
                        : item.reference,
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w900),
                  ),
                ),
                if (onOpenSource != null)
                  IconButton(
                    tooltip: 'فتح صفحة الرواية الأصلية',
                    onPressed: onOpenSource,
                    icon: const Icon(Icons.open_in_new_rounded),
                  ),
                IconButton(
                  tooltip: 'نسخ الرواية',
                  onPressed: onCopy,
                  icon: const Icon(Icons.copy_rounded),
                ),
              ],
            ),
            const Divider(height: 18),
            if (arabic.isNotEmpty)
              SelectableText(
                arabic,
                textDirection: TextDirection.rtl,
                textAlign: TextAlign.justify,
                style: theme.textTheme.titleMedium?.copyWith(
                  height: 2,
                  fontWeight: FontWeight.w600,
                ),
              )
            else
              Text(
                'لم تتعرّف الواجهة على حقل النص العربي في استجابة المصدر. يمكن مراجعة بيانات الاستجابة من مصدرها.',
                style: theme.textTheme.bodySmall,
              ),
            if (english.isNotEmpty) ...[
              const SizedBox(height: 12),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: EdgeInsets.zero,
                title: const Text('النص أو الترجمة الإضافية'),
                children: [
                  SelectableText(english,
                      textDirection: TextDirection.ltr,
                      style: theme.textTheme.bodyMedium?.copyWith(height: 1.6)),
                ],
              ),
            ],
            if (metadata.isNotEmpty)
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: const EdgeInsets.only(bottom: 6),
                title: Text('بيانات الرواية والسند والتقييمات (${metadata.length})'),
                children: [
                  for (final entry in metadata)
                    Padding(
                      padding: const EdgeInsets.only(top: 7),
                      child: SizedBox(
                        width: double.infinity,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(entry.key,
                                style: theme.textTheme.labelMedium?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  color: theme.colorScheme.primary,
                                )),
                            const SizedBox(height: 2),
                            SelectableText(
                              entry.value,
                              textDirection: TextDirection.rtl,
                              style: theme.textTheme.bodySmall?.copyWith(height: 1.55),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            if (onOpenSource != null)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  onPressed: onOpenSource,
                  icon: const Icon(Icons.link_rounded, size: 17),
                  label: const Text('صفحة الرواية في المصدر الأصلي'),
                ),
              ),
            const SizedBox(height: 5),
            Text(
              'المصدر التقني: Thaqalayn API',
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: theme.colorScheme.primary),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyHadithResult extends StatelessWidget {
  const _EmptyHadithResult({this.message = 'لم تظهر روايات تطابق هذا البحث.'});
  final String message;
  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            children: [
              Icon(Icons.search_off_rounded,
                  size: 34, color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 8),
              Text(message, textAlign: TextAlign.center),
            ],
          ),
        ),
      );
}
