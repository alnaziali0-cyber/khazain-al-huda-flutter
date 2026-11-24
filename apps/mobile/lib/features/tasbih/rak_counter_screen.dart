import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../components/app_text.dart';
import '../../core/haptics.dart';
import '../../core/providers.dart';
import '../../design/theme_provider.dart';

/// The rak' counter (عداد الركع).
///
/// It counts the raka'at of a single prayer with a target the user chooses
/// (four for the night prayers, three for Dhuhr and two for Asr by default),
/// ticks with haptics and keeps the count on the device.
class RakCounterScreen extends ConsumerStatefulWidget {
  const RakCounterScreen({super.key});

  @override
  ConsumerState<RakCounterScreen> createState() => _RakCounterScreenState();
}

class _RakCounterScreenState extends ConsumerState<RakCounterScreen> {
  static const String _countKey = 'rak_counter_count';
  static const String _targetKey = 'rak_counter_target';

  int _count = 0;
  int _target = 4;

  @override
  void initState() {
    super.initState();
    final prefs = ref.read(sharedPreferencesProvider);
    _count = prefs.getInt(_countKey) ?? 0;
    _target = prefs.getInt(_targetKey) ?? 4;
  }

  Future<void> _setCount(int value) async {
    setState(() => _count = value);
    await ref.read(sharedPreferencesProvider).setInt(_countKey, value);
  }

  Future<void> _setTarget(int value) async {
    setState(() => _target = value);
    await ref.read(sharedPreferencesProvider).setInt(_targetKey, value);
  }

  void _increment() {
    KhazainHaptics.light();
    if (_count >= _target) {
      KhazainHaptics.heavy();
      _setCount(0);
      return;
    }
    _setCount(_count + 1);
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(uiThemeProvider);
    final progress = _target <= 0 ? 0.0 : (_count / _target).clamp(0.0, 1.0);

    return Container(
      color: theme.color('bgApp'),
      child: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
          children: [
            AppText('عداد الركع', token: 'display'),
            const SizedBox(height: 6),
            AppText(
              'اضغط في كل ركمة، ويضبط العدّ نفسه عند بلوغ العدد المطلوب.',
              token: 'bodyDim',
              color: theme.color('textMuted'),
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.symmetric(vertical: 28),
              decoration: BoxDecoration(
                color: theme.color('surface1'),
                borderRadius: BorderRadius.circular(theme.cardRadius),
                border: Border.all(color: theme.color('hairline')),
              ),
              child: Column(
                children: [
                  Text(
                    '$_count / $_target',
                    style: TextStyle(
                      fontSize: 54 * theme.fontScale,
                      fontWeight: FontWeight.w700,
                      color: theme.color('goldBright'),
                      fontFamily: theme.fontFamily,
                    ),
                  ),
                  const SizedBox(height: 6),
                  AppText(
                    _count >= _target ? 'اكتملت الركعة' : 'الركعات المتبقية: ${_target - _count}',
                    token: 'bodyDim',
                    color: theme.color('textMuted'),
                  ),
                  const SizedBox(height: 18),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 6,
                        color: theme.color('gold'),
                        backgroundColor: theme.color('divider'),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            SizedBox(
              height: 64,
              child: FilledButton.icon(
                onPressed: _increment,
                icon: const Icon(Icons.add_rounded, size: 24),
                label: AppText('ركعة', token: 'h2'),
                style: FilledButton.styleFrom(
                  backgroundColor: theme.color('green'),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(theme.cardRadius),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _setCount(0),
                    child: AppText('تصفير', token: 'label'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _setTarget(_target == 4 ? 3 : _target == 3 ? 2 : 4),
                    child: AppText('الهدف: $_target', token: 'label'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            AppText(
              'العدد يُحفظ على الجهاز فقط ولا يُرسل إلى أي خادم.',
              token: 'bodyDim',
              color: theme.color('textMuted'),
            ),
          ],
        ),
      ),
    );
  }
}
