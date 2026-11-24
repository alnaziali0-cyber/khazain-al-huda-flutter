import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:khazain_al_huda/features/content/ziyara_library_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('shows local licensed visit texts and opens a bundled excerpt',
      (tester) async {
    final router = _testRouter();
    addTearDown(router.dispose);

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    expect(find.text('موسوعة الزيارات'), findsOneWidget);
    expect(find.textContaining('المواد:'), findsOneWidget);
    expect(find.text('آداب الزيارة واحترام الزائرين'), findsOneWidget);

    await tester.tap(find.text('افتح مقتطف عاشوراء'));
    await tester.pumpAndSettle();
    expect(find.text('مقتطف من زيارة عاشوراء'), findsOneWidget);
    expect(find.textContaining('ويكي مصدر'), findsOneWidget);
    expect(find.byType(SelectableText), findsOneWidget);
  });
}

GoRouter _testRouter() => GoRouter(
      initialLocation: '/visits',
      routes: [
        GoRoute(
          path: '/visits',
          builder: (context, state) => Scaffold(
            body: Column(
              children: [
                const Expanded(child: ZiyaraLibraryScreen()),
                TextButton(
                  onPressed: () => context.push('/visits/visit01_ashura'),
                  child: const Text('افتح مقتطف عاشوراء'),
                ),
              ],
            ),
          ),
        ),
        GoRoute(
          path: '/visits/:volumeId',
          builder: (context, state) => ZiyaraVolumeTextScreen(
            volumeId: state.pathParameters['volumeId'] ?? '',
          ),
        ),
      ],
    );
