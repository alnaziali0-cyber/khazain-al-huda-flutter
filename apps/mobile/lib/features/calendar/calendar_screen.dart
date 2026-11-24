import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';

import '../../components/app_card.dart';
import '../../components/app_text.dart';
import '../../core/hijri_date.dart';
import '../../design/theme_provider.dart';

/// The hijri calendar and the Ramadan imsakiya (S: التقويم الهجري / إمساكية
/// رمضان).
///
/// The month grid is computed from the tabular conversion used across the
/// app and is labelled as approximate; the Ramadan table is read from the
/// bundled offline prayer-time data so it works without a connection.
class CalendarScreen extends ConsumerStatefulWidget {
  const CalendarScreen({super.key, this.mode = 'hijri'});

  /// `hijri` or `ramadan`.
  final String mode;

  @override
  ConsumerState<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends ConsumerState<CalendarScreen> {
  ApproximateHijriDate _month = toApproximateHijri(DateTime.now());

  static const List<String> _weekDays = <String>[
    'الأحد',
    'الاثنين',
    'الثلاثاء',
    'الأربعاء',
    'الخميس',
    'الجمعة',
    'السبت',
  ];

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(uiThemeProvider);
    final isRamadan = widget.mode == 'ramadan';

    return Container(
      color: theme.color('bgApp'),
      child: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
          children: [
            AppText(isRamadan ? 'إمساكية رمضان' : 'التقويم الهجري',
                token: 'display'),
            const SizedBox(height: 4),
            AppText(
              isRamadan
                  ? 'أوقات الإمساك والإفطار من البيانات المحفوظة على الجهاز.'
                  : 'الشهر الهجري التقريبي — يمكن تصحيحه يدوياً من الإعدادات.',
              token: 'bodyDim',
              color: theme.color('textMuted'),
            ),
            const SizedBox(height: 18),
            if (isRamadan)
              const _RamadanTable()
            else
              _HijriMonthGrid(
                month: _month,
                weekDays: _weekDays,
                onShift: (delta) {
                  setState(() {
                    var month = _month.month + delta;
                    var year = _month.year;
                    if (month < 1) {
                      month = 12;
                      year -= 1;
                    } else if (month > 12) {
                      month = 1;
                      year += 1;
                    }
                    _month = ApproximateHijriDate(day: 1, month: month, year: year);
                  });
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _HijriMonthGrid extends ConsumerWidget {
  const _HijriMonthGrid({
    required this.month,
    required this.weekDays,
    required this.onShift,
  });

  final ApproximateHijriDate month;
  final List<String> weekDays;
  final ValueChanged<int> onShift;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(uiThemeProvider);
    final today = toApproximateHijri(DateTime.now());
    final days = _daysOfMonth(month);
    final firstWeekday = _firstWeekdayOfMonth(month);
    final leading = (firstWeekday + 1) % 7;

    return KzSurface(
      level: 1,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                onPressed: () => onShift(-1),
                icon: const Icon(Icons.chevron_right_rounded),
                tooltip: 'الشهر السابق',
              ),
              Expanded(
                child: AppText(
                  month.monthYearLabel,
                  token: 'h2',
                  textAlign: TextAlign.center,
                ),
              ),
              IconButton(
                onPressed: () => onShift(1),
                icon: const Icon(Icons.chevron_left_rounded),
                tooltip: 'الشهر التالي',
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              for (final day in weekDays)
                Expanded(
                  child: AppText(
                    day,
                    token: 'label',
                    color: theme.color('textMuted'),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              mainAxisSpacing: 4,
              crossAxisSpacing: 4,
              childAspectRatio: 1,
            ),
            itemCount: leading + days.length,
            itemBuilder: (context, index) {
              if (index < leading) return const SizedBox.shrink();
              final day = days[index - leading];
              final isToday = today.year == month.year &&
                  today.month == month.month &&
                  today.day == day;
              return Container(
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: isToday ? theme.color('green') : null,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isToday ? theme.color('green') : theme.color('hairline'),
                  ),
                ),
                child: AppText(
                  '$day',
                  token: 'body',
                  color: isToday
                      ? theme.color('textPrimary')
                      : theme.color('textSecondary'),
                  textAlign: TextAlign.center,
                ),
              );
            },
          ),
          const SizedBox(height: 12),
          AppText(
            'التاريخ الهجري في هذا التطبيق تقريبي، ويعتمد على الحساب لا على الرؤية. '
            'يمكنك تعديله يدوياً بمقدار يومين من صفحة الإعدادات.',
            token: 'bodyDim',
            color: theme.color('textMuted'),
          ),
        ],
      ),
    );
  }

  static List<int> _daysOfMonth(ApproximateHijriDate month) {
    final lengths = const <int>[
      30, 29, 30, 29, 30, 29, 30, 29, 30, 29, 30, 29,
    ];
    final base = lengths[month.month - 1];
    // Tabular months alternate; the conversion adds a day every leap cycle.
    final isLeap = ((month.year * 11) + 14) % 30 < 11;
    final length = (month.month == 12 && isLeap) ? base + 1 : base;
    return List<int>.generate(length, (index) => index + 1);
  }

  static int _firstWeekdayOfMonth(ApproximateHijriDate month) {
    // Walk back from a known anchor to find the weekday of the first day.
    final anchor = DateTime(2024, 3, 11); // 1 ربيع الأول 1445 (الاثنين)
    var days = 0;
    for (var index = 1; index < month.month; index++) {
      days = days +
        _daysOfMonth(
            ApproximateHijriDate(day: 1, month: index, year: month.year)).length;
    }
    days += (month.year - 1445) * 354;
    var date = anchor.add(Duration(days: days));
    return date.weekday - 1;
  }
}

/// The Ramadan imsakiya, read from the bundled offline prayer-time data.
class _RamadanTable extends ConsumerWidget {
  const _RamadanTable();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(uiThemeProvider);
    return FutureBuilder<List<_RamadanDay>>(
      future: _loadRamadan(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError || snapshot.data == null || snapshot.data!.isEmpty) {
          return KzSurface(
            level: 1,
            padding: const EdgeInsets.all(16),
            child: AppText(
              'تعذر تحميل بيانات الإمساكية المحفوظة على الجهاز.',
              token: 'body',
              color: theme.color('textMuted'),
            ),
          );
        }
        final days = snapshot.data!;
        return KzSurface(
          level: 1,
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
          child: Column(
            children: [
              Row(
                children: [
                  const Expanded(
                    flex: 3,
                    child: AppText('التاريخ', token: 'label'),
                  ),
                  const Expanded(
                    flex: 2,
                    child: AppText('الإمساك', token: 'label'),
                  ),
                  const Expanded(
                    flex: 2,
                    child: AppText('الإفطار', token: 'label'),
                  ),
                ],
              ),
              Divider(height: 18, color: theme.color('divider')),
              for (final day in days)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: AppText(
                          day.hijriLabel,
                          token: 'body',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: AppText(day.imsak, token: 'body'),
                      ),
                      Expanded(
                        flex: 2,
                        child: AppText(
                          day.isha,
                          token: 'body',
                          color: theme.color('gold'),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Future<List<_RamadanDay>> _loadRamadan() async {
    final raw = await rootBundle.loadString(
      'assets/data/prayer_times/karbala.csv',
    );
    final rows = const LineSplitter().convert(raw);
    final header = rows.first.split(',');
    final hijriIndex = header.indexOf('hijri_date');
    final imsakIndex = header.indexOf('imsak');
    final ishaIndex = header.indexOf('isha');
    final result = <_RamadanDay>[];
    final seen = <String>{};
    for (final row in rows.skip(1)) {
      final parts = row.split(',');
      if (parts.length <= ishaIndex) continue;
      final hijri = parts[hijriIndex];
      if (!hijri.startsWith('1447/09')) continue;
      final day = hijri.split('/').last;
      if (!seen.add(day)) continue;
      result.add(_RamadanDay(
        hijriLabel: 'رمضان $day هـ',
        imsak: parts[imsakIndex],
        isha: parts[ishaIndex],
      ));
    }
    return result;
  }
}

class _RamadanDay {
  const _RamadanDay({
    required this.hijriLabel,
    required this.imsak,
    required this.isha,
  });

  final String hijriLabel;
  final String imsak;
  final String isha;
}
