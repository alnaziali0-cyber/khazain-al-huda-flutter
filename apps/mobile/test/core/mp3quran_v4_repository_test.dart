import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:khazain_al_huda/core/mp3quran_v4_repository.dart';

void main() {
  group('MP3Quran v4 stable identifiers and catalogue models', () {
    test('reciter and recitation retain codes instead of numeric IDs', () {
      final reciter = Mp3QuranReciter.fromJson({
        'id': 810,
        'code': 'mahmoud-husary',
        'name': 'محمود خليل الحصري',
        'name_latin': 'Mahmoud Khalil Al-Hussary',
        'recitation_count': 5,
      });
      final recitation = Mp3QuranRecitation.fromJson({
        'id': 999,
        'code': 'mahmoud-husary/r1',
        'style': 'murattal',
        'riwayahs': [
          {'code': 'hafs_an_asim', 'qiraah': 'asim'},
        ],
        'has_ayah_timings': true,
        'coverage': {
          'complete': true,
          'surahs': [1, 2, 3],
        },
        'audio': {
          'base': 'https://cdn.mp3quran.net/audio/mahmoud-husary/r1/',
          'files': {'original': '{surah:03d}.mp3'},
        },
      });

      expect(reciter.code, 'mahmoud-husary');
      expect(recitation.code, 'mahmoud-husary/r1');
      expect(recitation.riwayahCodes, ['hafs_an_asim']);
      expect(recitation.coverageSurahs, [1, 2, 3]);
      expect(recitation.audioBase,
          'https://cdn.mp3quran.net/audio/mahmoud-husary/r1/');
      expect(recitation.originalPattern, '{surah:03d}.mp3');
    });

    test('bulk audio URL uses the source base and exact filename pattern', () {
      final recitation = Mp3QuranRecitation.fromJson({
        'code': 'mahmoud-husary/r1',
        'audio': {
          'base': 'https://cdn.mp3quran.net/audio/mahmoud-husary/r1/',
          'files': {'original': '{surah:03d}.mp3'},
        },
      });
      final repository = Mp3QuranV4Repository(dio: Dio());

      final uri = repository.buildSurahAudioUriFromRecitation(
        recitation: recitation,
        surahNumber: 4,
      );

      expect(uri,
          Uri.parse('https://cdn.mp3quran.net/audio/mahmoud-husary/r1/004.mp3'));
    });

    test('does not accept non-MP3Quran hosts for remote audio', () {
      final recitation = Mp3QuranRecitation(
        code: 'mahmoud-husary/r1',
        audioBase: 'https://example.org/audio/',
        originalPattern: '{surah:03d}.mp3',
      );
      final repository = Mp3QuranV4Repository(dio: Dio());

      expect(
        () => repository.buildSurahAudioUriFromRecitation(
          recitation: recitation,
          surahNumber: 1,
        ),
        throwsA(isA<Mp3QuranApiException>()),
      );
    });
  });

  test('word timings preserve heard order and repeated occurrences', () {
    final timings = Mp3QuranWordTimings.fromApiData({
      'surah': 1,
      'words': [
        [1, 1, 100, 260, 1],
        [1, 2, 270, 420, 1],
        [1, 1, 500, 660, 2],
      ],
      'text': {
        'ayahs': [
          [
            1,
            [
              [1, 'بِسْمِ'],
              [2, 'اللَّهِ'],
            ],
          ],
        ],
      },
    }, fallbackSurah: 1);

    expect(timings.words, hasLength(3));
    expect(timings.words.map((word) => word.startMs), [100, 270, 500]);
    expect(timings.words.map((word) => word.occurrence), [1, 1, 2]);
    expect(timings.textFor(timings.words.first), 'بِسْمِ');
    expect(timings.textFor(timings.words.last), 'بِسْمِ');
  });

  test('ayah timing parser keeps the basmalah and istiadhah markers', () {
    final timings = Mp3QuranAyahTimings.fromApiData({
      'surah': 1,
      'complete': true,
      'ayahs': [
        [0, 0, 4500],
        [-1, 4500, 8000],
        [1, 8001, 16000],
      ],
    }, fallbackSurah: 1);

    expect(timings.complete, isTrue);
    expect(timings.entries.map((item) => item.ayah), [0, -1, 1]);
  });
}
