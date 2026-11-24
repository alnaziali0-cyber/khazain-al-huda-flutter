import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/library_assistant_repository.dart';

class ImportedBookReaderScreen extends ConsumerStatefulWidget {
  const ImportedBookReaderScreen({super.key, required this.bookId});
  final int bookId;

  @override
  ConsumerState<ImportedBookReaderScreen> createState() => _ImportedBookReaderScreenState();
}

class _ImportedBookReaderScreenState extends ConsumerState<ImportedBookReaderScreen> {
  final List<Map<String, dynamic>> _pages = [];
  final List<Map<String, dynamic>> _toc = [];
  final ItemScrollController _itemScrollController = ItemScrollController();
  final ItemPositionsListener _itemPositionsListener = ItemPositionsListener.create();
  int _total = 0;
  int _offset = 0;
  bool _loading = true;
  bool _loadingMore = false;
  String _title = 'قراءة الكتاب';
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadBookAndPages();
  }

  Future<void> _loadBookAndPages() async {
    try {
      final repository = ref.read(libraryAssistantRepositoryProvider);
      final books = await repository.books();
      final matches = books.where((item) => item['id'] == widget.bookId);
      final book = matches.isEmpty ? null : matches.first;
      if (book == null) throw StateError('Book not found for this device.');
      final pageRows = await repository.bookPages(widget.bookId, limit: 60);
      final tocRows = await repository.bookToc(widget.bookId);
      if (!mounted) return;
      setState(() {
        _title = (book['title'] ?? _title).toString();
        _total = (book['page_count'] is int) ? book['page_count'] as int : pageRows.length;
        _pages.addAll(pageRows);
        _toc.addAll(tocRows);
        _offset = pageRows.length;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() { _loading = false; _error = 'تعذر تحميل الكتاب. تأكد من أن النسخة تخص هذا الجهاز.'; });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || _offset >= _total) return;
    setState(() => _loadingMore = true);
    try {
      final rows = await ref.read(libraryAssistantRepositoryProvider).bookPages(widget.bookId, limit: 60, offset: _offset);
      if (!mounted) return;
      setState(() {
        _pages.addAll(rows);
        _offset += rows.length;
        _loadingMore = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _showTableOfContents() async {
    if (_toc.isEmpty) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('لا يتضمن التصدير فهرس محتويات منظماً.')));
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(sheetContext).height * .7,
          child: Column(
            children: [
              const Padding(padding: EdgeInsets.all(16), child: Text('فهرس الكتاب', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18))),
              Expanded(
                child: ListView.builder(
                  itemCount: _toc.length,
                  itemBuilder: (context, index) {
                    final entry = _toc[index];
                    final pageNumber = entry['page_number'] is int ? entry['page_number'] as int : null;
                    return ListTile(
                      title: Text((entry['title'] ?? '').toString()),
                      subtitle: pageNumber == null ? null : Text('الصفحة $pageNumber'),
                      onTap: pageNumber == null ? null : () {
                        Navigator.pop(sheetContext);
                        _jumpToPage(pageNumber);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showBookSearch() async {
    final controller = TextEditingController();
    final query = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('البحث داخل الكتاب'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textDirection: TextDirection.rtl,
          decoration: const InputDecoration(hintText: 'اكتب كلمة أو عبارة'),
          onSubmitted: (value) => Navigator.pop(dialogContext, value.trim()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, controller.text.trim()), child: const Text('بحث')),
        ],
      ),
    );
    controller.dispose();
    if (query == null || query.trim().length < 2 || !mounted) return;
    try {
      final results = await ref.read(libraryAssistantRepositoryProvider).searchBook(widget.bookId, query.trim());
      if (!mounted) return;
      if (results.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('لم يُعثر على العبارة داخل النص المفهرس.')));
        return;
      }
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (sheetContext) => SafeArea(
          child: SizedBox(
            height: MediaQuery.sizeOf(sheetContext).height * .65,
            child: Column(
              children: [
                Padding(padding: const EdgeInsets.all(16), child: Text('نتائج البحث: ${results.length}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17))),
                Expanded(
                  child: ListView.builder(
                    itemCount: results.length,
                    itemBuilder: (context, index) {
                      final result = results[index];
                      final page = result['page_number'] is int ? result['page_number'] as int : 1;
                      return ListTile(
                        title: Text('الصفحة $page'),
                        subtitle: Text((result['snippet'] ?? '').toString(), maxLines: 3, overflow: TextOverflow.ellipsis),
                        onTap: () {
                          Navigator.pop(sheetContext);
                          _jumpToPage(page);
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تعذر البحث داخل الكتاب.')));
    }
  }

  Future<void> _jumpToPage(int pageNumber) async {
    if (pageNumber < 1) return;
    while (_offset < _total && (_pages.isEmpty || ((_pages.last['page_number'] as int?) ?? 0) < pageNumber)) {
      final before = _offset;
      try {
        final rows = await ref.read(libraryAssistantRepositoryProvider).bookPages(widget.bookId, limit: 60, offset: _offset);
        if (!mounted || rows.isEmpty) break;
        setState(() {
          _pages.addAll(rows);
            _offset += rows.length;
        });
      } catch (_) {
        break;
      }
      if (_offset == before) break;
    }
    if (!mounted) return;
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    final index = _pages.indexWhere((page) => page['page_number'] == pageNumber);
    if (index < 0 || !_itemScrollController.isAttached) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('لم يتم تحميل هذه الصفحة بعد.')));
      return;
    }
    await _itemScrollController.scrollTo(
      index: index,
      alignment: .08,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOut,
    );
  }

  Future<void> _copyBookText() async {
    try {
      final exported = await ref.read(libraryAssistantRepositoryProvider).exportBook(widget.bookId, format: 'txt');
      final content = exported['content'];
      if (content is String) {
        await Clipboard.setData(ClipboardData(text: content));
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('نُسخ النص إلى الحافظة.')));
      }
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تعذر تصدير نص الكتاب.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(tooltip: 'البحث داخل الكتاب', onPressed: _showBookSearch, icon: const Icon(Icons.search_rounded)),
          IconButton(tooltip: 'فهرس الكتاب', onPressed: _showTableOfContents, icon: const Icon(Icons.toc_rounded)),
          IconButton(tooltip: 'نسخ نص الكتاب', onPressed: _copyBookText, icon: const Icon(Icons.copy_all_rounded)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : ScrollablePositionedList.separated(
                  itemScrollController: _itemScrollController,
                  itemPositionsListener: _itemPositionsListener,
                  padding: const EdgeInsets.all(18),
                  itemCount: _pages.length + (_offset < _total ? 1 : 0),
                  separatorBuilder: (_, __) => const Divider(height: 32),
                  itemBuilder: (context, index) {
                    if (index == _pages.length) {
                      return Center(
                        child: TextButton.icon(
                          onPressed: _loadingMore ? null : _loadMore,
                          icon: _loadingMore ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.expand_more_rounded),
                          label: Text(_loadingMore ? 'جارٍ تحميل الصفحات' : 'تحميل المزيد (${_pages.length} من $_total)'),
                        ),
                      );
                    }
                    final page = _pages[index];
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text('الصفحة ${page['page_number'] ?? index + 1}', style: Theme.of(context).textTheme.titleSmall?.copyWith(color: Theme.of(context).colorScheme.secondary)),
                        const SizedBox(height: 10),
                        SelectableText((page['text_content'] ?? '').toString(), style: const TextStyle(fontSize: 17, height: 1.9)),
                      ],
                    );
                  },
                ),
    );
  }
}
