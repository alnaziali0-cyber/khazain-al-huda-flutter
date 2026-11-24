import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:khazain_al_huda/core/providers.dart';
import 'package:khazain_al_huda/features/mukhalafat/mukhalafat_screen.dart';
import 'package:khazain_al_huda/features/mukhalafat/mukhalafat_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _pumpMukhalafat(
    WidgetTester tester, {
  Size size = const Size(412, 900),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();

  await tester.pumpWidget(
    ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: const MaterialApp(home: Scaffold(body: MukhalafatScreen())),
    ),
  );
  await _settle(tester);
}

/// The screen loads the offline library, so the test pumps a few frames
/// instead of waiting for an endless progress animation to stop.
Future<void> _settle(WidgetTester tester) async {
  for (var index = 0; index < 12; index++) {
    await tester.pump(const Duration(milliseconds: 120));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the grid shows the six adhkar cards and never a blank tile',
      (tester) async {
    await _pumpMukhalafat(tester);

    for (final title in const [
      'أذكار الصباح والمساء',
      'أذكار بعد الصلاة',
      'أذكار النوم',
      'الاستغفار والتسبيح',
      'دعاء الكرب',
      'الرقية الشرعية',
    ]) {
      expect(find.text(title), findsOneWidget, reason: 'missing card $title');
    }
  });

  testWidgets('the floating action writes a new entry into the grid',
      (tester) async {
    await _pumpMukhalafat(tester);

    expect(find.byType(FloatingActionButton), findsOneWidget);
    expect(find.text('إضافة ذكر أو ورد'), findsOneWidget);

    await tester.tap(find.text('إضافة ذكر أو ورد'));
    await _settle(tester);

    await tester.enterText(
      find.widgetWithText(TextField, 'العنوان'),
      'ورد الصباح',
    );
    await _settle(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'حفظ'));
    await _settle(tester);

    expect(find.text('ورد الصباح'), findsOneWidget);
  });

  testWidgets('the layout does not overflow at the reference widths',
      (tester) async {
    await _pumpMukhalafat(tester, size: const Size(320, 900));
    expect(tester.takeException(), isNull, reason: 'overflow at 320');
    for (final width in const [360.0, 412.0, 768.0, 1024.0]) {
      tester.view.physicalSize = Size(width, 900);
      await _settle(tester);
      expect(tester.takeException(), isNull, reason: 'overflow at $width');
    }
  });

  test('the store keeps the entries the user adds', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final store = MukhalafatStore(prefs);

    store.add(title: 'ورد', note: 'يومي');
    expect(store.state.length, 1);
    expect(store.state.single.title, 'ورد');

    store.remove(store.state.single.id);
    expect(store.state, isEmpty);
  });
}
