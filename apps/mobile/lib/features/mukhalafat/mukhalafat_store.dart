import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/providers.dart';

/// A user-created entry ("مقصد") written into the leftovers grid (G3).
class MukhalafatEntry {
  const MukhalafatEntry({
    required this.id,
    required this.title,
    required this.note,
    required this.createdAtMillis,
  });

  final String id;
  final String title;
  final String note;
  final int createdAtMillis;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'title': title,
        'note': note,
        'createdAtMillis': createdAtMillis,
      };

  factory MukhalafatEntry.fromJson(Map<String, dynamic> json) =>
      MukhalafatEntry(
        id: json['id'] as String? ?? '',
        title: json['title'] as String? ?? '',
        note: json['note'] as String? ?? '',
        createdAtMillis: (json['createdAtMillis'] as num?)?.toInt() ?? 0,
      );
}

/// Persists the entries the user adds with the "إضافة مقصودة" action.
class MukhalafatStore extends StateNotifier<List<MukhalafatEntry>> {
  MukhalafatStore(this._prefs) : super(_read(_prefs));

  final SharedPreferences _prefs;
  static const String _key = 'mukhalafat_entries_v1';

  static List<MukhalafatEntry> _read(SharedPreferences prefs) {
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return const <MukhalafatEntry>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const <MukhalafatEntry>[];
      return decoded
          .whereType<Map>()
          .map((item) => MukhalafatEntry.fromJson(item.cast<String, dynamic>()))
          .toList(growable: false);
    } catch (_) {
      return const <MukhalafatEntry>[];
    }
  }

  /// Adds a new entry and returns the updated list.
  List<MukhalafatEntry> add({required String title, required String note}) {
    final entry = MukhalafatEntry(
      id: 'mkh_${DateTime.now().microsecondsSinceEpoch}',
      title: title.trim(),
      note: note.trim(),
      createdAtMillis: DateTime.now().millisecondsSinceEpoch,
    );
    final next = <MukhalafatEntry>[entry, ...state];
    state = next;
    _prefs.setString(_key, jsonEncode(
      next.map((item) => item.toJson()).toList(growable: false),
    ));
    return next;
  }

  void remove(String id) {
    final next = state.where((item) => item.id != id).toList(growable: false);
    state = next;
    _prefs.setString(_key, jsonEncode(
      next.map((item) => item.toJson()).toList(growable: false),
    ));
  }
}

final mukhalafatStoreProvider =
    StateNotifierProvider<MukhalafatStore, List<MukhalafatEntry>>((ref) {
  return MukhalafatStore(ref.watch(sharedPreferencesProvider));
});
