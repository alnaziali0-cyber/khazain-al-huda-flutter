import 'dart:convert';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/khazain_app.dart';
import 'core/audio_playback_service.dart';
import 'core/prayer_notification_service.dart';
import 'core/providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('ar');
  final preferences = await SharedPreferences.getInstance();
  await _clearRemovedTextSectionCaches(preferences);

  AppAudioPlayback audioPlayback;
  KhazainAudioHandler? registeredAudioHandler;
  try {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());
    await AudioService.init(
      builder: () {
        registeredAudioHandler = KhazainAudioHandler();
        return registeredAudioHandler!;
      },
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'com.khazain.alhuda.audio',
        androidNotificationChannelName: 'خزائن الهدى',
        androidNotificationChannelDescription:
            'تشغيل القرآن والأذان والحسينيات والأدعية والزيارات',
        androidNotificationOngoing: true,
        androidStopForegroundOnPause: true,
        androidNotificationIcon: 'mipmap/ic_launcher',
      ),
    );
    audioPlayback = registeredAudioHandler!;
  } catch (error) {
    // Local playback remains available on targets without native AudioService setup.
    debugPrint('Background audio service initialization failed: $error');
    audioPlayback = registeredAudioHandler ?? KhazainAudioHandler();
  }

  try {
    await PrayerNotificationService.instance.initialize();
  } catch (error) {
    debugPrint('Prayer notification initialization failed: $error');
  }
  runApp(ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(preferences),
      appAudioPlaybackProvider.overrideWithValue(audioPlayback),
    ],
    child: const KhazainApp(),
  ));
}

/// One-time cleanup of cached payloads for the intentionally cleared text sections.
/// Other preferences, prayer settings, favorites outside those sections, and all
/// Quran-related keys are left untouched.
Future<void> _clearRemovedTextSectionCaches(SharedPreferences prefs) async {
  const migrationKey = 'khazain_removed_text_sections_v1';
  if (prefs.getBool(migrationKey) == true) return;

  const exactKeys = <String>{
    'catalog_cache_book',
    'catalog_cache_hadith',
    'catalog_cache_dua',
    'catalog_cache_visit',
  };
  const prefixes = <String>[
    'catalog_cache_book_',
    'catalog_cache_hadith_',
    'catalog_cache_dua_',
    'catalog_cache_visit_',
    'book_pages_',
    'book_page_v2_',
  ];
  final obsolete = prefs.getKeys().where((key) =>
      !key.toLowerCase().contains('quran') &&
      (exactKeys.contains(key) || prefixes.any(key.startsWith))).toList();
  for (final key in obsolete) {
    await prefs.remove(key);
  }

  final cachedFavorites = prefs.getString('favorite_entries_cache');
  if (cachedFavorites != null) {
    try {
      final decoded = jsonDecode(cachedFavorites);
      if (decoded is List) {
        final retained = decoded.where((item) {
          if (item is! Map) return true;
          final type = item['entity_type']?.toString();
          return !const {'book', 'hadith', 'dua', 'visit'}.contains(type);
        }).toList(growable: false);
        await prefs.setString('favorite_entries_cache', jsonEncode(retained));
      }
    } catch (_) {
      // Do not discard an unreadable shared cache: it may still contain Quran favorites.
    }
  }
  await prefs.setBool(migrationKey, true);
}
