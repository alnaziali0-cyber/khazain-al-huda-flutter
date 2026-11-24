import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The developer-panel PIN.
///
/// The 4-digit PIN is never stored in plaintext: a random 16-byte salt is
/// generated once, the PIN is hashed with SHA-256 over `salt + pin`, and only
/// the salt and the digest are persisted.
///
/// On a web target the same contract is implemented with `crypto.subtle`;
/// on mobile the equivalent pure-Dart implementation (`package:crypto`) is
/// used because `crypto.subtle` does not exist outside the browser.
class DevPinService {
  DevPinService(this._prefs);

  final SharedPreferences _prefs;

  static const String storageKey = 'khzain.dev.pin';
  static const int pinLength = 4;
  static const int maxIdleMinutes = 5;

  bool get hasPin => _prefs.getString(storageKey) != null;

  /// The moment of the last successful unlock, used for the idle timeout.
  int? get lastUnlockMillis {
    final raw = _prefs.getString('$storageKey.lastUnlock');
    return raw == null ? null : int.tryParse(raw);
  }

  bool get isIdleLocked {
    final last = lastUnlockMillis;
    if (last == null) return true;
    final elapsed = DateTime.now().millisecondsSinceEpoch - last;
    return elapsed > Duration(minutes: maxIdleMinutes).inMilliseconds;
  }

  void markUnlocked() {
    _prefs.setString(
      '$storageKey.lastUnlock',
      DateTime.now().millisecondsSinceEpoch.toString(),
    );
  }

  /// Locks the panel immediately (backgrounding, rotation, manual lock).
  void lock() => _prefs.remove('$storageKey.lastUnlock');

  /// Creates a PIN. Returns false when the confirmation does not match.
  bool setPin(String pin, String confirmation) {
    if (pin.length != pinLength) return false;
    if (pin != confirmation) return false;
    final salt = _randomSalt();
    final hash = _hash(pin, salt);
    _prefs.setString(
      storageKey,
      jsonEncode(<String, dynamic>{'salt': salt, 'hash': hash}),
    );
    markUnlocked();
    return true;
  }

  /// Verifies a PIN against the stored salted digest.
  bool verify(String pin) {
    final raw = _prefs.getString(storageKey);
    if (raw == null) return false;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return false;
      final salt = decoded['salt'] as String? ?? '';
      final expected = decoded['hash'] as String? ?? '';
      if (salt.isEmpty || expected.isEmpty) return false;
      return _hash(pin, salt) == expected;
    } catch (_) {
      return false;
    }
  }

  void clearPin() => _prefs.remove(storageKey);

  static String _hash(String pin, String salt) =>
      sha256.convert(utf8.encode('$salt:$pin')).toString();

  static String _randomSalt() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }
}

/// The PIN challenge sheet shown before the developer panel opens.
class DevPinChallenge extends StatefulWidget {
  const DevPinChallenge({
    super.key,
    required this.service,
    required this.onUnlocked,
  });

  final DevPinService service;
  final VoidCallback onUnlocked;

  @override
  State<DevPinChallenge> createState() => _DevPinChallengeState();
}

class _DevPinChallengeState extends State<DevPinChallenge> {
  String _first = '';
  String _second = '';
  bool _confirming = false;
  bool _error = false;

  void _press(String digit) {
    setState(() {
      _error = false;
      if (!_confirming) {
        if (_first.length < DevPinService.pinLength) _first += digit;
      } else {
        if (_second.length < DevPinService.pinLength) _second += digit;
      }
    });
    _maybeSubmit();
  }

  void _maybeSubmit() {
    if (_confirming) {
      if (_second.length != DevPinService.pinLength) return;
      if (widget.service.setPin(_first, _second)) {
        widget.onUnlocked();
      } else {
        setState(() {
          _error = true;
          _first = '';
          _second = '';
          _confirming = false;
        });
      }
      return;
    }
    if (_first.length != DevPinService.pinLength) return;
    if (widget.service.hasPin) {
      if (widget.service.verify(_first)) {
        widget.service.markUnlocked();
        widget.onUnlocked();
      } else {
        setState(() {
          _error = true;
          _first = '';
        });
      }
    } else {
      setState(() => _confirming = true);
    }
  }

  void _backspace() {
    setState(() {
      _error = false;
      if (_confirming && _second.isNotEmpty) {
        _second = _second.substring(0, _second.length - 1);
      } else if (!(_confirming && _second.isEmpty) && _first.isNotEmpty) {
        _first = _first.substring(0, _first.length - 1);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final entered = _confirming ? _second : _first;
    final title = !widget.service.hasPin
        ? (_confirming ? 'أعد إدخال الرمز' : 'أنشئ رمز لوحة المطوّر')
        : 'رمز لوحة المطوّر';

    return Dialog(
      backgroundColor: const Color(0xFF2A2A2A),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _error
                  ? 'الرمز غير مطابق. حاول مرة أخرى.'
                  : '${DevPinService.pinLength} أرقام. يُحفظ مشفّراً بملح عشوائي.',
              style: theme.textTheme.bodySmall?.copyWith(color: Colors.white70),
            ),
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var index = 0; index < DevPinService.pinLength; index++)
                  Container(
                    width: 12,
                    height: 12,
                    margin: const EdgeInsets.symmetric(horizontal: 6),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: index < entered.length
                          ? const Color(0xFFBC9551)
                          : Colors.white24,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 18),
            GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 1.9,
              children: [
                for (final digit in const [
                  '1', '2', '3', '4', '5', '6', '7', '8', '9',
                ])
                  _Key(label: digit, onTap: () => _press(digit)),
                _Key(
                  label: 'مسح',
                  icon: Icons.backspace_outlined,
                  onTap: _backspace,
                ),
                _Key(label: '0', onTap: () => _press('0')),
                _Key(
                  label: 'دخول',
                  icon: Icons.check_rounded,
                  onTap: _maybeSubmit,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Key extends StatelessWidget {
  const _Key({this.label, this.icon, required this.onTap});

  final String? label;
  final IconData? icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF3C3C3C),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Center(
          child: icon != null
              ? Icon(icon, size: 18, color: Colors.white)
              : Text(
                  label!,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                  ),
                ),
        ),
      ),
    );
  }
}
