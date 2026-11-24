import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_preferences.dart';
import '../../core/prayer_notification_service.dart';
import '../../core/prayer_notification_sync.dart';

class PrayerAlarmReliabilityScreen extends ConsumerStatefulWidget {
  const PrayerAlarmReliabilityScreen({super.key});

  @override
  ConsumerState<PrayerAlarmReliabilityScreen> createState() =>
      _PrayerAlarmReliabilityScreenState();
}

class _PrayerAlarmReliabilityScreenState
    extends ConsumerState<PrayerAlarmReliabilityScreen>
    with WidgetsBindingObserver {
  late Future<PrayerNotificationCapabilities> _capabilities;
  bool _busy = false;

  PrayerNotificationService get _service =>
      PrayerNotificationService.instance;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _capabilities = _service.readCapabilities();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  void _refresh() {
    if (!mounted) return;
    setState(() => _capabilities = _service.readCapabilities());
  }

  Future<void> _enableNotifications() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final granted = await _service.requestPermissions();
      if (!granted) {
        _message(
          'لم يُمنح إذن الإشعارات. افتح معلومات التطبيق من إعدادات الهاتف وفعّل الإشعارات ثم أعد الفحص.',
        );
        return;
      }
      await ref
          .read(appPreferencesProvider.notifier)
          .setPrayerNotificationsEnabled(true);
      final scheduled = await syncPrayerNotifications(ref);
      _message('تم تفعيل التنبيهات وجدولة $scheduled تنبيهاً.');
    } catch (_) {
      await ref
          .read(appPreferencesProvider.notifier)
          .setPrayerNotificationsEnabled(false);
      _message('تعذر تفعيل التنبيهات. تحقق من أذونات الجهاز وحاول مجدداً.');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        _refresh();
      }
    }
  }

  Future<void> _requestExactAlarms() async {
    if (_busy) return;
    setState(() => _busy = true);
    var allowed = false;
    try {
      allowed = await _service.requestExactAlarmPermission();
    } catch (_) {
      allowed = false;
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        _refresh();
      }
    }
    if (mounted) {
      _message(allowed
          ? 'تم السماح بالتنبيهات الدقيقة.'
          : 'لم يتم منح صلاحية التنبيهات الدقيقة؛ سيستخدم التطبيق الجدولة غير الدقيقة عند توفرها.');
    }
  }

  Future<void> _testAdhan() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await _service.showTestPrayerNotification();
      _message('أُرسل إشعار الاختبار. صوت التنبيه هو صوت النظام الافتراضي.');
    } catch (error) {
      _message(error is StateError
          ? error.message.toString()
          : 'تعذر إرسال إشعار الاختبار. تحقق من أذونات الإشعارات.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _message(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _showBatteryHelp() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('السماح بالتنبيه في الخلفية'),
        content: const Text(
          'افتح معلومات تطبيق خزائن الهدى من إعدادات الهاتف، ثم افتح البطارية واختر السماح بالنشاط في الخلفية أو وضع عدم التقييد إن كان متاحاً. قد تختلف أسماء الخيارات حسب الشركة وإصدار Android. لا يستطيع هذا الإصدار قراءة حالة تحسين البطارية تلقائياً.',
          textAlign: TextAlign.right,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('حسناً'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final preferences = ref.watch(appPreferencesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('موثوقية منبّه الصلاة')),
      body: FutureBuilder<PrayerNotificationCapabilities>(
        future: _capabilities,
        builder: (context, snapshot) {
          final capabilities = snapshot.data;
          final loading = snapshot.connectionState == ConnectionState.waiting;
          final notificationEnabled = capabilities?.notificationsEnabled;
          final exactEnabled = capabilities?.exactAlarmsEnabled;
          final isAndroid = capabilities?.isAndroid ?? false;

          return ListView(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 30),
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(18, 20, 18, 20),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest
                      .withOpacity(.42),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: theme.colorScheme.outline.withOpacity(.12),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'تهيئة تنبيهات الصلاة',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      'تحقق من الأذونات المهمة حتى تصلك التنبيهات في وقتها. بعض إعدادات توفير الطاقة تُراجع من نظام الهاتف نفسه.',
                      textAlign: TextAlign.right,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurface.withOpacity(.68),
                        height: 1.65,
                      ),
                    ),
                    if (loading) ...[
                      const SizedBox(height: 14),
                      const LinearProgressIndicator(),
                    ],
                    if (snapshot.hasError) ...[
                      const SizedBox(height: 10),
                      Text(
                        'تعذر قراءة بعض حالات النظام. أعد المحاولة.',
                        style: TextStyle(color: theme.colorScheme.error),
                      ),
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: TextButton.icon(
                          onPressed: _refresh,
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('إعادة الفحص'),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'حالة الجهاز',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 6),
              _ReliabilityRow(
                icon: Icons.notifications_active_outlined,
                title: 'الإشعارات',
                description: notificationEnabled == true
                    ? 'يسمح النظام للتطبيق بإرسال الإشعارات.'
                    : notificationEnabled == false
                        ? 'الإشعارات معطّلة؛ لذلك لن يظهر تنبيه الصلاة.'
                        : 'حالة الإشعارات غير متاحة حالياً.',
                status: loading
                    ? 'جارٍ الفحص'
                    : notificationEnabled == true
                        ? 'مفعّل'
                        : notificationEnabled == false
                            ? 'إصلاح'
                            : 'غير معروف',
                state: loading
                    ? _ReliabilityState.pending
                    : notificationEnabled == true
                        ? _ReliabilityState.good
                        : notificationEnabled == false
                            ? _ReliabilityState.action
                            : _ReliabilityState.unknown,
                actionLabel: notificationEnabled == false ? 'تفعيل' : null,
                onAction: notificationEnabled == false
                    ? _enableNotifications
                    : null,
              ),
              _ReliabilityRow(
                icon: Icons.alarm_on_rounded,
                title: 'المنبّهات الدقيقة',
                description: exactEnabled == true
                    ? 'يسمح النظام بجدولة التنبيه في الوقت المحدد.'
                    : exactEnabled == false
                        ? 'يمكن استخدام تنبيهات غير دقيقة إلى أن تُمنح الصلاحية.'
                        : isAndroid
                            ? 'تعذر التأكد من صلاحية التنبيه الدقيق.'
                            : 'هذه الصلاحية خاصة بنظام Android.',
                status: loading
                    ? 'جارٍ الفحص'
                    : !isAndroid
                        ? 'غير مطلوب'
                        : exactEnabled == true
                            ? 'مفعّل'
                            : exactEnabled == false
                                ? 'إصلاح'
                                : 'غير معروف',
                state: loading
                    ? _ReliabilityState.pending
                    : !isAndroid || exactEnabled == true
                        ? _ReliabilityState.good
                        : exactEnabled == false
                            ? _ReliabilityState.action
                            : _ReliabilityState.unknown,
                actionLabel:
                    isAndroid && exactEnabled == false ? 'السماح' : null,
                onAction: isAndroid && exactEnabled == false
                    ? _requestExactAlarms
                    : null,
              ),
              _ReliabilityRow(
                icon: Icons.battery_saver_outlined,
                title: 'تحسين البطارية',
                description:
                    'لا تتوفر قراءة مباشرة لهذه الحالة في ملفات المنصة الحالية. راجع إعداد البطارية يدوياً.',
                status: 'تحقق يدوي',
                state: _ReliabilityState.unknown,
                actionLabel: 'إرشادات',
                onAction: _showBatteryHelp,
              ),
              _ReliabilityRow(
                icon: Icons.fullscreen_rounded,
                title: 'الأذان بشاشة كاملة',
                description:
                    'يعتمد التطبيق حالياً على إشعار النظام، ولا يستخدم عرضاً بملء الشاشة.',
                status: 'غير مطلوب',
                state: _ReliabilityState.neutral,
              ),
              _ReliabilityRow(
                icon: Icons.sync_rounded,
                title: 'قيود الخلفية',
                description:
                    'قد توقف بعض واجهات Android التنبيهات عند تقييد التطبيق. راجع إعدادات البطارية للتأكد من السماح بالنشاط في الخلفية.',
                status: 'تحقق يدوي',
                state: _ReliabilityState.unknown,
                actionLabel: 'إرشادات',
                onAction: _showBatteryHelp,
              ),
              const SizedBox(height: 22),
              FilledButton(
                onPressed: _busy ? null : _testAdhan,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(58),
                  backgroundColor: const Color(0xFF0B8A60),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30),
                  ),
                ),
                child: _busy
                    ? const SizedBox(
                        width: 21,
                        height: 21,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text(
                        'تجربة الأذان',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
              ),
              const SizedBox(height: 10),
              Text(
                'يرسل الاختبار إشعاراً فورياً بصوت النظام الافتراضي، ولا يشغّل تسجيلاً كاملاً للأذان. حالة التفعيل المحفوظة في التطبيق: ${preferences.prayerNotificationsEnabled ? 'مفعّلة' : 'متوقفة'}.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(height: 1.6),
              ),
              const SizedBox(height: 12),
              Center(
                child: TextButton.icon(
                  onPressed: _refresh,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('إعادة فحص الأذونات'),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

enum _ReliabilityState { good, action, unknown, pending, neutral }

class _ReliabilityRow extends StatelessWidget {
  const _ReliabilityRow({
    required this.icon,
    required this.title,
    required this.description,
    required this.status,
    required this.state,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String description;
  final String status;
  final _ReliabilityState state;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = switch (state) {
      _ReliabilityState.good => const Color(0xFF4CAF50),
      _ReliabilityState.action => theme.colorScheme.error,
      _ReliabilityState.unknown => const Color(0xFFC68C35),
      _ReliabilityState.pending => theme.colorScheme.primary,
      _ReliabilityState.neutral => theme.colorScheme.onSurface.withOpacity(.55),
    };
    final statusIcon = switch (state) {
      _ReliabilityState.good => Icons.check_rounded,
      _ReliabilityState.action => Icons.access_time_rounded,
      _ReliabilityState.unknown => Icons.info_outline_rounded,
      _ReliabilityState.pending => Icons.hourglass_top_rounded,
      _ReliabilityState.neutral => Icons.remove_circle_outline_rounded,
    };

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 13),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(statusIcon, color: color, size: 29),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  title,
                  textAlign: TextAlign.right,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  description,
                  textAlign: TextAlign.right,
                  style: theme.textTheme.bodySmall?.copyWith(
                    height: 1.55,
                    color: theme.colorScheme.onSurface.withOpacity(.66),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          if (onAction != null)
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(foregroundColor: color),
              child: Text(actionLabel ?? status),
            )
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 72),
              child: Text(
                status,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
