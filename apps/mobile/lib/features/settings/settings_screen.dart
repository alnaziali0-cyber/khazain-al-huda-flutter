import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../components/app_card.dart';
import '../../components/app_sheet.dart';
import '../../components/app_text.dart';
import '../../core/app_preferences.dart';
import '../../core/data_maintenance.dart' show selectedLocationSourceProvider;
import '../../core/governorate_selection_sheet.dart';
import '../../core/providers.dart';
import '../../design/theme_provider.dart';
import '../../devpanel/models.dart';
import '../../devpanel/store.dart';
import '../qibla/qibla_screen.dart' show qiblaLocationProvider;
import 'support_sheet.dart';

const _appVersionLabel = '0.2.0';

/// The settings screen (S2).
///
/// Three grouped blocks of 56dp rows on a `#3C3C3C` surface with a 28dp
/// radius. Every row opens a real screen or a real action (G17, G18).
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(uiThemeProvider);
    final themeMode = ref.watch(themeModeProvider);
    final prefs = ref.watch(appPreferencesProvider);
    final selectedGovernorate = ref.watch(selectedGovernorateProvider);
    final governorates = ref.watch(governoratesProvider);
    final appIcon = ref.watch(appIconProvider);

    final governorateName = governorates.whenOrNull(data: (items) {
          for (final item in items) {
            if (item.id == selectedGovernorate) return item.nameAr;
          }
          return 'لم تُحدد';
        }) ??
        (selectedGovernorate == null ? 'لم تُحدد' : 'جارٍ التحميل');

    return Container(
      color: theme.color('bgApp'),
      child: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
          children: [
            AppText('الإعدادات', token: 'display'),
            const SizedBox(height: 16),

            // Block 1 — the app and its notifications
            KzGroupCard(
              level: 2,
              children: [
                KzRow(
                  title: 'الأذونات',
                  subtitle: 'إذن الموقع والإشعارات والتخزين',
                  leading: const Icon(Icons.security_rounded, size: 20),
                  onTap: () => _showPermissions(context, ref),
                ),
                KzRow(
                  title: 'الإشعارات',
                  subtitle: prefs.prayerNotificationsEnabled
                      ? 'تنبيه دخول وقت الصلاة مفعّل'
                      : 'تنبيه دخول وقت الصلاة متوقف',
                  leading: const Icon(Icons.notifications_rounded, size: 20),
                  onTap: () => context.push('/settings/alarm'),
                ),
                KzRow(
                  title: 'الموقع',
                  subtitle: 'المحافظة المحددة حالياً',
                  trailing: _ValueText(governorateName),
                  leading: const Icon(Icons.location_on_outlined, size: 20),
                  onTap: () => _changeGovernorate(context, ref),
                ),
                KzRow(
                  title: 'أوقات الصلاة',
                  subtitle: 'طريقة الحساب والتعديلات اليدوية',
                  leading: const Icon(Icons.access_time_rounded, size: 20),
                  onTap: () => context.push('/settings/prayer'),
                ),
              ],
            ),
            const SizedBox(height: KhazainSpacingToken.group),

            // Block 2 — appearance
            KzGroupCard(
              level: 2,
              children: [
                KzRow(
                  title: 'لغة التطبيق',
                  trailing: const _ValueText('العربية'),
                  leading: const Icon(Icons.language_rounded, size: 20),
                  onTap: () => _showLanguageInfo(context),
                ),
                KzRow(
                  title: 'خط التطبيق',
                  trailing: _ValueText(prefs.appFontFamily.labelAr),
                  leading: const Icon(Icons.text_fields_rounded, size: 20),
                  onTap: () => _pickAppFont(context, ref, prefs.appFontFamily),
                ),
                KzRow(
                  title: 'حجم الخط',
                  trailing: _ValueText(prefs.textSize.labelAr),
                  leading: const Icon(Icons.format_size_rounded, size: 20),
                  onTap: () => _pickTextSize(context, ref, prefs.textSize),
                ),
                KzRow(
                  title: 'مظهر التطبيق',
                  trailing: _ValueText(_themeLabel(themeMode)),
                  leading: const Icon(Icons.dark_mode_outlined, size: 20),
                  onTap: () => _pickTheme(context, ref, themeMode),
                ),
                KzRow(
                  title: 'أيقونة التطبيق',
                  trailing: _ValueText(_appIconLabel(appIcon)),
                  leading: const Icon(Icons.apps_rounded, size: 20),
                  onTap: () => _pickAppIcon(context, ref),
                ),
              ],
            ),
            const SizedBox(height: KhazainSpacingToken.group),

            // Block 3 — data and support
            KzGroupCard(
              level: 2,
              children: [
                KzRow(
                  title: 'تنزيل الكتاب والملفات',
                  subtitle: 'المكتبة دون اتصال والتنزيلات المرخصة',
                  leading: const Icon(Icons.download_for_offline_outlined, size: 20),
                  onTap: () => context.push('/settings/privacy'),
                ),
                KzRow(
                  title: 'تصحيح الأوقات الهجرية',
                  subtitle: 'تعديل التاريخ الهجري يدوياً بمقدار يومين',
                  leading: const Icon(Icons.event_repeat_rounded, size: 20),
                  onTap: () => context.push('/calendar'),
                ),
                KzRow(
                  title: 'صوت الإذان',
                  subtitle: 'صوت التنبيه عند دخول الوقت',
                  leading: const Icon(Icons.volume_up_rounded, size: 20),
                  onTap: () => context.push('/settings/alarm'),
                ),
                KzRow(
                  title: 'المظهر الخاص',
                  subtitle: 'تصدير إعدادات المظهر واستيرادها',
                  leading: const Icon(Icons.palette_outlined, size: 20),
                  onTap: () => _showThemeTransfer(context, ref),
                ),
                KzRow(
                  title: 'الخصوصية ومسح البيانات',
                  subtitle: 'ما يُحفظ على الجهاز وكيف تحذفه',
                  leading: const Icon(Icons.privacy_tip_outlined, size: 20),
                  onTap: () => context.push('/settings/privacy'),
                ),
                KzRow(
                  title: 'تواصل معنا',
                  subtitle: 'واتساب وبريد ودعم التطبيق',
                  leading: const Icon(Icons.headset_mic_outlined, size: 20),
                  onTap: () => SupportSheet.show(context),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Center(
              child: AppText(
                'الإصدار $_appVersionLabel',
                token: 'bodyDim',
                color: theme.color('textMuted'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _themeLabel(ThemeMode mode) => switch (mode) {
        ThemeMode.light => 'فاتح',
        ThemeMode.dark => 'داكن',
        _ => 'تلقائي',
      };

  static String _appIconLabel(String value) => switch (value) {
        'ramadan' => 'رمضان',
        'mosque' => 'مسجد',
        'quran' => 'قرآن',
        _ => 'افتراضية',
      };

  static Future<void> _pickTheme(
      BuildContext context, WidgetRef ref, ThemeMode current) async {
    final chosen = await KzSheet.show<ThemeMode>(
      context,
      title: 'مظهر التطبيق',
      builder: (sheetContext) => KzOptionList(
        options: const [
          (id: 'system', label: 'تلقائي', hint: 'يتبع إعداد الجهاز'),
          (id: 'light', label: 'فاتح', hint: 'ألوان فاتحة'),
          (id: 'dark', label: 'داكن', hint: 'ألوان داكنة'),
        ],
        selectedId: current.name,
        onSelected: (id) => Navigator.of(sheetContext).pop(ThemeMode.values.firstWhere((mode) => mode.name == id)),
      ),
    );
    if (chosen == null || chosen == current || !context.mounted) return;
    await ref.read(themeModeProvider.notifier).setMode(chosen);
  }

  static Future<void> _pickTextSize(
      BuildContext context, WidgetRef ref, AppTextSize current) async {
    final chosen = await KzSheet.show<AppTextSize>(
      context,
      title: 'حجم الخط',
      builder: (sheetContext) => KzOptionList(
        options: [
          for (final size in AppTextSize.values)
            (id: size.storageKey, label: size.labelAr, hint: '${(size.factor * 100).round()}%'),
        ],
        selectedId: current.storageKey,
        onSelected: (id) => Navigator.of(sheetContext)
            .pop(AppTextSize.fromStorage(id)),
      ),
    );
    if (chosen == null || chosen == current || !context.mounted) return;
    await ref.read(appPreferencesProvider.notifier).setTextSize(chosen);
  }

  static Future<void> _pickAppFont(
      BuildContext context, WidgetRef ref, AppFontFamily current) async {
    final chosen = await KzSheet.show<AppFontFamily>(
      context,
      title: 'خط التطبيق',
      builder: (sheetContext) => KzOptionList(
        options: [
          for (final font in AppFontFamily.values)
            (id: font.storageKey, label: font.labelAr, hint: font.themeFamily),
        ],
        selectedId: current.storageKey,
        onSelected: (id) => Navigator.of(sheetContext)
            .pop(AppFontFamily.fromStorage(id)),
      ),
    );
    if (chosen == null || chosen == current || !context.mounted) return;
    await ref.read(appPreferencesProvider.notifier).setAppFontFamily(chosen);
  }

  static Future<void> _pickAppIcon(
      BuildContext context, WidgetRef ref) async {
    final chosen = await KzSheet.show<String>(
      context,
      title: 'أيقونة التطبيق',
      builder: (sheetContext) => KzOptionList(
        options: const [
          (id: 'default', label: 'افتراضية', hint: 'شعار خزائن الهدى'),
          (id: 'ramadan', label: 'رمضان', hint: 'أيقونة إمساكية'),
          (id: 'mosque', label: 'مسجد', hint: 'أيقونة المسجد'),
          (id: 'quran', label: 'قرآن', hint: 'أيقونة المصحف'),
        ],
        selectedId: ref.read(appIconProvider),
        onSelected: (id) => Navigator.of(sheetContext).pop(id),
      ),
    );
    if (chosen == null || !context.mounted) return;
    await ref.read(appIconProvider.notifier).select(chosen);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'حُفظت الأيقونة. تُطبَّق على أيقونة النظام بعد تحديث التطبيق.',
        ),
      ),
    );
  }

  static Future<void> _showThemeTransfer(
      BuildContext context, WidgetRef ref) async {
    await KzSheet.show(
      context,
      title: 'المظهر الخاص',
      builder: (sheetContext) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppText(
            'صدّر إعدادات المظهر لتشاركها أو تنقلها إلى جهاز آخر، أو استورد ملفاً سبق تصديره.',
            token: 'bodyDim',
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () {
              Navigator.of(sheetContext).pop();
              _exportTheme(context, ref);
            },
            icon: const Icon(Icons.upload_rounded, size: 18),
            label: const Text('تصدير إعدادات المظهر'),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: () {
              Navigator.of(sheetContext).pop();
              _importTheme(context, ref);
            },
            icon: const Icon(Icons.download_rounded, size: 18),
            label: const Text('استيراد إعدادات المظهر'),
          ),
        ],
      ),
    );
  }

  static Future<void> _exportTheme(BuildContext context, WidgetRef ref) async {
    final theme = ref.read(uiThemeProvider);
    final payload = jsonEncode(<String, dynamic>{
      'version': 1,
      'theme': theme.toJson(),
      'sections': ref.read(devStoreProvider).sections
          .map((section) => section.toJson())
          .toList(growable: false),
      'icons': ref.read(devStoreProvider).icons
          .map((icon) => icon.toJson())
          .toList(growable: false),
    });
    try {
      await Share.share(
        payload,
        subject: 'خزائن الهدى — إعدادات المظهر',
      );
    } catch (_) {
      if (!context.mounted) return;
      await Clipboard.setData(ClipboardData(text: payload));
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تعذرت المشاركة. نُسخت الإعدادات إلى الحافظة.'),
        ),
      );
    }
  }

  static Future<void> _importTheme(BuildContext context, WidgetRef ref) async {
    final result = await FilePicker.platform.pickFiles(
      withData: true,
      type: FileType.any,
    );
    if (result == null || result.files.isEmpty || !context.mounted) return;
    final bytes = result.files.first.bytes;
    if (bytes == null) return;
    try {
      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is! Map) throw const FormatException('ملف غير صالح');
      final store = ref.read(devStoreProvider.notifier);
      final themeJson = (decoded['theme'] as Map?)?.cast<String, dynamic>();
      if (themeJson != null) {
        final theme = UITheme.fromJson(themeJson);
        store.applyPatch(UIPatch(
          tokens: <String, dynamic>{
            'colors': theme.colors,
            'typography': theme.typography.map(
                (key, value) => MapEntry(key, value.toJson())),
            'radius': theme.radius,
            'spacing': theme.spacing,
            'grid': theme.grid,
          },
        ));
      }
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم استيراد إعدادات المظهر.')),
      );
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر قراءة الملف. تأكد أنه ملف إعدادات مظهر.')),
      );
    }
  }

  static Future<void> _showPermissions(BuildContext context, WidgetRef ref) async {
    await KzSheet.show(
      context,
      title: 'الأذونات',
      builder: (sheetContext) => const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _PermissionLine(
            icon: Icons.location_on_outlined,
            title: 'الموقع',
            detail: 'يُستخدم عند طلب اقتراح المحافظة فقط، ولا يُطلب في الخلفية.',
          ),
          _PermissionLine(
            icon: Icons.notifications_rounded,
            title: 'الإشعارات',
            detail: 'لتنبيه دخول وقت الصلاة فقط، ويمكن إيقافه بالكامل.',
          ),
          _PermissionLine(
            icon: Icons.music_note_rounded,
            title: 'الصوت في الخلفية',
            detail: 'لاستمرار تشغيل التلاوة والأذان أثناء استخدام تطبيقات أخرى.',
          ),
          _PermissionLine(
            icon: Icons.storage_rounded,
            title: 'التخزين',
            detail: 'لحفظ التسجيلات المرخصة للاستماع دون اتصال.',
          ),
        ],
      ),
    );
  }

  static Future<void> _showLanguageInfo(BuildContext context) async {
    await KzSheet.show(
      context,
      title: 'لغة التطبيق',
      builder: (sheetContext) => AppText(
        'النسخة الحالية عربية بالكامل (RTL). لغات إضافية ستُضاف وفق طلب المستخدمين.',
        token: 'body',
      ),
    );
  }

  static Future<void> _changeGovernorate(
      BuildContext context, WidgetRef ref) async {
    await showGovernorateSelectionSheet(context);
    if (!context.mounted) return;
    ref.invalidate(selectedLocationSourceProvider);
    ref.invalidate(qiblaLocationProvider);
    ref.invalidate(prayerTimesProvider);
  }
}

class _ValueText extends StatelessWidget {
  const _ValueText(this.value);

  final String value;

  @override
  Widget build(BuildContext context) => Text(
        value,
        style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurface.withOpacity(.6)),
      );
}

class _PermissionLine extends StatelessWidget {
  const _PermissionLine({
    required this.icon,
    required this.title,
    required this.detail,
  });

  final IconData icon;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppText(title, token: 'body'),
                const SizedBox(height: 2),
                AppText(detail, token: 'bodyDim'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Spacing token shortcut used by the settings blocks.
class KhazainSpacingToken {
  const KhazainSpacingToken._();

  static const double group = 24;
}
