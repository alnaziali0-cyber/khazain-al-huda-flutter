import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/providers.dart';

/// A piece of content the user opened but has not finished yet.
class FadaItem {
  const FadaItem({
    required this.id,
    required this.kind,
    required this.title,
    required this.subtitle,
    required this.route,
    required this.category,
    required this.lastViewedMillis,
    this.done = false,
  });

  final String id;
  final String kind;
  final String title;
  final String subtitle;
  final String route;

  /// One of: all · amal · quran · duas · visits · other.
  final String category;

  final int lastViewedMillis;
  final bool done;

  FadaItem copyWith({int? lastViewedMillis, bool? done}) => FadaItem(
        id: id,
        kind: kind,
        title: title,
        subtitle: subtitle,
        route: route,
        category: category,
        lastViewedMillis: lastViewedMillis ?? this.lastViewedMillis,
        done: done ?? this.done,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'kind': kind,
        'title': title,
        'subtitle': subtitle,
        'route': route,
        'category': category,
        'lastViewedMillis': lastViewedMillis,
        'done': done,
      };

  factory FadaItem.fromJson(Map<String, dynamic> json) => FadaItem(
        id: json['id'] as String? ?? '',
        kind: json['kind'] as String? ?? 'other',
        title: json['title'] as String? ?? '',
        subtitle: json['subtitle'] as String? ?? '',
        route: json['route'] as String? ?? '/',
        category: json['category'] as String? ?? 'other',
        lastViewedMillis: (json['lastViewedMillis'] as num?)?.toInt() ?? 0,
        done: json['done'] as bool? ?? false,
      );
}

/// Local persistence for the leftovers / "what is left" screen.
class FadaStore extends StateNotifier<List<FadaItem>> {
  FadaStore(this._prefs) : super(_read(_prefs));

  final SharedPreferences _prefs;
  static const String _key = 'fada_history_v1';
  static const int maxItems = 40;

  static List<FadaItem> _read(SharedPreferences prefs) {
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return const <FadaItem>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const <FadaItem>[];
      return decoded
          .whereType<Map>()
          .map((item) => FadaItem.fromJson(item.cast<String, dynamic>()))
          .toList(growable: false);
    } catch (_) {
      return const <FadaItem>[];
    }
  }

  void _persist() {
    _prefs.setString(_key, jsonEncode(
      state.map((item) => item.toJson()).toList(growable: false),
    ));
  }

  /// Records that the user opened an item.
  void record(FadaItem item) {
    final next = <FadaItem>[
      item.copyWith(lastViewedMillis: DateTime.now().millisecondsSinceEpoch),
      ...state.where((existing) => existing.id != item.id),
    ].take(maxItems).toList(growable: false);
    state = next;
    _persist();
  }

  /// Marks an item as finished — it moves out of the pending list.
  void markDone(String id) {
    state = state.map((item) => item.id == id ? item.copyWith(done: true) : item).toList(growable: false);
    _persist();
  }

  void remove(String id) {
    state = state.where((item) => item.id != id).toList(growable: false);
    _persist();
  }

  void clear() {
    state = const <FadaItem>[];
    _prefs.remove(_key);
  }
}

final fadaStoreProvider =
    StateNotifierProvider<FadaStore, List<FadaItem>>((ref) {
  return FadaStore(ref.watch(sharedPreferencesProvider));
});
