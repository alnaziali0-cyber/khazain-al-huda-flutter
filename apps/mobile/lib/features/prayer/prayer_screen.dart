import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/app_preferences.dart';
import '../../core/aladhan_prayer_times.dart';
import '../../core/data_maintenance.dart';
import '../../core/providers.dart';
import '../../core/models.dart';


Future<void> _selectPrayerDataSource(
    BuildContext context, WidgetRef ref, String? source) async {
  if (source == null) return;
  final isAlAdhan = source == 'aladhan_jafari' || source == 'aladhan_egyptian';
  final prefs = ref.read(sharedPreferencesProvider);
  if (isAlAdhan && prefs.getBool('aladhan_location_sharing_consent') != true) {
    final approved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('مشاركة إحداثيات الموقع'),
        content: const Text(
          'لحساب المواقيت عبر AlAdhan، سيرسل التطبيق إحداثيات الموقع المختار (GPS أو مركز المدينة/المحافظة) مباشرة إلى api.aladhan.com عبر HTTPS. لا يرسل الطلب معرّف الجهاز أو بيانات الحساب. قد يحتفظ مزود الخدمة ببيانات الطلب وفق سياسته. هل توافق على ذلك؟',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('أوافق'),
          ),
        ],
      ),
    );
    if (approved != true) return;
    await prefs.setBool('aladhan_location_sharing_consent', true);
  }

  await ref.read(selectedPrayerDataSourceProvider.notifier).select(
        source == 'app_default' ? null : source,
      );
  ref.invalidate(prayerTimesForDateProvider);
  ref.invalidate(prayerTimesProvider);
}

class PrayerScreen extends ConsumerWidget {
  const PrayerScreen({super.key});
  static const labels = {
    'imsak': 'الإمساك',
    'fajr': 'الفجر',
    'sunrise': 'الشروق',
    'dhuhr': 'الظهر',
    'asr': 'العصر',
    'sunset': 'الغروب',
    'maghrib': 'المغرب',
    'isha': 'العشاء',
    'islamic_midnight': 'منتصف الليل (من الغروب)',
    'islamic_midnight_latest_by': 'منتصف الليل (من المغرب)',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cities = ref.watch(prayerCitiesProvider);
    final selectedCity = ref.watch(selectedPrayerCityProvider);
    final selectedGovernorate = ref.watch(selectedGovernorateProvider);
    final method = ref.watch(selectedPrayerMethodProvider) ?? 'jafari_qom';
    final dataSource =
        ref.watch(selectedPrayerDataSourceProvider) ?? 'app_default';
    final times = ref.watch(prayerTimesProvider);
    final preferences = ref.watch(appPreferencesProvider);
    final hasAlAdhanConsent = ref
            .read(sharedPreferencesProvider)
            .getBool('aladhan_location_sharing_consent') ==
        true;
    final theme = Theme.of(context);

    return CustomScrollView(slivers: [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 30),
        sliver: SliverList(
          delegate: SliverChildListDelegate([
            Text(
              'مواقيت الصلاة',
              style: theme.textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 6),
            Text(
              dataSource == 'app_default'
                  ? 'مصدر مواقيت اليوم والحساب المحلي للأيام المقبلة موضّحان أدناه. لا تمثل النتائج اعتماداً مرجعياً.'
                  : 'المصدر المحدد يوفر مواقيت الأيام التي يحتاجها التطبيق، بما فيها جدول التنبيهات. لا تمثل النتائج اعتماداً مرجعياً.',
            ),
            const SizedBox(height: 12),
            Wrap(spacing: 9, runSpacing: 8, children: [
              OutlinedButton.icon(
                  onPressed: () => context.go('/qibla'),
                  icon: const Icon(Icons.explore_outlined),
                  label: const Text('اتجاه القبلة')),
            ]),
            const SizedBox(height: 18),
            DropdownButtonFormField<String>(
              value: dataSource,
              decoration: const InputDecoration(
                labelText: 'مصدر مواقيت الصلاة',
                prefixIcon: Icon(Icons.public_rounded),
              ),
              isExpanded: true,
              items: const [
                DropdownMenuItem(
                  value: 'app_default',
                  child: Text('المصدر الحالي للتطبيق'),
                ),
                DropdownMenuItem(
                  value: 'aladhan_jafari',
                  child: Text('AlAdhan — الحساب الجعفري (0)'),
                ),
                DropdownMenuItem(
                  value: 'aladhan_egyptian',
                  child: Text('AlAdhan — الهيئة المصرية (5)'),
                ),
              ],
              onChanged: (value) => _selectPrayerDataSource(context, ref, value),
            ),
            const SizedBox(height: 6),
            Text(
              dataSource == 'aladhan_jafari'
                  ? 'يستخدم طريقة AlAdhan الجعفرية (0). هذه طريقة حسابية خارجية وليست اعتماداً من مرجع ديني.'
                  : dataSource == 'aladhan_egyptian'
                      ? 'يستخدم طريقة الهيئة المصرية العامة للمساحة (5) كما في الوحدة المرفوعة. هذه الطريقة ليست الحساب الجعفري.'
                      : 'يستخدم التطبيق مصدره الحالي. لا تُرسل إحداثيات الموقع إلى AlAdhan في هذا الوضع.',
              style: theme.textTheme.bodySmall,
            ),
            if (dataSource != 'app_default' || hasAlAdhanConsent)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  onPressed: () async {
                    await ref
                        .read(selectedPrayerDataSourceProvider.notifier)
                        .select(null);
                    await ref
                        .read(sharedPreferencesProvider)
                        .remove('aladhan_location_sharing_consent');
                    ref.invalidate(selectedPrayerDataSourceProvider);
                    ref.invalidate(prayerTimesForDateProvider);
                    ref.invalidate(prayerTimesProvider);
                  },
                  icon: const Icon(Icons.privacy_tip_outlined, size: 18),
                  label: Text(dataSource == 'app_default'
                      ? 'إلغاء موافقة مشاركة الموقع'
                      : 'إيقاف AlAdhan وإلغاء موافقة الموقع'),
                ),
              ),
            const SizedBox(height: 18),
            if (selectedCity == null && selectedGovernorate != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: times.when(
                  data: (result) {
                    final isGps = result?.coordinateSource ==
                        'device_location_permission';
                    return Text(
                      isGps
                          ? 'يُستخدم موقع GPS المحفوظ في التخزين الآمن على هذا الجهاز.'
                          : 'تُستخدم إحداثيات مركز المحافظة المختارة تقريبياً.',
                      style: theme.textTheme.bodySmall,
                    );
                  },
                  loading: () => const SizedBox.shrink(),
                  error: (_, __) => const SizedBox.shrink(),
                ),
              ),
            cities.when(
              loading: () => const LinearProgressIndicator(),
              error: (error, _) =>
                  _ErrorCard(message: 'تعذر تحميل المدن: $error'),
              data: (items) {
                final selectedExists =
                    items.any((city) => city.cityId == selectedCity);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    DropdownButtonFormField<String>(
                      value: selectedExists ? selectedCity : null,
                      decoration:
                          const InputDecoration(labelText: 'اختر المدينة'),
                      isExpanded: true,
                      items: items
                          .map((city) => DropdownMenuItem(
                                value: city.cityId,
                                child: Text(
                                    '${city.cityNameAr} — ${city.governorateNameAr}'),
                              ))
                          .toList(growable: false),
                      onChanged: (value) async {
                        await ref
                            .read(selectedPrayerCityProvider.notifier)
                            .select(value);
                        if (value != null) {
                          try {
                            final coordinatesStore =
                                ref.read(locationCoordinatesStoreProvider);
                            final previousLocation =
                                await coordinatesStore.read();
                            if (previousLocation?.source == 'gps') {
                              await clearGpsPrayerCache(
                                ref.read(sharedPreferencesProvider),
                                previousLocation!.cacheToken,
                              );
                            }
                            await coordinatesStore.clear();
                          } catch (_) {
                            // The selected city still takes precedence; the secure value is never sent with this request.
                          }
                          await ref
                              .read(sharedPreferencesProvider)
                              .setString('selected_location_source', 'city');
                          ref.invalidate(selectedLocationSourceProvider);
                        }
                        ref.invalidate(prayerTimesProvider);
                      },
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'إحداثيات المدن في هذه القائمة تقريبية لمراكز المدن وغير متحققة ميدانياً. اختيار مدينة من القائمة يستبدل إحداثيات GPS أو مركز المحافظة.',
                      style: TextStyle(fontSize: 12),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 14),
            if (dataSource == 'app_default') ...[
              DropdownButtonFormField<String>(
                value: method,
                decoration: const InputDecoration(
                    labelText: 'طريقة الحساب المحلي للأيام المقبلة'),
                isExpanded: true,
                items: const [
                  DropdownMenuItem(
                      value: 'jafari_qom',
                      child: Text('ملف زوايا قم (غير معتمد مرجعياً)')),
                  DropdownMenuItem(
                      value: 'tehran',
                      child: Text('ملف زوايا طهران (غير معتمد مرجعياً)')),
                ],
                onChanged: (value) async {
                  await ref
                      .read(selectedPrayerMethodProvider.notifier)
                      .select(value);
                  ref.invalidate(prayerTimesForDateProvider);
                  ref.invalidate(prayerTimesProvider);
                },
              ),
              const SizedBox(height: 18),
            ],
            times.when(
              loading: () => const Center(
                  child: Padding(
                padding: EdgeInsets.all(28),
                child: CircularProgressIndicator(),
              )),
              error: (error, _) => _ErrorCard(
                  message:
                      'تعذر الحصول على المواقيت. تحقق من الاتصال ثم أعد المحاولة.\n$error'),
              data: (data) {
                if (data == null) {
                  return const _InfoCard(
                    title: 'لم تُحدد المدينة',
                    body:
                        'اختر المدينة يدوياً لعرض مواقيت اليوم. لا يحتاج هذا الاختيار إلى إذن الموقع.',
                  );
                }
                return _TimesPanel(data: data, preferences: preferences);
              },
            ),
          ]),
        ),
      ),
    ]);
  }
}

class _TimesPanel extends StatelessWidget {
  const _TimesPanel({required this.data, required this.preferences});
  final PrayerTimesResult data;
  final AppPreferences preferences;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final approximate =
        (data.coordinateAccuracy?.startsWith('approximate') ?? false) ||
            data.locationVerified == false;
    // Manual offsets change only what this device displays; the source values stay untouched.
    final times =
        applyPrayerOffsets(data.displayTimes, preferences.prayerOffsets);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(data.locationName ?? 'الموقع المحدد',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text(data.date, style: theme.textTheme.titleSmall),
                const SizedBox(height: 4),
                if (data.hijriDate != null) ...[
                  Text('التاريخ الهجري من المصدر: ${data.hijriDate}'),
                  const SizedBox(height: 4),
                ],
                Text('مصدر مواقيت اليوم: ${data.sourceLabel}'),
                Text('طريقة الحساب / المصدر: ${data.methodLabel}'),
                if (data.source == PrayerTimesSource.iraqJafariSchedule)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text(
                      'جدول حسابي محلي يغطي 2026–2027. ليس تقويماً رسمياً أو اعتماداً مرجعياً؛ قد تختلف الدقائق بحسب الإحداثيات والرؤية وطريقة الحساب.',
                      style: TextStyle(height: 1.55),
                    ),
                  ),
                if (data.source == PrayerTimesSource.alAdhanApi)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      data.definitions['method_id'] == 5
                          ? 'طريقة الحساب المختارة هي الهيئة المصرية العامة للمساحة (5)، وليست الطريقة الجعفرية. قارن النتائج مع جدول محلي معتمد قبل الاعتماد عليها للتنبيه أو العبادة.'
                          : 'طريقة الحساب المختارة هي AlAdhan الجعفرية (0). قد تختلف النتائج عن الجداول المحلية أو اعتماد المرجع؛ راجع التقويم المعتمد في منطقتك.',
                      style: theme.textTheme.bodySmall?.copyWith(height: 1.55),
                    ),
                  ),
                if (data.isStale)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text(
                        'بيانات مخزنة محلياً من آخر اتصال؛ قد لا تعكس تحديثاً حديثاً.',
                        style: TextStyle(color: Colors.orange)),
                  ),
                if (approximate)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text(
                        'تنبيه: الإحداثيات المستخدمة تقريبية لمركز المحافظة وغير موثقة ميدانياً. اختر مدينة أدق أو استخدم موقع GPS عند توفره.',
                        style: TextStyle(color: Colors.deepOrange)),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        ...PrayerScreen.labels.entries
            .where((entry) =>
                times.containsKey(entry.key) &&
                (preferences.showReferenceTimes ||
                    !referenceTimeKeys.contains(entry.key)))
            .map((entry) {
          final offset = preferences.offsetFor(entry.key);
          return Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              child: Row(children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(entry.value,
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                      if (offset != 0)
                        Text(
                          'معدّل يدوياً ${offset > 0 ? '+' : ''}$offset دقيقة',
                          style: const TextStyle(
                              fontSize: 12, color: Colors.deepOrange),
                        ),
                    ],
                  ),
                ),
                Text(toArabicDigits(times[entry.key] ?? '—'),
                    style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: theme.colorScheme.primary)),
              ]),
            ),
          );
        }),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'تنبيه فقهي: مصدر مواقيت اليوم هو ${data.sourceLabel}، ولا يعني ذلك اعتماداً من مرجع ديني. الحساب المحلي للأيام المقبلة تقديري أيضاً. قد تختلف معايير الفجر والمغرب والعشاء ومنتصف الليل؛ ولا يُنشأ وقت مفقود في رد المصدر.',
              style: theme.textTheme.bodySmall?.copyWith(height: 1.7),
            ),
          ),
        ),
      ],
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.title, required this.body});
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(body),
          ]),
        ),
      );
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Text(message, style: const TextStyle(color: Colors.redAccent)),
        ),
      );
}
