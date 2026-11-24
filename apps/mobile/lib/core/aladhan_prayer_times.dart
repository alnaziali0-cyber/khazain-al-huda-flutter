import 'package:dio/dio.dart';

import 'models.dart';

/// Localized digits retained from the uploaded JavaScript module.
String toArabicDigits(Object? value) => (value ?? '').toString().replaceAllMapped(
      RegExp(r'[0-9]'),
      (match) => '٠١٢٣٤٥٦٧٨٩'[int.parse(match.group(0)!)],
    );

/// Read-only AlAdhan client adapted from the uploaded AlFirdaws module.
/// It intentionally uses a dedicated Dio client without app/device interceptors.
class AlAdhanPrayerTimesRepository {
  AlAdhanPrayerTimesRepository({Dio? dio}) : _dio = dio ?? createDio();

  static const baseUrl = 'https://api.aladhan.com';
  static const defaultMethod = 5; // Preserved from the uploaded source module.
  static const shiaMethod = 0; // AlAdhan: Jafari / Shia Ithna-Ashari.
  static const egyptianMethod = 5; // Egyptian General Authority of Survey.

  final Dio _dio;

  static Dio createDio() => Dio(BaseOptions(
        baseUrl: baseUrl,
        connectTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 12),
        sendTimeout: const Duration(seconds: 8),
        headers: const {'Accept': 'application/json'},
      ));

  /// Fetches a specific Gregorian calendar day in the selected location's
  /// local calculation convention. Coordinates are sent directly to AlAdhan.
  Future<PrayerTimesResult> fetch({
    required double latitude,
    required double longitude,
    required DateTime date,
    int method = defaultMethod,
  }) async {
    _validateCoordinates(latitude, longitude);
    if (method != shiaMethod && method != egyptianMethod) {
      throw ArgumentError.value(method, 'method', 'Unsupported AlAdhan method.');
    }

    final apiDate = _formatApiDate(date);
    final response = await _dio.get<dynamic>(
      '/v1/timings/$apiDate',
      queryParameters: {
        'latitude': latitude,
        'longitude': longitude,
        'method': method,
        'midnightMode': method == shiaMethod ? 1 : 0,
      },
    );

    final payload = response.data;
    if (payload is! Map || payload['code'] != 200 || payload['data'] is! Map) {
      throw const FormatException('استجابة AlAdhan غير صالحة.');
    }
    final data = Map<String, dynamic>.from(payload['data'] as Map);
    final rawTimings = data['timings'];
    if (rawTimings is! Map) {
      throw const FormatException('استجابة AlAdhan لا تحتوي على المواقيت.');
    }
    final timings = Map<String, dynamic>.from(rawTimings);

    const requiredFields = <String, String>{
      'Fajr': 'fajr',
      'Sunrise': 'sunrise',
      'Dhuhr': 'dhuhr',
      'Asr': 'asr',
      'Maghrib': 'maghrib',
      'Isha': 'isha',
    };
    final displayTimes = <String, String>{};
    for (final entry in requiredFields.entries) {
      displayTimes[entry.value] = _requiredClock(timings, entry.key);
    }

    // The supplied module displays six prayer/solar entries. Sunset, Imsak,
    // and midnight are optional extras and must not make a valid API response fail.
    final sunset = _optionalClock(timings, 'Sunset');
    if (sunset != null) displayTimes['sunset'] = sunset;
    final imsak = _optionalClock(timings, 'Imsak');
    if (imsak != null) displayTimes['imsak'] = imsak;
    final midnight = _optionalClock(timings, 'Midnight');
    if (midnight != null) displayTimes['islamic_midnight'] = midnight;

    final dateData = data['date'] is Map
        ? Map<String, dynamic>.from(data['date'] as Map)
        : const <String, dynamic>{};
    final gregorian = dateData['gregorian'] is Map
        ? Map<String, dynamic>.from(dateData['gregorian'] as Map)
        : const <String, dynamic>{};
    if (gregorian['date'] is! String || gregorian['date'] != apiDate) {
      throw FormatException('تاريخ AlAdhan لا يطابق التاريخ المطلوب: $apiDate.');
    }
    final hijri = dateData['hijri'] is Map
        ? Map<String, dynamic>.from(dateData['hijri'] as Map)
        : const <String, dynamic>{};
    final meta = data['meta'] is Map
        ? Map<String, dynamic>.from(data['meta'] as Map)
        : const <String, dynamic>{};
    final methodData = meta['method'] is Map
        ? Map<String, dynamic>.from(meta['method'] as Map)
        : const <String, dynamic>{};
    final reportedMethodId = methodData['id'];
    if (reportedMethodId is! num || reportedMethodId.toInt() != method) {
      throw FormatException(
        'طريقة الحساب الواردة من AlAdhan لا تطابق الطريقة المطلوبة ($method).',
      );
    }

    final methodLabel = method == shiaMethod
        ? 'الجعفري الاثنا عشري — AlAdhan (0)'
        : 'الهيئة المصرية العامة للمساحة — AlAdhan (5)';

    return PrayerTimesResult(
      date: _dateKey(date),
      displayTimes: displayTimes,
      methodLabel: methodLabel,
      definitions: {
        'provider': 'AlAdhan',
        'source_url': '$baseUrl/v1/timings/$apiDate',
        'method_id': method,
        'method_name': methodData['name']?.toString() ?? methodLabel,
        'timezone': meta['timezone']?.toString(),
        'coordinate_delivery': 'direct_https_to_aladhan',
        'authority_approved': false,
      },
      isStale: false,
      source: PrayerTimesSource.alAdhanApi,
      hijriDate: _formatHijri(hijri),
    );
  }

  static String _formatApiDate(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}-${date.month.toString().padLeft(2, '0')}-${date.year.toString().padLeft(4, '0')}';

  static String _dateKey(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  static String _requiredClock(Map<String, dynamic> timings, String key) {
    final value = _optionalClock(timings, key);
    if (value == null) {
      throw FormatException('وقت $key غير موجود أو غير صالح في استجابة AlAdhan.');
    }
    return value;
  }

  static String? _optionalClock(Map<String, dynamic> timings, String key) {
    final raw = timings[key];
    if (raw is! String) return null;
    final match = RegExp(r'^\s*(\d{1,2}):(\d{2})').firstMatch(raw);
    if (match == null) return null;
    final hour = int.tryParse(match.group(1)!);
    final minute = int.tryParse(match.group(2)!);
    if (hour == null || minute == null || hour < 0 || hour > 23 || minute < 0 || minute > 59) {
      return null;
    }
    return '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
  }

  static String? _formatHijri(Map<String, dynamic> hijri) {
    final day = hijri['day']?.toString();
    final year = hijri['year']?.toString();
    final month = hijri['month'];
    final monthName = month is Map
        ? (month['ar'] ?? month['en'])?.toString()
        : null;
    if (day == null || year == null || monthName == null) return null;
    return '$day $monthName $year هـ';
  }

  static void _validateCoordinates(double latitude, double longitude) {
    if (!latitude.isFinite || latitude < -90 || latitude > 90) {
      throw ArgumentError.value(latitude, 'latitude', 'Invalid latitude.');
    }
    if (!longitude.isFinite || longitude < -180 || longitude > 180) {
      throw ArgumentError.value(longitude, 'longitude', 'Invalid longitude.');
    }
  }
}

int alAdhanMethodForSource(String source) => switch (source) {
      'aladhan_jafari' => AlAdhanPrayerTimesRepository.shiaMethod,
      'aladhan_egyptian' => AlAdhanPrayerTimesRepository.egyptianMethod,
      _ => throw ArgumentError.value(source, 'source', 'Not an AlAdhan source.'),
    };

String alAdhanCacheKey({
  required String locationIdentity,
  required String date,
  required int method,
}) {
  if (!RegExp(r'^(city|gps|governorate)_[A-Za-z0-9_-]{1,160}$')
          .hasMatch(locationIdentity) ||
      !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(date) ||
      (method != AlAdhanPrayerTimesRepository.shiaMethod &&
          method != AlAdhanPrayerTimesRepository.egyptianMethod)) {
    throw ArgumentError('Invalid AlAdhan prayer cache identity.');
  }
  return 'prayer_aladhan_${locationIdentity}_${date}_$method';
}
