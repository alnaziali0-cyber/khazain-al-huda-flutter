import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../components/khazain_icon.dart';
import '../../icons/khazain_icons.dart';
import '../dev_panel_screen.dart';
import '../models.dart';
import '../store.dart';

/// Icon manager: the 18 shipped glyphs with a live path / stroke / colour
/// editor and SVG export.
class IconsTab extends ConsumerWidget {
  const IconsTab({super.key, required this.log});

  final DevLogController log;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overrides = ref.watch(devStoreProvider).icons;

    final Map<String, IconDef> byId = {
      for (final icon in overrides) icon.id: icon,
    };

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
      children: [
        Row(
          children: [
            TextButton.icon(
              onPressed: () => _seedIcons(context, ref, log),
              icon: const Icon(Icons.download_rounded, size: 18),
              label: const Text('تهيئة الأيقونات'),
            ),
            const Spacer(),
            Text(
              '${kKhazainIcons.length} أيقونة',
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ],
        ),
        GridView.count(
          crossAxisCount: 4,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 0.92,
          children: [
            for (final definition in kKhazainIcons)
              _IconCell(
                definition: definition,
                iconOverride: byId[definition.id],
                onTap: () => _editIcon(context, ref, log, definition),
              ),
          ],
        ),
        const SizedBox(height: 18),
        OutlinedButton.icon(
          onPressed: () => _exportAll(context, ref),
          icon: const Icon(Icons.save_alt_rounded, size: 18),
          label: const Text('تصدير كل الأيقونات كـ SVG'),
        ),
      ],
    );
  }

  static void _seedIcons(
      BuildContext context, WidgetRef ref, DevLogController log) {
    ref.read(devStoreProvider.notifier).applyPatch(UIPatch(icons: [
      for (final definition in kKhazainIcons)
        {
          'op': 'add',
          'icon': definition.toIconDef().toJson(),
        },
    ]));
    log.add('تهيئة الأيقونات');
  }

  static Future<void> _editIcon(
    BuildContext context,
    WidgetRef ref,
    DevLogController log,
    KhazainIconDef definition,
  ) async {
    final store = ref.read(devStoreProvider.notifier);
    final current = ref.read(devStoreProvider).icons;
    IconDef? existing;
    for (final icon in current) {
      if (icon.id == definition.id) existing = icon;
    }
    final base = existing ?? definition.toIconDef();

    final pathController = TextEditingController(text: base.paths.join('\n'));
    final primaryController = TextEditingController(text: base.primary);
    final secondaryController =
        TextEditingController(text: base.secondary ?? '#BC9551');
    var stroke = base.stroke;

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setState) => AlertDialog(
          title: Text(definition.label),
          content: SizedBox(
            width: 420,
            height: 420,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    height: 96,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFFBF8),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: KhazainIcon(
                      definition.id,
                      size: 56,
                      primary: primaryController.text,
                      secondary: secondaryController.text,
                      stroke: stroke,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: pathController,
                    maxLines: 6,
                    style: const TextStyle(color: Colors.white, fontSize: 11),
                    decoration: const InputDecoration(
                      labelText: 'مسارات SVG (سطر لكل مسار)',
                      labelStyle: TextStyle(color: Colors.white54),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: primaryController,
                          style: const TextStyle(color: Colors.white),
                          decoration: const InputDecoration(
                            labelText: 'اللون الأساسي',
                            labelStyle: TextStyle(color: Colors.white54),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: secondaryController,
                          style: const TextStyle(color: Colors.white),
                          decoration: const InputDecoration(
                            labelText: 'اللون الثانوي',
                            labelStyle: TextStyle(color: Colors.white54),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      const Text('سماكة الخط',
                          style: TextStyle(color: Colors.white70, fontSize: 12)),
                      Expanded(
                        child: Slider(
                          value: stroke,
                          min: 1,
                          max: 4,
                          onChanged: (value) => setState(() => stroke = value),
                        ),
                      ),
                      Text(stroke.toStringAsFixed(1),
                          style: const TextStyle(color: Colors.white)),
                    ],
                  ),
                ],
              ),
            ),
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
      ),
    );

    if (saved == true) {
      final paths = pathController.text
          .split('\n')
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .toList(growable: false);
      store.applyPatch(UIPatch(icons: [
        {
          'op': 'update',
          'icon': IconDef(
            id: definition.id,
            paths: paths,
            size: 24,
            stroke: stroke,
            primary: primaryController.text.trim(),
            secondary: secondaryController.text.trim(),
            secondaryPathCount: definition.accentPaths.length,
          ).toJson(),
        },
      ]));
      log.add('تعديل أيقونة ${definition.label}');
    }

    pathController.dispose();
    primaryController.dispose();
    secondaryController.dispose();
  }

  static Future<void> _exportAll(
      BuildContext context, WidgetRef ref) async {
    final overrides = ref.read(devStoreProvider).icons;
    final Map<String, IconDef> byId = {
      for (final icon in overrides) icon.id: icon,
    };
    final buffer = StringBuffer();
    for (final definition in kKhazainIcons) {
      final icon = byId[definition.id] ?? definition.toIconDef();
      buffer
        ..write('<svg id="${definition.id}" xmlns="http://www.w3.org/2000/svg" '
            'viewBox="0 0 24 24" fill="none" stroke-linecap="round" '
            'stroke-linejoin="round">\n')
        ..writeln('  <title>${definition.label}</title>');
      for (final path in icon.primaryPaths) {
        buffer.writeln('  <path d="$path" stroke="${icon.primary}" '
            'stroke-width="${icon.stroke}"/>');
      }
      for (final path in icon.accentPaths) {
        buffer.writeln('  <path d="$path" stroke="${icon.secondary ?? icon.primary}" '
            'stroke-width="${icon.stroke}"/>');
      }
      buffer.writeln('</svg>\n');
    }
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/icons.svg');
      await file.writeAsString(buffer.toString());
      await Clipboard.setData(ClipboardData(text: buffer.toString()));
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('حُفظ ملف icons.svg ونُسخت محتوياته.')),
      );
    } catch (_) {
      if (!context.mounted) return;
      await Clipboard.setData(ClipboardData(text: buffer.toString()));
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر الحفظ على القرص؛ نُسخت المحتويات.')),
      );
    }
  }
}

class _IconCell extends StatelessWidget {
  const _IconCell({
    required this.definition,
    required this.iconOverride,
    required this.onTap,
  });

  final KhazainIconDef definition;
  final IconDef? iconOverride;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF2A2A2A),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 42,
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0xFFFFFBF8),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: KhazainIcon(
                  definition.id,
                  size: 26,
                  primary: iconOverride?.primary,
                  secondary: iconOverride?.secondary,
                  stroke: iconOverride?.stroke,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                definition.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white70, fontSize: 10),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
