import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../dev_panel_screen.dart';

/// Font manager: the bundled families, a live preview and an uploader that
/// registers a new family at runtime with [ui.FontLoader].
class FontsTab extends ConsumerStatefulWidget {
  const FontsTab({super.key, required this.log});

  final DevLogController log;

  @override
  ConsumerState<FontsTab> createState() => _FontsTabState();
}

class _FontsTabState extends ConsumerState<FontsTab> {
  static const List<({String family, String label})> _bundled =
      <({String family, String label})>[
    (family: 'NotoNaskhArabicUI', label: 'نسخ عربي'),
    (family: 'NotoKufiArabic', label: 'كوفي عربي'),
    (family: 'Tajawal', label: 'Tajawal'),
    (family: 'IBMPlexSansArabic', label: 'IBM Plex Sans Arabic'),
    (family: 'GeezaArabic', label: 'Geeza'),
    (family: 'BeINArabic', label: 'beIN Arabic'),
    (family: 'AlanSansLight', label: 'Alan Sans'),
    (family: 'AmiriQuran', label: 'Amiri (المصحف)'),
  ];

  final List<({String family, String label, String path})> _uploaded =
      <({String family, String label, String path})>[];
  String _preview = 'بسم الله الرحمن الرحيم';
  double _previewSize = 22;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF2A2A2A),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _preview,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: _previewSize,
                  height: 1.7,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                onChanged: (value) => setState(() => _preview = value),
                style: const TextStyle(color: Colors.white, fontSize: 12),
                decoration: const InputDecoration(
                  labelText: 'نص المعاينة',
                  labelStyle: TextStyle(color: Colors.white54),
                  isDense: true,
                ),
              ),
              Row(
                children: [
                  const Text('الحجم',
                      style: TextStyle(color: Colors.white70, fontSize: 12)),
                  Expanded(
                    child: Slider(
                      value: _previewSize,
                      min: 12,
                      max: 44,
                      onChanged: (value) => setState(() => _previewSize = value),
                    ),
                  ),
                  Text(_previewSize.toStringAsFixed(0),
                      style: const TextStyle(color: Colors.white)),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        OutlinedButton.icon(
          onPressed: _uploadFont,
          icon: const Icon(Icons.font_download_rounded, size: 18),
          label: const Text('رفع خط TTF / OTF'),
        ),
        const SizedBox(height: 14),
        const Text(
          'الخطوط المضمّنة',
          style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        for (final entry in _bundled)
          _FontRow(
            label: entry.label,
            family: entry.family,
            preview: _preview,
            size: _previewSize,
            onApply: () {
              widget.log.add('تجربة خط ${entry.label}');
              setState(() {});
            },
          ),
        if (_uploaded.isNotEmpty) ...[
          const SizedBox(height: 14),
          const Text(
            'خطوط مرفوعة',
            style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          for (final entry in _uploaded)
            _FontRow(
              label: entry.label,
              family: entry.family,
              preview: _preview,
              size: _previewSize,
              onApply: () => widget.log.add('تجربة خط ${entry.label}'),
            ),
        ],
      ],
    );
  }

  Future<void> _uploadFont() async {
    final result = await FilePicker.platform.pickFiles(
      withData: true,
      type: FileType.custom,
      allowedExtensions: const ['ttf', 'otf'],
    );
    if (result == null || result.files.isEmpty) return;
    final bytes = result.files.first.bytes;
    if (bytes == null) return;
    final family = 'KhazainUploaded${DateTime.now().millisecondsSinceEpoch}';
    try {
      final loader = FontLoader(family)
        ..addFont(Future<ByteData>.value(ByteData.sublistView(bytes)));
      await loader.load();
      final directory = await getApplicationDocumentsDirectory();
      final fontDirectory = Directory('${directory.path}/fonts');
      await fontDirectory.create(recursive: true);
      final file = File('${fontDirectory.path}/${result.files.first.name}');
      await file.writeAsBytes(bytes);
      if (!mounted) return;
      setState(() {
        _uploaded.add((
          family: family,
          label: result.files.first.name,
          path: file.path,
        ));
      });
      widget.log.add('رفع خط ${result.files.first.name}');
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر تسجيل الخط. تأكد أنه ملف TTF أو OTF صالح.')),
      );
    }
  }
}

class _FontRow extends StatelessWidget {
  const _FontRow({
    required this.label,
    required this.family,
    required this.preview,
    required this.size,
    required this.onApply,
  });

  final String label;
  final String family;
  final String preview;
  final double size;
  final VoidCallback onApply;

  @override
  Widget build(BuildContext context) {
    return Container(
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
                  label,
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
                Text(
                  preview,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: size * 0.7,
                    fontFamily: family,
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: onApply,
            child: Text(
              'معاينة',
              style: TextStyle(fontFamily: family, color: const Color(0xFFBC9551)),
            ),
          ),
        ],
      ),
    );
  }
}
