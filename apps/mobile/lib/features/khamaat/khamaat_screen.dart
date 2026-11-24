import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';

import '../../components/app_card.dart';
import '../../components/app_text.dart';
import '../../components/khazain_icon.dart';
import '../../components/state_view.dart';
import '../../design/theme_provider.dart';

/// "الخمات" — the five from the Ahl al-Bayt, read from the bundled offline
/// biographies with their source data preserved.
class KhamaatScreen extends ConsumerWidget {
  const KhamaatScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(uiThemeProvider);
    final entries = ref.watch(_biographiesProvider);

    return Container(
      color: theme.color('bgApp'),
      child: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
          children: [
            AppText('الخمسة الطاهرون', token: 'display'),
            const SizedBox(height: 4),
            AppText(
              'سيرة الخمسة الطاهرين من ملف السيرة المحفوظ على الجهاز.',
              token: 'bodyDim',
              color: theme.color('textMuted'),
            ),
            const SizedBox(height: 16),
            entries.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (_, __) => StateView(
                icon: const Icon(Icons.cloud_off_rounded),
                message: 'تعذر تحميل ملف السيرة.',
                actionLabel: 'إعادة المحاولة',
                onAction: () => ref.invalidate(_biographiesProvider),
              ),
              data: (list) {
                if (list.isEmpty) {
                  return const StateView(
                    icon: Icon(Icons.groups_rounded),
                    message: 'لا توجد بيانات سيرة في الجهاز.',
                  );
                }
                return Column(
                  children: [
                    for (final entry in list)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _BiographyCard(entry: entry),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _BiographyCard extends ConsumerWidget {
  const _BiographyCard({required this.entry});

  final Map<String, dynamic> entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(uiThemeProvider);
    final titles = (entry['titles'] as String? ?? '').trim();
    return KzSurface(
      level: 1,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              KhazainIcon('khamat', size: 26),
              const SizedBox(width: 10),
              Expanded(
                child: AppText(
                  (entry['name_ar'] as String? ?? '').trim(),
                  token: 'h2',
                  maxLines: 2,
                ),
              ),
            ],
          ),
          if (titles.isNotEmpty) ...[
            const SizedBox(height: 6),
            AppText(
              titles,
              token: 'body',
              color: theme.color('gold'),
            ),
          ],
          const SizedBox(height: 10),
          _Line(label: 'الميلاد', value: entry['birth_hijri']),
          _Line(label: 'الوفاة', value: entry['death_hijri']),
          _Line(label: 'الميلاد', value: entry['birth_place']),
          _Line(label: 'الدفن', value: entry['burial']),
          _Line(label: 'الأم', value: entry['mother']),
        ],
      ),
    );
  }
}

class _Line extends ConsumerWidget {
  const _Line({required this.label, required this.value});

  final String label;
  final Object? value;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(uiThemeProvider);
    final text = (value?.toString() ?? '').trim();
    if (text.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 60,
            child: AppText(
              label,
              token: 'label',
              color: theme.color('textMuted'),
            ),
          ),
          Expanded(
            child: AppText(text, token: 'body', color: theme.color('textSecondary')),
          ),
        ],
      ),
    );
  }
}

final _biographiesProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final raw = await rootBundle.loadString(
    'assets/data/ahl_al_bayt_biographies.json',
  );
  final decoded = jsonDecode(raw);
  if (decoded is! List) return const <Map<String, dynamic>>[];
  return decoded
      .whereType<Map>()
      .map((item) => item.cast<String, dynamic>())
      .toList(growable: false);
});
