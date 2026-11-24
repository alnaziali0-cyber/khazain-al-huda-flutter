import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../design/theme_provider.dart';
import '../../design/tokens/app_tokens.dart';
import '../../icons/khazain_icons.dart';
import '../store.dart';

/// The audit report: missing icons, duplicated titles, placeholder copy,
/// contrast ratios and grid overflow maths — with an auto-fix action.
class AuditTab extends ConsumerWidget {
  const AuditTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(uiThemeProvider);
    final state = ref.watch(devStoreProvider);
    final store = ref.read(devStoreProvider.notifier);

    final issues = <_Issue>[];

    // 1. Sections pointing at an unknown icon.
    for (final section in state.sections) {
      if (khazainIconById(section.iconId) == null &&
          !state.icons.any((icon) => icon.id == section.iconId)) {
        issues.add(_Issue(
          kind: 'أيقونة مفقودة',
          detail: 'القسم «${section.title}» يشير إلى أيقونة غير معروفة (${section.iconId}).',
          severity: _Severity.error,
        ));
      }
      if (section.title.trim().isEmpty) {
        issues.add(_Issue(
          kind: 'عنوان فارغ',
          detail: 'القسم ${section.id} بلا عنوان.',
          severity: _Severity.error,
        ));
      }
      if (section.route.trim().isEmpty) {
        issues.add(_Issue(
          kind: 'مسار فارغ',
          detail: 'القسم «${section.title}» بلا مسار.',
          severity: _Severity.warning,
        ));
      }
    }

    // 2. Duplicated section titles.
    final seen = <String, int>{};
    for (final section in state.sections) {
      seen[section.title] = (seen[section.title] ?? 0) + 1;
    }
    for (final entry in seen.entries) {
      if (entry.value > 1) {
        issues.add(_Issue(
          kind: 'عنوان مكرر',
          detail: 'العنوان «${entry.key}» مستخدم في ${entry.value} أقسام.',
          severity: _Severity.warning,
        ));
      }
    }

    // 3. Placeholder copy in the string overrides.
    const markers = ['TODO', 'Lorem', 'placeholder', 'coming soon', 'قريباً'];
    for (final entry in state.strings.entries) {
      for (final marker in markers) {
        if (entry.value.toLowerCase().contains(marker.toLowerCase())) {
          issues.add(_Issue(
            kind: 'نص بديل',
            detail: 'النص «${entry.key}» يحتوي على «$marker».',
            severity: _Severity.warning,
          ));
          break;
        }
      }
    }

    // 4. Contrast of the main token pairs (WCAG AA = 4.5:1).
    for (final pair in const [
      ('textPrimary', 'bgApp'),
      ('textSecondary', 'bgApp'),
      ('textMuted', 'bgApp'),
      ('gold', 'bgApp'),
      ('goldBright', 'bgApp'),
      ('textOnTile', 'tileBg'),
    ]) {
      final ratio = _contrast(theme.color(pair.$1), theme.color(pair.$2));
      if (ratio < 4.5) {
        issues.add(_Issue(
          kind: 'تباين ضعيف',
          detail:
              '${pair.$1} على ${pair.$2} = ${ratio.toStringAsFixed(2)}:1 (المطلوب 4.5:1).',
          severity: ratio < 3 ? _Severity.error : _Severity.warning,
        ));
      }
    }

    // 5. Grid overflow maths at the reference widths.
    for (final width in const [320.0, 360.0, 412.0, 768.0, 1024.0]) {
      final columns = KhazainGrid.columnsFor(width);
      final tile = KhazainGrid.tileSizeFor(width, columns);
      if (tile < 44) {
        issues.add(_Issue(
          kind: 'تجاوز في الشبكة',
          detail:
              'العرض ${width.toStringAsFixed(0)}dp يعطي بلاطة ${tile.toStringAsFixed(1)}dp (أقل من 44dp).',
          severity: _Severity.warning,
        ));
      }
    }

    final autoFixable = issues
        .where((issue) => issue.kind == 'أيقونة مفقودة' || issue.kind == 'عنوان فارغ')
        .length;

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: issues.isEmpty ? const Color(0xFF1F3A2E) : const Color(0xFF3A2A1F),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              Icon(
                issues.isEmpty ? Icons.check_circle_rounded : Icons.report_rounded,
                color: issues.isEmpty ? const Color(0xFF2FA36B) : const Color(0xFFBC9551),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  issues.isEmpty
                      ? 'لا توجد ملاحظات. الفحص يغطي الأيقونات والعناوين والنصوص البديلة والتباين وشبكة الأقسام.'
                      : '${issues.length} ملاحظة: ${issues.where((i) => i.severity == _Severity.error).length} خطأ و${issues.where((i) => i.severity == _Severity.warning).length} تحذير.',
                  style: const TextStyle(color: Colors.white, fontSize: 12, height: 1.6),
                ),
              ),
            ],
          ),
        ),
        if (autoFixable > 0) ...[
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: () {
              final broken = state.sections
                  .where((section) =>
                      khazainIconById(section.iconId) == null &&
                      !state.icons.any((icon) => icon.id == section.iconId))
                  .map((section) => section.id)
                  .toSet();
              final fixed = state.sections
                  .where((section) => !broken.contains(section.id))
                  .toList(growable: false);
              store.replace(state.copyWith(sections: fixed));
            },
            icon: const Icon(Icons.auto_fix_high_rounded, size: 18),
            label: Text('إصلاح تلقائي ($autoFixable)'),
          ),
        ],
        const SizedBox(height: 12),
        for (final issue in issues)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF2A2A2A),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: issue.severity == _Severity.error
                    ? const Color(0xFFE5484D)
                    : const Color(0xFFBC9551),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  issue.kind,
                  style: TextStyle(
                    color: issue.severity == _Severity.error
                        ? const Color(0xFFE5484D)
                        : const Color(0xFFBC9551),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  issue.detail,
                  style: const TextStyle(color: Colors.white70, fontSize: 12, height: 1.5),
                ),
              ],
            ),
          ),
      ],
    );
  }

  /// Relative luminance contrast ratio between two opaque colours.
  static double _contrast(Color a, Color b) {
    final la = _luminance(a);
    final lb = _luminance(b);
    final lighter = la > lb ? la : lb;
    final darker = la > lb ? lb : la;
    return (lighter + 0.05) / (darker + 0.05);
  }

  static double _luminance(Color color) {
    double channel(double value) {
      final normalised = value / 255;
      return normalised <= 0.03928
          ? normalised / 12.92
          : math.pow((normalised + 0.055) / 1.055, 2.4).toDouble();
    }

    final r = channel(color.r * 255);
    final g = channel(color.g * 255);
    final b = channel(color.b * 255);
    return 0.2126 * r + 0.7152 * g + 0.0722 * b;
  }
}

class _Issue {
  const _Issue({
    required this.kind,
    required this.detail,
    required this.severity,
  });

  final String kind;
  final String detail;
  final _Severity severity;
}

enum _Severity { warning, error }
