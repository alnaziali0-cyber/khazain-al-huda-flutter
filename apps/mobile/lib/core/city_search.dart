import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Arabic normalisation used by the city search.
///
/// Diacritics and tatweel are removed, the Arabic letter variants are
/// unified (أ إ آ ٱ → ا, ى → ي, ة → ه) and tatweel/kashida is dropped so a
/// user typing "النجف" finds "النجف" and a user typing "النجف" finds "النجف".
String normalizeArabic(String input) {
  final buffer = StringBuffer();
  for (final rune in input.runes) {
    if ((rune >= 0x0610 && rune <= 0x061A) ||
        (rune >= 0x064B && rune <= 0x065F) ||
        rune == 0x0640 ||
        (rune >= 0x06D6 && rune <= 0x06ED)) {
      continue;
    }
    switch (rune) {
      case 0x0623: // أ
      case 0x0625: // إ
      case 0x0622: // آ
      case 0x0671: // ٱ
        buffer.writeCharCode(0x0627); // ا
        break;
      case 0x0624: // ؤ
        buffer.writeCharCode(0x0648); // و
        break;
      case 0x0626: // ئ
      case 0x0649: // ى
      case 0x06CC: // ی
        buffer.writeCharCode(0x064A); // ي
        break;
      case 0x0629: // ة
        buffer.writeCharCode(0x0647); // ه
        break;
      default:
        buffer.writeCharCode(rune);
    }
  }
  return buffer
      .toString()
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

/// Normalises and lower-cases for comparison.
String normalizeSearchKey(String input) =>
    normalizeArabic(input).toLowerCase();

/// A city the user picked recently, together with how often it was picked.
class CityUsage {
  const CityUsage({
    required this.cityId,
    required this.nameAr,
    required this.governorateAr,
    required this.count,
    required this.lastUsedMillis,
  });

  final String cityId;
  final String nameAr;
  final String governorateAr;
  final int count;
  final int lastUsedMillis;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'cityId': cityId,
        'nameAr': nameAr,
        'governorateAr': governorateAr,
        'count': count,
        'lastUsedMillis': lastUsedMillis,
      };

  factory CityUsage.fromJson(Map<String, dynamic> json) => CityUsage(
        cityId: json['cityId'] as String? ?? '',
        nameAr: json['nameAr'] as String? ?? '',
        governorateAr: json['governorateAr'] as String? ?? '',
        count: (json['count'] as num?)?.toInt() ?? 1,
        lastUsedMillis: (json['lastUsedMillis'] as num?)?.toInt() ?? 0,
      );
}

/// Local persistence for the city search: recents, most-used and favourites.
class CityUsageStore {
  CityUsageStore(this._prefs);

  final SharedPreferences _prefs;

  static const String _recentKey = 'city_search_recents_v1';
  static const String _favouriteKey = 'city_search_favourites_v1';
  static const int maxRecents = 5;

  /// The five most recently chosen cities, newest first.
  List<CityUsage> recents() => _readList(_recentKey);

  /// Cities ordered by how often they were chosen.
  List<CityUsage> mostUsed() {
    final items = _readList(_recentKey).toList()
      ..sort((a, b) {
        final byCount = b.count.compareTo(a.count);
        if (byCount != 0) return byCount;
        return b.lastUsedMillis.compareTo(a.lastUsedMillis);
      });
    return items;
  }

  List<String> favourites() =>
      _prefs.getStringList(_favouriteKey) ?? const <String>[];

  bool isFavourite(String cityId) => favourites().contains(cityId);

  /// Records a selection and returns the updated recents list.
  List<CityUsage> recordSelection({
    required String cityId,
    required String nameAr,
    required String governorateAr,
  }) {
    final items = List<CityUsage>.from(_readList(_recentKey));
    final index = items.indexWhere((item) => item.cityId == cityId);
    if (index >= 0) {
      final existing = items.removeAt(index);
      items.insert(
        0,
        CityUsage(
          cityId: existing.cityId,
          nameAr: nameAr,
          governorateAr: governorateAr,
          count: existing.count + 1,
          lastUsedMillis: DateTime.now().millisecondsSinceEpoch,
        ),
      );
    } else {
      items.insert(
        0,
        CityUsage(
          cityId: cityId,
          nameAr: nameAr,
          governorateAr: governorateAr,
          count: 1,
          lastUsedMillis: DateTime.now().millisecondsSinceEpoch,
        ),
      );
    }
    final trimmed = items.take(maxRecents).toList(growable: false);
    _prefs.setString(_recentKey, jsonEncode(
      trimmed.map((item) => item.toJson()).toList(growable: false),
    ));
    return trimmed;
  }

  void toggleFavourite(String cityId) {
    final list = favourites().toList();
    if (list.contains(cityId)) {
      list.remove(cityId);
    } else {
      list.add(cityId);
    }
    _prefs.setStringList(_favouriteKey, list);
  }

  void clearRecents() => _prefs.remove(_recentKey);

  List<CityUsage> _readList(String key) {
    final raw = _prefs.getString(key);
    if (raw == null || raw.isEmpty) return const <CityUsage>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const <CityUsage>[];
      return decoded
          .whereType<Map>()
          .map((item) => CityUsage.fromJson(item.cast<String, dynamic>()))
          .toList(growable: true);
    } catch (_) {
      return const <CityUsage>[];
    }
  }
}
