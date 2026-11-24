import 'package:flutter_test/flutter_test.dart';
import 'package:khazain_al_huda/core/thaqalayn_repository.dart';

void main() {
  group('Thaqalayn model parsing', () {
    test('parses the public books catalogue field names', () {
      final book = ThaqalaynBook.fromJson({
        'bookId': 'Al-Kafi-Volume-1-Kulayni',
        'BookName': 'Al-Kāfi',
        'author': 'Shaykh al-Kulaynī',
        'englishName': 'The Sufficient',
        'idRangeMin': 1,
        'idRangeMax': 1449,
        'volume': 1,
      });

      expect(book.id, 'Al-Kafi-Volume-1-Kulayni');
      expect(book.name, 'Al-Kāfi');
      expect(book.minimumId, 1);
      expect(book.maximumId, 1449);
      expect(book.volume, 1);
    });

    test('accepts the source TypeScript BookId and Volume field aliases', () {
      final book = ThaqalaynBook.fromJson({
        'BookId': 'Al-Kafi-Volume-1-Kulayni',
        'BookName': 'Al-Kāfi',
        'Volume': 1,
        'idRangeMin': 1,
        'idRangeMax': 1449,
      });

      expect(book.id, 'Al-Kafi-Volume-1-Kulayni');
      expect(book.volume, 1);
    });

    test('reads Arabic and English text plus source metadata', () {
      final hadith = ThaqalaynHadith.fromJson({
        'id': 17,
        'bookName': 'Al-Kāfi',
        'arabicText': 'قال الإمام عليه السلام: اطلبوا العلم.',
        'englishText': 'Seek knowledge.',
        'chapter': 'باب فضل العلم',
      });

      expect(hadith.id, '17');
      expect(hadith.arabicText, contains('اطلبوا العلم'));
      expect(hadith.englishText, 'Seek knowledge.');
      expect(hadith.reference, contains('Al-Kāfi'));
      expect(hadith.metadata.map((entry) => entry.key), contains('الباب'));
      expect(hadith.metadata.map((entry) => entry.value), contains('باب فضل العلم'));
    });

    test('parses the live Thaqalayn v2 hadith schema and validates source URL', () {
      final hadith = ThaqalaynHadith.fromJson({
        'bookId': 'Uyun-akhbar-al-Rida-Volume-1-Saduq',
        'id': 80,
        'book': 'Uyun Akhbar al-Rida',
        'volume': 1,
        'category': 'Virtues of Imam al-Rida',
        'chapter': 'باب في ذكر الإمام الرضا',
        'author': 'Ibn Babawayh',
        'translator': 'English translator',
        'arabicText': 'قال عليه السلام: العلم نور.',
        'englishText': 'Knowledge is light.',
        'thaqalaynSanad': 'محمد بن يعقوب، عن علي بن إبراهيم.',
        'thaqalaynMatn': 'العلم نور.',
        'majlisiGrading': 'Hasan',
        'behbudiGrading': 'Sahih',
        'mohseniGrading': null,
        'URL': 'https://thaqalayn.net/hadith/11/2/80',
      });

      expect(hadith.id, '80');
      expect(hadith.bookName, 'Uyun Akhbar al-Rida');
      expect(hadith.arabicText, contains('العلم نور'));
      expect(hadith.englishText, 'Knowledge is light.');
      expect(hadith.sourceUri?.host, 'thaqalayn.net');
      expect(hadith.metadata.map((entry) => entry.key), containsAll([
        'التصنيف',
        'المجلد',
        'المؤلف',
        'المترجم',
        'السند كما أورده المصدر',
        'المتن كما حدده المصدر',
        'التقييم المنقول عن المجلسي',
        'التقييم المنقول عن البهبودي',
      ]));
      expect(hadith.metadata.map((entry) => entry.value), contains('Hasan'));
      expect(hadith.metadata.map((entry) => entry.value), isNot(contains('null')));
    });

    test('preserves nested full grading records and scholar references', () {
      final hadith = ThaqalaynHadith.fromJson({
        'id': 81,
        'arabicText': 'نص الرواية',
        'BehdudiGrading': 'Sahih',
        'GradingsFull': [
          {
            'grade_ar': 'حسن',
            'grade_en': 'Hasan',
            'reference_en': 'Mirat al-Uqul, volume 2',
            'author': {
              'name_ar': 'العلامة المجلسي',
              'name_en': 'Allama Majlisi',
              'death_date': '1111 AH',
            },
          },
        ],
      });

      final metadata = hadith.metadata;
      expect(metadata.map((entry) => entry.value), contains('Sahih'));
      final detailed = metadata
          .where((entry) => entry.key.startsWith('تفصيل التقييم المنقول'))
          .single
          .value;
      expect(detailed, contains('حسن'));
      expect(detailed, contains('Hasan'));
      expect(detailed, contains('العلامة المجلسي'));
      expect(detailed, contains('Allama Majlisi'));
      expect(detailed, contains('Mirat al-Uqul'));
      expect(detailed, contains('1111 AH'));
    });

    test('rejects source URLs that are not on the original Thaqalayn domain', () {
      final external = ThaqalaynHadith.fromJson({
        'id': 1,
        'URL': 'https://example.com/fake-hadith',
        'arabicText': 'نص عربي',
      });
      final insecure = ThaqalaynHadith.fromJson({
        'id': 2,
        'URL': 'http://thaqalayn.net/hadith/1',
        'arabicText': 'نص عربي',
      });

      expect(external.sourceUri, isNull);
      expect(insecure.sourceUri, isNull);
    });
  });
}
