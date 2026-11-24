import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../components/app_text.dart';
import '../../core/providers.dart';
import '../../design/theme_provider.dart';

/// The support sheet (G12).
///
/// It offers WhatsApp, e-mail and a copy-to-clipboard action, and keeps a
/// short local history of the support requests the user sent so the sheet is
/// never empty.
class SupportSheet {
  SupportSheet._();

  static const String whatsappUri = 'https://wa.me/9647866580209';
  static const String emailUri = 'mailto:khazain.alhuda.app@gmail.com';
  static const String _historyKey = 'support_history_v1';

  static Future<void> show(BuildContext context) async {
    final history = _readHistory(context);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => _SupportSheetContent(history: history),
    );
  }

  static List<Map<String, String>> _readHistory(BuildContext context) {
    try {
      final prefs =
          ProviderScope.containerOf(context, listen: false)
              .read(sharedPreferencesProvider);
      final raw = prefs.getString(_historyKey);
      if (raw == null || raw.isEmpty) return const <Map<String, String>>[];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const <Map<String, String>>[];
      return decoded
          .whereType<Map>()
          .map((item) => item.map(
              (key, value) => MapEntry(key.toString(), value.toString())))
          .toList(growable: false);
    } catch (_) {
      return const <Map<String, String>>[];
    }
  }

  static Future<void> _record(
      BuildContext context, String channel, String detail) async {
    try {
      final prefs =
          ProviderScope.containerOf(context, listen: false)
              .read(sharedPreferencesProvider);
      final history = _readHistory(context);
      final next = <Map<String, String>>[
        <String, String>{
          'channel': channel,
          'detail': detail,
          'at': DateTime.now().toIso8601String(),
        },
        ...history,
      ].take(8).toList(growable: false);
      await prefs.setString(
        _historyKey,
        jsonEncode(next),
      );
    } catch (_) {
      // The history is a convenience; failing to store it must not block
      // the support action.
    }
  }

  static Future<void> _open(BuildContext context, Uri uri) async {
    try {
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened && context.mounted) _showError(context);
    } catch (_) {
      if (context.mounted) _showError(context);
    }
  }

  static void _showError(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تعذر فتح وسيلة التواصل على هذا الجهاز.')),
    );
  }
}

class _SupportSheetContent extends ConsumerWidget {
  const _SupportSheetContent({required this.history});

  final List<Map<String, String>> history;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(uiThemeProvider);
    return Container(
      decoration: BoxDecoration(
        color: theme.color('surface1'),
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(theme.sheetRadius),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: theme.color('divider'),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              AppText('الدعم والتواصل', token: 'h2', textAlign: TextAlign.center),
              const SizedBox(height: 6),
              AppText(
                'اختر وسيلة التواصل المناسبة.',
                token: 'bodyDim',
                color: theme.color('textMuted'),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 14),
              _SupportAction(
                icon: Icons.chat_rounded,
                title: 'واتساب',
                subtitle: 'أسرع وسيلة للرد',
                onTap: () async {
                  await SupportSheet._record(context, 'واتساب', 'طلب دعم عبر واتساب');
                  await SupportSheet._open(
                    context,
                    Uri.parse(
                      '${SupportSheet.whatsappUri}?text=${Uri.encodeComponent('السلام عليكم، أحتاج مساعدة في تطبيق خزائن الهدى.')}',
                    ),
                  );
                },
              ),
              _SupportAction(
                icon: Icons.mail_outline_rounded,
                title: 'البريد الإلكتروني',
                subtitle: SupportSheet.emailUri.replaceFirst('mailto:', ''),
                onTap: () async {
                  await SupportSheet._record(context, 'بريد', 'طلب دعم عبر البريد');
                  await SupportSheet._open(context, Uri.parse(SupportSheet.emailUri));
                },
              ),
              _SupportAction(
                icon: Icons.copy_rounded,
                title: 'نسخ رابط الدعم',
                subtitle: 'انسخ العنوان وشاركه مع من تريد',
                trailingIcon: Icons.check_rounded,
                onTap: () async {
                  await Clipboard.setData(
                    const ClipboardData(
                      text:
                          'دعم تطبيق خزائن الهدى: واتساب 9647866580209 · البريد khazain.alhuda.app@gmail.com',
                    ),
                  );
                  await SupportSheet._record(context, 'نسخ', 'نسخ بيانات التواصل');
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('نُسخت بيانات التواصل.')),
                  );
                },
              ),
              if (history.isNotEmpty) ...[
                const SizedBox(height: 12),
                AppText('آخر الطلبات', token: 'h2'),
                const SizedBox(height: 6),
                for (final entry in history)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      children: [
                        Icon(Icons.history_rounded,
                            size: 15, color: theme.color('textMuted')),
                        const SizedBox(width: 8),
                        Expanded(
                          child: AppText(
                            '${entry['channel']} · ${entry['detail']}',
                            token: 'bodyDim',
                            color: theme.color('textMuted'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SupportAction extends ConsumerWidget {
  const _SupportAction({
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.trailingIcon,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final IconData? trailingIcon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(uiThemeProvider);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: theme.color('green').withOpacity(.22),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, size: 19, color: theme.color('gold')),
      ),
      title: AppText(title, token: 'body'),
      subtitle: subtitle == null
          ? null
          : AppText(subtitle!, token: 'bodyDim', color: theme.color('textMuted')),
      trailing: Icon(trailingIcon ?? Icons.open_in_new_rounded,
          size: 18, color: theme.color('textMuted')),
      onTap: onTap,
    );
  }
}
