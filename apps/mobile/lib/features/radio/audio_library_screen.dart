import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../components/app_card.dart';
import '../../components/app_text.dart';
import '../../components/chip_row.dart';
import '../../components/state_view.dart';
import '../../core/audio_playback_service.dart';
import '../../core/providers.dart';
import '../../design/theme_provider.dart';
import '../../design/tokens/app_tokens.dart';

typedef AudioTrackLoader = Future<List<Map<String, dynamic>>> Function();

/// The audio screen (S6 + S7).
///
/// A teal header carries the helper copy, the section rows use the two-tone
/// waveform glyph, and the player at the bottom offers a progress bar, a
/// 0.75–1.25× speed control and a download that reports progress in MB
/// (G15, G16).
class AudioLibraryScreen extends ConsumerStatefulWidget {
  const AudioLibraryScreen({super.key, this.loadTracks, this.playback});

  final AudioTrackLoader? loadTracks;
  final AppAudioPlayback? playback;

  @override
  ConsumerState<AudioLibraryScreen> createState() => _AudioLibraryScreenState();
}

class _AudioLibraryScreenState extends ConsumerState<AudioLibraryScreen> {
  static const _categories = <({String id, String title})>[
    (id: 'all', title: 'الكل'),
    (id: 'quran', title: 'القرآن'),
    (id: 'adhan', title: 'الأذان'),
    (id: 'hussainiyat', title: 'الحسينيات'),
    (id: 'duas', title: 'الأدعية'),
    (id: 'ziyara', title: 'الزيارات'),
    (id: 'lectures', title: 'المجالس'),
    (id: 'radio', title: 'الإذاعات'),
  ];

  late Future<List<Map<String, dynamic>>> _tracks;
  late final AppAudioPlayback _playback;
  StreamSubscription<PlaybackState>? _playerSubscription;
  StreamSubscription<Duration>? _positionSubscription;

  String _selectedCategory = 'all';
  int? _playingId;
  bool _isPlaying = false;
  Duration _position = Duration.zero;
  Duration? _duration;
  double _speed = 1;
  int? _downloadingId;
  double _downloadProgress = 0;

  @override
  void initState() {
    super.initState();
    _tracks = _loadTracks();
    _playback = widget.playback ?? ref.read(appAudioPlaybackProvider);
    _playerSubscription = _playback.playbackStateStream.listen((state) {
      if (!mounted) return;
      setState(() {
        _isPlaying = state.playing;
        if (state.processingState == AudioProcessingState.completed) {
          _playingId = null;
          _isPlaying = false;
          _position = Duration.zero;
        }
        if (state.speed != 0 && state.speed != _speed) {
          _speed = state.speed;
        }
      });
    });
    _positionSubscription = _playback.positionStream.listen((position) {
      if (!mounted) return;
      setState(() {
        _position = position;
        _duration = _playback.duration;
      });
    });
  }

  @override
  void dispose() {
    _playerSubscription?.cancel();
    _positionSubscription?.cancel();
    super.dispose();
  }

  Future<List<Map<String, dynamic>>> _loadTracks() async {
    if (widget.loadTracks != null) return widget.loadTracks!();
    try {
      final response = await ref.read(apiProvider).get<Map<String, dynamic>>(
            '/api/v1/public/catalog/audio',
            queryParameters: {'limit': 100, 'offset': 0},
          );
      final raw = response.data?['items'];
      if (raw is! List) return const [];
      return raw.whereType<Map>().map((item) => Map<String, dynamic>.from(item)).toList();
    } on DioException {
      return const [];
    }
  }

  List<Map<String, dynamic>> _filter(List<Map<String, dynamic>> tracks) {
    if (_selectedCategory == 'all') return tracks;
    return tracks
        .where((track) => _normaliseCategory(track['category']) == _selectedCategory)
        .toList();
  }

  String _normaliseCategory(Object? value) {
    final category = (value ?? '').toString().toLowerCase().trim();
    if (['quran', 'quran_recitation', 'tilawa'].contains(category)) return 'quran';
    if (['adhan', 'azan'].contains(category)) return 'adhan';
    if (['hussainiyat', 'latmiyat', 'nohay', 'qasida', 'mourning'].contains(category)) {
      return 'hussainiyat';
    }
    if (['dua', 'duas', 'munajat'].contains(category)) return 'duas';
    if (['ziyara', 'ziyarat', 'visit'].contains(category)) return 'ziyara';
    if (['lecture', 'lectures', 'majlis', 'majalis'].contains(category)) return 'lectures';
    if (category == 'radio') return 'radio';
    return category;
  }

  Future<void> _play(Map<String, dynamic> track) async {
    final id = track['id'] as int?;
    final url = track['source_url'] as String?;
    if (id == null || url == null || Uri.tryParse(url)?.scheme != 'https') return;
    try {
      if (_playingId == id) {
        if (_playback.isPlaying) {
          await _playback.pause();
        } else {
          await _playback.play();
        }
        return;
      }
      final title = (track['title'] ?? 'تسجيل صوتي').toString();
      await _playback.playRemote(
        uri: Uri.parse(url),
        id: id.toString(),
        title: title,
        artist: (track['reciter'] ?? 'خزائن الهدى').toString(),
        album: 'المكتبة الصوتية',
      );
      if (!mounted) return;
      setState(() {
        _playingId = id;
        _position = Duration.zero;
        _duration = _playback.duration;
      });
    } catch (_) {
      _message('تعذر تشغيل التسجيل. تحقق من الاتصال ومصدر الصوت.');
    }
  }

  /// Downloads a licensed track and reports progress in megabytes (G16).
  Future<void> _download(Map<String, dynamic> track) async {
    final id = track['id'] as int?;
    final url = track['download_url'] as String?;
    if (id == null ||
        track['can_download'] != true ||
        url == null ||
        Uri.tryParse(url)?.scheme != 'https') {
      _message('هذا التسجيل غير مرخص للتنزيل.');
      return;
    }
    setState(() {
      _downloadingId = id;
      _downloadProgress = 0;
    });
    try {
      final directory = await getApplicationDocumentsDirectory();
      final audioDirectory = Directory('${directory.path}/licensed_audio');
      await audioDirectory.create(recursive: true);
      final extension = _extensionFor(track['mime_type']?.toString());
      final file = File('${audioDirectory.path}/track_$id$extension');
      await ref.read(apiProvider).download(
            url,
            file.path,
            onReceiveProgress: (received, total) {
              if (!mounted) return;
              setState(() {
                _downloadProgress = total > 0 ? received / total : 0;
              });
            },
            options: Options(receiveTimeout: const Duration(minutes: 10)),
          );
      await _markDownloaded(id, file.path);
      if (!mounted) return;
      _message('تم تنزيل التسجيل (${_megabytes(file)}) للاستماع دون اتصال.');
    } catch (_) {
      _message('تعذر تنزيل التسجيل حالياً.');
    } finally {
      if (mounted) {
        setState(() {
          _downloadingId = null;
          _downloadProgress = 0;
        });
      }
    }
  }

  String _extensionFor(String? mime) => switch (mime) {
        'audio/mp4' => '.m4a',
        'audio/aac' => '.aac',
        'audio/ogg' => '.ogg',
        'audio/wav' => '.wav',
        'audio/flac' => '.flac',
        _ => '.mp3',
      };

  String _megabytes(File file) {
    final bytes = file.existsSync() ? file.lengthSync() : 0;
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} م.ب';
  }

  Future<void> _markDownloaded(int id, String path) async {
    try {
      final prefs = ref.read(sharedPreferencesProvider);
      await prefs.setString('downloaded_audio_$id', path);
    } catch (_) {
      // The download already succeeded on disk; only the marker is missing.
    }
  }

  bool _isDownloaded(int id) {
    try {
      final prefs = ref.read(sharedPreferencesProvider);
      final path = prefs.getString('downloaded_audio_$id');
      return path != null && File(path).existsSync();
    } catch (_) {
      return false;
    }
  }

  void _message(String value) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(value)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(uiThemeProvider);
    return Container(
      color: theme.color('bgApp'),
      child: SafeArea(
        bottom: false,
        child: FutureBuilder<List<Map<String, dynamic>>>(
          future: _tracks,
          builder: (context, snapshot) {
            final allTracks = snapshot.data ?? const <Map<String, dynamic>>[];
            final visibleTracks = _filter(allTracks);
            return Column(
              children: [
                _TealHeader(
                  helper: 'تسجيلات موثّقة الحقوق، تعمل دون اتصال بعد التنزيل.',
                  onRefresh: () => setState(() => _tracks = _loadTracks()),
                ),
                SizedBox(
                  height: 46,
                  child: ChipRow(
                    chips: _categories
                        .map((item) => (id: item.id, label: item.title))
                        .toList(growable: false),
                    selectedId: _selectedCategory,
                    onSelected: (id) => setState(() => _selectedCategory = id),
                  ),
                ),
                const SizedBox(height: 4),
                Expanded(
                  child: Builder(builder: (context) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snapshot.hasError) {
                      return StateView(
                        icon: const Icon(Icons.wifi_off_rounded),
                        message: 'تعذر الاتصال بمكتبة الصوتيات. تحقق من الشبكة ثم أعد المحاولة.',
                        actionLabel: 'إعادة المحاولة',
                        onAction: () => setState(() => _tracks = _loadTracks()),
                      );
                    }
                    if (visibleTracks.isEmpty) {
                      final categoryTitle = _categories
                          .firstWhere((item) => item.id == _selectedCategory)
                          .title;
                      return StateView(
                        icon: const Icon(Icons.library_music_outlined),
                        message: _selectedCategory == 'all'
                            ? 'لا توجد تسجيلات منشورة حتى الآن. تظهر هنا الملفات التي وثّق المشرف حقوق بثها فقط.'
                            : 'لا توجد تسجيلات منشورة ومرخصة في قسم $categoryTitle حالياً.',
                        actionLabel: 'تحديث',
                        onAction: () => setState(() => _tracks = _loadTracks()),
                      );
                    }
                    return ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                      itemCount: visibleTracks.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final track = visibleTracks[index];
                        final id = track['id'] as int?;
                        final playing =
                            id != null && id == _playingId && _isPlaying;
                        final canDownload = track['can_download'] == true &&
                            track['download_url'] is String;
                        return _AudioRow(
                          title: (track['title'] ?? 'تسجيل صوتي').toString(),
                          subtitle: [
                            if ((track['reciter'] ?? '').toString().isNotEmpty)
                              track['reciter'].toString(),
                            _categoryLabel(
                                _normaliseCategory(track['category'])),
                            if (track['duration_seconds'] is int)
                              _durationLabel(track['duration_seconds'] as int),
                          ].join(' · '),
                          playing: playing,
                          downloading: id != null && _downloadingId == id,
                          downloadProgress: _downloadProgress,
                          downloaded: id != null && _isDownloaded(id),
                          canDownload: canDownload,
                          onPlay: () => _play(track),
                          onDownload: canDownload ? () => _download(track) : null,
                        );
                      },
                    );
                  }),
                ),
                if (_playingId != null)
                  _PlayerBar(
                    position: _position,
                    duration: _duration,
                    speed: _speed,
                    isPlaying: _isPlaying,
                    onPlayPause: () async {
                      if (_playback.isPlaying) {
                        await _playback.pause();
                      } else {
                        await _playback.play();
                      }
                    },
                    onSeek: (value) => _playback.seekTo(value),
                    onSpeed: (value) async {
                      await _playback.setPlaybackSpeed(value);
                      if (mounted) setState(() => _speed = value);
                    },
                    onClose: () async {
                      await _playback.stop();
                      if (mounted) {
                        setState(() {
                          _playingId = null;
                          _position = Duration.zero;
                        });
                      }
                    },
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  String _durationLabel(int seconds) =>
      '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';

  /// The Arabic label of a catalogue category.
  String _categoryLabel(String category) => switch (category) {
        'quran' => 'القرآن',
        'adhan' => 'الأذان',
        'hussainiyat' => 'الحسينيات',
        'duas' => 'الأدعية',
        'ziyara' => 'الزيارات',
        'lectures' => 'المجالس',
        'radio' => 'الإذاعات',
        _ => category,
      };
}

class _TealHeader extends ConsumerWidget {
  const _TealHeader({required this.helper, required this.onRefresh});

  final String helper;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(uiThemeProvider);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: theme.color('tealSurface'),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(20)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppText('الصوتيات', token: 'h1'),
                const SizedBox(height: 4),
                AppText(
                  helper,
                  token: 'bodyDim',
                  color: theme.color('textSecondary'),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onRefresh,
            tooltip: 'تحديث',
            icon: Icon(Icons.refresh_rounded, color: theme.color('gold')),
          ),
        ],
      ),
    );
  }
}

/// The two-tone waveform glyph used by the audio rows (S7).
class WaveformGlyph extends StatelessWidget {
  const WaveformGlyph({super.key, this.size = 34, this.active = false});

  final double size;
  final bool active;

  static const List<double> _bars = <double>[
    0.35, 0.62, 0.48, 0.85, 0.55, 1, 0.72, 0.42, 0.66, 0.9, 0.5, 0.3,
  ];

  @override
  Widget build(BuildContext context) {
    final primary = active ? KhazainColors.greenActive : KhazainColors.green;
    const accent = KhazainColors.gold;
    return SizedBox(
      width: size,
      height: size,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          for (var index = 0; index < _bars.length; index++)
            Container(
              width: size * 0.055,
              height: size * _bars[index] * 0.92,
              decoration: BoxDecoration(
                color: index.isEven ? primary : accent,
                borderRadius: BorderRadius.circular(size * 0.03),
              ),
            ),
        ],
      ),
    );
  }
}

class _AudioRow extends ConsumerWidget {
  const _AudioRow({
    required this.title,
    required this.subtitle,
    required this.playing,
    required this.downloading,
    required this.downloadProgress,
    required this.downloaded,
    required this.canDownload,
    required this.onPlay,
    this.onDownload,
  });

  final String title;
  final String subtitle;
  final bool playing;
  final bool downloading;
  final double downloadProgress;
  final bool downloaded;
  final bool canDownload;
  final VoidCallback onPlay;
  final VoidCallback? onDownload;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(uiThemeProvider);
    return KzSurface(
      level: 1,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          WaveformGlyph(size: 32, active: playing),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppText(
                  title,
                  token: 'body',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                AppText(
                  subtitle.isEmpty ? 'تسجيل صوتي' : subtitle,
                  token: 'bodyDim',
                  color: theme.color('textMuted'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (downloading) ...[
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: downloadProgress == 0 ? null : downloadProgress,
                      minHeight: 3,
                      color: theme.color('gold'),
                      backgroundColor: theme.color('divider'),
                    ),
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            tooltip: playing ? 'إيقاف مؤقت' : 'تشغيل',
            onPressed: onPlay,
            icon: Icon(
              playing ? Icons.pause_circle_filled_rounded : Icons.play_circle_fill_rounded,
              size: 32,
              color: theme.color('gold'),
            ),
          ),
          if (canDownload)
            IconButton(
              tooltip: downloaded ? 'مُنزّل' : 'تنزيل',
              onPressed: downloading ? null : onDownload,
              icon: Icon(
                downloaded ? Icons.check_circle_rounded : Icons.download_rounded,
                size: 22,
                color: downloaded ? theme.color('success') : theme.color('textMuted'),
              ),
            ),
        ],
      ),
    );
  }
}

class _PlayerBar extends ConsumerWidget {
  const _PlayerBar({
    required this.position,
    required this.duration,
    required this.speed,
    required this.isPlaying,
    required this.onPlayPause,
    required this.onSeek,
    required this.onSpeed,
    required this.onClose,
  });

  final Duration position;
  final Duration? duration;
  final double speed;
  final bool isPlaying;
  final VoidCallback onPlayPause;
  final ValueChanged<Duration> onSeek;
  final ValueChanged<double> onSpeed;
  final VoidCallback onClose;

  static const List<double> _speeds = <double>[0.75, 1.0, 1.25];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(uiThemeProvider);
    final total = duration ?? Duration.zero;
    final max = total.inMilliseconds.toDouble();
    final value = max <= 0
        ? 0.0
        : position.inMilliseconds.toDouble().clamp(0.0, max);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      decoration: BoxDecoration(
        color: theme.color('surface1'),
        border: Border(top: BorderSide(color: theme.color('hairline'))),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Slider(
                    value: value,
                    max: max <= 0 ? 1 : max,
                    onChanged: max <= 0
                        ? null
                        : (next) => onSeek(
                              Duration(milliseconds: next.round()),
                            ),
                  ),
                ),
                AppText(
                  '${_format(position)} / ${_format(total)}',
                  token: 'bodyDim',
                  color: theme.color('textMuted'),
                ),
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      for (final option in _speeds)
                        Padding(
                          padding: const EdgeInsets.only(left: 6),
                          child: ChoiceChip(
                            label: Text('${option.toStringAsFixed(2)}×'),
                            selected: (speed - option).abs() < 0.01,
                            visualDensity: VisualDensity.compact,
                            onSelected: (_) => onSpeed(option),
                          ),
                        ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: onPlayPause,
                  tooltip: isPlaying ? 'إيقاف مؤقت' : 'تشغيل',
                  icon: Icon(
                    isPlaying
                        ? Icons.pause_circle_filled_rounded
                        : Icons.play_circle_fill_rounded,
                    size: 36,
                    color: theme.color('gold'),
                  ),
                ),
                IconButton(
                  onPressed: onClose,
                  tooltip: 'إغلاق',
                  icon: Icon(Icons.close_rounded, color: theme.color('textMuted')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String _format(Duration value) {
    final minutes = value.inMinutes;
    final seconds = value.inSeconds.remainder(60);
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}
