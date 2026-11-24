import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:khazain_al_huda/features/radio/shiavoice_library_screen.dart';

Map<String, dynamic> _fixture() => {
      'schema_version': 1,
      'exported_at': '2026-11-22T21:46:23.262Z',
      'source': {
        'notice_ar': 'لا يخزّن التطبيق الصوت',
        'website': 'https://shiavoice.com/',
      },
      'recent': [
        {
          'id': 'np16c',
          'title': 'توادعنا',
          'artist': 'أبو بشير النجفي',
          'page_path': '/play-np16c',
          'artist_path': '/@abu-bashir-alnajfi',
          'duration_seconds': 686,
          'category': 'poems',
        },
        {
          'id': 'sura01',
          'title': 'سورة البقرة',
          'artist': 'قارئ تجريبي',
          'page_path': '/play-sura01',
          'artist_path': '/@qari',
          'duration_seconds': 8446,
          'category': 'quran',
        },
      ],
      'favorites': {
        'track': [],
        'cat': [],
        'artist': [],
        'playlist': [],
        'tag': [],
      },
      'playlists': [],
      'queue': {
        'track_ids': ['np16c'],
        'index': 0,
        'shuffle': false,
        'repeat': 'off',
      },
    };

Widget _testApp(Widget child) => MaterialApp(
      home: Scaffold(body: child),
    );

void main() {
  testWidgets('shows imported recent tracks and source-only notice',
      (tester) async {
    await tester.pumpWidget(_testApp(
      ShiaVoiceLibraryScreen(loadLibrary: () async => _fixture()),
    ));
    await tester.pumpAndSettle();

    expect(find.text('مكتبة صوت الشيعة'), findsOneWidget);
    expect(find.text('توادعنا'), findsOneWidget);
    expect(find.text('سورة البقرة'), findsOneWidget);
    expect(find.textContaining('لا يقوم التطبيق بتنزيل الصوت'), findsOneWidget);
    expect(find.textContaining('26 تسجيل'), findsNothing);
  });

  testWidgets('filters recent catalogue by inferred category', (tester) async {
    await tester.pumpWidget(_testApp(
      ShiaVoiceLibraryScreen(loadLibrary: () async => _fixture()),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('القرآن'));
    await tester.pumpAndSettle();

    expect(find.text('سورة البقرة'), findsOneWidget);
    expect(find.text('توادعنا'), findsNothing);
  });

  testWidgets('opens the original validated track page, not a stream URL',
      (tester) async {
    Uri? opened;
    await tester.pumpWidget(_testApp(
      ShiaVoiceLibraryScreen(
        loadLibrary: () async => _fixture(),
        openUrl: (uri) async {
          opened = uri;
          return true;
        },
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('فتح في صوت الشيعة').first);
    await tester.pumpAndSettle();

    expect(opened, Uri.parse('https://shiavoice.com/play-np16c'));
  });

  testWidgets('shows the imported queue and honest empty saved sections',
      (tester) async {
    await tester.pumpWidget(_testApp(
      ShiaVoiceLibraryScreen(loadLibrary: () async => _fixture()),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.textContaining('القائمة الحالية'));
    await tester.pumpAndSettle();
    expect(find.text('توادعنا'), findsOneWidget);

    await tester.tap(find.textContaining('المفضلة'));
    await tester.pumpAndSettle();
    expect(find.text('لا توجد تسجيلات مفضلة في ملف التصدير.'), findsOneWidget);
  });
}
