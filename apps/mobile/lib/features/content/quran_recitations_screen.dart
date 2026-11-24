import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import '../../core/audio_playback_service.dart';
import '../../core/mp3quran_v4_repository.dart';
import '../../core/quran_text_repository.dart';

class QuranRecitationsScreen extends ConsumerStatefulWidget {
  const QuranRecitationsScreen({super.key});

  @override
  ConsumerState<QuranRecitationsScreen> createState() =>
      _QuranRecitationsScreenState();
}

class _QuranRecitationsScreenState
    extends ConsumerState<QuranRecitationsScreen> {
  final _searchController = TextEditingController();
  late final AppAudioPlayback _playback;
  StreamSubscription<PlaybackState>? _playbackSubscription;

  List<Mp3QuranReciter> _reciters = const [];
  List<Mp3QuranRecitation> _recitations = const [];
  Mp3QuranReciter? _selectedReciter;
  Mp3QuranRecitation? _selectedRecitation;
  String? _nextRecitersUrl;
  String _query = '';
  String? _error;
  int? _loadingSurah;
  int? _playingSurah;
  bool _loadingReciters = true;
  bool _loadingMoreReciters = false;
  bool _loadingRecitations = false;
  bool _isPlaying = false;

  @override
  void initState() {
    super.initState();
    _playback = ref.read(appAudioPlaybackProvider);
    _playbackSubscription = _playback.playbackStateStream.listen((state) {
      if (!mounted) return;
      setState(() {
        _isPlaying = state.playing;
        if (state.processingState == AudioProcessingState.completed) {
          _playingSurah = null;
          _isPlaying = false;
        }
      });
    });
    _loadReciters();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _playbackSubscription?.cancel();
    super.dispose();
  }

  Mp3QuranV4Repository get _repository =>
      ref.read(mp3QuranV4RepositoryProvider);

  Future<void> _loadReciters({String? query, String? nextUrl}) async {
    final isMore = nextUrl != null;
    setState(() {
      _error = null;
      if (isMore) {
        _loadingMoreReciters = true;
      } else {
        _loadingReciters = true;
        _query = query ?? _query;
        _reciters = const [];
        _nextRecitersUrl = null;
      }
    });
    try {
      final page = await _repository.listReciters(
        query: isMore ? null : _query,
        nextUrl: nextUrl,
      );
      if (!mounted) return;
      setState(() {
        _reciters = [..._reciters, ...page.items];
        _nextRecitersUrl = page.nextUrl;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = _errorText(error));
    } finally {
      if (mounted) {
        setState(() {
          _loadingReciters = false;
          _loadingMoreReciters = false;
        });
      }
    }
  }

  Future<void> _selectReciter(Mp3QuranReciter reciter) async {
    setState(() {
      _selectedReciter = reciter;
      _selectedRecitation = null;
      _recitations = const [];
      _loadingRecitations = true;
      _error = null;
    });
    try {
      final items = await _repository.listAllRecitations(
        reciterCode: reciter.code,
      );
      if (!mounted) return;
      setState(() => _recitations = items);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = _errorText(error));
    } finally {
      if (mounted) setState(() => _loadingRecitations = false);
    }
  }

  Future<void> _selectRecitation(Mp3QuranRecitation recitation) async {
    setState(() {
      _loadingRecitations = true;
      _error = null;
    });
    try {
      // Load the code-addressed resource to obtain audio.base and the original
      // file pattern used when preparing a multi-surah list.
      final details = await _repository.getRecitation(recitation.code);
      if (!mounted) return;
      setState(() => _selectedRecitation = details);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _selectedRecitation = recitation;
        _error = _errorText(error);
      });
    } finally {
      if (mounted) setState(() => _loadingRecitations = false);
    }
  }

  Future<void> _playSurah({
    required int surahNumber,
    required String surahName,
  }) async {
    final recitation = _selectedRecitation;
    final reciter = _selectedReciter;
    if (recitation == null || reciter == null) return;

    if (_playingSurah == surahNumber) {
      if (_isPlaying) {
        await _playback.pause();
      } else {
        await _playback.play();
      }
      return;
    }

    setState(() {
      _loadingSurah = surahNumber;
      _error = null;
    });
    try {
      final audio = await _repository.getSurahAudio(
        recitationCode: recitation.code,
        surahNumber: surahNumber,
      );
      await _playback.setLoopMode(LoopMode.off);
      await _playback.playRemote(
        uri: audio.originalUrl,
        id: 'mp3quran:${recitation.code}:$surahNumber',
        title: 'سورة $surahName',
        artist: reciter.name,
        album: 'تلاوات MP3Quran',
      );
      if (!mounted) return;
      setState(() => _playingSurah = surahNumber);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = _errorText(error));
    } finally {
      if (mounted) setState(() => _loadingSurah = null);
    }
  }

  Future<void> _openWordTimings(int surahNumber) async {
    final recitation = _selectedRecitation;
    if (recitation == null) return;
    final future = _repository.getWordTimings(
      recitationCode: recitation.code,
      surahNumber: surahNumber,
    );
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => _WordTimingsSheet(future: future),
    );
  }

  Future<void> _openAyahTimings(int surahNumber) async {
    final recitation = _selectedRecitation;
    if (recitation == null) return;
    final future = _repository.getAyahTimings(
      recitationCode: recitation.code,
      surahNumber: surahNumber,
    );
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => _AyahTimingsSheet(future: future),
    );
  }

  void _backToReciters() {
    setState(() {
      _selectedReciter = null;
      _selectedRecitation = null;
      _recitations = const [];
      _error = null;
    });
  }

  void _backToRecitations() {
    setState(() {
      _selectedRecitation = null;
      _error = null;
    });
  }

  String _errorText(Object error) {
    if (error is Mp3QuranApiException) return error.message;
    return 'تعذر الاتصال بخدمة التلاوات. تحقق من الإنترنت ثم أعد المحاولة.';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final quran = ref.watch(quranTextLibraryProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('قراء القرآن والتلاوات'),
        leading: IconButton(
          tooltip: _selectedReciter == null ? 'رجوع' : 'العودة',
          onPressed: _selectedRecitation != null
              ? _backToRecitations
              : _selectedReciter != null
                  ? _backToReciters
                  : () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        actions: [
          IconButton(
            tooltip: 'تحديث الفهرس',
            onPressed: _selectedReciter == null && !_loadingReciters
                ? () => _loadReciters(query: _query)
                : null,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_selectedReciter == null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 2),
              child: Align(
                alignment: Alignment.centerRight,
                child: Text(
                  'MP3Quran v4 · بيئة Staging · تشغيل متصل من المصدر فقط',
                  textDirection: TextDirection.rtl,
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ),
            ),
          if (_selectedReciter == null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: TextField(
                controller: _searchController,
                textDirection: TextDirection.rtl,
                textInputAction: TextInputAction.search,
                onSubmitted: (value) => _loadReciters(query: value.trim()),
                decoration: InputDecoration(
                  hintText: 'ابحث باسم القارئ بالعربية أو اللاتينية',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: IconButton(
                    tooltip: 'بحث',
                    onPressed: () =>
                        _loadReciters(query: _searchController.text.trim()),
                    icon: const Icon(Icons.arrow_forward_rounded),
                  ),
                ),
              ),
            ),
          if (_error != null)
            Material(
              color: theme.colorScheme.errorContainer.withOpacity(.55),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(
                  children: [
                    Icon(Icons.info_outline_rounded,
                        color: theme.colorScheme.onErrorContainer),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _error!,
                        textDirection: TextDirection.rtl,
                        style: TextStyle(color: theme.colorScheme.onErrorContainer),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          Expanded(
            child: _selectedReciter == null
                ? _buildReciters(theme)
                : _selectedRecitation == null
                    ? _buildRecitations(theme)
                    : quran.when(
                        loading: () => const Center(child: CircularProgressIndicator()),
                        error: (_, __) => _buildSurahs(theme, null),
                        data: (library) => _buildSurahs(theme, library),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildReciters(ThemeData theme) {
    if (_loadingReciters && _reciters.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_reciters.isEmpty) {
      return _EmptyState(
        message: _error == null
            ? 'لم يعثر الفهرس على قرّاء مطابقين.'
            : 'تعذر تحميل فهرس القرّاء.',
        onRetry: () => _loadReciters(query: _query),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 24),
      itemCount: _reciters.length + (_nextRecitersUrl == null ? 0 : 1),
      separatorBuilder: (_, __) => const SizedBox(height: 7),
      itemBuilder: (context, index) {
        if (index == _reciters.length) {
          return OutlinedButton.icon(
            onPressed: _loadingMoreReciters
                ? null
                : () => _loadReciters(nextUrl: _nextRecitersUrl),
            icon: _loadingMoreReciters
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.expand_more_rounded),
            label: const Text('عرض المزيد من القرّاء'),
          );
        }
        final reciter = _reciters[index];
        return Card(
          child: ListTile(
            onTap: () => _selectReciter(reciter),
            leading: const CircleAvatar(child: Icon(Icons.person_rounded)),
            title: Text(reciter.name,
                textDirection: TextDirection.rtl,
                style: const TextStyle(fontWeight: FontWeight.w800)),
            subtitle: Text(
              [
                if (reciter.nameLatin?.isNotEmpty == true) reciter.nameLatin!,
                if (reciter.recitationCount != null)
                  '${reciter.recitationCount} تلاوات',
              ].join(' · '),
              textDirection: TextDirection.ltr,
            ),
            trailing: const Icon(Icons.chevron_left_rounded),
          ),
        );
      },
    );
  }

  Widget _buildRecitations(ThemeData theme) {
    if (_loadingRecitations && _recitations.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    return Column(
      children: [
        _SelectedHeader(
          title: _selectedReciter?.name ?? '',
          subtitle: 'اختر الرواية أو نمط التلاوة',
        ),
        Expanded(
          child: _recitations.isEmpty
              ? _EmptyState(
                  message: 'لا توجد تلاوات منشورة لهذا القارئ في الفهرس.',
                  onRetry: _selectedReciter == null
                      ? null
                      : () => _selectReciter(_selectedReciter!),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(14, 6, 14, 24),
                  itemCount: _recitations.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 7),
                  itemBuilder: (context, index) {
                    final item = _recitations[index];
                    return Card(
                      child: ListTile(
                        onTap: () => _selectRecitation(item),
                        leading: const CircleAvatar(
                            child: Icon(Icons.graphic_eq_rounded)),
                        title: Text(_styleName(item.style),
                            style: const TextStyle(fontWeight: FontWeight.w800)),
                        subtitle: Text(
                          [
                            if (item.riwayahCodes.isNotEmpty)
                              item.riwayahCodes.map(_riwayahName).join('، '),
                            '${item.coverageSurahs.length} سورة متاحة',
                            if (item.hasAyahTimings) 'توقيت الآيات متوفر',
                          ].join(' · '),
                          textDirection: TextDirection.rtl,
                        ),
                        trailing: const Icon(Icons.chevron_left_rounded),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildSurahs(ThemeData theme, QuranTextLibrary? library) {
    final recitation = _selectedRecitation!;
    final numbers = recitation.coverageSurahs.toList()..sort();
    return Column(
      children: [
        _SelectedHeader(
          title: _selectedReciter?.name ?? '',
          subtitle:
              '${_styleName(recitation.style)} · ${recitation.riwayahCodes.map(_riwayahName).join('، ')}',
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'السور المتاحة: ${numbers.length}',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (recitation.hasAyahTimings)
                const Chip(
                  avatar: Icon(Icons.sync_alt_rounded, size: 16),
                  label: Text('توقيت الآيات'),
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
        ),
        Expanded(
          child: numbers.isEmpty
              ? const _EmptyState(
                  message: 'لا توجد قائمة سور منشورة لهذه التلاوة.',
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 24),
                  itemCount: numbers.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 6),
                  itemBuilder: (context, index) {
                    final number = numbers[index];
                    final surah = library?.surahByNumber(number);
                    final name = surah?.nameAr ?? 'السورة $number';
                    final isCurrent = _playingSurah == number;
                    final isLoading = _loadingSurah == number;
                    return Card(
                      child: ListTile(
                        leading: CircleAvatar(
                          child: Text(number.toString()),
                        ),
                        title: Text(name,
                            style: const TextStyle(fontWeight: FontWeight.w800)),
                        subtitle: Text(
                          surah == null ? 'رقم السورة $number' : '${surah.ayahCount} آية',
                        ),
                        trailing: SizedBox(
                          width: recitation.hasAyahTimings ? 132 : 94,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              if (recitation.hasAyahTimings)
                                IconButton(
                                  tooltip: 'توقيت الآيات',
                                  visualDensity: VisualDensity.compact,
                                  onPressed: () => _openAyahTimings(number),
                                  icon: const Icon(Icons.schedule_rounded),
                                ),
                              IconButton(
                                tooltip: 'توقيت الكلمات',
                                visualDensity: VisualDensity.compact,
                                onPressed: () => _openWordTimings(number),
                                icon: const Icon(Icons.format_list_numbered_rounded),
                              ),
                              IconButton(
                                tooltip: isCurrent && _isPlaying
                                    ? 'إيقاف مؤقت'
                                    : 'تشغيل السورة',
                                visualDensity: VisualDensity.compact,
                                onPressed: isLoading
                                    ? null
                                    : () => _playSurah(
                                          surahNumber: number,
                                          surahName: name,
                                        ),
                                icon: isLoading
                                    ? const SizedBox.square(
                                        dimension: 18,
                                        child: CircularProgressIndicator(strokeWidth: 2),
                                      )
                                    : Icon(isCurrent && _isPlaying
                                        ? Icons.pause_rounded
                                        : Icons.play_arrow_rounded),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  static String _styleName(String? style) => switch (style) {
        'murattal' => 'مرتل',
        'mujawwad' => 'مجود',
        'muallim' => 'معلّم',
        'featured' => 'مختارات',
        'archival' => 'أرشيفية',
        _ => style ?? 'تلاوة قرآنية',
      };

  static String _riwayahName(String code) => switch (code) {
        'hafs_an_asim' => 'حفص عن عاصم',
        'warsh_an_nafi' => 'ورش عن نافع',
        'qalun_an_nafi' => 'قالون عن نافع',
        'shuba_an_asim' => 'شعبة عن عاصم',
        _ => code.replaceAll('_', ' '),
      };
}

class _SelectedHeader extends StatelessWidget {
  const _SelectedHeader({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 4),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: theme.colorScheme.primary.withOpacity(.08),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                textDirection: TextDirection.rtl,
                style: const TextStyle(fontWeight: FontWeight.w900)),
            const SizedBox(height: 4),
            Text(subtitle,
                textDirection: TextDirection.rtl,
                style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.library_music_outlined, size: 42),
              const SizedBox(height: 12),
              Text(message, textAlign: TextAlign.center),
              if (onRetry != null) ...[
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('إعادة المحاولة'),
                ),
              ],
            ],
          ),
        ),
      );
}

class _AyahTimingsSheet extends StatelessWidget {
  const _AyahTimingsSheet({required this.future});

  final Future<Mp3QuranAyahTimings> future;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * .68,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text('توقيتات الآيات',
                style: theme.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w900)),
          ),
          const Divider(height: 1),
          Expanded(
            child: FutureBuilder<Mp3QuranAyahTimings>(
              future: future,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError || !snapshot.hasData) {
                  final error = snapshot.error;
                  return _EmptyState(
                    message: error is Mp3QuranApiException
                        ? error.message
                        : 'تعذر تحميل توقيتات الآيات لهذه السورة.',
                  );
                }
                final entries = snapshot.data!.entries;
                if (entries.isEmpty) {
                  return const _EmptyState(
                      message: 'لا تتوفر توقيتات آيات لهذه السورة.');
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(14, 8, 14, 24),
                  itemCount: entries.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final entry = entries[index];
                    final label = entry.ayah == 0
                        ? 'البسملة'
                        : entry.ayah == -1
                            ? 'الاستعاذة'
                            : 'الآية ${entry.ayah}';
                    return ListTile(
                      title: Text(label,
                          textDirection: TextDirection.rtl,
                          style: const TextStyle(fontWeight: FontWeight.w800)),
                      subtitle: Text('${entry.startMs}–${entry.endMs} ms'),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _WordTimingsSheet extends StatelessWidget {
  const _WordTimingsSheet({required this.future});

  final Future<Mp3QuranWordTimings> future;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * .78,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 8),
            child: Column(
              children: [
                Text('توقيتات كلمات السورة',
                    style: theme.textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w900)),
                const SizedBox(height: 6),
                Text(
                  'هذه التوقيتات آلية وقد تتضمن فروقاً تصل إلى نحو 50 مللي ثانية، وقد تخطئ في محاذاة بعض الكلمات.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: FutureBuilder<Mp3QuranWordTimings>(
              future: future,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError || !snapshot.hasData) {
                  final error = snapshot.error;
                  return _EmptyState(
                    message: error is Mp3QuranApiException
                        ? error.message
                        : 'تعذر تحميل توقيتات الكلمات لهذه السورة.',
                  );
                }
                final data = snapshot.data!;
                if (data.words.isEmpty) {
                  return const _EmptyState(
                      message: 'لا تتوفر توقيتات كلمات لهذه السورة.');
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(14, 8, 14, 24),
                  itemCount: data.words.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final word = data.words[index];
                    final text = data.textFor(word) ?? 'الكلمة ${word.wordPosition}';
                    return ListTile(
                      dense: true,
                      leading: CircleAvatar(
                        radius: 15,
                        child: Text('${index + 1}', style: const TextStyle(fontSize: 11)),
                      ),
                      title: Text(text,
                          textDirection: TextDirection.rtl,
                          style: const TextStyle(fontWeight: FontWeight.w800)),
                      subtitle: Text(
                        'الآية ${word.ayah} · ${word.startMs}–${word.endMs} ms · التكرار ${word.occurrence}',
                        textDirection: TextDirection.rtl,
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
