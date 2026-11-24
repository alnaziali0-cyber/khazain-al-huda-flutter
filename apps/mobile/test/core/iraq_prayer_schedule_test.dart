import 'package:flutter_test/flutter_test.dart';
import 'package:khazain_al_huda/core/iraq_prayer_schedule.dart';
import 'package:khazain_al_huda/core/models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late IraqPrayerScheduleRepository repository;
  setUp(() => repository = IraqPrayerScheduleRepository());

  test('loads the Hilla Jaafari timetable offline with its source metadata',
      () async {
    final result = await repository.lookup(
      date: DateTime(2026, 1, 1),
      governorateId: 'babil',
    );

    expect(result, isNotNull);
    expect(result!.source, PrayerTimesSource.iraqJafariSchedule);
    expect(result.locationName, 'الحلة · بابل');
    expect(result.hijriDate, '1447/07/11');
    expect(result.displayTimes['imsak'], '05:36');
    expect(result.displayTimes['fajr'], '05:46');
    expect(result.displayTimes['sunrise'], '07:04');
    expect(result.displayTimes['dhuhr'], '12:06');
    expect(result.displayTimes['maghrib'], '17:24');
    expect(result.displayTimes['islamic_midnight'], '23:27');
    expect(result.definitions['officially_verified'], isFalse);

    final restored = PrayerTimesResult.fromJson(result.toJson());
    expect(restored.source, PrayerTimesSource.iraqJafariSchedule);
    expect(restored.displayTimes, result.displayTimes);
  });

  test('uses the selected city row rather than the governorate capital',
      () async {
    final result = await repository.lookup(
      date: DateTime(2026, 1, 1),
      governorateId: 'saladin',
      cityId: 'IQ-SD-SAM',
    );

    expect(result, isNotNull);
    expect(result!.locationName, 'سامراء · صلاح الدين');
  });

  test('declines unsupported locations and dates outside the bundled range',
      () async {
    expect(
      await repository.lookup(
        date: DateTime(2026, 11, 18),
        governorateId: 'halabja',
      ),
      isNull,
    );
    expect(
      await repository.lookup(
        date: DateTime(2028, 1, 1),
        governorateId: 'baghdad',
      ),
      isNull,
    );
  });
}
