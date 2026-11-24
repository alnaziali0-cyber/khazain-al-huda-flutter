import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../design/theme_provider.dart';
import '../dev_panel_screen.dart';
import '../models.dart';
import '../store.dart';

/// Design tokens editor.
///
/// Live edits are applied through a [UIPatch] so every change is undoable and
/// exportable as `tokens.json`, `tokens.css` or `tokens.ts`.
class TokensTab extends ConsumerWidget {
  const TokensTab({super.key, required this.log});

  final DevLogController log;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(uiThemeProvider);
    final store = ref.read(devStoreProvider.notifier);

    final colors = theme.colors.entries.toList();
    final typography = theme.typography.entries.toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
      children: [
        _SectionHeader(
          title: 'الألوان',
          trailing: TextButton.icon(
            onPressed: () => _export(context, ref, 'json'),
            icon: const Icon(Icons.save_alt_rounded, size: 16),
            label: const Text('تصدير'),
          ),
        ),
        for (final entry in colors)
          _ColorRow(
            name: entry.key,
            value: entry.value,
            onChanged: (value) {
              store.applyPatch(UIPatch(tokens: <String, dynamic>{
                'colors': <String, String>{entry.key: value},
              }));
              log.add('لون $entry.key → $value');
            },
          ),
        const SizedBox(height: 16),
        const _SectionHeader(title: 'الخطوط'),
        for (final entry in typography)
          _TypeRow(
            name: entry.key,
            spec: entry.value,
            onChanged: (spec) {
              store.applyPatch(UIPatch(tokens: <String, dynamic>{
                'typography': <String, dynamic>{entry.key: spec.toJson()},
              }));
              log.add('خط ${entry.key} محدّث');
            },
          ),
        const SizedBox(height: 16),
        const _SectionHeader(title: 'الزوايا والمسافات'),
        _NumberRow(
          label: 'زوايا البطاقة',
          value: theme.cardRadius,
          onChanged: (value) => _patchNumber(ref, store, 'radius', 'card', value, log),
        ),
        _NumberRow(
          label: 'زوايا البلاطة',
          value: theme.tileRadius,
          onChanged: (value) => _patchNumber(ref, store, 'radius', 'tile', value, log),
        ),
        _NumberRow(
          label: 'زوايا الرقائق',
          value: theme.chipRadius,
          onChanged: (value) => _patchNumber(ref, store, 'radius', 'chip', value, log),
        ),
        _NumberRow(
          label: 'زوايا الورقة',
          value: theme.sheetRadius,
          onChanged: (value) => _patchNumber(ref, store, 'radius', 'sheet', value, log),
        ),
        for (final entry in theme.spacing.entries)
          _NumberRow(
            label: 'تباعد ${entry.key}',
            value: entry.value,
            onChanged: (value) =>
                _patchNumber(ref, store, 'spacing', entry.key, value, log),
          ),
        const SizedBox(height: 16),
        const _SectionHeader(title: 'الشبكة'),
        _NumberRow(
          label: 'عدد الأعمدة',
          value: theme.grid['columns'] ?? 4,
          onChanged: (value) =>
              _patchNumber(ref, store, 'grid', 'columns', value, log),
        ),
        _NumberRow(
          label: 'نسبة التباعد',
          value: theme.grid['gutter'] ?? 0.35,
          onChanged: (value) =>
              _patchNumber(ref, store, 'grid', 'gutter', value, log),
        ),
        _NumberRow(
          label: 'الحشو الجانبي',
          value: theme.grid['sidePadding'] ?? 16,
          onChanged: (value) =>
              _patchNumber(ref, store, 'grid', 'sidePadding', value, log),
        ),
        _NumberRow(
          label: 'نسبة البلاطة',
          value: theme.grid['tileAspect'] ?? 1,
          onChanged: (value) =>
              _patchNumber(ref, store, 'grid', 'tileAspect', value, log),
        ),
      ],
    );
  }

  static void _patchNumber(
    WidgetRef ref,
    dynamic store,
    String group,
    String key,
    double value,
    DevLogController log,
  ) {
    store.applyPatch(UIPatch(tokens: <String, dynamic>{
      group: <String, double>{key: value},
    }));
    log.add('$group.$key → $value');
  }

  Future<void> _export(
      BuildContext context, WidgetRef ref, String format) async {
    final theme = ref.read(uiThemeProvider);
    final contents = switch (format) {
      'css' => _toCss(theme),
      'ts' => _toTs(theme),
      _ => const JsonEncoder.withIndent('  ').convert(theme.toJson()),
    };
    final extension = switch (format) {
      'css' => 'css',
      'ts' => 'ts',
      _ => 'json',
    };
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/tokens.$extension');
      await file.writeAsString(contents);
      await Clipboard.setData(ClipboardData(text: contents));
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('حُفظ الملف tokens.$extension ونُسخت محتوياته.')),
      );
    } catch (_) {
      if (!context.mounted) return;
      await Clipboard.setData(ClipboardData(text: contents));
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر الحفظ على القرص؛ نُسخت المحتويات.')),
      );
    }
  }

  static String _toCss(UITheme theme) {
    final buffer = StringBuffer(':root {\n');
    theme.colors.forEach((key, value) {
      buffer.write('  --$key: $value;\n');
    });
    theme.typography.forEach((key, value) {
      buffer.write('  --font-$key: ${value.size}px;\n');
      buffer.write('  --font-$key-weight: ${value.weight};\n');
      buffer.write('  --font-$key-line: ${value.lineHeight};\n');
    });
    theme.radius.forEach((key, value) {
      buffer.write('  --radius-$key: ${value}px;\n');
    });
    theme.spacing.forEach((key, value) {
      buffer.write('  --space-$key: ${value}px;\n');
    });
    buffer.write('}\n');
    return buffer.toString();
  }

  static String _toTs(UITheme theme) {
    final buffer = StringBuffer('export const tokens = ')
      ..write(const JsonEncoder.withIndent('  ').convert(theme.toJson()))
      ..write(' as const;\n');
    return buffer.toString();
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 6, 4, 8),
      child: Row(
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          const Spacer(),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

class _ColorRow extends StatefulWidget {
  const _ColorRow({
    required this.name,
    required this.value,
    required this.onChanged,
  });

  final String name;
  final String value;
  final ValueChanged<String> onChanged;

  @override
  State<_ColorRow> createState() => _ColorRowState();
}

class _ColorRowState extends State<_ColorRow> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.value);

  @override
  void didUpdateWidget(covariant _ColorRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      _controller.text = widget.value;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hex = widget.value.replaceFirst('#', '');
    final parsed = int.tryParse(hex, radix: 16);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: parsed == null
                  ? Colors.transparent
                  : Color(0xFF000000 | parsed),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white24),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 96,
            child: Text(
              widget.name,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ),
          Expanded(
            child: TextField(
              controller: _controller,
              style: const TextStyle(color: Colors.white, fontSize: 12),
              onSubmitted: widget.onChanged,
              decoration: const InputDecoration(
                isDense: true,
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              ),
            ),
          ),
          IconButton(
            tooltip: 'تطبيق',
            onPressed: () => widget.onChanged(_controller.text.trim()),
            icon: const Icon(Icons.check_rounded, size: 18, color: Colors.white70),
          ),
        ],
      ),
    );
  }
}

class _TypeRow extends StatelessWidget {
  const _TypeRow({
    required this.name,
    required this.spec,
    required this.onChanged,
  });

  final String name;
  final TypographySpec spec;
  final ValueChanged<TypographySpec> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 96,
            child: Text(
              name,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${spec.size.toStringAsFixed(0)} / ${spec.weight}',
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                ),
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 3,
                    thumbShape:
                        const RoundSliderThumbShape(enabledThumbRadius: 7),
                  ),
                  child: Slider(
                    value: spec.size,
                    min: 9,
                    max: 34,
                    onChanged: (value) => onChanged(
                      spec.copyWith(size: value),
                    ),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'أثقل',
            onPressed: () => onChanged(
              spec.copyWith(weight: spec.weight >= 700 ? 400 : spec.weight + 100),
            ),
            icon: const Icon(Icons.format_bold_rounded,
                size: 18, color: Colors.white70),
          ),
        ],
      ),
    );
  }
}

class _NumberRow extends StatefulWidget {
  const _NumberRow({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final double value;
  final ValueChanged<double> onChanged;

  @override
  State<_NumberRow> createState() => _NumberRowState();
}

class _NumberRowState extends State<_NumberRow> {
  late double _value = widget.value;

  @override
  void didUpdateWidget(covariant _NumberRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) _value = widget.value;
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 130,
          child: Text(
            widget.label,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ),
        Expanded(
          child: Slider(
            value: _value.clamp(0, 40),
            max: 40,
            onChanged: (value) {
              setState(() => _value = value);
              widget.onChanged(value);
            },
          ),
        ),
        SizedBox(
          width: 46,
          child: Text(
            _value.toStringAsFixed(1),
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontSize: 12),
          ),
        ),
      ],
    );
  }
}
