import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/sections/section_catalogue.dart';
import '../../icons/khazain_icons.dart';
import '../dev_panel_screen.dart';
import '../models.dart';
import '../store.dart';

/// Sections manager: add, remove, reorder, hide, lock and re-icon sections.
class SectionsTab extends ConsumerWidget {
  const SectionsTab({super.key, required this.log});

  final DevLogController log;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.watch(devStoreProvider.notifier);
    final sections = ref.watch(devStoreProvider).sections;

    if (sections.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.grid_view_rounded, size: 48, color: Colors.white38),
              const SizedBox(height: 14),
              const Text(
                'لا توجد أقسام في مخزن المطوّر.',
                style: TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () {
                  store.replace(ref.read(devStoreProvider).copyWith(
                    sections: [
                      for (final section in kAppSections)
                        DevSection(
                          id: section.id,
                          title: section.title,
                          iconId: section.iconId,
                          group: section.group,
                          order: section.order,
                          visible: true,
                          locked: false,
                          route: section.route,
                        ),
                    ],
                  ));
                  log.add('تهيئة كتالوج الأقسام الافتراضي');
                },
                icon: const Icon(Icons.download_rounded, size: 18),
                label: const Text('تهيئة الكتالوج الافتراضي'),
              ),
            ],
          ),
        ),
      );
    }

    final groups = <String, List<DevSection>>{};
    for (final section in sections) {
      groups.putIfAbsent(section.group, () => <DevSection>[]).add(section);
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
      children: [
        Row(
          children: [
            TextButton.icon(
              onPressed: () => _addSection(context, ref, log),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('قسم جديد'),
            ),
            const Spacer(),
            Text(
              '${sections.length} قسم',
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ],
        ),
        for (final entry in groups.entries) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 14, 4, 6),
            child: Text(
              entry.key,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          for (final section in entry.value)
            _SectionRow(
              section: section,
              log: log,
              onMove: (delta) {
                final ordered = List<DevSection>.from(sections);
                final index = ordered.indexWhere((item) => item.id == section.id);
                final target = index + delta;
                if (index < 0 || target < 0 || target >= ordered.length) return;
                final other = ordered[target];
                ordered[index] = other.copyWith(order: section.order);
                ordered[target] = section.copyWith(order: other.order);
                store.replace(
                  ref.read(devStoreProvider).copyWith(sections: ordered),
                );
                log.add('نقل ${section.title}');
              },
              onToggleVisible: (value) => _patch(ref, log, section.id, {
                'visible': value,
              }),
              onToggleLocked: (value) => _patch(ref, log, section.id, {
                'locked': value,
              }),
              onIcon: (iconId) => _patch(ref, log, section.id, {'iconId': iconId}),
              onTitle: (title) => _patch(ref, log, section.id, {'title': title}),
              onRoute: (route) => _patch(ref, log, section.id, {'route': route}),
              onDelete: () {
                _patch(ref, log, section.id, {'visible': false});
                log.add('إخفاء ${section.title}');
              },
            ),
        ],
      ],
    );
  }

  static void _patch(
    WidgetRef ref,
    DevLogController log,
    String id,
    Map<String, dynamic> changes,
  ) {
    ref.read(devStoreProvider.notifier).applyPatch(UIPatch(sections: [
      {
        'op': 'update',
        'section': <String, dynamic>{'id': id, ...changes},
      },
    ]));
    log.add('تعديل القسم $id');
  }

  static Future<void> _addSection(
      BuildContext context, WidgetRef ref, DevLogController log) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('قسم جديد'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'عنوان القسم'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text.trim()),
            child: const Text('إضافة'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (result == null || result.isEmpty) return;
    final id = 'custom_${DateTime.now().millisecondsSinceEpoch}';
    ref.read(devStoreProvider.notifier).applyPatch(UIPatch(sections: [
      {
        'op': 'add',
        'section': <String, dynamic>{
          'id': id,
          'title': result,
          'iconId': 'quran',
          'group': 'أرشيف',
          'order': 99,
          'visible': true,
          'locked': false,
          'route': '',
        },
      },
    ]));
    log.add('إضافة قسم $result');
  }
}

class _SectionRow extends StatelessWidget {
  const _SectionRow({
    required this.section,
    required this.log,
    required this.onMove,
    required this.onToggleVisible,
    required this.onToggleLocked,
    required this.onIcon,
    required this.onTitle,
    required this.onRoute,
    required this.onDelete,
  });

  final DevSection section;
  final DevLogController log;
  final ValueChanged<int> onMove;
  final ValueChanged<bool> onToggleVisible;
  final ValueChanged<bool> onToggleLocked;
  final ValueChanged<String> onIcon;
  final ValueChanged<String> onTitle;
  final ValueChanged<String> onRoute;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
      decoration: BoxDecoration(
        color: const Color(0xFF2A2A2A),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => _editField(context, 'العنوان', section.title, onTitle),
                  child: Text(
                    section.title,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                  ),
                ),
              ),
              IconButton(
                tooltip: 'أعلى',
                onPressed: () => onMove(-1),
                icon: const Icon(Icons.keyboard_arrow_up_rounded,
                    size: 18, color: Colors.white54),
              ),
              IconButton(
                tooltip: 'أسفل',
                onPressed: () => onMove(1),
                icon: const Icon(Icons.keyboard_arrow_down_rounded,
                    size: 18, color: Colors.white54),
              ),
              IconButton(
                tooltip: section.visible ? 'إخفاء' : 'إظهار',
                onPressed: () => onToggleVisible(!section.visible),
                icon: Icon(
                  section.visible
                      ? Icons.visibility_rounded
                      : Icons.visibility_off_rounded,
                  size: 18,
                  color: section.visible ? Colors.white70 : Colors.white24,
                ),
              ),
              IconButton(
                tooltip: section.locked ? 'فتح' : 'قفل',
                onPressed: () => onToggleLocked(!section.locked),
                icon: Icon(
                  section.locked ? Icons.lock_rounded : Icons.lock_open_rounded,
                  size: 18,
                  color: section.locked ? const Color(0xFFBC9551) : Colors.white54,
                ),
              ),
              IconButton(
                tooltip: 'إخفاء القسم',
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline_rounded,
                    size: 18, color: Colors.white54),
              ),
            ],
          ),
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => _editField(context, 'المسار', section.route, onRoute),
                  child: Text(
                    section.route,
                    style: const TextStyle(color: Colors.white38, fontSize: 11),
                  ),
                ),
              ),
              PopupMenuButton<String>(
                tooltip: 'تغيير الأيقونة',
                onSelected: onIcon,
                itemBuilder: (context) => [
                  for (final icon in kKhazainIcons)
                    PopupMenuItem<String>(
                      value: icon.id,
                      child: Text(icon.label),
                    ),
                ],
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  child: Text(
                    'الأيقونة: ${khazainIconById(section.iconId)?.label ?? section.iconId}',
                    style: const TextStyle(color: Colors.white54, fontSize: 11),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static Future<void> _editField(
    BuildContext context,
    String label,
    String value,
    ValueChanged<String> onChanged,
  ) async {
    final controller = TextEditingController(text: value);
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(label),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text.trim()),
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (result != null) onChanged(result);
  }
}
