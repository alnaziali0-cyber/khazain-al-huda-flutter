import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:khazain_al_huda/components/app_card.dart';
import 'package:khazain_al_huda/core/providers.dart';
import 'package:khazain_al_huda/features/sections/sections_screen.dart';
import 'package:khazain_al_huda/features/sections/section_catalogue.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _pumpSections(WidgetTester tester, {Size size = const Size(412, 900)}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();

  await tester.pumpWidget(
    ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: const MaterialApp(
        locale: Locale('ar'),
        supportedLocales: <Locale>[Locale('ar')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: Scaffold(body: SectionsScreen()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the screen renders every section as an individual feature card',
      (tester) async {
    await _pumpSections(tester);

    // The grid is a lazy sliver, so the test scrolls through the groups
    // before asserting that every tile exists.
    final scrollable = find.byType(Scrollable).first;
    for (final section in kAppSections) {
      await tester.scrollUntilVisible(
        find.text(section.title),
        240,
        scrollable: scrollable,
      );
      expect(find.text(section.title), findsOneWidget,
          reason: 'missing tile ${section.title}');
    }

    expect(find.text('إضافة قسم'), findsNothing);
    expect(find.byType(KzTile), findsWidgets);
  });

  testWidgets('no group renders an empty hole', (tester) async {
    await _pumpSections(tester);

    // Every tile in a group has a label; a blank tile would break the layout.
    final tiles = tester.widgetList<KzTile>(find.byType(KzTile)).toList();
    expect(tiles, isNotEmpty);
    for (final tile in tiles) {
      expect(tile.label.trim(), isNotEmpty);
    }
  });

  testWidgets('search filters sections and can be cleared', (tester) async {
    await _pumpSections(tester);

    await tester.enterText(find.byType(TextField), 'مكتبة صوت الشيعة');
    await tester.pumpAndSettle();

    expect(find.text('مكتبة صوت الشيعة'), findsOneWidget);
    expect(find.text('القرآن الكريم'), findsNothing);

    await tester.tap(find.byTooltip('مسح البحث'));
    await tester.pumpAndSettle();

    expect(find.text('القرآن الكريم'), findsOneWidget);
  });

  testWidgets('the layout does not overflow at the reference widths',
      (tester) async {
    await _pumpSections(tester, size: const Size(320, 900));
    expect(tester.takeException(), isNull, reason: 'overflow at 320');
    for (final width in const [360.0, 412.0, 768.0, 1024.0]) {
      tester.view.physicalSize = Size(width, 900);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'overflow at $width');
    }
  });

  testWidgets('the screen renders in right-to-left', (tester) async {
    await _pumpSections(tester);
    final context = tester.element(find.byType(SectionsScreen));
    expect(Directionality.of(context), TextDirection.rtl);
  });
}
