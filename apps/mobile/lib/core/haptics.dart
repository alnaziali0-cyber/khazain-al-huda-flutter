import 'package:flutter/services.dart';

/// Thin wrapper around the platform haptic feedback so every call site
/// respects the user's "haptics enabled" preference and never throws on
/// devices without a vibrator.
class KhazainHaptics {
  const KhazainHaptics._();

  static bool _enabled = true;

  /// Mirrors the user preference stored in `AppPreferences`.
  static void setEnabled(bool value) => _enabled = value;

  static Future<void> selection() async {
    if (!_enabled) return;
    try {
      await HapticFeedback.selectionClick();
    } catch (_) {
      // Haptics are best-effort.
    }
  }

  static Future<void> light() async {
    if (!_enabled) return;
    try {
      await HapticFeedback.lightImpact();
    } catch (_) {
      // Haptics are best-effort.
    }
  }

  static Future<void> medium() async {
    if (!_enabled) return;
    try {
      await HapticFeedback.mediumImpact();
    } catch (_) {
      // Haptics are best-effort.
    }
  }

  static Future<void> heavy() async {
    if (!_enabled) return;
    try {
      await HapticFeedback.heavyImpact();
    } catch (_) {
      // Haptics are best-effort.
    }
  }
}
