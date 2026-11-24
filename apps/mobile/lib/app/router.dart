import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/home/home_screen.dart';
import '../features/sections/sections_screen.dart';
import '../features/adhkar/adhkar_screen.dart';
import '../features/amal/amal_screen.dart';
import '../features/calendar/calendar_screen.dart';
import '../features/city/city_search_screen.dart';
import '../features/fada/fada_screen.dart';
import '../features/khamaat/khamaat_screen.dart';
import '../features/mukhalafat/mukhalafat_screen.dart';
import '../features/tasbih/rak_counter_screen.dart';
import '../features/qibla/qibla_screen.dart';
import '../features/prayer/prayer_screen.dart';
import '../features/tasbih/tasbih_screen.dart';
import '../features/radio/radio_screen.dart';
import '../features/radio/audio_library_screen.dart';
import '../features/radio/shiavoice_library_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/settings/prayer_alarm_reliability_screen.dart';
import '../features/settings/source_catalog_screen.dart';
import '../features/content/content_screen.dart';
import '../features/content/ahl_al_bayt_content_screen.dart';
import '../features/content/wallpapers_screen.dart';
import '../features/content/ziyara_library_screen.dart';
import '../features/content/ahlul_bayt_treasures_screen.dart';
import '../features/content/events_screen.dart';
import '../features/content/imams_screen.dart';
import '../features/content/quran_library_screen.dart';
import '../features/content/quran_recitations_screen.dart';
import '../features/favorites/favorites_screen.dart';
import '../features/visitor/visitor_guide_screen.dart';
import '../features/hadith/thaqalayn_hadith_screen.dart';
import '../features/assistant/library_assistant_screen.dart';
import '../features/library/imported_book_reader_screen.dart';
import '../features/library/imported_books_screen.dart';
import '../features/content/quran_text_reader_screen.dart';
import '../features/content/local_text_library.dart';
import '../features/governorate/governorate_selection_screen.dart';
import '../features/settings/settings_subpages.dart';
import 'app_shell.dart';

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/setup',
        builder: (context, state) => GovernorateSelectionScreen(
          isChangeMode: state.uri.queryParameters['mode'] == 'change',
        ),
      ),
      GoRoute(
        path: '/settings/prayer',
        builder: (context, state) => const PrayerSettingsScreen(),
      ),
      GoRoute(
        path: '/settings/alarm',
        builder: (context, state) => const PrayerAlarmReliabilityScreen(),
      ),
      GoRoute(
        path: '/settings/privacy',
        builder: (context, state) => const PrivacyDataScreen(),
      ),
      ShellRoute(
        builder: (context, state, child) =>
            AppShell(location: state.uri.path, child: child),
        routes: [
          GoRoute(path: '/', builder: (context, state) => const HomeScreen()),
          GoRoute(
              path: '/sections',
              builder: (context, state) => const SectionsScreen()),
          GoRoute(
              path: '/assistant',
              builder: (context, state) => const LibraryAssistantScreen()),
          GoRoute(
              path: '/library/imported/:bookId',
              builder: (context, state) => ImportedBookReaderScreen(
                bookId: int.tryParse(state.pathParameters['bookId'] ?? '') ?? 0,
              )),
          GoRoute(
              path: '/visitor-guide',
              builder: (context, state) => const VisitorGuideScreen()),
          GoRoute(
              path: '/ahl-al-bayt',
              builder: (context, state) => const AhlAlBaytContentScreen()),
          GoRoute(
              path: '/imams',
              builder: (context, state) => const ImamsScreen()),
          GoRoute(
              path: '/wallpapers',
              builder: (context, state) => const WallpapersScreen()),
          GoRoute(
              path: '/qibla', builder: (context, state) => const QiblaScreen()),
          GoRoute(
              path: '/prayer',
              builder: (context, state) => const PrayerScreen()),
          GoRoute(
              path: '/tasbih',
              builder: (context, state) => TasbihScreen(
                preset: state.uri.queryParameters['preset'] == 'misira'
                    ? TasbihPreset.misira
                    : TasbihPreset.tasbih,
              )),
          GoRoute(
              path: '/rak-counter',
              builder: (context, state) => const RakCounterScreen()),
          GoRoute(
              path: '/fada',
              builder: (context, state) => const FadaScreen()),
          GoRoute(
              path: '/mukhalafat',
              builder: (context, state) => const MukhalafatScreen()),
          GoRoute(
              path: '/city',
              builder: (context, state) => const CitySearchScreen()),
          GoRoute(
              path: '/adhkar',
              builder: (context, state) =>
                  AdhkarScreen(category: state.uri.queryParameters['category'])),
          GoRoute(
              path: '/amal',
              builder: (context, state) => const AmalScreen()),
          GoRoute(
              path: '/khamaat',
              builder: (context, state) => const KhamaatScreen()),
          GoRoute(
              path: '/calendar',
              builder: (context, state) =>
                  CalendarScreen(mode: state.uri.queryParameters['mode'] ?? 'hijri')),
          GoRoute(
              path: '/settings',
              builder: (context, state) => const SettingsScreen()),
          GoRoute(
              path: '/sources',
              builder: (context, state) => const SourceCatalogScreen()),
          GoRoute(
              path: '/favorites',
              builder: (context, state) => const FavoritesScreen()),
          GoRoute(
              path: '/radio', builder: (context, state) => const RadioScreen()),
          GoRoute(
              path: '/quran',
              builder: (context, state) => const QuranLibraryScreen()),
          GoRoute(
              path: '/quran/recitations',
              builder: (context, state) => const QuranRecitationsScreen()),
          GoRoute(
              path: '/quran/:surahNumber',
              builder: (context, state) {
                final surahNumber =
                    int.tryParse(state.pathParameters['surahNumber'] ?? '') ??
                        0;
                final ayahNumber =
                    int.tryParse(state.uri.queryParameters['ayah'] ?? '');
                return QuranTextReaderScreen(
                    surahNumber: surahNumber, initialAyahNumber: ayahNumber);
              }),
          GoRoute(
              path: '/library',
              builder: (context, state) => const ImportedBooksScreen()),
          GoRoute(
              path: '/hadith',
              builder: (context, state) => const ThaqalaynHadithScreen()),
          GoRoute(
              path: '/hadith/local',
              builder: (context, state) => const ContentStatusScreen(
                  title: 'الروايات المحفوظة دون إنترنت',
                  description: 'نصوص محلية محدودة مع بيانات المصدر والترخيص.',
                  contentType: 'hadith')),
          GoRoute(
              path: '/duas',
              builder: (context, state) => AhlulBaytTreasuresScreen(
                  section: AhlulBaytTreasuresSection.duas,
                  initialSearch: state.uri.queryParameters['search'])),
          GoRoute(
              path: '/duas/local',
              builder: (context, state) => const ContentStatusScreen(
                  title: 'الأدعية المحلية الموثقة',
                  description: 'مقتطفات ومواد محلية مع بيانات المصدر والترخيص.',
                  contentType: 'dua')),
          GoRoute(
              path: '/duas/:duaId',
              builder: (context, state) => AhlulBaytTreasuresReaderScreen(
                  textId: int.tryParse(state.pathParameters['duaId'] ?? '') ?? 0)),
          GoRoute(
              path: '/visits',
              builder: (context, state) => AhlulBaytTreasuresScreen(
                  section: AhlulBaytTreasuresSection.visits,
                  initialSearch: state.uri.queryParameters['search'])),
          GoRoute(
              path: '/visits/local',
              builder: (context, state) => const ZiyaraLibraryScreen()),
          GoRoute(
              path: '/visits/treasures/:textId',
              builder: (context, state) => AhlulBaytTreasuresReaderScreen(
                  textId: int.tryParse(state.pathParameters['textId'] ?? '') ?? 0)),
          GoRoute(
              path: '/visits/:volumeId',
              builder: (context, state) => ZiyaraVolumeTextScreen(
                  volumeId: state.pathParameters['volumeId'] ?? '')),
          GoRoute(
              path: '/events',
              builder: (context, state) => const EventsScreen()),
          GoRoute(
              path: '/ethics',
              builder: (context, state) => const ContentStatusScreen(
                  title: 'الأخلاقيات الإسلامية',
                  description: 'دروس أخلاقية نصية محفوظة محلياً.',
                  contentType: 'ethics_lesson')),
          GoRoute(
              path: '/stories',
              builder: (context, state) => const ContentStatusScreen(
                  title: 'القصص التربوية',
                  description: 'قصص خيالية أصلية، وليست روايات منسوبة.',
                  contentType: 'story')),
          GoRoute(
              path: '/content/:itemId',
              builder: (context, state) => LocalTextReaderScreen(
                  entryId: state.pathParameters['itemId'] ?? '')),
          GoRoute(
              path: '/audio',
              builder: (context, state) => const AudioLibraryScreen()),
          GoRoute(
              path: '/shiavoice',
              builder: (context, state) => const ShiaVoiceLibraryScreen()),
          GoRoute(
              path: '/book/:bookId',
              builder: (context, state) {
                final extra = state.extra;
                final title = extra is Map && extra['title'] is String
                    ? extra['title'] as String
                    : 'المكتبة الإسلامية';
                // Older book-volume links now open the bundled offline text
                // catalogue rather than a non-existent PDF/remote reader.
                return LocalTextLibraryScreen(
                  category: 'book',
                  title: title,
                );
              }),
        ],
      ),
    ],
  );
});
