import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Public REST integration for Thaqalayn's Shia hadith catalogue.
/// The repository deliberately does not infer hadith authenticity/grading.
class ThaqalaynRepository {
  ThaqalaynRepository({Dio? dio, SharedPreferences? preferences})
      : _dio = dio ??
            Dio(BaseOptions(
              baseUrl: 'https://www.thaqalayn-api.net/api/v2',
              connectTimeout: const Duration(seconds: 12),
              receiveTimeout: const Duration(seconds: 18),
              sendTimeout: const Duration(seconds: 12),
              headers: const {'Accept': 'application/json'},
              responseType: ResponseType.json,
            )),
        _preferences = preferences;

  final Dio _dio;
  final SharedPreferences? _preferences;

  static const _booksCacheKey = 'thaqalayn_books_cache_v1';
  static const _lastHadithCacheKey = 'thaqalayn_last_hadith_cache_v1';

  Future<List<ThaqalaynBook>> fetchBooks({bool refresh = false}) async {
    try {
      final response = await _dio.get<dynamic>('/allbooks');
      final raw = _asList(response.data);
      final books = raw
          .whereType<Map>()
          .map((item) => ThaqalaynBook.fromJson(
              Map<String, dynamic>.from(item)))
          .where((book) => book.id.isNotEmpty && book.name.isNotEmpty)
          .toList(growable: false)
        ..sort((a, b) => a.name.compareTo(b.name));
      if (books.isEmpty) {
        throw const FormatException('لم تُرجع خدمة الثقلين فهرس كتب صالحاً.');
      }
      await _preferences?.setString(
          _booksCacheKey, jsonEncode(raw));
      return books;
    } catch (_) {
      if (refresh) rethrow;
      final cached = _preferences?.getString(_booksCacheKey);
      if (cached == null) rethrow;
      final raw = jsonDecode(cached);
      return _booksFromRaw(raw);
    }
  }

  Future<List<ThaqalaynHadith>> search({
    required String query,
    String? bookId,
  }) async {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) return const [];
    final path = bookId == null || bookId.isEmpty
        ? '/query'
        : '/query/${Uri.encodeComponent(bookId)}';
    final response = await _dio.get<dynamic>(
      path,
      queryParameters: {'q': cleanQuery},
    );
    final items = _hadithsFromRaw(response.data);
    await _cacheLastHadiths(items);
    return items;
  }

  Future<ThaqalaynHadith> random({String? bookId}) async {
    final path = bookId == null || bookId.isEmpty
        ? '/random'
        : '/${Uri.encodeComponent(bookId)}/random';
    final response = await _dio.get<dynamic>(path);
    final items = _hadithsFromRaw(response.data);
    if (items.isEmpty) {
      throw const FormatException('لم تُرجع خدمة الثقلين حديثاً عشوائياً.');
    }
    await _cacheLastHadiths(items);
    return items.first;
  }

  Future<ThaqalaynHadith> fetchHadith({
    required String bookId,
    required int hadithId,
  }) async {
    final response = await _dio.get<dynamic>(
      '/${Uri.encodeComponent(bookId)}/$hadithId',
    );
    final items = _hadithsFromRaw(response.data);
    if (items.isEmpty) {
      throw const FormatException('لم يُعثر على نص الحديث المطلوب.');
    }
    await _cacheLastHadiths(items);
    return items.first;
  }

  Future<List<ThaqalaynHadith>> readLastCachedHadiths() async {
    final cached = _preferences?.getString(_lastHadithCacheKey);
    if (cached == null) return const [];
    try {
      return _hadithsFromRaw(jsonDecode(cached));
    } catch (_) {
      return const [];
    }
  }

  Future<void> _cacheLastHadiths(List<ThaqalaynHadith> items) async {
    if (items.isEmpty) return;
    await _preferences?.setString(
      _lastHadithCacheKey,
      jsonEncode(items.take(40).map((item) => item.raw).toList()),
    );
  }

  static List<ThaqalaynBook> _booksFromRaw(dynamic raw) => _asList(raw)
      .whereType<Map>()
      .map((item) => ThaqalaynBook.fromJson(Map<String, dynamic>.from(item)))
      .where((book) => book.id.isNotEmpty && book.name.isNotEmpty)
      .toList(growable: false);

  static List<dynamic> _asList(dynamic payload) {
    if (payload is List) return payload;
    if (payload is Map) {
      for (final key in const [
        'data',
        'results',
        'items',
        'hadiths',
        'books',
        'result',
      ]) {
        final value = payload[key];
        if (value is List) return value;
      }
      return [payload];
    }
    return const [];
  }

  static List<ThaqalaynHadith> _hadithsFromRaw(dynamic payload) =>
      _asList(payload)
          .whereType<Map>()
          .map((item) => ThaqalaynHadith.fromJson(
              Map<String, dynamic>.from(item)))
          .toList(growable: false);
}

class ThaqalaynBook {
  const ThaqalaynBook({
    required this.id,
    required this.name,
    required this.author,
    required this.englishName,
    required this.description,
    required this.minimumId,
    required this.maximumId,
    required this.volume,
  });

  final String id;
  final String name;
  final String author;
  final String englishName;
  final String description;
  final int minimumId;
  final int maximumId;
  final int? volume;

  factory ThaqalaynBook.fromJson(Map<String, dynamic> json) {
    int toInt(dynamic value, {int fallback = 1}) =>
        value is num ? value.toInt() : int.tryParse('$value') ?? fallback;
    return ThaqalaynBook(
      id: '${json['bookId'] ?? json['BookId'] ?? json['id'] ?? ''}',
      name: '${json['BookName'] ?? json['bookName'] ?? json['name'] ?? ''}',
      author: '${json['author'] ?? ''}',
      englishName: '${json['englishName'] ?? ''}',
      description: '${json['bookDescription'] ?? json['description'] ?? ''}',
      minimumId: toInt(json['idRangeMin']),
      maximumId: toInt(json['idRangeMax']),
      volume: (json['volume'] ?? json['Volume']) == null
          ? null
          : toInt(json['volume'] ?? json['Volume']),
    );
  }

  String get subtitle => [
        if (author.isNotEmpty) author,
        if (volume != null) 'المجلد $volume',
        if (maximumId > 0) '$maximumId رواية في نطاق الفهرس',
      ].join(' • ');
}

class ThaqalaynHadith {
  const ThaqalaynHadith(this.raw);

  factory ThaqalaynHadith.fromJson(Map<String, dynamic> json) =>
      ThaqalaynHadith(json);

  final Map<String, dynamic> raw;

  static const _arabicKeys = [
    'arabic',
    'Arabic',
    'arabicText',
    'arabic_text',
    'textArabic',
    'text_ar',
    'hadithArabic',
    'HadithArabic',
    'hadith_text_ar',
    'narrationArabic',
    'contentAr',
    'matnAr',
    'thaqalaynMatn',
    'matn',
    'hadith',
    'text',
    'content',
    'body',
  ];
  static const _englishKeys = [
    'english',
    'English',
    'englishText',
    'english_text',
    'textEnglish',
    'text_en',
    'hadithEnglish',
    'HadithEnglish',
    'hadith_text_en',
    'translation',
    'contentEn',
    'matnEn',
    'translatedText',
    'translated_text',
  ];

  String _firstString(List<String> keys) {
    for (final key in keys) {
      final value = raw[key];
      if (value is String && value.trim().isNotEmpty) return value.trim();
      if (value is num) return value.toString();
      if (value is Map) {
        for (final nested in value.values) {
          if (nested is String && nested.trim().isNotEmpty) {
            return nested.trim();
          }
        }
      }
    }
    return '';
  }

  String get arabicText {
    final candidate = _firstString(_arabicKeys);
    if (_containsArabic(candidate)) return candidate;
    final discovered = _allStrings(raw, excludedKeys: const {
      'book', 'bookname', 'booktitle', 'bookdescription', 'description',
      'author', 'translator', 'chapter', 'chaptername', 'narrator',
      'reference', 'grade', 'id', 'bookid', 'volume', 'category',
      'thaqalaynsanad', 'thaqalaynmatn', 'majlisigrading',
      'behbudigrading', 'behdudigrading', 'mohsenigrading',
      'gradingsfull', 'gradear', 'grade_ar', 'gradeen', 'grade_en',
      'referencear', 'reference_ar', 'referenceen', 'reference_en',
      'namear', 'name_ar', 'nameen', 'name_en', 'death_date', 'deathdate',
    }).where(_containsArabic).toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    return discovered.isEmpty ? '' : discovered.first;
  }

  String get englishText {
    final candidate = _firstString(_englishKeys);
    if (candidate.isNotEmpty && !_containsArabic(candidate)) return candidate;
    final discovered = _allStrings(raw, excludedKeys: const {
      'book', 'bookname', 'booktitle', 'bookdescription', 'description',
      'author', 'translator', 'chapter', 'chaptername', 'narrator',
      'reference', 'grade', 'id', 'bookid', 'volume', 'category',
      'thaqalaynsanad', 'thaqalaynmatn', 'majlisigrading',
      'behbudigrading', 'behdudigrading', 'mohsenigrading',
      'gradingsfull', 'gradear', 'grade_ar', 'gradeen', 'grade_en',
      'referencear', 'reference_ar', 'referenceen', 'reference_en',
      'namear', 'name_ar', 'nameen', 'name_en', 'death_date', 'deathdate',
    })
        .where((value) => !_containsArabic(value) && value.length > 20)
        .toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    return discovered.isEmpty ? '' : discovered.first;
  }

  String get id => _firstString([
        'id',
        'hadithId',
        'HadithId',
        'hadith_id',
        'hadithNo',
        'number',
      ]);
  String get bookName => _firstString(['bookName', 'BookName', 'book', 'bookTitle']);
  String get bookId => _firstString(['bookId', 'book_id']);
  String get reference => [
        if (bookName.isNotEmpty) bookName,
        if (id.isNotEmpty) 'رقم $id',
        if (bookId.isNotEmpty && bookName.isEmpty) bookId,
      ].join(' • ');

  /// A validated link to the original narration page, not an arbitrary URL
  /// supplied by an unexpected API field.
  Uri? get sourceUri {
    final value = _firstString(['URL', 'url', 'sourceUrl', 'source_url']);
    if (value.isEmpty) return null;
    final uri = Uri.tryParse(value);
    if (uri == null ||
        uri.scheme.toLowerCase() != 'https' ||
        uri.userInfo.isNotEmpty ||
        uri.port != 443 ||
        !(uri.host.toLowerCase() == 'thaqalayn.net' ||
            uri.host.toLowerCase().endsWith('.thaqalayn.net'))) {
      return null;
    }
    return uri;
  }

  /// Source-provided bibliographic and transmission details. The labels make
  /// it clear that sanad/matn segmentation and gradings are reproduced from
  /// Thaqalayn rather than independently evaluated by this application.
  List<MapEntry<String, String>> get metadata {
    const fields = <(String, String)>[
      ('chapter', 'الباب'),
      ('chapterName', 'الباب'),
      ('category', 'التصنيف'),
      ('volume', 'المجلد'),
      ('author', 'المؤلف'),
      ('translator', 'المترجم'),
      ('narrator', 'الراوي'),
      ('thaqalaynSanad', 'السند كما أورده المصدر'),
      ('chain', 'السند'),
      ('isnad', 'السند'),
      ('thaqalaynMatn', 'المتن كما حدده المصدر'),
      ('majlisiGrading', 'التقييم المنقول عن المجلسي'),
      ('behbudiGrading', 'التقييم المنقول عن البهبودي'),
      ('BehdudiGrading', 'التقييم المنقول عن البهبودي'),
      ('behdudiGrading', 'التقييم المنقول عن البهبودي'),
      ('BehbudiGrading', 'التقييم المنقول عن البهبودي'),
      ('mohseniGrading', 'التقييم المنقول عن المحسني'),
      ('MohseniGrading', 'التقييم المنقول عن المحسني'),
      ('grade', 'التقييم المنقول'),
      ('reference', 'المرجع'),
    ];
    final result = <MapEntry<String, String>>[];
    final seen = <String>{};
    void add(String label, dynamic value) {
      if (value == null) return;
      final text = value is String ? value.trim() : value.toString().trim();
      if (text.isEmpty || text.toLowerCase() == 'null') return;
      final fingerprint = '$label\u0000$text';
      if (seen.add(fingerprint)) result.add(MapEntry(label, text));
    }

    for (final (key, label) in fields) {
      add(label, raw[key]);
    }

    // The REST/GraphQL schema can return several grading records, each with
    // a nested scholar/author object and its own bibliographic reference.
    // Preserve the source's original wording; do not synthesize a verdict.
    final fullGradings =
        raw['GradingsFull'] ?? raw['gradingsFull'] ?? raw['gradings_full'];
    if (fullGradings is List) {
      var gradingNumber = 0;
      for (final rawGrading in fullGradings) {
        if (rawGrading is! Map) continue;
        gradingNumber += 1;
        final grading = Map<String, dynamic>.from(rawGrading);

        String nestedText(Map<String, dynamic> source, List<String> keys) {
          for (final key in keys) {
            final value = source[key];
            if (value is String && value.trim().isNotEmpty) {
              return value.trim();
            }
            if (value is num) return value.toString();
          }
          return '';
        }

        final gradeAr = nestedText(grading, ['grade_ar', 'gradeAr']);
        final gradeEn = nestedText(grading, ['grade_en', 'gradeEn']);
        final grade = nestedText(grading, ['grade']);
        final authorRaw = grading['author'] ?? grading['scholar'];
        final author = authorRaw is Map
            ? Map<String, dynamic>.from(authorRaw)
            : <String, dynamic>{};
        final authorName = nestedText(
          author,
          ['name_ar', 'name_en', 'name', 'authorName'],
        );
        final authorNameEn = nestedText(author, ['name_en']);
        final authorDeath = nestedText(author, ['death_date', 'deathDate']);
        final reference = nestedText(
          grading,
          ['reference_ar', 'reference_en', 'reference', 'citation'],
        );

        final details = <String>[
          if (gradeAr.isNotEmpty) gradeAr,
          if (gradeEn.isNotEmpty && gradeEn != gradeAr) gradeEn,
          if (gradeAr.isEmpty && gradeEn.isEmpty && grade.isNotEmpty) grade,
          if (authorName.isNotEmpty) 'العالم: $authorName',
          if (authorNameEn.isNotEmpty && authorNameEn != authorName)
            'اسم لاتيني: $authorNameEn',
          if (authorDeath.isNotEmpty) 'تاريخ الوفاة كما في المصدر: $authorDeath',
          if (reference.isNotEmpty) 'المرجع: $reference',
        ];
        if (details.isNotEmpty) {
          add('تفصيل التقييم المنقول ${gradingNumber}', details.join(' • '));
        }
      }
    }
    return result;
  }

  static bool _containsArabic(String value) =>
      RegExp(r'[\u0600-\u06FF]').hasMatch(value);

  static List<String> _allStrings(
    dynamic value, {
    Set<String> excludedKeys = const {},
  }) {
    final result = <String>[];
    void visit(dynamic item, [String key = '']) {
      if (excludedKeys.contains(key.toLowerCase())) return;
      if (item is String) {
        final text = item.trim();
        if (text.isNotEmpty && text.length > 2) result.add(text);
      } else if (item is Map) {
        for (final entry in item.entries) {
          visit(entry.value, entry.key.toString());
        }
      } else if (item is List) {
        for (final child in item) {
          visit(child);
        }
      }
    }

    visit(value);
    return result;
  }
}
