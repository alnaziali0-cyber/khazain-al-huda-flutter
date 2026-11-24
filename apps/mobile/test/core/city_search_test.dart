import 'package:flutter_test/flutter_test.dart';
import 'package:khazain_al_huda/core/city_search.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('arabic normalisation', () {
    test('strips the diacritics and the tatweel', () {
      expect(normalizeArabic('النَّجَف'), 'النجف');
      expect(normalizeArabic('كربـــلاء'), 'كربلاء');
    });

    test('unifies the alef, yeh and ta marbuta variants', () {
      expect(normalizeArabic('أحمد'), 'احمد');
      expect(normalizeArabic('إسلام'), 'اسلام');
      expect(normalizeArabic('آمنة'), 'امنه');
      expect(normalizeArabic('مصطفى'), 'مصطفي');
      expect(normalizeArabic('Provisionة'), 'Provisionه');
    });

    test('keeps the search key lower-cased', () {
      expect(normalizeSearchKey('Baghdad'), 'baghdad');
      expect(normalizeSearchKey('  النجف  '), 'النجف');
    });
  });

  group('city usage store', () {
    late SharedPreferences prefs;
    late CityUsageStore store;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      store = CityUsageStore(prefs);
    });

    test('keeps only the last five selected cities', () {
      for (var index = 0; index < 8; index++) {
        store.recordSelection(
          cityId: 'city$index',
          nameAr: 'مدينة $index',
          governorateAr: 'محافظة',
        );
      }
      final recents = store.recents();
      expect(recents.length, CityUsageStore.maxRecents);
      expect(recents.first.cityId, 'city7');
      expect(recents.last.cityId, 'city3');
    });

    test('counts the repetitions and orders the most used first', () {
      store.recordSelection(
          cityId: 'a', nameAr: 'أ', governorateAr: 'ب');
      store.recordSelection(
          cityId: 'b', nameAr: 'ب', governorateAr: 'ب');
      store.recordSelection(
          cityId: 'a', nameAr: 'أ', governorateAr: 'ب');
      store.recordSelection(
          cityId: 'a', nameAr: 'أ', governorateAr: 'ب');

      final mostUsed = store.mostUsed();
      expect(mostUsed.first.cityId, 'a');
      expect(mostUsed.first.count, 3);
      expect(mostUsed.last.cityId, 'b');
    });

    test('favourites can be toggled', () {
      expect(store.isFavourite('karbala'), isFalse);
      store.toggleFavourite('karbala');
      expect(store.isFavourite('karbala'), isTrue);
      store.toggleFavourite('karbala');
      expect(store.isFavourite('karbala'), isFalse);
    });

    test('the recents can be cleared', () {
      store.recordSelection(
          cityId: 'a', nameAr: 'أ', governorateAr: 'ب');
      store.clearRecents();
      expect(store.recents(), isEmpty);
    });
  });
}
