import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/library_assistant_repository.dart';

class ImportedBooksScreen extends ConsumerStatefulWidget {
  const ImportedBooksScreen({super.key});

  @override
  ConsumerState<ImportedBooksScreen> createState() => _ImportedBooksScreenState();
}

class _ImportedBooksScreenState extends ConsumerState<ImportedBooksScreen> {
  late Future<List<Map<String, dynamic>>> _books;

  @override
  void initState() {
    super.initState();
    _books = ref.read(libraryAssistantRepositoryProvider).books();
  }

  Future<void> _refresh() async {
    final next = ref.read(libraryAssistantRepositoryProvider).books();
    setState(() => _books = next);
    await next;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('المكتبة الإسلامية')),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<List<Map<String, dynamic>>>(
          future: _books,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return ListView(children: const [SizedBox(height: 130), Center(child: Text('تعذر الاتصال بمكتبتك الخاصة.'))]);
            }
            final books = snapshot.data ?? const [];
            if (books.isEmpty) {
              return ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  const SizedBox(height: 66),
                  Icon(Icons.local_library_outlined, size: 64, color: theme.colorScheme.secondary),
                  const SizedBox(height: 18),
                  Text('مكتبتك الخاصة فارغة حالياً', textAlign: TextAlign.center, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 10),
                  const Text('استخدم المساعد الذكي للبحث عن كتاب أو إنشاء معاينة لاستيراد نسخة شخصية من مصدر تتوفر له بيانات ترخيص مناسبة. لا تُنشر المواد تلقائياً.', textAlign: TextAlign.center, style: TextStyle(height: 1.7)),
                  const SizedBox(height: 18),
                  Center(child: FilledButton.icon(onPressed: () => context.push('/assistant'), icon: const Icon(Icons.auto_awesome_rounded), label: const Text('فتح المساعد الذكي'))),
                ],
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: books.length + 1,
              separatorBuilder: (_, __) => const SizedBox(height: 9),
              itemBuilder: (context, index) {
                if (index == 0) {
                  return const Padding(
                    padding: EdgeInsets.only(bottom: 8),
                    child: Text('النسخ التي استوردتها إلى هذا الجهاز. حالة الحقوق لا تتحول إلى موافقة نشر تلقائياً.', style: TextStyle(height: 1.6)),
                  );
                }
                final book = books[index - 1];
                return Card(
                  child: ListTile(
                    leading: const CircleAvatar(child: Icon(Icons.menu_book_rounded)),
                    title: Text((book['title'] ?? '').toString(), maxLines: 2, overflow: TextOverflow.ellipsis),
                    subtitle: Text('${book['author'] ?? 'مؤلف غير محدد'} · ${book['page_count'] ?? 0} صفحة · ${book['rights_status'] ?? 'غير متحقق'}'),
                    trailing: const Icon(Icons.chevron_left_rounded),
                    onTap: book['id'] is int ? () => context.push('/library/imported/${book['id']}') : null,
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
