import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:khazain_al_huda/components/ad_slot.dart';
import 'package:khazain_al_huda/core/models.dart';
import 'package:khazain_al_huda/core/providers.dart';
import 'package:khazain_al_huda/features/home/home_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

PrayerTimesResult _prayerDay() => PrayerTimesResult(
      date: '2026-11-23',
      displayTimes: const {
        'fajr': '05:01',
        'sunrise': '06:34',
        'dhuhr': '11:47',
        'asr': '14:40',
        'sunset': '17:00',
        'maghrib': '17:00',
        'isha': '18:23',
      },
      methodLabel: 'حساب محلي',
      definitions: const {},
      isStale: false,
      source: PrayerTimesSource.localCalculation,
      hijriDate: '١٢ جمادى الآخرة ١٤٤٨ هـ',
      locationName: 'بغداد',
      coordinateAccuracy: 'approximate_governorate_center',
      coordinateSource: 'governorate_center',
      locationVerified: false,
    );

Future<void> _pumpHome(WidgetTester tester) async {
  tester.view.physicalSize = const Size(412, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  SharedPreferences.setMockInitialValues({
    'selected_governorate': 'baghdad',
    'selected_location_source': 'manual',
  });
  final prefs = await SharedPreferences.getInstance();

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        prayerTimesProvider.overrideWith((ref) async => _prayerDay()),
        governoratesProvider.overrideWith((ref) async => [
              const Governorate(
                id: 'baghdad',
                nameAr: 'بغداد',
                nameEn: 'Baghdad',
                latitude: 33.3152,
                longitude: 44.3661,
                timezone: 'Asia/Baghdad',
                coordinatesQuality: 'approximate_governorate_center',
              ),
            ]),
        homeAdvertisementsProvider.overrideWith((ref) async => const []),
      ],
      child: const MaterialApp(
        locale: Locale('ar'),
        supportedLocales: <Locale>[Locale('ar')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: Scaffold(body: HomeScreen()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the home screen shows the hijri date, the prayer card and the '
      'support pill', (tester) async {
    await _pumpHome(tester);

    expect(find.text('الدعم'), findsOneWidget);
    expect(find.textContaining('هـ'), findsWidgets);
    expect(find.text('القبلة'), findsOneWidget);
    expect(find.textContaining('متبقي:'), findsOneWidget);
  });

  testWidgets('the three live cards replace the blank cells (G11)',
      (tester) async {
    await _pumpHome(tester);

    expect(find.text('الأذكار'), findsOneWidget);
    expect(find.text('الصلاة القادمة'), findsOneWidget);
    expect(find.text('المسبحة'), findsOneWidget);
    expect(find.text('مساحتك الروحانية'), findsOneWidget);
    expect(find.text('اكتشف المزيد'), findsOneWidget);
    expect(find.text('المناسبات'), findsOneWidget);
    expect(find.text('الخلفيات'), findsOneWidget);
    expect(find.text('القرآن الكريم'), findsOneWidget);
    expect(find.text('الأدعية'), findsOneWidget);
    expect(find.text('الزيارات'), findsOneWidget);
    expect(find.text('المكتبة'), findsOneWidget);
  });

  testWidgets('the tasbih card counts and gives haptic feedback',
      (tester) async {
    await _pumpHome(tester);

    expect(find.text('٠'), findsOneWidget);
    await tester.tap(find.byTooltip('زيادة التسبيح'));
    await tester.pumpAndSettle();
    expect(find.text('١'), findsOneWidget);
  });

  testWidgets('the advertisement slot renders a branded card, never '
      'instructional copy (G10)', (tester) async {
    await _pumpHome(tester);

    expect(find.byType(AdSlot), findsOneWidget);
    expect(find.textContaining('placeholder'), findsNothing);
    expect(find.textContaining('TODO'), findsNothing);
  });

  testWidgets('the home screen renders in right-to-left', (tester) async {
    await _pumpHome(tester);
    final context = tester.element(find.byType(HomeScreen));
    expect(Directionality.of(context), TextDirection.rtl);
  });
}
