import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../dev_panel_screen.dart';
import '../models.dart';
import '../store.dart';

/// Strings tab: edit the inline copy without touching the source.
class StringsTab extends ConsumerWidget {
  const StringsTab({super.key, required this.log});

  final DevLogController log;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.watch(devStoreProvider.notifier);
    final strings = ref.watch(devStoreProvider).strings;

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
      children: [
        Row(
          children: [
            TextButton.icon(
              onPressed: () => _addString(context, ref, log),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('نص جديد'),
            ),
            const Spacer(),
            Text(
              '${strings.length} نص',
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ],
        ),
        if (strings.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'لا توجد نصوص مخصّصة. أضف مفتاحاً ونصاً ليُستخدم في الشاشات.',
              style: TextStyle(color: Colors.white54),
              textAlign: TextAlign.center,
            ),
          ),
        for (final entry in strings.entries)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
            decoration: BoxDecoration(
              color: const Color(0xFF2A2A2A),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.key,
                        style: const TextStyle(
                          color: Color(0xFFBC9551),
                          fontSize: 11,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        entry.value,
                        style: const TextStyle(color: Colors.white, fontSize: 13),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'تعديل',
                  onPressed: () => _editString(context, ref, log, entry.key, entry.value),
                  icon: const Icon(Icons.edit_rounded,
                      size: 18, color: Colors.white54),
                ),
                IconButton(
                  tooltip: 'حذف',
                  onPressed: () {
                    final next = Map<String, String>.from(strings)..remove(entry.key);
                    store.applyPatch(UIPatch(strings: next));
                    log.add('حذف النص ${entry.key}');
                  },
                  icon: const Icon(Icons.delete_outline_rounded,
                      size: 18, color: Colors.white54),
                ),
              ],
            ),
          ),
      ],
    );
  }

  static Future<void> _addString(
      BuildContext context, WidgetRef ref, DevLogController log) async {
    final keyController = TextEditingController();
    final valueController = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('نص جديد'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: keyController,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'المفتاح'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: valueController,
              decoration: const InputDecoration(labelText: 'النص'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
    if (result == true &&
        keyController.text.trim().isNotEmpty &&
        valueController.text.trim().isNotEmpty) {
      ref.read(devStoreProvider.notifier).applyPatch(UIPatch(strings: {
        keyController.text.trim(): valueController.text.trim(),
      }));
      log.add('إضافة نص ${keyController.text.trim()}');
    }
    keyController.dispose();
    valueController.dispose();
  }

  static Future<void> _editString(
    BuildContext context,
    WidgetRef ref,
    DevLogController log,
    String key,
    String value,
  ) async {
    final controller = TextEditingController(text: value);
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(key),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
    if (result == true) {
      ref.read(devStoreProvider.notifier).applyPatch(UIPatch(strings: {
        key: controller.text.trim(),
      }));
      log.add('تعديل النص $key');
    }
    controller.dispose();
  }
}
