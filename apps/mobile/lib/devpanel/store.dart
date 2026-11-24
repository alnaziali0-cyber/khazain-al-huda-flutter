import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/providers.dart';
import 'models.dart';

/// Storage key for the persisted developer state (spec: `khzain.dev.v1`).
const String kDevStateKey = 'khzain.dev.v1';

/// Maximum number of undo/redo steps retained.
const int kDevHistoryLimit = 50;

/// The developer store: a single reducer-backed state object with a bounded
/// undo/redo history, persisted to `SharedPreferences` under `khzain.dev.v1`.
class DevStoreController extends StateNotifier<DevState> {
  DevStoreController(this._prefs) : super(_read(_prefs));

  final SharedPreferences _prefs;
  final List<DevState> _undo = <DevState>[];
  final List<DevState> _redo = <DevState>[];

  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;

  static DevState _read(SharedPreferences prefs) {
    final raw = prefs.getString(kDevStateKey);
    if (raw == null || raw.isEmpty) return const DevState();
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const DevState();
      return DevState.fromJson(decoded.cast<String, dynamic>());
    } catch (_) {
      // A corrupt store must never brick the app: fall back to defaults.
      return const DevState();
    }
  }

  /// Applies a state transition, recording it for undo and persisting it.
  ///
  /// A failing transaction rolls the state back completely before rethrowing.
  void _commit(DevState next) {
    _undo.add(state);
    if (_undo.length > kDevHistoryLimit) _undo.removeAt(0);
    _redo.clear();
    state = next;
    _persist();
  }

  void _persist() {
    _prefs.setString(kDevStateKey, state.encode());
  }

  /// Applies a patch atomically. When any part of the patch throws, the
  /// previous state is restored in full (no partial application).
  DevState applyPatch(UIPatch patch) {
    final previous = state;
    try {
      final next = _applyPatchUnsafe(previous, patch);
      _commit(next);
      return next;
    } catch (_) {
      state = previous;
      _persist();
      rethrow;
    }
  }

  DevState _applyPatchUnsafe(DevState base, UIPatch patch) {
    var next = base;

    final tokens = patch.tokens;
    if (tokens != null) {
      final colors = (tokens['colors'] as Map?)?.cast<String, dynamic>();
      if (colors != null) {
        final palette = Map<String, String>.from(
            next.colorOverrides['dark'] ?? const <String, String>{});
        palette.addAll(
            colors.map((key, value) => MapEntry(key, value.toString())));
        next = next.copyWith(
          colorOverrides: <String, Map<String, String>>{
            ...next.colorOverrides,
            'dark': palette,
          },
        );
      }

      final typography = (tokens['typography'] as Map?)?.cast<String, dynamic>();
      if (typography != null) {
        final merged = Map<String, Map<String, dynamic>>.from(
            next.typeOverrides.map(
                (key, value) => MapEntry(key, Map<String, dynamic>.from(value))));
        typography.forEach((key, value) {
          if (value is Map) {
            merged[key] = Map<String, dynamic>.from(value.cast<String, dynamic>());
          }
        });
        next = next.copyWith(typeOverrides: merged);
      }

      final radius = (tokens['radius'] as Map?)?.cast<String, dynamic>();
      if (radius != null) {
        next = next.copyWith(
          radiusOverrides: <String, double>{
            ...next.radiusOverrides,
            ...radius.map((key, value) => MapEntry(key, (value as num).toDouble())),
          },
        );
      }

      final spacing = (tokens['spacing'] as Map?)?.cast<String, dynamic>();
      if (spacing != null) {
        next = next.copyWith(
          spacingOverrides: <String, double>{
            ...next.spacingOverrides,
            ...spacing.map((key, value) => MapEntry(key, (value as num).toDouble())),
          },
        );
      }

      final grid = (tokens['grid'] as Map?)?.cast<String, dynamic>();
      if (grid != null) {
        next = next.copyWith(
          gridOverrides: <String, double>{
            ...next.gridOverrides,
            ...grid.map((key, value) => MapEntry(key, (value as num).toDouble())),
          },
        );
      }
    }

    final sectionOps = patch.sections;
    if (sectionOps != null) {
      var sections = List<DevSection>.from(next.sections);
      for (final op in sectionOps) {
        final kind = op['op'] as String? ?? 'update';
        final payload = (op['section'] as Map?)?.cast<String, dynamic>() ?? {};
        switch (kind) {
          case 'add':
            sections.add(DevSection.fromJson(payload));
          case 'remove':
            final id = payload['id'];
            sections = sections.where((item) => item.id != id).toList();
          case 'reorder':
            final id = payload['id'];
            final order = (payload['order'] as num?)?.toInt();
            sections = sections
                .map((item) => item.id == id && order != null
                    ? item.copyWith(order: order)
                    : item)
                .toList();
          case 'update':
          default:
            final id = payload['id'];
            sections = sections.map((item) {
              if (item.id != id) return item;
              return DevSection.fromJson(<String, dynamic>{
                ...item.toJson(),
                ...payload,
                'id': item.id,
              });
            }).toList();
        }
      }
      next = next.copyWith(sections: sections);
    }

    final iconOps = patch.icons;
    if (iconOps != null) {
      var icons = List<IconDef>.from(next.icons);
      for (final op in iconOps) {
        final kind = op['op'] as String? ?? 'update';
        final payload = (op['icon'] as Map?)?.cast<String, dynamic>() ?? {};
        final icon = IconDef.fromJson(payload);
        final index = icons.indexWhere((item) => item.id == icon.id);
        if (kind == 'add' || index < 0) {
          icons.add(icon);
        } else {
          icons[index] = icon;
        }
      }
      next = next.copyWith(icons: icons);
    }

    final layoutOps = patch.layout;
    if (layoutOps != null) {
      final layout = Map<String, LayoutNode>.from(next.layout);
      for (final op in layoutOps) {
        final route = op['route'] as String? ?? '';
        final tree = (op['tree'] as Map?)?.cast<String, dynamic>();
        if (route.isEmpty || tree == null) continue;
        layout[route] = LayoutNode.fromJson(tree);
      }
      next = next.copyWith(layout: layout);
    }

    final stringOverrides = patch.strings;
    if (stringOverrides != null) {
      next = next.copyWith(strings: <String, String>{
        ...next.strings,
        ...stringOverrides,
      });
    }

    final assetOps = patch.assets;
    if (assetOps != null) {
      final assets = List<DevAsset>.from(next.assets);
      for (final op in assetOps) {
        final payload = (op['asset'] as Map?)?.cast<String, dynamic>();
        if (payload == null) continue;
        assets.add(DevAsset.fromJson(payload));
      }
      next = next.copyWith(assets: assets);
    }

    return next;
  }

  /// Reverts the most recent transaction.
  void undo() {
    if (_undo.isEmpty) return;
    _redo.add(state);
    if (_redo.length > kDevHistoryLimit) _redo.removeAt(0);
    state = _undo.removeLast();
    _persist();
  }

  /// Re-applies the most recently undone transaction.
  void redo() {
    if (_redo.isEmpty) return;
    _undo.add(state);
    if (_undo.length > kDevHistoryLimit) _undo.removeAt(0);
    state = _redo.removeLast();
    _persist();
  }

  /// Replaces the whole state (used by import and reset).
  void replace(DevState next) => _commit(next);

  /// Removes every developer override and returns to the shipped defaults.
  void reset() => _commit(const DevState());

  /// Exports the current state as a JSON document.
  String export() => state.encode();

  /// Imports a previously exported document. Throws on malformed input; the
  /// caller keeps the previous state because [replace] is never reached.
  void importJson(String source) {
    final decoded = jsonDecode(source);
    if (decoded is! Map) {
      throw const FormatException('Invalid developer state document.');
    }
    replace(DevState.fromJson(decoded.cast<String, dynamic>()));
  }
}

final devStoreProvider =
    StateNotifierProvider<DevStoreController, DevState>((ref) {
  return DevStoreController(ref.watch(sharedPreferencesProvider));
});

/// Overrides produced by the developer panel, merged into the live theme.
final devThemeOverridesProvider = Provider<Map<String, dynamic>>((ref) {
  final dev = ref.watch(devStoreProvider);
  return <String, dynamic>{
    'dark': dev.colorOverrides['dark'] ?? const <String, String>{},
    'light': dev.colorOverrides['light'] ?? const <String, String>{},
    'typography': dev.typeOverrides,
    'radius': dev.radiusOverrides,
    'spacing': dev.spacingOverrides,
    'grid': dev.gridOverrides,
    'direction': dev.direction,
  };
});

/// The section catalogue actually rendered by the app. It starts from the
/// shipped catalogue and is overridden by the developer panel.
final devSectionsProvider = Provider<List<DevSection>>((ref) {
  final dev = ref.watch(devStoreProvider);
  return dev.sections;
});
