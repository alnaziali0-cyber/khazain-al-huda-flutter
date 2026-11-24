import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

typedef ShiaVoiceLibraryLoader = Future<Map<String, dynamic>> Function();
typedef ShiaVoiceUrlOpener = Future<bool> Function(Uri uri);

class ShiaVoiceLibraryScreen extends StatefulWidget {
  const ShiaVoiceLibraryScreen({
    super.key,
    this.loadLibrary,
    this.openUrl,
  });

  final ShiaVoiceLibraryLoader? loadLibrary;
  final ShiaVoiceUrlOpener? openUrl;

  @override
  State<ShiaVoiceLibraryScreen> createState() => _ShiaVoiceLibraryScreenState();
}

class _ShiaVoiceLibraryScreenState extends State<ShiaVoiceLibraryScreen> {
  static const _assetPath =
      'assets/data/catalogs/shiavoice_recent_library.json';
  static const _tabs = <({String id, String title, IconData icon})>[
    (id: 'recent', title: 'آخر الاستماع', icon: Icons.history_rounded),
    (id: 'queue', title: 'القائمة الحالية', icon: Icons.queue_music_rounded),
    (id: 'favorites', title: 'المفضلة', icon: Icons.favorite_border_rounded),
    (id: 'playlists', title: 'قوائم التشغيل', icon: Icons.playlist_play_rounded),
  ];
  static const _categories = <({String id, String title})>[
    (id: 'all', title: 'الكل'),
    (id: 'quran', title: 'القرآن'),
    (id: 'adhan', title: 'الأذان'),
    (id: 'duas', title: 'الأدعية والأذكار'),
    (id: 'poems', title: 'قصائد ومقاطع'),
  ];

  late Future<Map<String, dynamic>> _library;
  final TextEditingController _searchController = TextEditingController();
  String _selectedTab = 'recent';
  String _selectedCategory = 'all';
  String _search = '';

  @override
  void initState() {
    super.initState();
    _library = _loadLibrary();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<Map<String, dynamic>> _loadLibrary() async {
    final loaded = widget.loadLibrary != null
        ? await widget.loadLibrary!()
        : jsonDecode(await rootBundle.loadString(_assetPath))
            as Map<String, dynamic>;
    final rows = loaded['recent'];
    if (rows is! List) {
      throw const FormatException('Invalid ShiaVoice recent list.');
    }
    return loaded;
  }

  List<Map<String, dynamic>> _tracksFor(
    Map<String, dynamic> library,
  ) {
    final recent = (library['recent'] as List)
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
    switch (_selectedTab) {
      case 'queue':
        final queue = library['queue'];
        final ids = queue is Map && queue['track_ids'] is List
            ? (queue['track_ids'] as List).whereType<String>().toSet()
            : <String>{};
        return recent.where((track) => ids.contains(track['id'])).toList();
      case 'favorites':
        final favorites = library['favorites'];
        final ids = favorites is Map && favorites['track'] is List
            ? (favorites['track'] as List)
                .whereType<String>()
                .toSet()
            : <String>{};
        return recent.where((track) => ids.contains(track['id'])).toList();
      case 'recent':
      default:
        return recent;
    }
  }

  List<Map<String, dynamic>> _visibleTracks(
    Map<String, dynamic> library,
  ) {
    var rows = _tracksFor(library);
    if (_selectedTab == 'recent' && _selectedCategory != 'all') {
      rows = rows
          .where((track) => track['category'] == _selectedCategory)
          .toList();
    }
    final query = _search.trim().toLowerCase();
    if (query.isNotEmpty) {
      rows = rows.where((track) {
        final title = (track['title'] ?? '').toString().toLowerCase();
        final artist = (track['artist'] ?? '').toString().toLowerCase();
        return title.contains(query) || artist.contains(query);
      }).toList();
    }
    return rows;
  }

  Uri? _safeSourceUri(Object? path, {required bool artist}) {
    if (path is! String) return null;
    final pattern = artist
        ? RegExp(r'^/@[A-Za-z0-9_-]+$')
        : RegExp(r'^/play-[A-Za-z0-9]+$');
    if (!pattern.hasMatch(path)) return null;
    return Uri.https('shiavoice.com', path);
  }

  Future<void> _openSource(Map<String, dynamic> track) async {
    final uri = _safeSourceUri(track['page_path'], artist: false);
    if (uri == null) {
      _showMessage('رابط التسجيل غير صالح في ملف التصدير.');
      return;
    }
    try {
      final opened = widget.openUrl != null
          ? await widget.openUrl!(uri)
          : await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened && mounted) {
        _showMessage('تعذر فتح صفحة التسجيل لدى المصدر.');
      }
    } catch (_) {
      _showMessage('تعذر فتح صفحة التسجيل لدى المصدر.');
    }
  }

  Future<void> _openArtist(Map<String, dynamic> track) async {
    final uri = _safeSourceUri(track['artist_path'], artist: true);
    if (uri == null) {
      _showMessage('صفحة القارئ غير متاحة في ملف التصدير.');
      return;
    }
    try {
      final opened = widget.openUrl != null
          ? await widget.openUrl!(uri)
          : await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened && mounted) {
        _showMessage('تعذر فتح صفحة القارئ.');
      }
    } catch (_) {
      _showMessage('تعذر فتح صفحة القارئ.');
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  String _duration(Object? value) {
    if (value is! int || value < 0) return '';
    final hours = value ~/ 3600;
    final minutes = (value % 3600) ~/ 60;
    final seconds = value % 60;
    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:'
          '${seconds.toString().padLeft(2, '0')}';
    }
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  String _formatExportDate(Object? value) {
    if (value is! String) return 'تصدير مستورد';
    final date = DateTime.tryParse(value)?.toLocal();
    if (date == null) return 'تصدير مستورد';
    return 'تاريخ التصدير: ${date.year}/${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')}';
  }

  int _count(Map<String, dynamic> library, String tab) {
    if (tab == 'recent') return (library['recent'] as List).length;
    if (tab == 'queue') {
      final queue = library['queue'];
      return queue is Map && queue['track_ids'] is List
          ? (queue['track_ids'] as List).length
          : 0;
    }
    if (tab == 'favorites') {
      final favorites = library['favorites'];
      return favorites is Map && favorites['track'] is List
          ? (favorites['track'] as List).length
          : 0;
    }
    final playlists = library['playlists'];
    return playlists is List ? playlists.length : 0;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FutureBuilder<Map<String, dynamic>>(
      future: _library,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError || snapshot.data == null) {
          return _empty('تعذر قراءة ملف مكتبة صوت الشيعة المستورد.');
        }
        final library = snapshot.data!;
        final tracks = _visibleTracks(library);
        final selectedTab = _tabs.firstWhere((tab) => tab.id == _selectedTab);
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 10),
              child: Row(
                children: [
                  Icon(Icons.library_music_rounded,
                      color: theme.colorScheme.primary, size: 30),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'مكتبة صوت الشيعة',
                          style: theme.textTheme.headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w900),
                        ),
                        Text(
                          'سجلّك المستورد من موقع صوت الشيعة',
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'تحديث الملف',
                    onPressed: () => setState(() => _library = _loadLibrary()),
                    icon: const Icon(Icons.refresh_rounded),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.info_outline_rounded,
                              color: theme.colorScheme.primary, size: 19),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text(
                              'عرض مرتبط بالمصدر الأصلي',
                              style: TextStyle(fontWeight: FontWeight.w800),
                            ),
                          ),
                          Text(
                            '${(library['recent'] as List).length} تسجيل',
                            style: theme.textTheme.labelMedium,
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'تُفتح صفحة التسجيل على shiavoice.com. لا يقوم التطبيق بتنزيل الصوت أو إعادة استضافته، ولا توجد إفادة بأن التطبيق تابع للموقع.',
                        style: theme.textTheme.bodySmall?.copyWith(height: 1.45),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _formatExportDate(library['exported_at']),
                        style: theme.textTheme.labelSmall,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            SizedBox(
              height: 50,
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                scrollDirection: Axis.horizontal,
                itemCount: _tabs.length,
                separatorBuilder: (_, __) => const SizedBox(width: 7),
                itemBuilder: (context, index) {
                  final tab = _tabs[index];
                  final selected = _selectedTab == tab.id;
                  return ChoiceChip(
                    selected: selected,
                    avatar: Icon(tab.icon, size: 17),
                    label: Text('${tab.title} (${_count(library, tab.id)})'),
                    onSelected: (_) => setState(() {
                      _selectedTab = tab.id;
                      _selectedCategory = 'all';
                      _search = '';
                      _searchController.clear();
                    }),
                  );
                },
              ),
            ),
            if (_selectedTab == 'recent')
              SizedBox(
                height: 46,
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  scrollDirection: Axis.horizontal,
                  itemCount: _categories.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 7),
                  itemBuilder: (context, index) {
                    final category = _categories[index];
                    return ChoiceChip(
                      selected: _selectedCategory == category.id,
                      label: Text(category.title),
                      onSelected: (_) =>
                          setState(() => _selectedCategory = category.id),
                    );
                  },
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 7, 14, 8),
              child: TextField(
                controller: _searchController,
                onChanged: (value) => setState(() => _search = value),
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search_rounded),
                  hintText: 'ابحث باسم التسجيل أو القارئ',
                  suffixIcon: _search.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'مسح البحث',
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _search = '');
                          },
                          icon: const Icon(Icons.close_rounded),
                        ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  isDense: true,
                ),
              ),
            ),
            Expanded(
              child: tracks.isEmpty
                  ? _empty(_emptyMessage(selectedTab.title))
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(14, 4, 14, 20),
                      itemCount: tracks.length,
                      separatorBuilder: (_, __) =>
                          const SizedBox(height: 7),
                      itemBuilder: (context, index) {
                        final track = tracks[index];
                        final title =
                            (track['title'] ?? 'تسجيل صوتي').toString();
                        final artist = (track['artist'] ?? '').toString();
                        final duration = _duration(track['duration_seconds']);
                        final matchingCategories = _categories
                            .where((item) => item.id == track['category'])
                            .toList();
                        final category = matchingCategories.isEmpty
                            ? null
                            : matchingCategories.first.title;
                        return Card(
                          child: ListTile(
                            onTap: () => _openSource(track),
                            leading: CircleAvatar(
                              child: Icon(_iconFor(track['category'])),
                            ),
                            title: Text(
                              title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w800),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text([
                                  if (artist.isNotEmpty) artist,
                                  if (duration.isNotEmpty) duration,
                                  if (category != null) category,
                                ].join(' · ')),
                                if (_safeSourceUri(track['artist_path'],
                                        artist: true) !=
                                    null)
                                  Align(
                                    alignment: AlignmentDirectional.centerStart,
                                    child: TextButton(
                                      onPressed: () => _openArtist(track),
                                      style: TextButton.styleFrom(
                                        padding: EdgeInsets.zero,
                                        minimumSize: const Size(0, 28),
                                        tapTargetSize:
                                            MaterialTapTargetSize.shrinkWrap,
                                      ),
                                      child: const Text('صفحة القارئ'),
                                    ),
                                  ),
                              ],
                            ),
                            trailing: IconButton(
                              tooltip: 'فتح في صوت الشيعة',
                              onPressed: () => _openSource(track),
                              icon: const Icon(Icons.open_in_new_rounded),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }

  IconData _iconFor(Object? category) => switch (category) {
        'quran' => Icons.menu_book_rounded,
        'adhan' => Icons.mosque_rounded,
        'duas' => Icons.volunteer_activism_rounded,
        _ => Icons.music_note_rounded,
      };

  String _emptyMessage(String tab) {
    if (_search.isNotEmpty) return 'لا توجد نتائج مطابقة للبحث.';
    if (tab == 'المفضلة') return 'لا توجد تسجيلات مفضلة في ملف التصدير.';
    if (tab == 'قوائم التشغيل') return 'لا توجد قوائم تشغيل محفوظة في الملف.';
    if (tab == 'القائمة الحالية') return 'قائمة التشغيل المستوردة فارغة.';
    return 'لا توجد تسجيلات في هذا القسم.';
  }

  Widget _empty(String message) => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.library_music_outlined, size: 46),
              const SizedBox(height: 14),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(height: 1.6),
              ),
            ],
          ),
        ),
      );
}
