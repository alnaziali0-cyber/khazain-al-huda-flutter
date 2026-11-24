import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:khazain_al_huda/core/audio_playback_service.dart';
import 'package:khazain_al_huda/core/providers.dart';
import 'package:khazain_al_huda/features/radio/audio_library_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakePlayback implements AppAudioPlayback {
  @override
  Stream<PlaybackState> get playbackStateStream => const Stream<PlaybackState>.empty();

  @override
  bool get isPlaying => false;

  @override
  Stream<Duration> get positionStream => const Stream<Duration>.empty();

  @override
  Duration? get duration => null;

  @override
  double get speed => 1;

  @override
  Future<void> seekTo(Duration position) async {}

  @override
  Future<void> setPlaybackSpeed(double speed) async {}

  @override
  Future<void> pause() async {}

  @override
  Future<void> play() async {}

  @override
  Future<void> playLocal({
    required String path,
    required String id,
    required String title,
    String artist = 'خزائن الهدى',
    String album = 'القرآن الكريم',
  }) async {}

  @override
  Future<void> playRemote({
    required Uri uri,
    required String id,
    required String title,
    String artist = 'خزائن الهدى',
    String album = 'المكتبة الصوتية',
  }) async {}

  @override
  Future<void> setLoopMode(LoopMode mode) async {}

  @override
  Future<void> stop() async {}
}

Widget _testApp(Widget child) => ProviderScope(
      overrides: [
        appAudioPlaybackProvider.overrideWithValue(_FakePlayback()),
        sharedPreferencesProvider.overrideWithValue(
          _testPreferences(),
        ),
      ],
      child: MaterialApp(home: Scaffold(body: child)),
    );

SharedPreferences _testPreferences() {
  SharedPreferences.setMockInitialValues({});
  return _preferences;
}

late final SharedPreferences _preferences;

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    _preferences = await SharedPreferences.getInstance();
  });

  testWidgets('shows empty licensed catalogue state', (tester) async {
    await tester.pumpWidget(_testApp(
      AudioLibraryScreen(loadTracks: () async => []),
    ));
    await tester.pumpAndSettle();
    expect(find.text('الصوتيات'), findsOneWidget);
    expect(find.textContaining('تسجيلات موثّقة الحقوق'), findsOneWidget);
    expect(find.textContaining('https://'), findsNothing);
  });

  testWidgets('shows only published tracks returned by the public catalogue',
      (tester) async {
    await tester.pumpWidget(_testApp(AudioLibraryScreen(loadTracks: () async => [
      {
        'id': 7,
        'title': 'أذان تجريبي مرخص',
        'category': 'adhan',
        'source_url': 'https://example.org/audio.mp3',
        'can_download': false,
      }
    ])));
    await tester.pumpAndSettle();
    expect(find.text('أذان تجريبي مرخص'), findsOneWidget);
    // The row shows the Arabic label of the catalogue category.
    expect(find.textContaining('الأذان'), findsWidgets);
    expect(find.byTooltip('تنزيل مرخص'), findsNothing);
  });
}
