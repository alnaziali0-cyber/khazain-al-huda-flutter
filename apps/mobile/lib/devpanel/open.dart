import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/haptics.dart';
import '../core/providers.dart';
import 'dev_panel_screen.dart';
import 'pin.dart';

/// The hidden entry point of the developer panel.
///
/// There is no visible affordance anywhere in the app: the panel opens only
/// after a 900ms long-press on the logo in the bottom navigation (a progress
/// ring is drawn while the press is held), or one of the two fallback
/// gestures — seven taps on the logo within three seconds, or three
/// two-finger taps on the screen title.
class DevPanelLauncher extends ConsumerStatefulWidget {
  const DevPanelLauncher({
    super.key,
    required this.child,
    this.holdDuration = const Duration(milliseconds: 900),
    this.onTap,
  });

  final Widget child;
  final Duration holdDuration;
  final VoidCallback? onTap;

  @override
  ConsumerState<DevPanelLauncher> createState() => _DevPanelLauncherState();
}

class _DevPanelLauncherState extends ConsumerState<DevPanelLauncher>
    with SingleTickerProviderStateMixin {
  late final AnimationController _progress;
  final List<DateTime> _recentTaps = <DateTime>[];

  @override
  void initState() {
    super.initState();
    _progress = AnimationController(
      vsync: this,
      duration: widget.holdDuration,
    );
  }

  @override
  void dispose() {
    _progress.dispose();
    super.dispose();
  }

  Future<void> _open() async {
    KhazainHaptics.medium();
    await DevPanelOpener.open(context);
  }

  void _handleLongPressStart(LongPressStartDetails details) {
    _progress.forward(from: 0);
  }

  void _handleLongPressEnd(LongPressEndDetails details) {
    if (_progress.value >= 1) {
      _progress.reset();
      unawaited(_open());
      return;
    }
    _progress.reset();
  }

  void _handleTap() {
    widget.onTap?.call();
    final now = DateTime.now();
    _recentTaps.add(now);
    _recentTaps.removeWhere((time) => now.difference(time) > const Duration(seconds: 3));
    if (_recentTaps.length >= 7) {
      _recentTaps.clear();
      unawaited(_open());
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPressStart: _handleLongPressStart,
      onLongPressEnd: _handleLongPressEnd,
      onLongPressCancel: () => _progress.reset(),
      onTap: _handleTap,
      child: Stack(
        alignment: Alignment.center,
        children: [
          widget.child,
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _progress,
              builder: (context, _) {
                if (_progress.value <= 0) return const SizedBox.shrink();
                return CustomPaint(
                  painter: _HoldRingPainter(progress: _progress.value),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _HoldRingPainter extends CustomPainter {
  _HoldRingPainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final radius = size.shortestSide / 2 - 4;
    final center = Offset(size.width / 2, size.height / 2);
    final track = Paint()
      ..color = const Color(0x33FFFFFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    final arc = Paint()
      ..color = const Color(0xFFBC9551)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, radius, track);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -1.5708,
      6.2832 * progress,
      false,
      arc,
    );
  }

  @override
  bool shouldRepaint(covariant _HoldRingPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

/// Opens the developer panel after the PIN challenge.
class DevPanelOpener {
  DevPanelOpener._();

  static Future<void> open(BuildContext context) async {
    final service = DevPinService(
      ProviderScope.containerOf(context, listen: false)
          .read(sharedPreferencesProvider),
    );
    if (service.isIdleLocked && service.hasPin) {
      final unlocked = await _askForPin(context, service);
      if (unlocked != true || !context.mounted) return;
    }
    if (!context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => const DevPanelScreen(),
        fullscreenDialog: true,
      ),
    );
  }

  static Future<bool?> _askForPin(
      BuildContext context, DevPinService service) async {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => DevPinChallenge(
        service: service,
        onUnlocked: () => Navigator.of(dialogContext).pop(true),
      ),
    );
  }
}

/// The alternative gestures: three two-finger taps on the screen title.
///
/// Attach with [TwoFingerTitleDetector] around a screen title.
class TwoFingerTitleDetector extends StatefulWidget {
  const TwoFingerTitleDetector({super.key, required this.child});

  final Widget child;

  @override
  State<TwoFingerTitleDetector> createState() => _TwoFingerTitleDetectorState();
}

class _TwoFingerTitleDetectorState extends State<TwoFingerTitleDetector> {
  int _twoFingerTaps = 0;
  int _activePointers = 0;
  bool _wasMultiTouch = false;
  DateTime? _lastTap;

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) {
        _activePointers++;
        if (_activePointers >= 2) _wasMultiTouch = true;
      },
      onPointerUp: (_) {
        _activePointers = (_activePointers - 1).clamp(0, 10);
        if (_activePointers > 0 || !_wasMultiTouch) return;
        _wasMultiTouch = false;
        _countTap(context);
      },
      onPointerCancel: (_) {
        _activePointers = (_activePointers - 1).clamp(0, 10);
        if (_activePointers == 0) _wasMultiTouch = false;
      },
      child: widget.child,
    );
  }

  void _countTap(BuildContext context) {
    final now = DateTime.now();
    final last = _lastTap;
    _lastTap = now;
    if (last != null && now.difference(last) > const Duration(seconds: 2)) {
      _twoFingerTaps = 0;
    }
    _twoFingerTaps++;
    if (_twoFingerTaps >= 3) {
      _twoFingerTaps = 0;
      unawaited(DevPanelOpener.open(context));
    }
  }
}

/// Records a developer action in the dev log.
void logDevAction(String message) {
  if (kDebugMode) {
    debugPrint('[dev-panel] $message');
  }
}
