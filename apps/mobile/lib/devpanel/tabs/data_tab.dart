import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../dev_panel_screen.dart';
import '../store.dart';

/// Data tab: seed, reset, import, export and back up the developer state.
class DataTab extends ConsumerWidget {
  const DataTab({super.key, required this.log});

  final DevLogController log;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(devStoreProvider);
    final store = ref.read(devStoreProvider.notifier);

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
      children: [
        _Stat(
          label: 'أقسام',
          value: '${state.sections.length}',
        ),
        _Stat(label: 'أيقونات', value: '${state.icons.length}'),
        _Stat(label: 'نصوص', value: '${state.strings.length}'),
        _Stat(label: 'أصول', value: '${state.assets.length}'),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: () {
            store.reset();
            log.add('إعادة ضبط مخزن المطوّر');
          },
          icon: const Icon(Icons.restart_alt_rounded, size: 18),
          label: const Text('إعادة الضبط'),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: () => _export(context, ref, log),
          icon: const Icon(Icons.upload_rounded, size: 18),
          label: const Text('تصدير الحالة'),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: () => _import(context, ref, log),
          icon: const Icon(Icons.download_rounded, size: 18),
          label: const Text('استيراد حالة'),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: () => _backup(context, ref, log),
          icon: const Icon(Icons.backup_rounded, size: 18),
          label: const Text('نسخة احتياطية محلية'),
        ),
        const SizedBox(height: 20),
        const Text(
          'كل تعديل يمرّ عبر مخزن المطوّر، ويمكن التراجع 50 خطوة، وأي عملية فاشلة تُرجِع الحالة السابقة بالكامل.',
          style: TextStyle(color: Colors.white54, fontSize: 12, height: 1.6),
        ),
      ],
    );
  }

  Future<void> _export(
      BuildContext context, WidgetRef ref, DevLogController log) async {
    final payload = ref.read(devStoreProvider.notifier).export();
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/khzain.dev.v1.json');
      await file.writeAsString(payload);
      await Share.shareXFiles(
        <XFile>[XFile(file.path)],
        subject: 'خزائن الهدى — حالة المطوّر',
      );
      log.add('تصدير الحالة');
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر التصدير.')),
      );
    }
  }

  Future<void> _import(
      BuildContext context, WidgetRef ref, DevLogController log) async {
    final result = await FilePicker.platform.pickFiles(withData: true);
    if (result == null || result.files.isEmpty) return;
    final bytes = result.files.first.bytes;
    if (bytes == null) return;
    try {
      ref.read(devStoreProvider.notifier).importJson(utf8.decode(bytes));
      log.add('استيراد الحالة');
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('الملف غير صالح.')),
      );
    }
  }

  Future<void> _backup(
      BuildContext context, WidgetRef ref, DevLogController log) async {
    final directory = await getApplicationDocumentsDirectory();
    final file = File('${directory.path}/khzain.dev.v1.backup.json');
    await file.writeAsString(ref.read(devStoreProvider.notifier).export());
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('حُفظت النسخة في ${file.path}')),
    );
    log.add('نسخة احتياطية');
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF2A2A2A),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: const TextStyle(color: Colors.white70)),
          ),
          Text(value, style: const TextStyle(color: Colors.white)),
        ],
      ),
    );
  }
}
