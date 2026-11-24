import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('loads the local Hijri occasions and Ahl al-Bayt biographical datasets',
      () async {
    final events = jsonDecode(await rootBundle
        .loadString('assets/data/shia_occasions_hijri.json')) as List;
    final people = jsonDecode(await rootBundle
        .loadString('assets/data/ahl_al_bayt_biographies.json')) as List;

    expect(events, hasLength(44));
    expect(people, hasLength(16));
    expect(events.every((item) => item is Map && item['event_ar'] is String),
        isTrue);
    expect(people.every((item) => item is Map && item['name_ar'] is String),
        isTrue);
    expect(events.toString(), isNot(contains('https://')));
    expect(people.toString(), isNot(contains('wikidata')));
  });
}
