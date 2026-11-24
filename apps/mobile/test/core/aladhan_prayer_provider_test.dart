import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:khazain_al_huda/core/aladhan_prayer_times.dart';
import 'package:khazain_al_huda/core/location_coordinates_store.dart';
import 'package:khazain_al_huda/core/models.dart';
import 'package:khazain_al_huda/core/providers.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

final _baghdad = Governorate(
  id: 'baghdad',
  nameAr: 'بغداد',
  nameEn: 'Baghdad',
  latitude: 33.3152,
  longitude: 44.3661,
  timezone: 'Asia/Baghdad',
  coordinatesQuality: 'approximate_governorate_center',
);

DateTime _baghdadToday() {
  final zone = tz.getLocation('Asia/Baghdad');
  final now = tz.TZDateTime.from(DateTime.now().toUtc(), zone);
  return DateTime(now.year, now.month, now.day);
}

class _FakeCoordinatesStore implements LocationCoordinatesStore {
  _FakeCoordinatesStore([this.value]);

  final StoredLocationCoordinates? value;

  @override
  Future<StoredLocationCoordinates?> read() async => value;
  @override
  Future<void> clear() async {}
  @override
  Future<void> write(StoredLocationCoordinates coordinates) async {}
}

class _FakeAlAdhanRepository extends AlAdhanPrayerTimesRepository {
  int calls = 0;
  int? lastMethod;
  double? lastLatitude;
  double? lastLongitude;
  DateTime? lastDate;

  @override
  Future<PrayerTimesResult> fetch({
    required double latitude,
    required double longitude,
    required DateTime date,
    int method = AlAdhanPrayerTimesRepository.defaultMethod,
  }) async {
    calls++;
    lastMethod = method;
    lastLatitude = latitude;
    lastLongitude = longitude;
    lastDate = date;
    return PrayerTimesResult(
      date: '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}',
      displayTimes: const {
        'fajr': '05:01',
        'sunrise': '06:24',
        'dhuhr': '11:47',
        'asr': '14:42',
        'sunset': '17:10',
        'maghrib': '17:10',
        'isha': '18:30',
      },
      methodLabel: method == 0 ? 'AlAdhan Jafari' : 'AlAdhan Egyptian',
      definitions: {'method_id': method},
      isStale: false,
      source: PrayerTimesSource.alAdhanApi,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tz_data.initializeTimeZones();

  test('selected AlAdhan Jafari source is used for requested dates', () async {
    SharedPreferences.setMockInitialValues({
      'selected_governorate': 'baghdad',
      'selected_location_source': 'manual',
      'prayer_data_source': 'aladhan_jafari',
      'aladhan_location_sharing_consent': true,
    });
    final prefs = await SharedPreferences.getInstance();
    final api = _FakeAlAdhanRepository();
    final container = ProviderContainer(overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      governoratesProvider.overrideWith((ref) async => [_baghdad]),
      prayerCitiesProvider.overrideWith((ref) async => const []),
      locationCoordinatesStoreProvider
          .overrideWithValue(_FakeCoordinatesStore()),
      alAdhanPrayerTimesApiSourceProvider.overrideWithValue(api),
    ]);
    addTearDown(container.dispose);

    final requestedDay = _baghdadToday();
    final result = await container.read(
      prayerTimesForDateProvider(requestedDay).future,
    );

    expect(api.calls, 1);
    expect(api.lastMethod, 0);
    expect(api.lastLatitude, 33.3152);
    expect(api.lastLongitude, 44.3661);
    expect(api.lastDate, requestedDay);
    expect(result!.source, PrayerTimesSource.alAdhanApi);
    expect(result.locationName, 'بغداد');
  });

  test('AlAdhan can use saved GPS coordinates without a governorate selection',
      () async {
    SharedPreferences.setMockInitialValues({
      'selected_location_source': 'gps',
      'prayer_data_source': 'aladhan_jafari',
      'aladhan_location_sharing_consent': true,
    });
    final prefs = await SharedPreferences.getInstance();
    final api = _FakeAlAdhanRepository();
    final container = ProviderContainer(overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      governoratesProvider.overrideWith((ref) async => const []),
      prayerCitiesProvider.overrideWith((ref) async => const []),
      locationCoordinatesStoreProvider.overrideWithValue(
        _FakeCoordinatesStore(const StoredLocationCoordinates(
          latitude: 32.54,
          longitude: 44.42,
          source: 'gps',
          cacheToken: '01234567890123456789',
        )),
      ),
      alAdhanPrayerTimesApiSourceProvider.overrideWithValue(api),
    ]);
    addTearDown(container.dispose);

    final result = await container.read(
      prayerTimesForDateProvider(_baghdadToday()).future,
    );

    expect(api.calls, 1);
    expect(api.lastLatitude, 32.54);
    expect(api.lastLongitude, 44.42);
    expect(result, isNotNull);
    expect(result!.coordinateSource, 'device_location_permission');
  });

  test('external AlAdhan request is blocked when location consent is absent',
      () async {
    SharedPreferences.setMockInitialValues({
      'selected_governorate': 'baghdad',
      'selected_location_source': 'manual',
      'prayer_data_source': 'aladhan_egyptian',
    });
    final prefs = await SharedPreferences.getInstance();
    final api = _FakeAlAdhanRepository();
    final container = ProviderContainer(overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      governoratesProvider.overrideWith((ref) async => [_baghdad]),
      prayerCitiesProvider.overrideWith((ref) async => const []),
      locationCoordinatesStoreProvider
          .overrideWithValue(_FakeCoordinatesStore()),
      alAdhanPrayerTimesApiSourceProvider.overrideWithValue(api),
    ]);
    addTearDown(container.dispose);

    await expectLater(
      container.read(prayerTimesForDateProvider(_baghdadToday()).future),
      throwsA(isA<StateError>()),
    );
    expect(api.calls, 0);
  });
}
