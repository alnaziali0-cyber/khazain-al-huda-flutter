import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:khazain_al_huda/features/visitor/visitor_guide_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('offline visitor guide seed has unique, Iraq-bounded sourced places', () async {
    final decoded = jsonDecode(await rootBundle.loadString(
      'assets/data/visitor_guide/iraq_places.json',
    )) as Map<String, dynamic>;
    final items = decoded['items'] as List<dynamic>;
    final places = items
        .map((item) => VisitorPlace.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList(growable: false);

    expect(places.length, greaterThanOrEqualTo(8));
    expect(places.map((place) => place.id).toSet(), hasLength(places.length));
    expect(places.every((place) => place.name.trim().isNotEmpty), isTrue);
    expect(places.every((place) => place.coordinateSource.trim().isNotEmpty), isTrue);
    expect(places.every((place) => Uri.parse(place.sourceUrl).scheme == 'https'), isTrue);
    expect(places.every((place) => place.latitude >= 29 && place.latitude <= 38), isTrue);
    expect(places.every((place) => place.longitude >= 38 && place.longitude <= 49), isTrue);
    expect(decoded['coverage_note'], contains('ليست سجلاً شاملاً'));
    expect(decoded['map_note'], contains('لا تعرض الشوارع'));
  });

  test('rejects an out-of-Iraq visitor coordinate', () {
    expect(
      () => VisitorPlace.fromJson({
        'id': 'invalid',
        'name': 'مكان غير صالح',
        'governorate': 'بغداد',
        'city': 'بغداد',
        'type': 'shrine',
        'description': 'اختبار',
        'latitude': 0,
        'longitude': 0,
        'coordinate_source': 'test',
        'source_url': 'https://example.org',
        'coordinate_status': 'test',
      }),
      throwsFormatException,
    );
  });
}
