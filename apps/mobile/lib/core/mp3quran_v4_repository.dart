import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

const mp3QuranV4ApiOrigin = 'https://api-staging.mp3quran.net';
const mp3QuranV4BasePath = '/v4';

final mp3QuranV4RepositoryProvider = Provider<Mp3QuranV4Repository>((ref) {
  final dio = Dio(BaseOptions(
    baseUrl: mp3QuranV4ApiOrigin,
    connectTimeout: const Duration(seconds: 12),
    receiveTimeout: const Duration(seconds: 25),
    sendTimeout: const Duration(seconds: 12),
    headers: const {
      'Accept': 'application/json',
      'Accept-Language': 'ar',
    },
  ));
  ref.onDispose(dio.close);
  return Mp3QuranV4Repository(dio: dio);
});

typedef Mp3QuranCacheDirectory = Future<Directory> Function();

/// Read-only MP3Quran API v4 client.
///
/// The cache stores response bodies and ETags in the app support directory.
/// Numeric API IDs are deliberately never persisted; reciter and recitation
/// codes are the only identifiers retained by this client.
class Mp3QuranV4Repository {
  Mp3QuranV4Repository({
    Dio? dio,
    Mp3QuranCacheDirectory? cacheDirectory,
    Future<void> Function(Duration)? delay,
  })  : _dio = dio ?? _createDio(),
        _cacheDirectory = cacheDirectory ?? getApplicationSupportDirectory,
        _delay = delay ?? Future<void>.delayed;

  final Dio _dio;
  final Mp3QuranCacheDirectory _cacheDirectory;
  final Future<void> Function(Duration) _delay;

  static Dio _createDio() => Dio(BaseOptions(
        baseUrl: mp3QuranV4ApiOrigin,
        connectTimeout: const Duration(seconds: 12),
        receiveTimeout: const Duration(seconds: 25),
        headers: const {'Accept': 'application/json', 'Accept-Language': 'ar'},
      ));

  Future<Mp3QuranApiPage<Mp3QuranReciter>> listReciters({
    String? query,
    String? nextUrl,
    int limit = 50,
  }) async {
    final uri = nextUrl == null
        ? _routeUri('/reciters', {
            'locale': 'ar',
            'limit': limit.toString(),
            if (query != null && query.trim().isNotEmpty) 'q': query.trim(),
          })
        : _nextPageUri(nextUrl);
    final body = await _getJson(uri);
    final rows = _readList(body['data'], 'reciters.data');
    return Mp3QuranApiPage<Mp3QuranReciter>(
      items: rows
          .map((row) => Mp3QuranReciter.fromJson(
              Map<String, dynamic>.from(row as Map)))
          .toList(growable: false),
      nextUrl: _readNextUrl(body),
      count: _readCount(body),
    );
  }

  Future<Mp3QuranApiPage<Mp3QuranRecitation>> listRecitations({
    required String reciterCode,
    String? nextUrl,
    int limit = 50,
  }) async {
    final uri = nextUrl == null
        ? _routeUri('/recitations', {
            'locale': 'ar',
            'limit': limit.toString(),
            'reciter': reciterCode,
          })
        : _nextPageUri(nextUrl);
    final body = await _getJson(uri);
    final rows = _readList(body['data'], 'recitations.data');
    return Mp3QuranApiPage<Mp3QuranRecitation>(
      items: rows
          .map((row) => Mp3QuranRecitation.fromJson(
              Map<String, dynamic>.from(row as Map)))
          .toList(growable: false),
      nextUrl: _readNextUrl(body),
      count: _readCount(body),
    );
  }

  Future<List<Mp3QuranRecitation>> listAllRecitations({
    required String reciterCode,
  }) async {
    final items = <Mp3QuranRecitation>[];
    String? next;
    do {
      final page = await listRecitations(
        reciterCode: reciterCode,
        nextUrl: next,
      );
      items.addAll(page.items);
      next = page.nextUrl;
    } while (next != null && next.isNotEmpty);
    return List<Mp3QuranRecitation>.unmodifiable(items);
  }

  Future<Mp3QuranRecitation> getRecitation(String code) async {
    _validateRecitationCode(code);
    final body = await _getJson(_routeUri('/recitations/${_codePath(code)}'));
    return Mp3QuranRecitation.fromJson(_readObject(body['data'], 'recitation.data'));
  }

  /// Gets the official ready-to-use audio URL for one surah.
  ///
  /// The API's files.original.url is used rather than inventing a path from an
  /// internal numeric ID or assuming an audio filename.
  Future<Mp3QuranSurahAudio> getSurahAudio({
    required String recitationCode,
    required int surahNumber,
  }) async {
    _validateRecitationCode(recitationCode);
    _validateSurahNumber(surahNumber);
    final body = await _getJson(_routeUri(
      '/recitations/${_codePath(recitationCode)}/surahs/$surahNumber',
    ));
    final data = _readObject(body['data'], 'surah_audio.data');
    final files = _readObject(data['files'], 'surah_audio.files');
    final original = _readObject(files['original'], 'surah_audio.files.original');
    final url = _safeAudioUri(original['url']);
    return Mp3QuranSurahAudio(
      surahNumber: _readInt(data['surah'], 'surah_audio.surah', fallback: surahNumber),
      originalUrl: url,
      bytes: _optionalInt(original['bytes']),
      sha256: original['sha256']?.toString(),
      bitrateKbps: _optionalInt(original['bitrate_kbps']),
      timingLevels: _readStringList(data['timings']),
    );
  }

  /// Builds multiple surah URLs from the recitation's documented audio.base
  /// and audio.files.original pattern. One-surah playback should use
  /// [getSurahAudio] so the API supplies the complete URL directly.
  Uri buildSurahAudioUriFromRecitation({
    required Mp3QuranRecitation recitation,
    required int surahNumber,
  }) {
    _validateSurahNumber(surahNumber);
    final base = recitation.audioBase;
    final pattern = recitation.originalPattern;
    if (base == null || pattern == null || base.isEmpty || pattern.isEmpty) {
      throw const Mp3QuranApiException(
        code: 'audio_pattern_missing',
        message: 'لم يوفّر المصدر قالب رابط صوتي لهذه التلاوة.',
      );
    }
    final expanded = pattern
        .replaceAll('{surah:03d}', surahNumber.toString().padLeft(3, '0'))
        .replaceAll('{surah}', surahNumber.toString());
    if (expanded.contains('{') || expanded.contains('}')) {
      throw const Mp3QuranApiException(
        code: 'audio_pattern_unsupported',
        message: 'قالب رابط الصوت الوارد من المصدر غير مدعوم.',
      );
    }
    final baseUri = Uri.tryParse(base);
    if (baseUri == null || baseUri.scheme != 'https' ||
        !_isMp3QuranHost(baseUri.host)) {
      throw const Mp3QuranApiException(
        code: 'invalid_audio_base',
        message: 'عنوان الصوت الوارد من المصدر غير آمن.',
      );
    }
    return _safeAudioUri(baseUri.resolve(expanded).toString());
  }

  Future<Mp3QuranAyahTimings> getAyahTimings({
    required String recitationCode,
    required int surahNumber,
  }) async {
    _validateRecitationCode(recitationCode);
    _validateSurahNumber(surahNumber);
    final uri = _routeUri(
      '/recitations/${_codePath(recitationCode)}/surahs/$surahNumber/ayah-timings',
      const {},
    );
    final body = await _getJson(uri);
    final data = _readObject(body['data'], 'ayah_timings.data');
    return Mp3QuranAyahTimings.fromApiData(
      data,
      fallbackSurah: surahNumber,
    );
  }

  Future<Mp3QuranWordTimings> getWordTimings({
    required String recitationCode,
    required int surahNumber,
    int? ayahNumber,
  }) async {
    _validateRecitationCode(recitationCode);
    _validateSurahNumber(surahNumber);
    if (ayahNumber != null && ayahNumber < 1) {
      throw ArgumentError.value(ayahNumber, 'ayahNumber');
    }
    final uri = _routeUri(
      '/recitations/${_codePath(recitationCode)}/surahs/$surahNumber/word-timings',
      {
        'include': 'text',
        if (ayahNumber != null) 'ayah': ayahNumber.toString(),
      },
    );
    final body = await _getJson(uri);
    final data = _readObject(body['data'], 'word_timings.data');
    return Mp3QuranWordTimings.fromApiData(
      data,
      fallbackSurah: surahNumber,
    );
  }

  Future<Map<String, dynamic>> _getJson(Uri uri) async {
    final cache = await _readCache(uri);
    var sentEtag = cache?.etag;
    for (var attempt = 0; attempt < 3; attempt++) {
      final headers = <String, dynamic>{
        if (sentEtag != null && sentEtag.isNotEmpty) 'If-None-Match': sentEtag,
      };
      final response = await _dio.getUri<dynamic>(
        uri,
        options: Options(
          headers: headers,
          responseType: ResponseType.json,
          validateStatus: (status) => status != null && status >= 200 && status < 600,
        ),
      );
      final status = response.statusCode ?? 0;
      if (status == 304) {
        if (cache == null) {
          sentEtag = null;
          continue;
        }
        return cache.body;
      }
      final body = _sanitizeNumericResourceIds(_asObject(response.data));
      if (status >= 200 && status < 300) {
        await _writeCache(uri, response.headers.value('etag'), body);
        return body;
      }

      final error = _readApiError(body, status);
      if (status == 429 || status == 503) {
        final retryAfter = _retryAfter(response.headers.value('retry-after'));
        if (attempt < 2 && retryAfter != null) {
          await _delay(retryAfter);
          continue;
        }
      }
      throw error;
    }
    throw const Mp3QuranApiException(
      code: 'cache_revalidation_failed',
      message: 'تعذر استعادة استجابة محفوظة من خدمة التلاوات.',
    );
  }

  Future<_Mp3QuranCachedResponse?> _readCache(Uri uri) async {
    try {
      final file = await _cacheFile(uri);
      if (!await file.exists()) return null;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map || decoded['body'] is! Map) return null;
      return _Mp3QuranCachedResponse(
        etag: decoded['etag']?.toString(),
        body: Map<String, dynamic>.from(decoded['body'] as Map),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeCache(
    Uri uri,
    String? etag,
    Map<String, dynamic> body,
  ) async {
    try {
      final file = await _cacheFile(uri);
      await file.parent.create(recursive: true);
      final temp = File('${file.path}.tmp');
      await temp.writeAsString(
        jsonEncode({'etag': etag, 'body': body}),
        flush: true,
      );
      if (await file.exists()) await file.delete();
      await temp.rename(file.path);
    } catch (_) {
      // A cache failure must not block online Quran playback.
    }
  }

  Future<File> _cacheFile(Uri uri) async {
    final directory = await _cacheDirectory();
    final digest = sha256.convert(utf8.encode(uri.toString())).toString();
    return File('${directory.path}${Platform.pathSeparator}mp3quran_v4_$digest.json');
  }

  Uri _routeUri(String route, [Map<String, String> query = const {}]) {
    final path = '$mp3QuranV4BasePath$route';
    return Uri.parse(mp3QuranV4ApiOrigin).replace(
      path: path,
      queryParameters: query.isEmpty ? null : query,
    );
  }

  Uri _nextPageUri(String nextUrl) {
    final parsed = Uri.parse(nextUrl);
    final resolved = parsed.hasScheme
        ? parsed
        : Uri.parse(mp3QuranV4ApiOrigin).resolveUri(parsed);
    if (resolved.scheme != 'https' ||
        resolved.host != Uri.parse(mp3QuranV4ApiOrigin).host) {
      throw const Mp3QuranApiException(
        code: 'invalid_next_link',
        message: 'رابط الصفحة التالية خارج نطاق خدمة MP3Quran.',
      );
    }
    // Do not add, remove, or re-encode query parameters from links.next.
    return resolved;
  }

  static String _codePath(String code) =>
      code.split('/').map(Uri.encodeComponent).join('/');

  static void _validateRecitationCode(String code) {
    if (code.trim().isEmpty ||
        !RegExp(r'^[A-Za-z0-9_-]+/[A-Za-z0-9_-]+$').hasMatch(code)) {
      throw ArgumentError.value(code, 'code', 'Expected a recitation code.');
    }
  }

  static void _validateSurahNumber(int value) {
    if (value < 1 || value > 114) {
      throw RangeError.range(value, 1, 114, 'surahNumber');
    }
  }

  static Uri _safeAudioUri(Object? value) {
    final uri = Uri.tryParse(value?.toString() ?? '');
    if (uri == null || uri.scheme != 'https' || !_isMp3QuranHost(uri.host)) {
      throw const Mp3QuranApiException(
        code: 'invalid_audio_url',
        message: 'عنوان الملف الصوتي لا يطابق نطاق MP3Quran الآمن.',
      );
    }
    return uri;
  }

  static bool _isMp3QuranHost(String host) =>
      host == 'mp3quran.net' || host.endsWith('.mp3quran.net');

  static Duration? _retryAfter(String? header) {
    final seconds = int.tryParse(header?.trim() ?? '');
    if (seconds == null || seconds < 0) return null;
    return Duration(seconds: seconds);
  }

  static Map<String, dynamic> _asObject(Object? value) {
    if (value is Map) return Map<String, dynamic>.from(value);
    if (value is String) {
      final decoded = jsonDecode(value);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    }
    return <String, dynamic>{};
  }

  /// Remove unstable numeric identifiers from any code-addressed reciter or
  /// recitation resource before the response can enter the local ETag cache.
  static Map<String, dynamic> _sanitizeNumericResourceIds(
    Map<String, dynamic> body,
  ) {
    dynamic sanitize(dynamic value) {
      if (value is List) {
        return value.map(sanitize).toList(growable: false);
      }
      if (value is Map) {
        final result = <String, dynamic>{};
        for (final entry in value.entries) {
          final key = entry.key.toString();
          if (key == 'id' && value['code'] is String && entry.value is num) {
            continue;
          }
          result[key] = sanitize(entry.value);
        }
        return result;
      }
      return value;
    }

    return Map<String, dynamic>.from(sanitize(body) as Map);
  }

  static Map<String, dynamic> _readObject(Object? value, String field) {
    if (value is Map) return Map<String, dynamic>.from(value);
    throw FormatException('Expected object at $field.');
  }

  static List<dynamic> _readList(Object? value, String field) {
    if (value is List) return value;
    throw FormatException('Expected array at $field.');
  }

  static String? _readNextUrl(Map<String, dynamic> body) {
    final links = body['links'];
    if (links is! Map) return null;
    final next = links['next'];
    return next is String && next.isNotEmpty ? next : null;
  }

  static int? _readCount(Map<String, dynamic> body) {
    final meta = body['meta'];
    if (meta is! Map) return null;
    return _optionalInt(meta['count']);
  }

  static int? _optionalInt(Object? value) =>
      value is num ? value.toInt() : int.tryParse(value?.toString() ?? '');

  static int _readInt(Object? value, String field, {int? fallback}) {
    final result = _optionalInt(value) ?? fallback;
    if (result == null) throw FormatException('Expected integer at $field.');
    return result;
  }

  static List<String> _readStringList(Object? value) {
    if (value is! List) return const <String>[];
    return value.map((item) => item.toString()).toList(growable: false);
  }

  static Map<String, String> _parseWordTexts(Object? textValue) {
    if (textValue is! Map) return const <String, String>{};
    final rawAyahs = textValue['ayahs'];
    if (rawAyahs is! List) return const <String, String>{};
    final result = <String, String>{};
    for (final ayahRow in rawAyahs) {
      if (ayahRow is! List || ayahRow.length < 2 || ayahRow[1] is! List) continue;
      final ayah = _optionalInt(ayahRow[0]);
      if (ayah == null) continue;
      for (final wordRow in ayahRow[1] as List) {
        if (wordRow is! List || wordRow.length < 2) continue;
        final position = _optionalInt(wordRow[0]);
        if (position == null) continue;
        result['$ayah:$position'] = wordRow[1].toString();
      }
    }
    return Map.unmodifiable(result);
  }

  static Mp3QuranApiException _readApiError(
    Map<String, dynamic> body,
    int status,
  ) {
    final raw = body['error'];
    final error = raw is Map ? Map<String, dynamic>.from(raw) : const <String, dynamic>{};
    final code = error['code']?.toString() ?? 'http_error';
    final message = error['message']?.toString() ?? 'تعذر إكمال طلب خدمة التلاوات.';
    final field = error['field']?.toString();
    final localMessage = switch (code) {
      'not_found' => 'لم يعثر المصدر على القارئ أو التلاوة المطلوبة.',
      'audio_missing' => 'لا يتوفر تسجيل لهذه السورة ضمن هذه التلاوة.',
      'invalid_parameter' || 'unknown_parameter' || 'validation_failed' =>
        'رفض المصدر أحد معلمات الطلب${field == null ? '' : ': $field'}.',
      'rate_limited' => 'طلبات كثيرة؛ ستتم إعادة المحاولة بعد مهلة المصدر.',
      'queue_full' => 'خدمة معالجة المقطع مشغولة؛ ستتم إعادة المحاولة بعد مهلة المصدر.',
      'internal' => 'حدث خطأ داخلي في خدمة MP3Quran.',
      _ => message,
    };
    return Mp3QuranApiException(
      code: code,
      message: localMessage,
      field: field,
      statusCode: status,
      sourceMessage: message,
    );
  }
}

class Mp3QuranApiPage<T> {
  const Mp3QuranApiPage({required this.items, this.nextUrl, this.count});

  final List<T> items;
  final String? nextUrl;
  final int? count;
}

class Mp3QuranReciter {
  const Mp3QuranReciter({
    required this.code,
    required this.name,
    this.nameLatin,
    this.recitationCount,
  });

  final String code;
  final String name;
  final String? nameLatin;
  final int? recitationCount;

  factory Mp3QuranReciter.fromJson(Map<String, dynamic> json) {
    final code = json['code']?.toString() ?? '';
    final name = json['name']?.toString() ?? '';
    if (code.isEmpty || name.isEmpty) {
      throw const FormatException('Reciter code and name are required.');
    }
    return Mp3QuranReciter(
      code: code,
      name: name,
      nameLatin: json['name_latin']?.toString(),
      recitationCount: Mp3QuranV4Repository._optionalInt(json['recitation_count']),
    );
  }
}

class Mp3QuranRecitation {
  const Mp3QuranRecitation({
    required this.code,
    this.style,
    this.riwayahCodes = const <String>[],
    this.hasAyahTimings = false,
    this.coverageSurahs = const <int>[],
    this.audioBase,
    this.originalPattern,
  });

  final String code;
  final String? style;
  final List<String> riwayahCodes;
  final bool hasAyahTimings;
  final List<int> coverageSurahs;
  final String? audioBase;
  final String? originalPattern;

  factory Mp3QuranRecitation.fromJson(Map<String, dynamic> json) {
    final code = json['code']?.toString() ?? '';
    if (!RegExp(r'^[A-Za-z0-9_-]+/[A-Za-z0-9_-]+$').hasMatch(code)) {
      throw const FormatException('A stable recitation code is required.');
    }
    final rawRiwayahs = json['riwayahs'];
    final riwayahCodes = rawRiwayahs is List
        ? rawRiwayahs.whereType<Map>().map((item) => item['code']?.toString() ?? '')
            .where((item) => item.isNotEmpty).toList(growable: false)
        : const <String>[];
    final rawCoverage = json['coverage'];
    final rawSurahs = rawCoverage is Map ? rawCoverage['surahs'] : null;
    final surahs = rawSurahs is List
        ? rawSurahs.map(Mp3QuranV4Repository._optionalInt).whereType<int>().toList(growable: false)
        : const <int>[];
    final rawAudio = json['audio'];
    final audio = rawAudio is Map ? rawAudio : const <String, dynamic>{};
    final rawFiles = audio['files'];
    final files = rawFiles is Map ? rawFiles : const <String, dynamic>{};
    final rawOriginal = files['original'];
    final original = rawOriginal is Map ? rawOriginal : const <String, dynamic>{};
    final originalPattern = rawOriginal is String
        ? rawOriginal
        : original['pattern']?.toString() ?? original['url']?.toString();
    return Mp3QuranRecitation(
      code: code,
      style: json['style']?.toString(),
      riwayahCodes: List.unmodifiable(riwayahCodes),
      hasAyahTimings: json['has_ayah_timings'] == true,
      coverageSurahs: List.unmodifiable(surahs),
      audioBase: audio['base']?.toString(),
      originalPattern: originalPattern,
    );
  }
}

class Mp3QuranSurahAudio {
  const Mp3QuranSurahAudio({
    required this.surahNumber,
    required this.originalUrl,
    this.bytes,
    this.sha256,
    this.bitrateKbps,
    this.timingLevels = const <String>[],
  });

  final int surahNumber;
  final Uri originalUrl;
  final int? bytes;
  final String? sha256;
  final int? bitrateKbps;
  final List<String> timingLevels;
}

class Mp3QuranAyahTiming {
  const Mp3QuranAyahTiming({
    required this.ayah,
    required this.startMs,
    required this.endMs,
  });

  final int ayah;
  final int startMs;
  final int endMs;
}

class Mp3QuranAyahTimings {
  const Mp3QuranAyahTimings({
    required this.surahNumber,
    required this.complete,
    required this.entries,
  });

  factory Mp3QuranAyahTimings.fromApiData(
    Map<String, dynamic> data, {
    required int fallbackSurah,
  }) {
    final raw = Mp3QuranV4Repository._readList(
      data['ayahs'],
      'ayah_timings.data.ayahs',
    );
    final timings = raw.map((entry) {
      if (entry is! List || entry.length < 3) {
        throw const FormatException('Invalid ayah timing entry.');
      }
      return Mp3QuranAyahTiming(
        ayah: Mp3QuranV4Repository._readInt(entry[0], 'ayah'),
        startMs: Mp3QuranV4Repository._readInt(entry[1], 'start_ms'),
        endMs: Mp3QuranV4Repository._readInt(entry[2], 'end_ms'),
      );
    }).toList(growable: false);
    return Mp3QuranAyahTimings(
      surahNumber: Mp3QuranV4Repository._readInt(
        data['surah'],
        'surah',
        fallback: fallbackSurah,
      ),
      complete: data['complete'] == true,
      entries: List.unmodifiable(timings),
    );
  }

  final int surahNumber;
  final bool complete;
  final List<Mp3QuranAyahTiming> entries;
}

class Mp3QuranWordTiming {
  const Mp3QuranWordTiming({
    required this.ayah,
    required this.wordPosition,
    required this.startMs,
    required this.endMs,
    required this.occurrence,
  });

  final int ayah;
  final int wordPosition;
  final int startMs;
  final int endMs;
  final int occurrence;
}

class Mp3QuranWordTimings {
  const Mp3QuranWordTimings({
    required this.surahNumber,
    required this.words,
    required this.wordTexts,
  });

  factory Mp3QuranWordTimings.fromApiData(
    Map<String, dynamic> data, {
    required int fallbackSurah,
  }) {
    final raw = Mp3QuranV4Repository._readList(
      data['words'],
      'word_timings.data.words',
    );
    // Do not sort or de-duplicate. The API's order is the heard order, and
    // repeated words remain separate entries with their own occurrence index.
    final words = raw.map((entry) {
      if (entry is! List || entry.length < 5) {
        throw const FormatException('Invalid word timing entry.');
      }
      return Mp3QuranWordTiming(
        ayah: Mp3QuranV4Repository._readInt(entry[0], 'word.ayah'),
        wordPosition: Mp3QuranV4Repository._readInt(entry[1], 'word.word_position'),
        startMs: Mp3QuranV4Repository._readInt(entry[2], 'word.start_ms'),
        endMs: Mp3QuranV4Repository._readInt(entry[3], 'word.end_ms'),
        occurrence: Mp3QuranV4Repository._readInt(entry[4], 'word.occurrence'),
      );
    }).toList(growable: false);
    return Mp3QuranWordTimings(
      surahNumber: Mp3QuranV4Repository._readInt(
        data['surah'],
        'surah',
        fallback: fallbackSurah,
      ),
      words: List.unmodifiable(words),
      wordTexts: Mp3QuranV4Repository._parseWordTexts(data['text']),
    );
  }

  final int surahNumber;
  final List<Mp3QuranWordTiming> words;
  final Map<String, String> wordTexts;

  String? textFor(Mp3QuranWordTiming word) =>
      wordTexts['${word.ayah}:${word.wordPosition}'];
}

class Mp3QuranApiException implements Exception {
  const Mp3QuranApiException({
    required this.code,
    required this.message,
    this.field,
    this.statusCode,
    this.sourceMessage,
  });

  final String code;
  final String message;
  final String? field;
  final int? statusCode;
  final String? sourceMessage;

  @override
  String toString() => 'Mp3QuranApiException($code, $statusCode): $message';
}

class _Mp3QuranCachedResponse {
  const _Mp3QuranCachedResponse({required this.body, this.etag});

  final String? etag;
  final Map<String, dynamic> body;
}
