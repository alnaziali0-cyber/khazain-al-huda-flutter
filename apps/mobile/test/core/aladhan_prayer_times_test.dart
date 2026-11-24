import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:khazain_al_huda/core/aladhan_prayer_times.dart';
import 'package:khazain_al_huda/core/models.dart';

Map<String, dynamic> _payload() => {
      'code': 200,
      'status': 'OK',
      'data': {
        'timings': {
          'Fajr': '05:01 (AST)',
          'Sunrise': '06:24',
          'Dhuhr': '11:47',
          'Asr': '14:42',
          'Sunset': '17:10',
          'Maghrib': '17:10',
          'Isha': '18:30',
          'Imsak': '04:51',
          'Midnight': '23:15',
        },
        'date': {
          'gregorian': {'date': '20-11-2026'},
          'hijri': {
            'day': '10',
            'year': '1448',
            'month': {'ar': 'جمادى الآخرة', 'en': 'Jumada al-Akhirah'},
          },
        },
        'meta': {
          'timezone': 'Asia/Baghdad',
          'method': {'id': 5, 'name': 'Egyptian General Authority of Survey'},
        },
      },
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('parses the uploaded method-5 module response and maps Arabic prayer keys',
      () async {
    final adapter = _AlAdhanAdapter(jsonEncode(_payload()));
    final repository = AlAdhanPrayerTimesRepository(dio: _dio(adapter));
    final result = await repository.fetch(
      latitude: 32.48,
      longitude: 44.43,
      date: DateTime(2026, 11, 20),
    );

    expect(adapter.request!.path, '/v1/timings/20-11-2026');
    expect(adapter.request!.queryParameters['method'], 5);
    expect(adapter.request!.queryParameters['latitude'], 32.48);
    expect(adapter.request!.queryParameters['longitude'], 44.43);
    expect(adapter.request!.queryParameters['midnightMode'], 0);
    expect(result.source, PrayerTimesSource.alAdhanApi);
    expect(result.methodLabel, contains('الهيئة المصرية'));
    expect(result.displayTimes['fajr'], '05:01');
    expect(result.displayTimes['sunrise'], '06:24');
    expect(result.displayTimes['islamic_midnight'], '23:15');
    expect(result.hijriDate, '10 جمادى الآخرة 1448 هـ');
  });

  test('keeps sunset optional because it is not part of the uploaded display list',
      () async {
    final payload = _payload();
    (payload['data']['timings'] as Map).remove('Sunset');
    final result = await AlAdhanPrayerTimesRepository(
      dio: _dio(_AlAdhanAdapter(jsonEncode(payload))),
    ).fetch(
      latitude: 32.48,
      longitude: 44.43,
      date: DateTime(2026, 11, 20),
    );

    expect(result.displayTimes['fajr'], '05:01');
    expect(result.displayTimes.containsKey('sunset'), isFalse);
  });

  test('uses AlAdhan Jafari method 0 and Jafari midnight mode when selected',
      () async {
    final payload = _payload();
    payload['data']['meta']['method'] = {
      'id': 0,
      'name': 'Jafari / Shia Ithna-Ashari',
    };
    final adapter = _AlAdhanAdapter(jsonEncode(payload));
    final repository = AlAdhanPrayerTimesRepository(dio: _dio(adapter));
    final result = await repository.fetch(
      latitude: 32.48,
      longitude: 44.43,
      date: DateTime(2026, 11, 20),
      method: 0,
    );

    expect(adapter.request!.queryParameters['method'], 0);
    expect(adapter.request!.queryParameters['midnightMode'], 1);
    expect(result.methodLabel, contains('الجعفري الاثنا عشري'));
  });

  test('does not add app device identity headers to the external request',
      () async {
    final adapter = _AlAdhanAdapter(jsonEncode(_payload()));
    await AlAdhanPrayerTimesRepository(dio: _dio(adapter)).fetch(
      latitude: 32.48,
      longitude: 44.43,
      date: DateTime(2026, 11, 20),
    );

    expect(adapter.request!.headers.keys.map((key) => key.toLowerCase()),
        isNot(contains('x-device-key')));
  });

  test('rejects malformed coordinates and unsupported methods before request',
      () async {
    final adapter = _AlAdhanAdapter(jsonEncode(_payload()));
    final repository = AlAdhanPrayerTimesRepository(dio: _dio(adapter));

    await expectLater(
      repository.fetch(
        latitude: double.nan,
        longitude: 44.43,
        date: DateTime(2026, 11, 20),
      ),
      throwsArgumentError,
    );
    await expectLater(
      repository.fetch(
        latitude: 32.48,
        longitude: 44.43,
        date: DateTime(2026, 11, 20),
        method: 99,
      ),
      throwsArgumentError,
    );
    expect(adapter.request, isNull);
  });

  test('rejects missing required prayer times and mismatched dates', () async {
    final missing = _payload();
    (missing['data']['timings'] as Map).remove('Asr');
    await expectLater(
      AlAdhanPrayerTimesRepository(
        dio: _dio(_AlAdhanAdapter(jsonEncode(missing))),
      ).fetch(
        latitude: 32.48,
        longitude: 44.43,
        date: DateTime(2026, 11, 20),
      ),
      throwsA(isA<FormatException>()),
    );

    final wrongDate = _payload();
    wrongDate['data']['date']['gregorian']['date'] = '21-11-2026';
    await expectLater(
      AlAdhanPrayerTimesRepository(
        dio: _dio(_AlAdhanAdapter(jsonEncode(wrongDate))),
      ).fetch(
        latitude: 32.48,
        longitude: 44.43,
        date: DateTime(2026, 11, 20),
      ),
      throwsA(isA<FormatException>()),
    );

    final wrongMethod = _payload();
    wrongMethod['data']['meta']['method']['id'] = 0;
    await expectLater(
      AlAdhanPrayerTimesRepository(
        dio: _dio(_AlAdhanAdapter(jsonEncode(wrongMethod))),
      ).fetch(
        latitude: 32.48,
        longitude: 44.43,
        date: DateTime(2026, 11, 20),
        method: 5,
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test('converts time digits to Arabic-Indic numerals', () {
    expect(toArabicDigits('05:10'), '٠٥:١٠');
    expect(toArabicDigits('1:02'), '١:٠٢');
  });

  test('AlAdhan cache keys include location identity, date and method without coordinates', () {
    final key = alAdhanCacheKey(
      locationIdentity: 'gps_random-token-that-is-long-enough',
      date: '2026-11-20',
      method: 0,
    );
    expect(key, 'prayer_aladhan_gps_random-token-that-is-long-enough_2026-11-20_0');
    expect(key, isNot(contains('32.48')));
  });

  test('AlAdhan source round-trips through the local cache model', () {
    final result = PrayerTimesResult(
      displayTimes: const {'fajr': '05:01'},
      date: '2026-11-20',
      methodLabel: 'AlAdhan test',
      definitions: const {'method_id': 0},
      isStale: false,
      source: PrayerTimesSource.alAdhanApi,
    );
    final restored = PrayerTimesResult.fromJson(result.toJson());
    expect(restored.source, PrayerTimesSource.alAdhanApi);
    expect(restored.displayTimes['fajr'], '05:01');
  });
}

Dio _dio(_AlAdhanAdapter adapter) {
  final dio = Dio(BaseOptions(
    baseUrl: AlAdhanPrayerTimesRepository.baseUrl,
    headers: const {'Accept': 'application/json'},
  ));
  dio.httpClientAdapter = adapter;
  return dio;
}

class _AlAdhanAdapter implements HttpClientAdapter {
  _AlAdhanAdapter(this.body);

  final String body;
  final int statusCode = 200;
  RequestOptions? request;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    request = options;
    return ResponseBody.fromString(
      body,
      statusCode,
      headers: {
        Headers.contentTypeHeader: ['application/json; charset=utf-8'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
