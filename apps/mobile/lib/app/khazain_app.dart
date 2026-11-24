import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'router.dart';
import 'theme.dart';
import '../core/app_preferences.dart';
import '../core/prayer_notification_service.dart';
import '../core/prayer_notification_sync.dart';
import '../core/providers.dart';
import '../design/theme_provider.dart';

class KhazainApp extends ConsumerStatefulWidget {
  const KhazainApp({super.key});

  @override
  ConsumerState<KhazainApp> createState() => _KhzainAppState();
}

class _KhzainAppState extends ConsumerState<KhazainApp>
    with WidgetsBindingObserver {
  bool _sameOffsets(Map<String, int> a, Map<String, int> b) {
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      if (b[entry.key] != entry.value) return false;
    }
    return true;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Refresh the rolling notification window whenever the user returns.
      ref.invalidate(prayerTimesProvider);
    }
  }

  Future<void> _syncNotifications() async {
    try {
      await syncPrayerNotifications(ref);
    } catch (error) {
      debugPrint('Prayer notification schedule refresh failed: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(prayerTimesProvider, (previous, next) {
      if (!ref.read(appPreferencesProvider).prayerNotificationsEnabled) return;
      next.when(
        data: (result) {
          if (result != null) {
            unawaited(_syncNotifications());
          } else {
            unawaited(PrayerNotificationService.instance.cancelPrayerAlerts());
          }
        },
        loading: () {},
        error: (error, stack) {
          debugPrint(
              'Prayer times unavailable; clearing potentially outdated alerts: $error');
          unawaited(PrayerNotificationService.instance.cancelPrayerAlerts());
        },
      );
    });

    ref.listen<AppPreferences>(appPreferencesProvider, (previous, next) {
      final wasEnabled = previous?.prayerNotificationsEnabled ?? false;
      if (wasEnabled != next.prayerNotificationsEnabled) {
        if (!next.prayerNotificationsEnabled) {
          unawaited(PrayerNotificationService.instance.cancelPrayerAlerts());
        }
        return;
      }
      if (next.prayerNotificationsEnabled &&
          previous != null &&
          !_sameOffsets(previous.prayerOffsets, next.prayerOffsets)) {
        unawaited(_syncNotifications());
      }
    });

    final themeMode = ref.watch(themeModeProvider);
    final uiTheme = ref.watch(uiThemeProvider);
    final router = ref.watch(routerProvider);

    final isDark = themeMode == ThemeMode.dark ||
        (themeMode == ThemeMode.system &&
            MediaQueryData.fromView(View.of(context)).platformBrightness ==
                Brightness.dark);

    return MaterialApp.router(
      title: 'خَزَائِنُ الهُدَى',
      debugShowCheckedModeBanner: false,
      theme: buildThemeData(uiTheme, isDark: isDark),
      darkTheme: buildThemeData(uiTheme, isDark: true),
      themeMode: themeMode,
      builder: (context, child) {
        // Preserve OS accessibility scaling while applying the user's text-size
        // choice from the settings screen.
        final mediaQuery = MediaQuery.of(context);
        final systemScale = mediaQuery.textScaler.scale(1.0);
        final scale = (systemScale * uiTheme.fontScale).clamp(0.8, 2.4).toDouble();
        final direction =
            uiTheme.direction == 'ltr' ? TextDirection.ltr : TextDirection.rtl;
        return Directionality(
          textDirection: direction,
          child: MediaQuery(
            data: mediaQuery.copyWith(textScaler: TextScaler.linear(scale)),
            child: child ?? const SizedBox.shrink(),
          ),
        );
      },
      routerConfig: router,
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
    );
  }
}
