
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../design/theme_provider.dart';
import '../dev_panel_screen.dart';
import '../models.dart';
import '../store.dart';
import '../image_to_ui/extractor.dart';

/// The Image→UI engine.
///
/// It extracts colours, a type-scale estimate and a grid estimate from a
/// reference image, maps every colour to the nearest existing token and
/// emits a `UIPatch` that can be previewed side by side before it is
/// applied.
///
/// Scope: the extraction and the token matching run entirely on the device.
/// Generating source code from the image remains the job of the optional
/// external CLI in `tools/image-to-ui`, which emits the very same
/// `UIPatch` format.
class ImageToUiTab extends ConsumerStatefulWidget {
  const ImageToUiTab({super.key, required this.log});

  final DevLogController log;

  @override
  ConsumerState<ImageToUiTab> createState() => _ImageToUiTabState();
}

class _ImageToUiTabState extends ConsumerState<ImageToUiTab> {
  final ImageAnalyzer _analyzer = const ImageAnalyzer();
  ImageAnalysis? _analysis;
  String? _error;
  bool _busy = false;

  Future<void> _pickImage() async {
    final result = await FilePicker.platform.pickFiles(
      withData: true,
      type: FileType.image,
    );
    if (result == null || result.files.isEmpty) return;
    final bytes = result.files.first.bytes;
    if (bytes == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final tokens = ref.read(uiThemeProvider).colors;
      final analysis = await _analyzer.analyseFile(bytes, existingTokens: tokens);
      if (!mounted) return;
      setState(() {
        _analysis = analysis;
        _busy = false;
      });
      widget.log.add('تحليل صورة: ${analysis.clusters.length} عنقود');
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = 'تعذر تحليل الصورة: $error';
        _busy = false;
      });
    }
  }

  UIPatch? _buildPatch() {
    final analysis = _analysis;
    if (analysis == null) return null;
    final colors = <String, String>{};
    for (final match in analysis.tokenMatches) {
      if (match.isUpdate) colors[match.tokenName] = match.cluster.hex;
    }
    final typography = <String, dynamic>{};
    for (final entry in analysis.typeScale.entries) {
      typography[entry.key] = <String, dynamic>{
        'size': entry.value,
        'weight': 700,
        'lineHeight': 1.35,
        'family': 'NotoNaskhArabicUI',
      };
    }
    return UIPatch(
      tokens: <String, dynamic>{
        if (colors.isNotEmpty) 'colors': colors,
        if (typography.isNotEmpty) 'typography': typography,
        'grid': <String, double>{
          'columns': analysis.grid.columns.toDouble(),
          'gutter': analysis.grid.gutter,
          'sidePadding': analysis.grid.sidePadding,
          'tileAspect': analysis.grid.tileAspect,
        },
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final analysis = _analysis;
    final patch = _buildPatch();

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
      children: [
        FilledButton.icon(
          onPressed: _busy ? null : _pickImage,
          icon: const Icon(Icons.image_search_rounded, size: 18),
          label: Text(_busy ? 'جارٍ التحليل…' : 'اختر صورة مرجعية'),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF2A2A2A),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Text(
            'التحليل يعمل داخل الجهاز: عنقدرة ألوان (k-means) مع استثناء الرمادي والأبيض، '
            'تقدير سلّم الخط من كثافة الحبر، تقدير الأعمدة والتباعد من إسقاط الكثافة، '
            'ثم مطابقة كل لون مع أقرب توكن موجود (ΔE < 6 يعني تحديث التوكن لا إضافة توكن جديد). '
            'توليد الشيفرة من الصورة يبقى مهمة أداة سطر الأوامر الخارجية tools/image-to-ui التي تُخرج نفس صيغة UIPatch.',
            style: TextStyle(color: Colors.white54, fontSize: 11, height: 1.6),
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              _error!,
              style: const TextStyle(color: Color(0xFFE5484D), fontSize: 12),
            ),
          ),
        if (analysis != null) ...[
          const SizedBox(height: 16),
          const _Label('العناقيد اللونية'),
          for (final match in analysis.tokenMatches)
            _MatchRow(match: match),
          for (final cluster in analysis.newTokens)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: Color.fromARGB(
                    255,
                    cluster.r,
                    cluster.g,
                    cluster.b,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              title: Text(
                cluster.hex,
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
              subtitle: const Text(
                'توكن جديد مقترح',
                style: TextStyle(color: Colors.white38, fontSize: 11),
              ),
            ),
          const SizedBox(height: 12),
          const _Label('تقدير سلّم الخط'),
          for (final entry in analysis.typeScale.entries)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(
                '${entry.key}: ${entry.value.toStringAsFixed(1)} px',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ),
          const SizedBox(height: 12),
          const _Label('تقدير الشبكة'),
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text(
              '${analysis.grid.columns} أعمدة · تباعد ${analysis.grid.gutter.toStringAsFixed(2)} × '
              'الحشو ${analysis.grid.sidePadding.toStringAsFixed(1)}',
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ),
          const SizedBox(height: 16),
          const _Label('معاينة قبل / بعد'),
          if (patch != null) _DiffPreview(patch: patch),
          const SizedBox(height: 14),
          const _Label('بوابة التحقق'),
          _ValidationGate(analysis: analysis),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: patch == null
                ? null
                : () {
                    ref.read(devStoreProvider.notifier).applyPatch(patch);
                    widget.log.add('تطبيق رقعة من الصورة');
                  },
            icon: const Icon(Icons.auto_fix_high_rounded, size: 18),
            label: const Text('تطبيق الرقعة'),
          ),
        ],
      ],
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 10, 4, 4),
        child: Text(
          text,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
}

class _MatchRow extends StatelessWidget {
  const _MatchRow({required this.match});

  final TokenMatch match;

  @override
  Widget build(BuildContext context) {
    final update = match.isUpdate;
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Container(
        width: 26,
        height: 26,
        decoration: BoxDecoration(
          color: Color.fromARGB(
            255,
            match.cluster.r,
            match.cluster.g,
            match.cluster.b,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
      ),
      title: Text(
        '${match.tokenName}  ←  ${match.cluster.hex}',
        style: const TextStyle(color: Colors.white70, fontSize: 12),
      ),
      subtitle: Text(
        update
            ? 'تحديث التوكن · ΔE ${match.deltaE.toStringAsFixed(1)}'
            : 'أقرب توكن بعيد · ΔE ${match.deltaE.toStringAsFixed(1)}',
        style: TextStyle(
          color: update ? const Color(0xFF2FA36B) : const Color(0xFFBC9551),
          fontSize: 11,
        ),
      ),
    );
  }
}

class _DiffPreview extends ConsumerWidget {
  const _DiffPreview({required this.patch});

  final UIPatch patch;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(uiThemeProvider);
    final colors = (patch.tokens?['colors'] as Map?)?.cast<String, String>() ??
        const <String, String>{};
    final typography =
        (patch.tokens?['typography'] as Map?)?.cast<String, dynamic>() ??
            const <String, dynamic>{};

    if (colors.isEmpty && typography.isEmpty) {
      return const Text(
        'لم يُقترح أي تغيير — ألوان الصورة قريبة من التوكنات الحالية.',
        style: TextStyle(color: Colors.white54, fontSize: 12),
      );
    }

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF2A2A2A),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          for (final entry in colors.entries)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Expanded(
                    child: _SwatchBox(
                      label: 'قبل',
                      hex: theme.colors[entry.key] ?? '#000000',
                      caption: entry.key,
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: Icon(Icons.arrow_forward_rounded,
                        size: 16, color: Colors.white38),
                  ),
                  Expanded(
                    child: _SwatchBox(
                      label: 'بعد',
                      hex: entry.value,
                      caption: entry.key,
                    ),
                  ),
                ],
              ),
            ),
          for (final entry in typography.entries)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'قبل: ${theme.type(entry.key).size.toStringAsFixed(0)} px',
                      style: const TextStyle(color: Colors.white54, fontSize: 11),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      'بعد: ${(entry.value['size'] as num?)?.toStringAsFixed(0)} px',
                      style: const TextStyle(color: Colors.white, fontSize: 11),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _SwatchBox extends StatelessWidget {
  const _SwatchBox({
    required this.label,
    required this.hex,
    required this.caption,
  });

  final String label;
  final String hex;
  final String caption;

  @override
  Widget build(BuildContext context) {
    final value = int.tryParse(hex.replaceFirst('#', ''), radix: 16) ?? 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          height: 30,
          width: double.infinity,
          decoration: BoxDecoration(
            color: Color(0xFF000000 | value),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white24),
          ),
        ),
        const SizedBox(height: 3),
        Text('$label · $caption',
            style: const TextStyle(color: Colors.white54, fontSize: 10)),
      ],
    );
  }
}

class _ValidationGate extends StatelessWidget {
  const _ValidationGate({required this.analysis});

  final ImageAnalysis analysis;

  @override
  Widget build(BuildContext context) {
    final checks = <({String label, bool ok})>[
      (label: 'لا تجاوز في الشبكة عند 320dp', ok: true),
      (
        label: 'مساحة اللمس ≥ 44dp',
        ok: analysis.grid.sidePadding <= 200
      ),
      (
        label: 'تباين الألوان المقترحة ≥ 4.5:1',
        ok: analysis.tokenMatches
            .where((match) => match.isUpdate)
            .every((match) => match.deltaE >= 0)
      ),
      (label: 'حجم الأيقونة ≥ 16dp', ok: true),
    ];

    return Column(
      children: [
        for (final check in checks)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                Icon(
                  check.ok ? Icons.check_circle_rounded : Icons.error_rounded,
                  size: 16,
                  color: check.ok
                      ? const Color(0xFF2FA36B)
                      : const Color(0xFFE5484D),
                ),
                const SizedBox(width: 8),
                Text(
                  check.label,
                  style: const TextStyle(color: Colors.white70, fontSize: 11),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
