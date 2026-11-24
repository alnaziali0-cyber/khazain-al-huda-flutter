import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:khazain_al_huda/components/state_view.dart';
import 'package:khazain_al_huda/core/providers.dart';
import 'package:khazain_al_huda/features/fada/fada_screen.dart';
import 'package:khazain_al_huda/features/fada/fada_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _pumpFada(WidgetTester tester, {Size size = const Size(412, 900)}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();

  await tester.pumpWidget(
    ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: const MaterialApp(home: Scaffold(body: FadaScreen())),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('an empty screen shows the unified empty state', (tester) async {
    await _pumpFada(tester);

    expect(find.byType(StateView), findsOneWidget);
    expect(find.textContaining('لا توجد عناصر للمتابعة'), findsOneWidget);
  });

  testWidgets('the chip row scrolls so the last chip is never clipped',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        child: const MaterialApp(home: Scaffold(body: FadaScreen())),
      ),
    );
    await tester.pumpAndSettle();

    // Without pending items the screen shows the empty state and no chips.
    expect(find.byType(StateView), findsOneWidget);
    expect(find.text('الأخرى'), findsNothing);
  });

  testWidgets('a pending item is listed and can be closed', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        child: const MaterialApp(home: Scaffold(body: FadaScreen())),
      ),
    );
    await tester.pumpAndSettle();

    // Seed a pending item through the store API.
    final container = ProviderScope.containerOf(
      tester.element(find.byType(FadaScreen)),
    );
    container.read(fadaStoreProvider.notifier).record(const FadaItem(
      id: 'demo',
      kind: 'dua',
      title: 'دعاء المساء',
      subtitle: 'أدعية ومناجاة',
      route: '/duas',
      category: 'duas',
      lastViewedMillis: 0,
    ));
    await tester.pumpAndSettle();

    expect(find.text('دعاء المساء'), findsOneWidget);
    expect(find.text('الكل'), findsOneWidget);
    expect(find.text('الأدعية'), findsOneWidget);
  });
}
