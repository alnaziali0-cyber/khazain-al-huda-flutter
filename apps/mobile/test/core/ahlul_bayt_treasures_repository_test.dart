import 'package:flutter_test/flutter_test.dart';
import 'package:khazain_al_huda/core/ahlul_bayt_treasures_repository.dart';

void main() {
  group('Ahlul Bayt Treasures index parsing', () {
    test('preserves source ids when null or empty slots exist', () {
      final items = AhlulBaytTreasuresRepository.parseIndex('''
        ["", "Dua Kumayl", null, "Ziarat Ashura", "  "]
      ''');

      expect(items, hasLength(2));
      expect(items[0].id, 1);
      expect(items[0].name, 'Dua Kumayl');
      expect(items[1].id, 3);
      expect(items[1].name, 'Ziarat Ashura');
    });

    test('classifies ziarat titles independently from dua titles', () {
      const dua = AhlulBaytTreasuresIndexEntry(id: 8, name: 'Dua Kumayl');
      const visit =
          AhlulBaytTreasuresIndexEntry(id: 24, name: 'Ziarat Ashura');

      expect(dua.isZiyara, isFalse);
      expect(visit.isZiyara, isTrue);
    });
  });

  group('Ahlul Bayt Treasures text parsing', () {
    test('preserves Arabic, translation, transliteration and UI hints', () {
      final dua = AhlulBaytTreasuresText.fromJson({
        'id': 8,
        'name': 'Dua Kumayl',
        'rows': [
          {
            'index': 1,
            'show_id': '',
            'arabic': 'بِسْمِ اللَّهِ الرَّحْمَٰنِ الرَّحِيمِ',
            'translation': 'In the name of Allah.',
            'transliteration': 'Bismillah.',
            'instruction': '',
            'title': '',
          },
          {
            'index': 2,
            'show_id': '1',
            'arabic': 'اللَّهُمَّ إِنِّي أَسْأَلُكَ',
            'translation': 'O Allah, I ask You.',
            'transliteration': 'Allahumma inni as’aluka.',
            'instruction': '',
            'title': 'Opening',
          },
          {
            'index': 3,
            'show_id': '',
            'arabic': '',
            'translation': '',
            'transliteration': '',
            'instruction': 'Repeat 3 times',
            'title': '',
          },
        ],
      });

      expect(dua.id, 8);
      expect(dua.name, 'Dua Kumayl');
      expect(dua.rows, hasLength(3));
      expect(dua.rows.first.showId, isEmpty);
      expect(dua.rows.first.arabic, contains('بِسْمِ اللَّهِ'));
      expect(dua.rows.first.translation, 'In the name of Allah.');
      expect(dua.rows.first.transliteration, 'Bismillah.');
      expect(dua.rows[1].showId, '1');
      expect(dua.rows[1].title, 'Opening');
      expect(dua.rows[2].instruction, 'Repeat 3 times');
      expect(dua.rows[2].arabic, isEmpty);
    });

    test('rejects a malformed record instead of displaying partial text', () {
      expect(
        () => AhlulBaytTreasuresText.fromJson({'id': 'invalid', 'rows': []}),
        throwsFormatException,
      );
    });
  });
}
