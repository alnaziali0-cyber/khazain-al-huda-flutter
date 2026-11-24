import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:khazain_al_huda/core/models.dart';
import 'package:khazain_al_huda/core/providers.dart';
import 'package:khazain_al_huda/features/home/home_screen.dart';

Future<void> _pumpHomeWithAds(
  WidgetTester tester,
  List<Map<String, dynamic>> advertisements,
) async {
  SharedPreferences.setMockInitialValues({
    'selected_governorate': 'baghdad',
    'selected_location_source': 'manual',
  });
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      prayerTimesProvider.overrideWith((ref) async => null),
      governoratesProvider.overrideWith((ref) async => [
            Governorate(
              id: 'baghdad',
              nameAr: 'بغداد',
              nameEn: 'Baghdad',
              latitude: 33.3152,
              longitude: 44.3661,
              timezone: 'Asia/Baghdad',
              coordinatesQuality: 'approximate_governorate_center',
            ),
          ]),
      homeAdvertisementsProvider.overrideWith((ref) async => advertisements),
    ],
    child: const MaterialApp(home: Scaffold(body: HomeScreen())),
  ));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('home shows a wide published text banner without exposing its URL',
      (tester) async {
    const launcherChannel = MethodChannel('plugins.flutter.io/url_launcher');
    final launchCalls = <MethodCall>[];
    launcherChannel.setMockMethodCallHandler((call) async {
      launchCalls.add(call);
      return true;
    });

    try {
      await _pumpHomeWithAds(tester, [
        {
          'content_type': 'announcement',
          'title': 'إعلان تجريبي',
          'body_markdown': 'تفاصيل قصيرة للإعلان.',
          'target_url': 'https://example.org/campaign',
          'image_url': null,
        },
      ]);

      expect(find.byKey(const ValueKey('home-announcement-carousel')),
          findsOneWidget);
      expect(find.text('إعلان تجريبي'), findsOneWidget);
      expect(find.text('تفاصيل قصيرة للإعلان.'), findsOneWidget);
      expect(find.text('https://example.org/campaign'), findsNothing);
      final bannerRect = tester.getRect(
        find.byKey(const ValueKey('home-announcement-carousel')),
      );
      expect(bannerRect.height, 116);

      await tester.tap(find.byKey(const ValueKey('home-announcement-card-surface-0')));
      await tester.pumpAndSettle();
      expect(
        launchCalls.any((call) =>
            call.arguments is Map &&
            (call.arguments as Map)['url'] ==
                'https://example.org/campaign'),
        isTrue,
      );
    } finally {
      launcherChannel.setMockMethodCallHandler(null);
    }
  });

  testWidgets('image banner opens when its surface is tapped',
      (tester) async {
    const launcherChannel = MethodChannel('plugins.flutter.io/url_launcher');
    final launchCalls = <MethodCall>[];
    launcherChannel.setMockMethodCallHandler((call) async {
      launchCalls.add(call);
      return true;
    });

    try {
      await _pumpHomeWithAds(tester, [
        {
          'content_type': 'announcement',
          'title': 'إعلان مصوّر',
          'body_markdown': '',
          'target_url': 'https://example.org/image-campaign',
          'image_url': '/media/announcement.png',
        },
      ]);

      expect(find.byKey(const ValueKey('home-announcement-card-surface-0')),
          findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('home-announcement-card-surface-0')));
      await tester.pumpAndSettle();
      expect(
        launchCalls.any((call) =>
            call.arguments is Map &&
            (call.arguments as Map)['url'] ==
                'https://example.org/image-campaign'),
        isTrue,
      );
    } finally {
      launcherChannel.setMockMethodCallHandler(null);
    }
  });

  testWidgets('home has no advertisement slot when there are no published ads',
      (tester) async {
    await _pumpHomeWithAds(tester, const []);

    expect(find.byKey(const ValueKey('home-announcement-carousel')),
        findsNothing);
  });
}
