import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_preferences.dart';
import '../../core/providers.dart';
import '../../design/theme_provider.dart';
import '../models.dart';
import '../store.dart';

/// Theme tab: dark / light / system, font scale, the RTL-LTR debug switch,
/// the diacritics switch and the accent colour.
class ThemeTab extends ConsumerWidget {
  const ThemeTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(uiThemeProvider);
    final mode = ref.watch(themeModeProvider);
    final prefs = ref.watch(appPreferencesProvider);
    final store = ref.read(devStoreProvider.notifier);
    final direction = ref.watch(devStoreProvider).direction;

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
      children: [
        const _Label('وضع العرض'),
        for (final entry in const [
          (ThemeMode.system, 'تلقائي', 'يتبع إعداد الجهاز'),
          (ThemeMode.dark, 'داكن', 'الوضع الأساسي للتطبيق'),
          (ThemeMode.light, 'فاتح', 'نسخة فاتحة للمAccessibility'),
        ])
          RadioListTile<ThemeMode>(
            value: entry.$1,
            groupValue: mode,
            onChanged: (value) {
              if (value != null) {
                ref.read(themeModeProvider.notifier).setMode(value);
              }
            },
            title: Text(entry.$2, style: const TextStyle(color: Colors.white)),
            subtitle: Text(entry.$3,
                style: const TextStyle(color: Colors.white54, fontSize: 11)),
            activeColor: const Color(0xFFBC9551),
          ),
        const SizedBox(height: 10),
        const _Label('حجم الخط'),
        Row(
          children: [
            Expanded(
              child: Slider(
                value: prefs.textSize.factor,
                min: 0.85,
                max: 1.3,
                divisions: 4,
                label: prefs.textSize.labelAr,
                onChanged: (value) {
                  final closest = AppTextSize.values.reduce((a, b) =>
                      (a.factor - value).abs() <= (b.factor - value).abs()
                          ? a
                          : b);
                  ref.read(appPreferencesProvider.notifier).setTextSize(closest);
                },
              ),
            ),
            Text(prefs.textSize.labelAr,
                style: const TextStyle(color: Colors.white, fontSize: 12)),
          ],
        ),
        const SizedBox(height: 10),
        const _Label('اتجاه الواجهة (تشخيص)'),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'rtl', label: Text('RTL')),
            ButtonSegment(value: 'ltr', label: Text('LTR')),
          ],
          selected: <String>{direction},
          onSelectionChanged: (values) {
            store.replace(
              ref.read(devStoreProvider).copyWith(direction: values.first),
            );
          },
        ),
        const SizedBox(height: 10),
        const _Label('لون التمييز'),
        Wrap(
          spacing: 10,
          children: [
            for (final entry in const [
              ('gold', '#BC9551'),
              ('green', '#174940'),
              ('greenActive', '#177737'),
              ('goldBright', '#FDE104'),
            ])
              _Swatch(
                label: entry.$1,
                hex: entry.$2,
                selected: theme.colors[entry.$1]?.toUpperCase() == entry.$2,
                onTap: () => store.applyPatch(UIPatch(tokens: <String, dynamic>{
                  'colors': <String, String>{entry.$1: entry.$2},
                })),
              ),
          ],
        ),
        const SizedBox(height: 18),
        SwitchListTile(
          value: prefs.showDiacritics,
          onChanged: (value) =>
              ref.read(appPreferencesProvider.notifier).setShowDiacritics(value),
          title: const Text('إظهار التشكيل في النصوص الخطية',
              style: TextStyle(color: Colors.white)),
          subtitle: const Text('يمكن إخفاؤه دون تغيير حجم الخط',
              style: TextStyle(color: Colors.white54, fontSize: 11)),
          activeColor: const Color(0xFFBC9551),
        ),
        const _Label('حجم النص الخطي'),
        Row(
          children: [
            Expanded(
              child: Slider(
                value: prefs.calligraphicScale,
                min: 0.8,
                max: 1.6,
                divisions: 8,
                onChanged: (value) => ref
                    .read(appPreferencesProvider.notifier)
                    .setCalligraphicScale(value),
              ),
            ),
            Text(prefs.calligraphicScale.toStringAsFixed(2),
                style: const TextStyle(color: Colors.white, fontSize: 12)),
          ],
        ),
      ],
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 12, 4, 4),
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

class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.label,
    required this.hex,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String hex;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final value = int.tryParse(hex.replaceFirst('#', ''), radix: 16) ?? 0;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 62,
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: Color(0xFF000000 | value),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? const Color(0xFFBC9551) : Colors.white24,
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            Text(
              label,
              style: const TextStyle(color: Colors.white, fontSize: 9),
            ),
          ],
        ),
      ),
    );
  }
}
