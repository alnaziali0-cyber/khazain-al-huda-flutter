import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/library_assistant_repository.dart';

const _night = Color(0xFF031D29);
const _nightBorder = Color(0xFF244451);
const _teal = Color(0xFF258BA3);
const _mint = Color(0xFF2AA69F);
const _pale = Color(0xFFE6F2F4);

class LibraryAssistantScreen extends ConsumerStatefulWidget {
  const LibraryAssistantScreen({super.key});

  @override
  ConsumerState<LibraryAssistantScreen> createState() => _LibraryAssistantScreenState();
}

class _LibraryAssistantScreenState extends ConsumerState<LibraryAssistantScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final List<_AssistantMessage> _messages = [
    const _AssistantMessage(
      text: 'السلام عليكم ورحمة الله\nأنا مساعد خزائن الهدى. أستطيع البحث في مكتبتك والمصادر المتاحة، وتجهيز معاينة استيراد مع توضيح حالة الحقوق قبل أي تنزيل.',
      isUser: false,
    ),
  ];
  bool _sending = false;

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send([String? value]) async {
    final text = (value ?? _input.text).trim();
    if (text.isEmpty || _sending) return;
    _input.clear();
    setState(() {
      _sending = true;
      _messages.add(_AssistantMessage(text: text, isUser: true));
    });
    _jumpToLatest();
    try {
      final history = _messages
          .take(_messages.length - 1)
          .where((item) => item.data == null)
          .toList()
          .reversed
          .take(10)
          .toList()
          .reversed
          .map((item) => {'role': item.isUser ? 'user' : 'assistant', 'content': item.text})
          .toList();
      final result = await ref.read(libraryAssistantRepositoryProvider).chat(
            message: text,
            history: history,
          );
      if (!mounted) return;
      setState(() {
        _messages.add(_AssistantMessage(
          text: (result['answer'] ?? 'وصلت الاستجابة دون نص.').toString(),
          isUser: false,
          data: result['data'],
          notice: result['provider_notice']?.toString(),
        ));
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _messages.add(_AssistantMessage(
            text: 'تعذر الاتصال بخادم المكتبة. تحقق من اتصال الإنترنت وعنوان الخادم، ثم أعد المحاولة.',
            isUser: false,
            notice: _safeError(error),
          )));
    } finally {
      if (mounted) {
        setState(() => _sending = false);
        _jumpToLatest();
      }
    }
  }

  String _safeError(Object error) {
    return error.toString().replaceAll(RegExp(r'Bearer\s+\S+'), 'Bearer [محجوب]');
  }

  void _jumpToLatest() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 240), curve: Curves.easeOut);
      }
    });
  }

  Future<void> _showSourceIdentifierDialog() async {
    final controller = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF102F3C),
        title: const Text('رابط أو معرّف Internet Archive', style: TextStyle(color: _pale)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: _pale),
          decoration: const InputDecoration(
            hintText: 'مثال: identifier أو رابط العنصر',
            hintStyle: TextStyle(color: Colors.white54),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: const Text('معاينة')),
        ],
      ),
    );
    controller.dispose();
    if (value == null || value.isEmpty || !mounted) return;
    final identifier = _archiveIdentifier(value);
    if (identifier == null) {
      _showSnack('الرابط غير صالح. استخدم معرّف عنصر Internet Archive أو رابط details/identifier.');
      return;
    }
    setState(() {
      _messages.add(_AssistantMessage(text: 'جهّز معاينة استيراد للكتاب: $identifier', isUser: true));
      _sending = true;
    });
    try {
      final result = await ref.read(libraryAssistantRepositoryProvider).previewImport(identifier);
      if (!mounted) return;
      final job = result['job'] is Map ? Map<String, dynamic>.from(result['job'] as Map) : null;
      setState(() => _messages.add(_AssistantMessage(
            text: (result['confirmation_notice_ar'] ?? 'تم تجهيز المعاينة.').toString(),
            isUser: false,
            data: {'preview': result, if (job != null) 'job': job},
          )));
    } catch (error) {
      if (!mounted) return;
      setState(() => _messages.add(_AssistantMessage(text: 'تعذّر إنشاء معاينة الاستيراد. تحقق من المعرّف أو حالة المصدر.\n${_safeError(error)}', isUser: false)));
    } finally {
      if (mounted) {
        setState(() => _sending = false);
        _jumpToLatest();
      }
    }
  }

  String? _archiveIdentifier(String raw) {
    final uri = Uri.tryParse(raw);
    if (uri == null || !uri.hasAuthority) {
      return RegExp(r'^[A-Za-z0-9._-]{5,80}$').hasMatch(raw) ? raw : null;
    }
    if (uri.scheme != 'https' || uri.host != 'archive.org') return null;
    if (!uri.path.startsWith('/details/')) return null;
    final parts = uri.path.split('/').where((part) => part.isNotEmpty).toList();
    if (parts.length < 2 || !RegExp(r'^[A-Za-z0-9._-]{5,80}$').hasMatch(parts[1])) return null;
    return parts[1];
  }

  Future<void> _previewIdentifier(String identifier) async {
    if (_sending) return;
    setState(() {
      _sending = true;
      _messages.add(_AssistantMessage(text: 'إنشاء معاينة للمعرّف $identifier', isUser: true));
    });
    try {
      final result = await ref.read(libraryAssistantRepositoryProvider).previewImport(identifier);
      if (!mounted) return;
      final job = result['job'] is Map ? Map<String, dynamic>.from(result['job'] as Map) : null;
      setState(() => _messages.add(_AssistantMessage(
            text: (result['confirmation_notice_ar'] ?? 'تم تجهيز المعاينة.').toString(),
            isUser: false,
            data: {'preview': result, if (job != null) 'job': job},
          )));
    } catch (error) {
      if (!mounted) return;
      setState(() => _messages.add(_AssistantMessage(text: 'تعذر إنشاء المعاينة لهذا العنصر.\n${_safeError(error)}', isUser: false)));
    } finally {
      if (mounted) {
        setState(() => _sending = false);
        _jumpToLatest();
      }
    }
  }

  Future<void> _confirmImport(int jobId) async {
    setState(() => _sending = true);
    try {
      final result = await ref.read(libraryAssistantRepositoryProvider).confirmImport(jobId);
      if (!mounted) return;
      final book = result['book'] is Map ? Map<String, dynamic>.from(result['book'] as Map) : const <String, dynamic>{};
      setState(() => _messages.add(_AssistantMessage(
            text: book.isEmpty
                ? 'انتهت العملية، لكن لم يرجع الخادم بطاقة كتاب.'
                : 'أضيفت النسخة إلى مكتبتك الخاصة: ${book['title'] ?? 'كتاب'}\nهذه نسخة خاصة ومسودة غير منشورة؛ حقوقها تحتاج مراجعة مستقلة قبل أي إتاحة عامة.',
            isUser: false,
            data: {'book': book, 'job': result['job']},
          )));
    } catch (error) {
      if (!mounted) return;
      setState(() => _messages.add(_AssistantMessage(text: 'لم يكتمل الاستيراد. لم تُنشر أي نسخة عامة.\n${_safeError(error)}', isUser: false)));
    } finally {
      if (mounted) {
        setState(() => _sending = false);
        _jumpToLatest();
      }
    }
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: _night,
        body: Stack(
          children: [
            const Positioned.fill(child: CustomPaint(painter: _StarFieldPainter())),
            SafeArea(
              child: Column(
                children: [
                  _header(context),
                  Expanded(
                    child: ListView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                      itemCount: _messages.length + (_sending ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (_sending && index == _messages.length) return const _ThinkingIndicator();
                        return _MessageView(
                          message: _messages[index],
                          onPreviewConfirm: _confirmImport,
                          onPreview: _previewIdentifier,
                          onBookTap: (id) => context.push('/library/imported/$id'),
                        );
                      },
                    ),
                  ),
                  if (_messages.length == 1) _quickPrompts(),
                  _composer(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: SizedBox(
        height: 54,
        child: Row(
          children: [
            _RoundHeaderButton(icon: Icons.arrow_forward_ios_rounded, onTap: () => context.go('/sections')),
            const Spacer(),
            const Text('المساعد الذكي', style: TextStyle(color: _pale, fontSize: 18, fontWeight: FontWeight.w800)),
            const Spacer(),
            _RoundHeaderButton(
              icon: Icons.info_outline_rounded,
              onTap: () => showDialog<void>(
                context: context,
                builder: (context) => AlertDialog(
                  backgroundColor: const Color(0xFF102F3C),
                  title: const Text('عن المساعد', style: TextStyle(color: _pale)),
                  content: const Text('يربط المساعد بخدمات المكتبة المصرّح بها. نتائج البحث الخارجي بيانات وصفية، ولا يبدأ تنزيل كتاب إلا بعد معاينة وموافقة صريحة. الكتب المستوردة تبقى خاصة ومسودات إلى حين مراجعة الحقوق.', style: TextStyle(color: _pale)),
                  actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('حسناً'))],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _quickPrompts() {
    const prompts = ['ابحث عن كتاب الكافي', 'اكتشف المصادر المتاحة', 'اعرض الكتب المستوردة', 'حالة الاستيراد'];
    return SizedBox(
      height: 48,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        scrollDirection: Axis.horizontal,
        itemCount: prompts.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) => ActionChip(
          backgroundColor: const Color(0xAA0D3343),
          side: const BorderSide(color: _nightBorder),
          label: Text(prompts[index], style: const TextStyle(color: _pale, fontSize: 12)),
          onPressed: _sending ? null : () => _send(prompts[index]),
        ),
      ),
    );
  }

  Widget _composer() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: const BoxDecoration(
        color: Color(0xE6031D29),
        border: Border(top: BorderSide(color: Color(0x332D6473))),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          IconButton(
            tooltip: 'إرفاق معرّف مصدر',
            onPressed: _sending ? null : _showSourceIdentifierDialog,
            icon: const Icon(Icons.attach_file_rounded, color: Colors.white70),
          ),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xCC102F3D),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: const Color(0xFF2B4A56)),
              ),
              child: TextField(
                controller: _input,
                minLines: 1,
                maxLines: 5,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _send(),
                style: const TextStyle(color: _pale, fontSize: 14),
                decoration: const InputDecoration(
                  hintText: 'اسأل عن كتاب أو مصدر...',
                  hintStyle: TextStyle(color: Colors.white54, fontSize: 13),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Material(
            color: _teal,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: _sending ? null : _send,
              child: SizedBox(
                width: 48,
                height: 48,
                child: Icon(_sending ? Icons.hourglass_top_rounded : Icons.send_rounded, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AssistantMessage {
  const _AssistantMessage({required this.text, required this.isUser, this.data, this.notice});
  final String text;
  final bool isUser;
  final Object? data;
  final String? notice;
}

class _MessageView extends StatelessWidget {
  const _MessageView({required this.message, required this.onPreviewConfirm, required this.onPreview, required this.onBookTap});
  final _AssistantMessage message;
  final Future<void> Function(int jobId) onPreviewConfirm;
  final ValueChanged<String> onPreview;
  final ValueChanged<int> onBookTap;

  @override
  Widget build(BuildContext context) {
    final isUser = message.isUser;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: isUser ? MainAxisAlignment.start : MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isUser) ...[
            const _SparkleAvatar(),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                  decoration: BoxDecoration(
                    color: isUser ? _teal.withOpacity(.92) : const Color(0xCC102F3D),
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(19),
                      topRight: const Radius.circular(19),
                      bottomLeft: Radius.circular(isUser ? 19 : 5),
                      bottomRight: Radius.circular(isUser ? 5 : 19),
                    ),
                    border: Border.all(color: isUser ? const Color(0x4456B4C8) : _nightBorder),
                  ),
                  child: SelectableText(message.text, style: const TextStyle(color: _pale, height: 1.55, fontSize: 14)),
                ),
                if (message.notice != null && message.notice!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 6, right: 6, left: 6),
                    child: Text(message.notice!, style: const TextStyle(color: Color(0xFF9BB3BC), fontSize: 11)),
                  ),
                if (message.data != null) _AssistantDataCards(data: message.data!, onPreviewConfirm: onPreviewConfirm, onPreview: onPreview, onBookTap: onBookTap),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AssistantDataCards extends StatelessWidget {
  const _AssistantDataCards({required this.data, required this.onPreviewConfirm, required this.onPreview, required this.onBookTap});
  final Object data;
  final Future<void> Function(int jobId) onPreviewConfirm;
  final ValueChanged<String> onPreview;
  final ValueChanged<int> onBookTap;

  @override
  Widget build(BuildContext context) {
    final dataMap = data is Map ? Map<String, dynamic>.from(data as Map) : <String, dynamic>{};
    final job = dataMap['job'] is Map ? Map<String, dynamic>.from(dataMap['job'] as Map) : null;
    final preview = dataMap['preview'] is Map ? Map<String, dynamic>.from(dataMap['preview'] as Map) : null;
    final book = dataMap['book'] is Map ? Map<String, dynamic>.from(dataMap['book'] as Map) : null;
    final search = dataMap['data'] is Map ? Map<String, dynamic>.from(dataMap['data'] as Map) : dataMap;
    final remote = search['remote'];
    final local = search['local'];
    final items = data is List ? data : search['items'];
    final widgets = <Widget>[];
    if (preview != null && job != null) {
      widgets.add(_PreviewCard(preview: preview, job: job, onConfirm: onPreviewConfirm));
    }
    if (book != null && book['id'] is int) {
      widgets.add(_BookCard(book: book, onTap: () => onBookTap(book['id'] as int)));
    }
    if (local is List) {
      for (final item in local.whereType<Map>()) {
        widgets.add(_LocalBookCard(book: Map<String, dynamic>.from(item), onBookTap: onBookTap));
      }
    }
    if (remote is List) {
      for (final item in remote.whereType<Map>()) {
        widgets.add(_RemoteBookCard(book: Map<String, dynamic>.from(item), onPreview: onPreview));
      }
    }
    if (items is List && local == null && remote == null) {
      for (final item in items.whereType<Map>()) {
        final row = Map<String, dynamic>.from(item);
        if (row.containsKey('source_key')) {
          widgets.add(_SourceConnectorCard(source: row));
        } else {
          widgets.add(_CompactDataCard(item: row));
        }
      }
    }
    if (search['imports_by_status'] is Map || search['private_books'] is int) {
      widgets.add(_StatusCard(data: search));
    }
    if (widgets.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 9),
      child: Column(children: widgets),
    );
  }
}

class _RemoteBookCard extends StatelessWidget {
  const _RemoteBookCard({required this.book, required this.onPreview});
  final Map<String, dynamic> book;
  final ValueChanged<String> onPreview;
  @override
  Widget build(BuildContext context) {
    final title = (book['title'] ?? 'عنوان غير متاح').toString();
    final identifier = (book['identifier'] ?? '').toString();
    return _GlassDataCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(color: _pale, fontWeight: FontWeight.w800)),
        if (book['author'] != null) Text('المؤلف: ${book['author']}', style: const TextStyle(color: Colors.white70, fontSize: 12)),
        Text('المصدر: Internet Archive · ${book['rights_status'] ?? 'غير متحقق'}', style: const TextStyle(color: Color(0xFFB4C8CF), fontSize: 11)),
        const SizedBox(height: 8),
        Text('معرّف المصدر: $identifier', style: const TextStyle(color: Colors.white60, fontSize: 11)),
        const Text('هذه نتيجة وصفية فقط؛ المعاينة لا تعني اعتماد الترخيص.', style: TextStyle(color: Color(0xFFE0C58D), fontSize: 11)),
        const SizedBox(height: 6),
        OutlinedButton.icon(onPressed: identifier.isEmpty ? null : () => onPreview(identifier), icon: const Icon(Icons.fact_check_outlined), label: const Text('معاينة الاستيراد'), style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFF9BD5DE))),
      ]),
    );
  }
}

class _LocalBookCard extends StatelessWidget {
  const _LocalBookCard({required this.book, required this.onBookTap});
  final Map<String, dynamic> book;
  final ValueChanged<int> onBookTap;
  @override
  Widget build(BuildContext context) => _GlassDataCard(
        onTap: book['id'] is int ? () => onBookTap(book['id'] as int) : null,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text((book['title'] ?? '').toString(), style: const TextStyle(color: _pale, fontWeight: FontWeight.w800)),
          Text('المؤلف: ${book['author'] ?? 'غير محدد'} · الصفحات: ${book['page_count'] ?? 0}', style: const TextStyle(color: Colors.white70, fontSize: 12)),
          const Text('نسخة خاصة بهذا الجهاز', style: TextStyle(color: Color(0xFF8FD2C9), fontSize: 11)),
        ]),
      );
}

class _PreviewCard extends StatelessWidget {
  const _PreviewCard({required this.preview, required this.job, required this.onConfirm});
  final Map<String, dynamic> preview;
  final Map<String, dynamic> job;
  final Future<void> Function(int jobId) onConfirm;
  @override
  Widget build(BuildContext context) {
    final canConfirm = preview['can_confirm'] == true && job['id'] is int;
    return _GlassDataCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text((job['title'] ?? 'معاينة كتاب').toString(), style: const TextStyle(color: _pale, fontWeight: FontWeight.w800)),
        Text('المصدر: ${job['source_item_id'] ?? ''}', style: const TextStyle(color: Colors.white70, fontSize: 12)),
        Text('حالة الحقوق: ${job['rights_status'] ?? 'غير محسومة'}', style: const TextStyle(color: Color(0xFFE0C58D), fontSize: 12)),
        Text('الملف: ${job['selected_file'] ?? 'غير متاح'}', style: const TextStyle(color: Colors.white70, fontSize: 12)),
        const SizedBox(height: 8),
        if (canConfirm)
          FilledButton.icon(
            onPressed: () => onConfirm(job['id'] as int),
            icon: const Icon(Icons.download_rounded),
            label: const Text('تأكيد النسخة الشخصية'),
            style: FilledButton.styleFrom(backgroundColor: _teal, foregroundColor: Colors.white),
          )
        else
          const Text('لا يتاح الاستيراد قبل تحقق شروط الحقوق ووجود ملف مناسب.', style: TextStyle(color: Colors.white70, fontSize: 12)),
      ]),
    );
  }
}

class _BookCard extends StatelessWidget {
  const _BookCard({required this.book, required this.onTap});
  final Map<String, dynamic> book;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => _GlassDataCard(
        onTap: book['id'] is int ? onTap : null,
        child: Row(children: [
          const Icon(Icons.menu_book_rounded, color: Color(0xFF83C8CF)),
          const SizedBox(width: 10),
          Expanded(child: Text((book['title'] ?? 'كتاب مستورد').toString(), style: const TextStyle(color: _pale, fontWeight: FontWeight.w700))),
          const Icon(Icons.chevron_left_rounded, color: Colors.white70),
        ]),
      );
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.data});
  final Map<String, dynamic> data;
  @override
  Widget build(BuildContext context) => _GlassDataCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('الكتب الخاصة: ${data['private_books'] ?? 0}', style: const TextStyle(color: _pale)),
          Text('إجمالي عمليات الاستيراد: ${data['imports_total'] ?? 0}', style: const TextStyle(color: _pale)),
          if (data['imports_by_status'] is Map)
            Text((data['imports_by_status'] as Map).entries.map((entry) => '${entry.key}: ${entry.value}').join(' · '), style: const TextStyle(color: Colors.white70, fontSize: 11)),
        ]),
      );
}


class _SourceConnectorCard extends StatelessWidget {
  const _SourceConnectorCard({required this.source});
  final Map<String, dynamic> source;
  @override
  Widget build(BuildContext context) => _GlassDataCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text((source['name_ar'] ?? source['source_key'] ?? 'مصدر').toString(), style: const TextStyle(color: _pale, fontWeight: FontWeight.w800)),
          Text('الحالة: ${source['status'] ?? 'غير محددة'}', style: const TextStyle(color: Color(0xFF9FD2D8), fontSize: 12)),
          Text((source['policy_ar'] ?? '').toString(), style: const TextStyle(color: Colors.white70, fontSize: 12, height: 1.5)),
        ]),
      );
}

class _CompactDataCard extends StatelessWidget {
  const _CompactDataCard({required this.item});
  final Map<String, dynamic> item;
  @override
  Widget build(BuildContext context) => _GlassDataCard(
        child: Text(item.entries.map((entry) => '${entry.key}: ${entry.value}').join('\n'), style: const TextStyle(color: _pale, fontSize: 12)),
      );
}

class _GlassDataCard extends StatelessWidget {
  const _GlassDataCard({required this.child, this.onTap});
  final Widget child;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(top: 7),
        decoration: BoxDecoration(
          color: const Color(0xCC0A2937),
          borderRadius: BorderRadius.circular(17),
          border: Border.all(color: _nightBorder),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(17),
            child: Padding(padding: const EdgeInsets.all(13), child: child),
          ),
        ),
      );
}

class _RoundHeaderButton extends StatelessWidget {
  const _RoundHeaderButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Material(
        color: const Color(0xAA153847),
        shape: const CircleBorder(side: BorderSide(color: _nightBorder)),
        child: InkWell(customBorder: const CircleBorder(), onTap: onTap, child: SizedBox(width: 42, height: 42, child: Icon(icon, color: _pale, size: 20))),
      );
}

class _SparkleAvatar extends StatelessWidget {
  const _SparkleAvatar();
  @override
  Widget build(BuildContext context) => Container(
        width: 38,
        height: 38,
        decoration: const BoxDecoration(color: _mint, shape: BoxShape.circle),
        child: const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 20),
      );
}

class _ThinkingIndicator extends StatelessWidget {
  const _ThinkingIndicator();
  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Row(children: [
          _SparkleAvatar(),
          SizedBox(width: 10),
          Text('أفحص المصادر وأجهّز الإجابة...', style: TextStyle(color: Colors.white70, fontSize: 12)),
          SizedBox(width: 8),
          SizedBox(width: 13, height: 13, child: CircularProgressIndicator(strokeWidth: 1.6, color: Color(0xFF86C8D2))),
        ]),
      );
}

class _StarFieldPainter extends CustomPainter {
  const _StarFieldPainter();
  static const _points = <Offset>[
    Offset(.06, .08), Offset(.21, .15), Offset(.46, .09), Offset(.72, .13), Offset(.91, .08),
    Offset(.12, .29), Offset(.35, .24), Offset(.63, .31), Offset(.84, .27), Offset(.96, .39),
    Offset(.07, .53), Offset(.27, .48), Offset(.52, .57), Offset(.77, .5), Offset(.9, .65),
    Offset(.16, .74), Offset(.4, .71), Offset(.68, .78), Offset(.85, .88), Offset(.25, .93),
  ];
  @override
  void paint(Canvas canvas, Size size) {
    final star = Paint()..color = const Color(0x667CA5B1);
    final faint = Paint()..color = const Color(0x226E9AA8);
    for (var index = 0; index < _points.length; index++) {
      final point = Offset(_points[index].dx * size.width, _points[index].dy * size.height);
      final radius = index % 4 == 0 ? 1.6 : 1.0;
      canvas.drawCircle(point, radius, index % 3 == 0 ? star : faint);
      if (index % 4 == 0) {
        final glow = Paint()..color = const Color(0x226E9AA8)..strokeWidth = 0.7;
        canvas.drawLine(point.translate(-4, 0), point.translate(4, 0), glow);
        canvas.drawLine(point.translate(0, -4), point.translate(0, 4), glow);
      }
    }
    final shade = Paint()..shader = RadialGradient(colors: [Colors.transparent, Colors.black.withOpacity(.16)], radius: 1.1).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, shade);
  }

  @override
  bool shouldRepaint(covariant _StarFieldPainter oldDelegate) => false;
}
