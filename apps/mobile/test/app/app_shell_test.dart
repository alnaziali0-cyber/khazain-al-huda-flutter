import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:khazain_al_huda/app/app_shell.dart';
import 'package:khazain_al_huda/components/bottom_nav.dart';
import 'package:khazain_al_huda/core/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('the bottom navigation exposes five destinations in RTL order',
      (tester) async {
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        ShellRoute(
          builder: (context, state, child) =>
              AppShell(location: state.uri.path, child: child),
          routes: [
            GoRoute(
              path: '/',
              builder: (context, state) => const Text('route:home'),
            ),
            GoRoute(
              path: '/quran',
              builder: (context, state) => const Text('route:quran'),
              routes: [
                GoRoute(
                  path: ':surahNumber',
                  builder: (context, state) => Text(
                      'route:quran:${state.pathParameters['surahNumber']}'),
                ),
              ],
            ),
            GoRoute(
              path: '/duas',
              builder: (context, state) => const Text('route:duas'),
            ),
            GoRoute(
              path: '/library',
              builder: (context, state) => const Text('route:library'),
            ),
            GoRoute(
              path: '/sections',
              builder: (context, state) => const Text('route:sections'),
            ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);

    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        child: MaterialApp.router(
          routerConfig: router,
          locale: const Locale('ar'),
          supportedLocales: const [Locale('ar')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('route:home'), findsOneWidget);

    // Five core destinations are always visible in the primary navigation.
    expect(find.text('الرئيسية'), findsOneWidget);
    expect(find.text('القرآن'), findsOneWidget);
    expect(find.text('الأدعية'), findsOneWidget);
    expect(find.text('المكتبة'), findsOneWidget);
    expect(find.text('المزيد'), findsOneWidget);

    // The right-most tab is the home tab in an RTL layout.
    final labels = tester.widgetList<Text>(find.text('الرئيسية')).toList();
    expect(labels, isNotEmpty);

    await tester.tap(find.text('القرآن'));
    await tester.pumpAndSettle();
    expect(find.text('route:quran'), findsOneWidget);

    await tester.tap(find.text('الأدعية'));
    await tester.pumpAndSettle();
    expect(find.text('route:duas'), findsOneWidget);

    await tester.tap(find.text('المكتبة'));
    await tester.pumpAndSettle();
    expect(find.text('route:library'), findsOneWidget);

    await tester.tap(find.text('المزيد'));
    await tester.pumpAndSettle();
    expect(find.text('route:sections'), findsOneWidget);

    // The logo has a developer-panel long-press gesture, but a normal tap
    // must still navigate to the home destination.
    await tester.tap(find.byType(Image).first);
    await tester.pumpAndSettle();
    expect(find.text('route:home'), findsOneWidget);
  });

  test('the five navigation items are ordered from right to left', () {
    expect(
      kBottomNavItems.map((item) => item.label).toList(),
      <String>['الرئيسية', 'القرآن', 'الأدعية', 'المكتبة', 'المزيد'],
    );
    expect(
      kBottomNavItems.map((item) => item.route).toList(),
      <String>['/', '/quran', '/duas', '/library', '/sections'],
    );
  });
}
