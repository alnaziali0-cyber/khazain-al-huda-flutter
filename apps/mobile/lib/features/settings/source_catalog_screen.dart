import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models.dart';
import '../../core/providers.dart';
import '../../core/safe_display_text.dart';

class SourceCatalogScreen extends ConsumerWidget {
  const SourceCatalogScreen({super.key});

  String _category(String value) => switch (value) {
        'radio' => 'إذاعة',
        'quran_audio' => 'صوتيات قرآنية',
        'organization_media' => 'جهة إعلامية',
        'prayer_times_reference' => 'مرجع مواقيت',
        'geographic_data' => 'بيانات جغرافية',
        'shia_library' => 'مكتبة إسلامية شيعية',
        'shia_hadith_library' => 'مصدر روايات وحديث',
        'shia_audio_library' => 'مكتبة صوتية شيعية',
        'api_integration' => 'تكامل واجهة برمجية',
        'shia_research_library' => 'مكتبة بحثية شيعية',
        'telegram_library' => 'قناة كتب تيليجرام',
        'hadith_translation' => 'ترجمات أحاديث نبوية',
        'quran_translation' => 'ترجمات معاني القرآن',
        'quran_text' => 'نص المصحف',
        'quran_font' => 'خط قرآني',
        'islamic_text_corpus' => 'مدونة تراثية',
        'quran_audio_dataset' => 'مجموعة صوتية بحثية',
        _ => value,
      };

  String _license(String value) => switch (value) {
        'not_granted_contact_required' => 'لم تُمنح صلاحية الاستخدام',
        'reference_only_permission_for_reuse_unconfirmed' =>
          'مرجع فقط؛ إذن إعادة الاستخدام غير مثبت',
        'unverified_channel_identity' => 'القناة غير متحققة',
        'check_data_license_before_redistribution' =>
          'تحقق من الترخيص قبل إعادة التوزيع',
        'non_commercial_permission_required' => 'غير تجاري وبإذن أصحاب الحقوق',
        'approved' => 'موافق عليه',
        'cc_by_3_0_verbatim_no_changes' => 'CC BY 3.0 · نقل حرفي دون تعديل',
        'sil_ofl_1_1_bundled_with_notice' =>
          'SIL OFL 1.1 · توزيع مع إشعار الرخصة',
        'cc_by_nc_sa_4_0_noncommercial_item_review_required' =>
          'CC BY-NC-SA 4.0 · غير تجاري ومراجعة كل مادة',
        'cc0_1_0_declared_source_provenance_review_required' =>
          'CC0 1.0 معلن · تدقيق أصل التسجيل مطلوب',
        'cc_by_4_0_quranws_with_kfgqpc_software_terms' =>
          'CC BY 4.0 · شروط مجمع الملك فهد للنسخة الرقمية',
        'redistribution_allowed_with_publisher_conditions' =>
          'إعادة نشر مسموحة بشروط الناشر ومراجعة كل ترجمة',
        'redistribution_allowed_with_publisher_conditions_review_required' =>
          'إعادة نشر مشروطة؛ الإصدار والمراجعة مطلوبان',
        'api_streaming_only_rights_review_required' =>
          'تشغيل من المصدر فقط؛ حقوق التسجيلات تحتاج مراجعة',
        'item_level_license_review_required' =>
          'مراجعة ترخيص كل عنصر على حدة',
        'user_supplied_export_rights_unverified' =>
          'تصدير يقدمه المستخدم؛ الحقوق غير متحققة',
        _ => 'الحالة غير محددة',
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sources = ref.watch(sourceCatalogProvider);
    final theme = Theme.of(context);
    return CustomScrollView(slivers: [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 32),
        sliver: SliverList(
          delegate: SliverChildListDelegate([
            Text('المصادر والتوثيق',
                style: theme.textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w900)),
            const SizedBox(height: 10),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(15),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'مكتبة خزائن الهدى النصية المحلية',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 7),
                    const Text(
                      'تضم 103 مواد نصية تعمل دون اتصال. المواد التحريرية الأصلية مرخصة وفق CC BY 4.0 مع الإسناد إلى خزائن الهدى، ومقتطفات ويكي مصدر وفق CC BY-SA 4.0 مع الإسناد والمشاركة بالمثل. تظهر بيانات المصدر والرخصة داخل كل مادة، وتفاصيلها محفوظة في مجلد المكتبة.',
                      style: TextStyle(height: 1.65),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(15),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Ahlul Bayt Treasures — مجموعة الأدعية والزيارات',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 7),
                    const Text(
                      'مجموعة بيانات عامة المصدر تضم نصوصاً عربية وترجمات إنجليزية ونقلاً صوتياً وتعليمات عرض. فهرس الأسماء يُحمّل أولاً، ثم يُنزّل نص JSONL عند فتح المادة ويُحفظ محلياً. إصدار البيانات: 1.0.1. لا تُعامل بيانات المجموعة على أنها توثيق سندي مستقل.',
                      style: TextStyle(height: 1.65),
                    ),
                    const SizedBox(height: 8),
                    const SelectableText(
                      'المشروع: github.com/KazTronics/AhlulBayt_Treasures\nالرخصة البرمجية: MIT — البيانات موصوفة في README بأنها Public Domain.',
                      style: TextStyle(height: 1.6),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            sources.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, __) => Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: const Text('تعذر تحميل قائمة المصادر حالياً.'),
                ),
              ),
              data: (items) => Column(
                children: items
                    .map((item) => _SourceCard(
                          item: item,
                          category: _category(item.category),
                          license: _license(item.licenseStatus),
                        ))
                    .toList(growable: false),
              ),
            ),
          ]),
        ),
      ),
    ]);
  }
}

class _SourceCard extends StatelessWidget {
  const _SourceCard(
      {required this.item, required this.category, required this.license});

  final SourceCatalogEntry item;
  final String category;
  final String license;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ExpansionTile(
        title: Text(safeDisplayText(item.name),
            style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Text('${safeDisplayText(category)} · $license',
            style: Theme.of(context).textTheme.bodySmall),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          Align(
              alignment: Alignment.centerRight,
              child: Text(safeDisplayText(item.observed),
                  style: const TextStyle(height: 1.6))),
          const SizedBox(height: 8),
          Align(
              alignment: Alignment.centerRight,
              child: Text('الغرض: ${safeDisplayText(item.useFor)}',
                  style: const TextStyle(height: 1.6))),
          const SizedBox(height: 8),
          Align(
              alignment: Alignment.centerRight,
              child: Text(safeDisplayText(item.notes),
                  style: const TextStyle(height: 1.6, color: Colors.deepOrange))),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              'تُحفظ تفاصيل المصدر والحقوق في سجل التوثيق الداخلي؛ لا يوجد زر لفتح موقع خارجي.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}
