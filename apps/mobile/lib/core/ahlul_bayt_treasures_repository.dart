import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';

/// Client for the public Ahlul Bayt Treasures data repository.
///
/// The upstream project is a static dataset, not a hosted REST API. The app
/// downloads the small names index first, then downloads the JSONL corpus only
/// when a user opens an item. Both files are cached in application support
/// storage so previously opened content remains available offline.
class AhlulBaytTreasuresRepository {
  AhlulBaytTreasuresRepository({
    Dio? dio,
    Future<Directory> Function()? supportDirectoryProvider,
  })  : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 20),
              receiveTimeout: const Duration(minutes: 3),
              sendTimeout: const Duration(seconds: 20),
              headers: const {'Accept': 'application/json'},
            )),
        _supportDirectoryProvider =
            supportDirectoryProvider ?? getApplicationSupportDirectory;

  static const String version = '1.0.1';
  static const String repositoryUrl =
      'https://github.com/KazTronics/AhlulBayt_Treasures';
  static const String _commit =
      'a59bd5f8fe078532622a08ea60c19d164fb425cb';
  static const String _rawBase =
      'https://raw.githubusercontent.com/KazTronics/AhlulBayt_Treasures/$_commit';
  static const String _namesUrl = '$_rawBase/duas_names.json';
  static const String _dataUrl = '$_rawBase/duas_data.jsonl';

  final Dio _dio;
  final Future<Directory> Function() _supportDirectoryProvider;

  Future<List<AhlulBaytTreasuresIndexEntry>>? _indexFuture;
  Future<File>? _dataFileFuture;

  Future<List<AhlulBaytTreasuresIndexEntry>> loadIndex({
    bool refresh = false,
  }) {
    if (refresh) _indexFuture = null;
    return _indexFuture ??= _loadIndex(refresh: refresh);
  }

  Future<List<AhlulBaytTreasuresIndexEntry>> _loadIndex({
    required bool refresh,
  }) async {
    final file = await _cacheFile('duas_names_$version.json');
    if (!refresh && await file.exists() && await file.length() > 2) {
      try {
        return parseIndex(await file.readAsString());
      } catch (_) {
        await file.delete();
      }
    }

    final temporary = File('${file.path}.part');
    try {
      await _dio.download(_namesUrl, temporary.path);
      final content = await temporary.readAsString();
      final entries = parseIndex(content);
      if (await file.exists()) await file.delete();
      await temporary.rename(file.path);
      return entries;
    } catch (_) {
      if (await temporary.exists()) await temporary.delete();
      if (await file.exists() && await file.length() > 2) {
        return parseIndex(await file.readAsString());
      }
      rethrow;
    }
  }

  Future<AhlulBaytTreasuresText> fetchText(
    int id, {
    bool refresh = false,
  }) async {
    if (id <= 0) throw ArgumentError.value(id, 'id', 'يجب أن يكون موجباً.');
    final file = await _obtainDataFile(refresh: refresh);
    await for (final line in file
        .openRead()
        .transform(utf8.decoder)
        .transform(const LineSplitter())) {
      final value = line.trim();
      if (value.isEmpty) continue;
      final decoded = jsonDecode(value);
      if (decoded is! Map) continue;
      final rawId = decoded['id'];
      final rowId = rawId is num ? rawId.toInt() : int.tryParse('$rawId');
      if (rowId == id) {
        return AhlulBaytTreasuresText.fromJson(
          Map<String, dynamic>.from(decoded),
        );
      }
    }
    throw StateError('لم يُعثر على النص رقم $id في مجموعة البيانات.');
  }

  Future<File> _obtainDataFile({bool refresh = false}) {
    if (refresh) _dataFileFuture = null;
    return _dataFileFuture ??= _downloadOrReadDataFile(refresh: refresh);
  }

  Future<File> _downloadOrReadDataFile({required bool refresh}) async {
    final file = await _cacheFile('duas_data_$version.jsonl');
    if (!refresh && await file.exists() && await file.length() > 1024) {
      try {
        await _validateJsonl(file);
        return file;
      } catch (_) {
        await file.delete();
      }
    }

    final temporary = File('${file.path}.part');
    try {
      await _dio.download(_dataUrl, temporary.path);
      final length = await temporary.length();
      if (length < 1024) {
        throw const FormatException('ملف الأدعية المستلم أصغر من المتوقع.');
      }
      await _validateJsonl(temporary);
      if (await file.exists()) await file.delete();
      await temporary.rename(file.path);
      return file;
    } catch (_) {
      if (await temporary.exists()) await temporary.delete();
      if (await file.exists() && await file.length() > 1024) {
        try {
          await _validateJsonl(file);
          return file;
        } catch (_) {
          // Do not silently fall back to a corrupt local copy.
        }
      }
      rethrow;
    }
  }

  Future<void> _validateJsonl(File file) async {
    var foundRecord = false;
    await for (final line in file
        .openRead()
        .transform(utf8.decoder)
        .transform(const LineSplitter())) {
      if (line.trim().isEmpty) continue;
      final decoded = jsonDecode(line);
      if (decoded is Map && decoded['id'] != null && decoded['rows'] is List) {
        foundRecord = true;
        break;
      }
    }
    if (!foundRecord) {
      throw const FormatException('تنسيق مجموعة الأدعية JSONL غير معروف.');
    }
  }

  Future<File> _cacheFile(String name) async {
    final support = await _supportDirectoryProvider();
    final directory = Directory('${support.path}/ahlulbayt_treasures');
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return File('${directory.path}/$name');
  }

  static List<AhlulBaytTreasuresIndexEntry> parseIndex(String content) {
    final decoded = jsonDecode(content);
    if (decoded is! List) {
      throw const FormatException('فهرس أسماء الأدعية ليس قائمة JSON.');
    }
    final entries = <AhlulBaytTreasuresIndexEntry>[];
    for (var index = 1; index < decoded.length; index++) {
      final value = decoded[index];
      if (value is! String || value.trim().isEmpty) continue;
      entries.add(AhlulBaytTreasuresIndexEntry(
        id: index,
        name: value.trim(),
      ));
    }
    if (entries.isEmpty) {
      throw const FormatException('فهرس أسماء الأدعية فارغ.');
    }
    return List.unmodifiable(entries);
  }
}

class AhlulBaytTreasuresIndexEntry {
  const AhlulBaytTreasuresIndexEntry({required this.id, required this.name});

  final int id;
  final String name;

  bool get isZiyara {
    final normalized = name.toLowerCase();
    return normalized.contains('ziarat') ||
        normalized.contains('ziyara') ||
        normalized.contains('visit');
  }
}

class AhlulBaytTreasuresText {
  const AhlulBaytTreasuresText({
    required this.id,
    required this.name,
    required this.rows,
  });

  final int id;
  final String name;
  final List<AhlulBaytTreasuresTextRow> rows;

  factory AhlulBaytTreasuresText.fromJson(Map<String, dynamic> json) {
    final rawId = json['id'];
    final id = rawId is num ? rawId.toInt() : int.tryParse('$rawId') ?? 0;
    final rawRows = json['rows'];
    if (id <= 0 || rawRows is! List) {
      throw const FormatException('سجل النص لا يحتوي على معرّف وصفوف صالحة.');
    }
    return AhlulBaytTreasuresText(
      id: id,
      name: json['name']?.toString().trim() ?? '',
      rows: List.unmodifiable(rawRows
          .whereType<Map>()
          .map((row) => AhlulBaytTreasuresTextRow.fromJson(
                Map<String, dynamic>.from(row),
              ))),
    );
  }
}

class AhlulBaytTreasuresTextRow {
  const AhlulBaytTreasuresTextRow({
    required this.index,
    required this.showId,
    required this.arabic,
    required this.translation,
    required this.transliteration,
    required this.instruction,
    required this.title,
  });

  final int index;
  final String showId;
  final String arabic;
  final String translation;
  final String transliteration;
  final String instruction;
  final String title;

  factory AhlulBaytTreasuresTextRow.fromJson(Map<String, dynamic> json) {
    int toInt(dynamic value) =>
        value is num ? value.toInt() : int.tryParse('$value') ?? 0;
    String toText(dynamic value) => value?.toString() ?? '';
    return AhlulBaytTreasuresTextRow(
      index: toInt(json['index']),
      showId: toText(json['show_id']),
      arabic: toText(json['arabic']),
      translation: toText(json['translation']),
      transliteration: toText(json['transliteration']),
      instruction: toText(json['instruction']),
      title: toText(json['title']),
    );
  }
}
