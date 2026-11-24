import 'package:flutter/services.dart';

import 'models.dart';

/// Offline Ja'fari timetable distributed with the November 2026 data bundle.
/// It is a calculated reference table, not an official or marja-approved calendar.
class IraqPrayerScheduleRepository {
  static const _assetPrefix = 'assets/data/prayer_times/';
  static const _files = <String, String>{
    'anbar': 'anbar.csv',
    'muthanna': 'muthanna.csv',
    'qadisiyyah': 'qadisiyyah.csv',
    'babil': 'babil.csv',
    'baghdad': 'baghdad.csv',
    'basra': 'basra.csv',
    'dhi_qar': 'dhi_qar.csv',
    'diyala': 'diyala.csv',
    'duhok': 'duhok.csv',
    'erbil': 'erbil.csv',
    'karbala': 'karbala.csv',
    'kirkuk': 'kirkuk.csv',
    'maysan': 'maysan.csv',
    'najaf': 'najaf.csv',
    'nineveh': 'nineveh.csv',
    'saladin': 'saladin.csv',
    'sulaymaniyah': 'sulaymaniyah.csv',
    'wasit': 'wasit.csv',
  };

  static const _capitals = <String, String>{
    'anbar': 'الرمادي',
    'muthanna': 'السماوة',
    'qadisiyyah': 'الديوانية',
    'babil': 'الحلة',
    'baghdad': 'بغداد',
    'basra': 'البصرة',
    'dhi_qar': 'الناصرية',
    'diyala': 'بعقوبة',
    'duhok': 'دهوك',
    'erbil': 'أربيل',
    'karbala': 'كربلاء',
    'kirkuk': 'كركوك',
    'maysan': 'العمارة',
    'najaf': 'النجف',
    'nineveh': 'الموصل',
    'saladin': 'تكريت',
    'sulaymaniyah': 'السليمانية',
    'wasit': 'الكوت',
  };

  static const _governorateNames = <String, String>{
    'anbar': 'الأنبار',
    'muthanna': 'المثنى',
    'qadisiyyah': 'القادسية',
    'babil': 'بابل',
    'baghdad': 'بغداد',
    'basra': 'البصرة',
    'dhi_qar': 'ذي قار',
    'diyala': 'ديالى',
    'duhok': 'دهوك',
    'erbil': 'أربيل',
    'karbala': 'كربلاء',
    'kirkuk': 'كركوك',
    'maysan': 'ميسان',
    'najaf': 'النجف',
    'nineveh': 'نينوى',
    'saladin': 'صلاح الدين',
    'sulaymaniyah': 'السليمانية',
    'wasit': 'واسط',
  };

  // These IDs are the app's existing public city-catalog identifiers.
  static const _cityById = <String, ({String governorateId, String name})>{
    'IQ-BG-BAG': (governorateId: 'baghdad', name: 'بغداد'),
    'IQ-BB-HIL': (governorateId: 'babil', name: 'الحلة'),
    'IQ-KR-KAR': (governorateId: 'karbala', name: 'كربلاء'),
    'IQ-NJ-NAJ': (governorateId: 'najaf', name: 'النجف'),
    'IQ-BS-BAS': (governorateId: 'basra', name: 'البصرة'),
    'IQ-NI-MOS': (governorateId: 'nineveh', name: 'الموصل'),
    'IQ-AN-RAM': (governorateId: 'anbar', name: 'الرمادي'),
    'IQ-SD-TIK': (governorateId: 'saladin', name: 'تكريت'),
    'IQ-DY-BAQ': (governorateId: 'diyala', name: 'بعقوبة'),
    'IQ-WA-KUT': (governorateId: 'wasit', name: 'الكوت'),
    'IQ-QD-DIW': (governorateId: 'qadisiyyah', name: 'الديوانية'),
    'IQ-DQ-NAS': (governorateId: 'dhi_qar', name: 'الناصرية'),
    'IQ-MS-AMR': (governorateId: 'maysan', name: 'العمارة'),
    'IQ-MT-SAM': (governorateId: 'muthanna', name: 'السماوة'),
    'IQ-KK-KIR': (governorateId: 'kirkuk', name: 'كركوك'),
    'IQ-AR-ERB': (governorateId: 'erbil', name: 'أربيل'),
    'IQ-SL-SUL': (governorateId: 'sulaymaniyah', name: 'السليمانية'),
    'IQ-DH-DUH': (governorateId: 'duhok', name: 'دهوك'),
    'IQ-HL-HAL': (governorateId: 'halabja', name: 'حلبجة'),
    'IQ-SD-SAM': (governorateId: 'saladin', name: 'سامراء'),
  };

  final Map<String, Future<List<_PrayerScheduleRow>>> _loads = {};

  Future<PrayerTimesResult?> lookup({
    required DateTime date,
    required String? governorateId,
    String? cityId,
  }) async {
    final day = DateTime(date.year, date.month, date.day);
    if (day.isBefore(DateTime(2026, 1, 1)) ||
        day.isAfter(DateTime(2027, 12, 31))) {
      return null;
    }

    final selectedCity = cityId == null ? null : _cityById[cityId];
    if (cityId != null && selectedCity == null) return null;
    if (selectedCity != null && governorateId != null &&
        selectedCity.governorateId != governorateId) {
      return null;
    }
    final effectiveGovernorate = selectedCity?.governorateId ?? governorateId;
    if (effectiveGovernorate == null || !_files.containsKey(effectiveGovernorate)) {
      return null;
    }
    if (cityId != null && selectedCity == null) return null;

    final rows = await (_loads[effectiveGovernorate] ??=
        _loadGovernorate(effectiveGovernorate));
    final dateKey = _formatDate(day);
    final cityName = selectedCity?.name ?? _capitals[effectiveGovernorate];
    if (cityName == null) return null;

    _PrayerScheduleRow? matched;
    for (final row in rows) {
      if (row.date == dateKey && row.city == cityName) {
        matched = row;
        break;
      }
    }
    if (matched == null) return null;

    final governorateName = _governorateNames[effectiveGovernorate] ?? '';
    return PrayerTimesResult(
      displayTimes: {
        'imsak': matched.imsak,
        'fajr': matched.fajr,
        'sunrise': matched.sunrise,
        'dhuhr': matched.dhuhr,
        'asr': matched.asr,
        'sunset': matched.sunset,
        'maghrib': matched.maghrib,
        'isha': matched.isha,
        'islamic_midnight': matched.midnight,
      },
      date: dateKey,
      methodLabel: 'جدول جعفري محلي — صيغة حساب قم (غير معتمد مرجعياً)',
      definitions: const {
        'method': 'jafari_qom_variant',
        'fajr_degrees': 16,
        'maghrib_degrees': 4,
        'isha_degrees': 14,
        'sunrise_refraction_degrees': 0.833,
        'asr_shadow_factor': 1,
        'midnight_definition': 'midpoint_between_sunset_and_next_fajr',
        'calculation_precision': 'NOAA/Meeus low precision',
        'officially_verified': false,
      },
      isStale: false,
      source: PrayerTimesSource.iraqJafariSchedule,
      // The source column is tagged iran_official, not an Iraqi moon-sighting
      // authority. Do not expose it as the user's Hijri date.
      hijriDate: null,
      locationName: '$cityName · $governorateName',
      coordinateAccuracy: 'approximate_city_center_calculated_schedule',
      coordinateSource: 'local_iraq_jafari_2026_2027_dataset',
      locationVerified: false,
    );
  }

  Future<List<_PrayerScheduleRow>> _loadGovernorate(String id) async {
    final filename = _files[id];
    if (filename == null) return const [];
    final source = await rootBundle.loadString('$_assetPrefix$filename');
    final lines = source.split('\n');
    if (lines.isEmpty ||
        lines.first.trim() !=
            'location_id,date,hijri_date,hijri_basis,city_ar,governorate_ar,imsak,fajr,sunrise,dhuhr,asr,sunset,maghrib,isha,midnight') {
      throw const FormatException('Invalid Iraqi prayer timetable asset.');
    }
    final rows = <_PrayerScheduleRow>[];
    for (var index = 1; index < lines.length; index++) {
      final line = lines[index].trim();
      if (line.isEmpty) continue;
      final columns = line.split(',');
      if (columns.length != 15 || !_isValidClock(columns[7]) ||
          !_isValidClock(columns[8]) || !_isValidClock(columns[9]) ||
          !_isValidClock(columns[10]) || !_isValidClock(columns[11]) ||
          !_isValidClock(columns[12]) || !_isValidClock(columns[13]) ||
          !_isValidClock(columns[14])) {
        throw const FormatException('Malformed prayer timetable row.');
      }
      rows.add(_PrayerScheduleRow(
        date: columns[1],
        hijriDate: columns[2],
        city: columns[4],
        imsak: columns[6],
        fajr: columns[7],
        sunrise: columns[8],
        dhuhr: columns[9],
        asr: columns[10],
        sunset: columns[11],
        maghrib: columns[12],
        isha: columns[13],
        midnight: columns[14],
      ));
    }
    return List<_PrayerScheduleRow>.unmodifiable(rows);
  }

  static bool _isValidClock(String value) =>
      RegExp(r'^(?:[01]\d|2[0-3]):[0-5]\d$').hasMatch(value);

  static String _formatDate(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}

class _PrayerScheduleRow {
  const _PrayerScheduleRow({
    required this.date,
    required this.hijriDate,
    required this.city,
    required this.imsak,
    required this.fajr,
    required this.sunrise,
    required this.dhuhr,
    required this.asr,
    required this.sunset,
    required this.maghrib,
    required this.isha,
    required this.midnight,
  });

  final String date;
  final String hijriDate;
  final String city;
  final String imsak;
  final String fajr;
  final String sunrise;
  final String dhuhr;
  final String asr;
  final String sunset;
  final String maghrib;
  final String isha;
  final String midnight;
}
