import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../components/ad_slot.dart';
import '../../components/app_sheet.dart';
import '../../components/app_text.dart';
import '../../core/aladhan_prayer_times.dart';
import '../../core/app_preferences.dart';
import '../../core/governorate_selection_sheet.dart';
import '../../core/haptics.dart';
import '../../core/hijri_date.dart';
import '../../core/models.dart';
import '../../core/providers.dart';
import '../../design/theme_provider.dart';
import '../../devpanel/open.dart';
import '../settings/support_sheet.dart';
import 'home_announcement_slot.dart';

/// The home screen (S8).
///
/// A night-sky gradient header carries the hijri date and the prayer card;
/// a persistent sheet underneath carries the advertisement slot and three
/// live cards (G11) — no blank cells.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  late DateTime _now;
  Timer? _clock;
  bool _showingFirstSelection = false;
  int _tasbihCount = 0;

  @override
  void initState() {
    super.initState();
    _now = DateTime.now();
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _ensureFirstSelection());
  }

  Future<void> _ensureFirstSelection() async {
    if (!mounted ||
        _showingFirstSelection ||
        ref.read(selectedGovernorateProvider) != null) return;
    _showingFirstSelection = true;
    await showGovernorateSelectionSheet(context, requiredSelection: true);
    if (mounted) setState(() => _showingFirstSelection = false);
  }

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }

  void _incrementTasbih() {
    KhazainHaptics.light();
    setState(() => _tasbihCount = (_tasbihCount + 1) % 34);
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(uiThemeProvider);
    final selectedId = ref.watch(selectedGovernorateProvider);
    final govs = ref.watch(governoratesProvider);
    final prayer = ref.watch(prayerTimesProvider);
    final offsets = ref
        .watch(appPreferencesProvider.select((prefs) => prefs.prayerOffsets));
    final hijri = toApproximateHijri(_now);

    final governorate = govs.whenOrNull(data: (items) {
      for (final item in items) {
        if (item.id == selectedId) return item;
      }
      return null;
    });

    final media = MediaQuery.of(context);
    final headerHeight = (media.size.height * 0.44).clamp(280.0, 420.0);

    return Container(
      color: theme.color('bgApp'),
      child: Column(
        children: [
          Container(
            height: headerHeight,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: <Color>[
                  theme.color('skyTop'),
                  theme.color('skyBottom'),
                ],
              ),
            ),
            child: SafeArea(
              bottom: false,
              child: Column(
                children: [
                  _TopBar(
                    onSupport: () => unawaited(SupportSheet.show(context)),
                    onMenu: () => _openMenu(context),
                  ),
                  const SizedBox(height: 6),
                  TwoFingerTitleDetector(
                    child: AppText(
                      hijri.label,
                      token: 'h2',
                      color: theme.color('textPrimary'),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: _PrayerCard(
                        now: _now,
                        prayer: prayer,
                        offsets: offsets,
                        governorateName: governorate?.nameAr,
                        onLocationTap: () =>
                            showGovernorateSelectionSheet(context),
                        onOpenPrayer: () => context.go('/prayer'),
                        onQibla: () => context.push('/qibla'),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
          Expanded(
            child: _HomeSheet(
              tasbihCount: _tasbihCount,
              onTasbihTap: _incrementTasbih,
              advertisements: ref.watch(homeAdvertisementsProvider),
              apiBaseUrl: ref.watch(apiProvider).options.baseUrl,
            ),
          ),
        ],
      ),
    );
  }

  void _openMenu(BuildContext context) {
    KzSheet.show(
      context,
      title: 'خزائن الهدى',
      builder: (sheetContext) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _MenuRow(
            icon: Icons.grid_view_rounded,
            label: 'الأقسام',
            onTap: () {
              Navigator.of(sheetContext).pop();
              context.go('/sections');
            },
          ),
          _MenuRow(
            icon: Icons.graphic_eq_rounded,
            label: 'الصوتيات',
            onTap: () {
              Navigator.of(sheetContext).pop();
              context.go('/audio');
            },
          ),
          _MenuRow(
            icon: Icons.star_outline_rounded,
            label: 'متابعتي',
            onTap: () {
              Navigator.of(sheetContext).pop();
              context.go('/fada');
            },
          ),
          _MenuRow(
            icon: Icons.photo_library_outlined,
            label: 'مساحتي',
            onTap: () {
              Navigator.of(sheetContext).pop();
              context.go('/mukhalafat');
            },
          ),
          _MenuRow(
            icon: Icons.favorite_rounded,
            label: 'المفضلة',
            onTap: () {
              Navigator.of(sheetContext).pop();
              context.push('/favorites');
            },
          ),
          _MenuRow(
            icon: Icons.settings_rounded,
            label: 'الإعدادات',
            onTap: () {
              Navigator.of(sheetContext).pop();
              context.go('/settings');
            },
          ),
        ],
      ),
    );
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, size: 20),
      title: AppText(label, token: 'body'),
      onTap: onTap,
    );
  }
}

class _TopBar extends ConsumerWidget {
  const _TopBar({required this.onSupport, required this.onMenu});

  final VoidCallback onSupport;
  final VoidCallback onMenu;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(uiThemeProvider);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Row(
        children: [
          _GlassPill(
            icon: Icons.support_agent_rounded,
            label: 'الدعم',
            onTap: onSupport,
          ),
          const Spacer(),
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              AppText(
                'خزائن الهدى',
                token: 'body',
                color: theme.color('textPrimary'),
              ),
              AppText(
                'مساحة معرفية وعبادية',
                token: 'label',
                color: theme.color('textMuted'),
              ),
            ],
          ),
          const Spacer(),
          Semantics(
            button: true,
            label: 'القائمة',
            child: InkWell(
              onTap: onMenu,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Icon(
                  Icons.menu_rounded,
                  size: 26,
                  color: theme.color('textPrimary'),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GlassPill extends ConsumerWidget {
  const _GlassPill({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(uiThemeProvider);
    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(22),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(.2),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: Colors.white.withOpacity(.33)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 17, color: theme.color('textPrimary')),
                const SizedBox(width: 6),
                AppText(
                  label,
                  token: 'label',
                  color: theme.color('textPrimary'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PrayerCard extends ConsumerWidget {
  const _PrayerCard({
    required this.now,
    required this.prayer,
    required this.offsets,
    required this.governorateName,
    required this.onLocationTap,
    required this.onOpenPrayer,
    required this.onQibla,
  });

  final DateTime now;
  final AsyncValue<PrayerTimesResult?> prayer;
  final Map<String, int> offsets;
  final String? governorateName;
  final VoidCallback onLocationTap;
  final VoidCallback onOpenPrayer;
  final VoidCallback onQibla;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(uiThemeProvider);

    return Container(
      decoration: BoxDecoration(
        color: theme.color('surface1').withOpacity(.94),
        borderRadius: BorderRadius.circular(theme.cardRadius),
        border: Border.all(color: Colors.white.withOpacity(.2)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: prayer.when(
        loading: () => const SizedBox(
          height: 120,
          child: Center(child: CircularProgressIndicator()),
        ),
        error: (_, __) => _PrayerCardError(onRetry: onOpenPrayer),
        data: (data) {
          if (data == null) {
            return _PrayerCardError(
              onRetry: onLocationTap,
              label: 'اختر المحافظة لعرض المواقيت',
            );
          }
          final times = applyPrayerOffsets(data.displayTimes, offsets);
          final next = _nextPrayer(times, now);
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: onLocationTap,
                      child: AppText(
                        '${data.locationName ?? governorateName ?? 'الموقع'} · مواقيت الصلاة',
                        token: 'body',
                        color: theme.color('textSecondary'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  _QiblaBadge(onTap: onQibla),
                ],
              ),
              const SizedBox(height: 4),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: AlignmentDirectional.centerStart,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(
                        toArabicDigits(next.$2),
                        style: TextStyle(
                          fontSize: 46 * theme.fontScale,
                          fontWeight: FontWeight.w700,
                          height: 1.05,
                          color: theme.color('goldBright'),
                          fontFamily: theme.fontFamily,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(
                        Icons.wb_sunny_rounded,
                        size: 34,
                        color: theme.color('goldBright'),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 2),
              Flexible(
                child: AppText(
                  'الصلاة القادمة: ${next.$3}',
                  token: 'bodyDim',
                  color: theme.color('textMuted'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (next.$4.isNotEmpty)
                Flexible(
                  child: AppText(
                    'متبقي: ${next.$4}',
                    token: 'bodyDim',
                    color: theme.color('goldBright'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              if (data.hijriDate != null)
                Flexible(
                  child: AppText(
                    'التاريخ الهجري من المصدر: ${data.hijriDate}',
                    token: 'bodyDim',
                    color: theme.color('textMuted'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              Flexible(
                child: AppText(
                  'مصدر مواقيت اليوم: ${data.sourceLabel}',
                  token: 'bodyDim',
                  color: theme.color('textMuted'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  static (String, String, String, String) _nextPrayer(
      Map<String, String> values, DateTime now) {
    final keys = <(String, String)>[
      ('fajr', 'الفجر'),
      ('dhuhr', 'الظهر'),
      ('asr', 'العصر'),
      ('maghrib', 'المغرب'),
      ('isha', 'العشاء'),
    ];
    for (final item in keys) {
      final value = values[item.$1];
      if (value == null) continue;
      final parts = value.split(':');
      if (parts.length < 2) continue;
      final hour = int.tryParse(parts[0]);
      final minute = int.tryParse(parts[1]);
      if (hour == null || minute == null) continue;
      final prayerTime = DateTime(now.year, now.month, now.day, hour, minute);
      if (prayerTime.isAfter(now)) {
        final remaining = prayerTime.difference(now);
        return (
          item.$2,
          value,
          item.$2,
          _formatRemaining(remaining),
        );
      }
    }
    return ('—', '--:--', 'لا توجد مواقيت', '');
  }

  static String _formatRemaining(Duration remaining) {
    final hours = remaining.inHours;
    final minutes = remaining.inMinutes.remainder(60);
    if (hours <= 0) return 'بعد $minutes دقيقة';
    return 'بعد $hours ساعة و$minutes دقيقة';
  }
}

class _QiblaBadge extends ConsumerWidget {
  const _QiblaBadge({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(uiThemeProvider);
    return Semantics(
      button: true,
      label: 'القبلة',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: theme.color('gold').withOpacity(.16),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: theme.color('gold')),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.explore_rounded, size: 15, color: theme.color('gold')),
                const SizedBox(width: 5),
                AppText(
                  'القبلة',
                  token: 'label',
                  color: theme.color('gold'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PrayerCardError extends ConsumerWidget {
  const _PrayerCardError({required this.onRetry, this.label});

  final VoidCallback onRetry;
  final String? label;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(uiThemeProvider);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppText(
          label ?? 'تعذر تحميل المواقيت حالياً.',
          token: 'body',
          color: theme.color('textSecondary'),
        ),
        const SizedBox(height: 10),
        OutlinedButton(
          onPressed: onRetry,
          style: OutlinedButton.styleFrom(
            foregroundColor: theme.color('gold'),
            side: BorderSide(color: theme.color('gold')),
          ),
          child: AppText('إعادة المحاولة', token: 'label'),
        ),
      ],
    );
  }
}

/// Premium home content: live worship cards and direct content shortcuts.
class _HomeSheet extends ConsumerWidget {
  const _HomeSheet({
    required this.tasbihCount,
    required this.onTasbihTap,
    required this.advertisements,
    required this.apiBaseUrl,
  });

  final int tasbihCount;
  final VoidCallback onTasbihTap;
  final AsyncValue<List<Map<String, dynamic>>> advertisements;
  final String apiBaseUrl;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(uiThemeProvider);
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: theme.color('bgApp'),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
        border: Border(top: BorderSide(color: theme.color('hairline'))),
      ),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 26),
        children: [
          Center(
            child: Container(
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: theme.color('textMuted').withOpacity(.42),
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (advertisements.maybeWhen(
            data: (items) => items.isNotEmpty,
            orElse: () => false,
          ))
            HomeAnnouncementSlot(
              advertisements: advertisements,
              apiBaseUrl: apiBaseUrl,
            )
          else
            const AdSlot(height: 120),
          const SizedBox(height: 22),
          Row(
            children: [
              Expanded(
                child: AppText(
                  'مساحتك الروحانية',
                  token: 'h2',
                  color: theme.color('textPrimary'),
                ),
              ),
              AppText(
                'كل ما تحتاجه أقرب إليك',
                token: 'bodyDim',
                color: theme.color('textMuted'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _LiveCard(
                    icon: Icons.auto_awesome_rounded,
                    title: 'الأذكار',
                    caption: 'أذكار وتسبيح يومي',
                    onTap: () => context.push('/adhkar'),
                  ),
                ),
                const SizedBox(width: 10),
                const Expanded(child: _NextPrayerCard()),
                const SizedBox(width: 10),
                Expanded(
                  child: _LiveCard(
                    icon: Icons.grain_rounded,
                    title: 'المسبحة',
                    caption: 'عداد التسبيح',
                    value: toArabicDigits(tasbihCount),
                    onTap: () => context.push('/tasbih'),
                    onValueTap: onTasbihTap,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          AppText(
            'اكتشف المزيد',
            token: 'h2',
            color: theme.color('textPrimary'),
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final shortcuts = <Widget>[
                _HomeShortcut(
                  icon: Icons.menu_book_rounded,
                  title: 'القرآن الكريم',
                  subtitle: 'المصحف والتلاوات',
                  onTap: () => context.push('/quran'),
                ),
                _HomeShortcut(
                  icon: Icons.volunteer_activism_rounded,
                  title: 'الأدعية',
                  subtitle: 'أدعية ومناجاة',
                  onTap: () => context.push('/duas'),
                ),
                _HomeShortcut(
                  icon: Icons.mosque_rounded,
                  title: 'الزيارات',
                  subtitle: 'زيارة ومراقد',
                  onTap: () => context.push('/visits'),
                ),
                _HomeShortcut(
                  icon: Icons.local_library_outlined,
                  title: 'المكتبة',
                  subtitle: 'كتب ومراجع',
                  onTap: () => context.push('/library'),
                ),
                _HomeShortcut(
                  icon: Icons.event_available_rounded,
                  title: 'المناسبات',
                  subtitle: 'مناسبات أهل البيت',
                  onTap: () => context.push('/events'),
                ),
                _HomeShortcut(
                  icon: Icons.wallpaper_rounded,
                  title: 'الخلفيات',
                  subtitle: 'خلفيات الهاتف',
                  onTap: () => context.push('/wallpapers'),
                ),
              ];
              final cardWidth = (constraints.maxWidth - 12) / 2;
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (var index = 0; index < shortcuts.length; index++)
                    SizedBox(width: cardWidth, child: shortcuts[index]),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _HomeShortcut extends ConsumerWidget {
  const _HomeShortcut({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(uiThemeProvider);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(theme.cardRadius),
        child: Ink(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
              colors: [
                theme.color('surface2'),
                theme.color('surface1'),
              ],
            ),
            borderRadius: BorderRadius.circular(theme.cardRadius),
            border: Border.all(color: theme.color('hairline')),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: theme.color('gold').withOpacity(.14),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: theme.color('gold'), size: 23),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    AppText(title, token: 'body', color: theme.color('textPrimary')),
                    const SizedBox(height: 3),
                    AppText(
                      subtitle,
                      token: 'bodyDim',
                      color: theme.color('textMuted'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_left_rounded,
                color: theme.color('textMuted'),
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LiveCard extends ConsumerWidget {
  const _LiveCard({
    required this.icon,
    required this.title,
    required this.caption,
    required this.onTap,
    this.value,
    this.onValueTap,
  });

  final IconData icon;
  final String title;
  final String caption;
  final VoidCallback onTap;
  final String? value;
  final VoidCallback? onValueTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(uiThemeProvider);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(theme.cardRadius),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: theme.color('surface1'),
            borderRadius: BorderRadius.circular(theme.cardRadius),
            border: Border.all(color: theme.color('hairline')),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 20, color: theme.color('gold')),
              const SizedBox(height: 10),
              if (value != null)
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        value!,
                        style: TextStyle(
                          fontSize: 22 * theme.fontScale,
                          fontWeight: FontWeight.w700,
                          color: theme.color('textPrimary'),
                          fontFamily: theme.fontFamily,
                        ),
                      ),
                    ),
                    if (onValueTap != null)
                      IconButton(
                        tooltip: 'زيادة التسبيح',
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 32,
                          minHeight: 32,
                        ),
                        onPressed: onValueTap,
                        icon: Icon(
                          Icons.add_circle_outline_rounded,
                          size: 19,
                          color: theme.color('gold'),
                        ),
                      ),
                  ],
                ),
              AppText(
                title,
                token: 'label',
                color: theme.color('textPrimary'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              AppText(
                caption,
                token: 'bodyDim',
                color: theme.color('textMuted'),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NextPrayerCard extends ConsumerWidget {
  const _NextPrayerCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prayer = ref.watch(prayerTimesProvider);
    final offsets = ref
        .watch(appPreferencesProvider.select((prefs) => prefs.prayerOffsets));

    String title = 'الصلاة القادمة';
    String caption = 'جارٍ الحساب…';
    prayer.whenData((data) {
      if (data == null) return;
      final times = applyPrayerOffsets(data.displayTimes, offsets);
      const keys = <(String, String)>[
        ('fajr', 'الفجر'),
        ('dhuhr', 'الظهر'),
        ('asr', 'العصر'),
        ('maghrib', 'المغرب'),
        ('isha', 'العشاء'),
      ];
      final now = DateTime.now();
      for (final item in keys) {
        final value = times[item.$1];
        if (value == null) continue;
        final parts = value.split(':');
        if (parts.length < 2) continue;
        final hour = int.tryParse(parts[0]);
        final minute = int.tryParse(parts[1]);
        if (hour == null || minute == null) continue;
        final time = DateTime(now.year, now.month, now.day, hour, minute);
        if (time.isAfter(now)) {
          final remaining = time.difference(now);
          title = item.$2;
          caption = remaining.inHours > 0
              ? 'بعد ${remaining.inHours} س و${remaining.inMinutes.remainder(60)} د'
              : 'بعد ${remaining.inMinutes} دقيقة';
          break;
        }
      }
    });

    return _LiveCard(
      icon: Icons.access_time_filled_rounded,
      title: title,
      caption: caption,
      onTap: () => context.go('/prayer'),
    );
  }
}
