import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers.dart';

class LibraryAssistantRepository {
  const LibraryAssistantRepository(this._dio);
  final Dio _dio;

  Future<Map<String, dynamic>> chat({
    required String message,
    List<Map<String, String>> history = const [],
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/v1/public/assistant/chat',
      data: {'message': message, 'history': history},
    );
    return Map<String, dynamic>.from(response.data ?? const {});
  }

  Future<Map<String, dynamic>> previewImport(String identifier) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/v1/public/library/imports/preview',
      data: {'source_key': 'internet_archive', 'identifier': identifier},
    );
    return Map<String, dynamic>.from(response.data ?? const {});
  }

  Future<Map<String, dynamic>> confirmImport(int jobId) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/v1/public/library/imports/$jobId/confirm',
      data: {'confirm_personal_copy': true},
    );
    return Map<String, dynamic>.from(response.data ?? const {});
  }

  Future<Map<String, dynamic>> exportBook(int bookId, {String format = 'txt'}) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/v1/public/library/books/$bookId/export',
      queryParameters: {'format': format},
    );
    return Map<String, dynamic>.from(response.data ?? const {});
  }

  Future<Map<String, dynamic>> status() async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/v1/public/library/status',
    );
    return Map<String, dynamic>.from(response.data ?? const {});
  }

  Future<List<Map<String, dynamic>>> books() async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/v1/public/library/books',
    );
    final raw = response.data?['items'];
    if (raw is! List) return const [];
    return raw.whereType<Map>().map((item) => Map<String, dynamic>.from(item)).toList();
  }

  Future<List<Map<String, dynamic>>> searchBook(int bookId, String query, {int limit = 30}) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/v1/public/library/books/$bookId/search',
      queryParameters: {'q': query, 'limit': limit},
    );
    final raw = response.data?['items'];
    if (raw is! List) return const [];
    return raw.whereType<Map>().map((item) => Map<String, dynamic>.from(item)).toList();
  }

  Future<List<Map<String, dynamic>>> bookToc(int bookId) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/v1/public/library/books/$bookId/toc',
    );
    final raw = response.data?['items'];
    if (raw is! List) return const [];
    return raw.whereType<Map>().map((item) => Map<String, dynamic>.from(item)).toList();
  }

  Future<List<Map<String, dynamic>>> bookEditions(int bookId) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/v1/public/library/books/$bookId/editions',
    );
    final raw = response.data?['items'];
    if (raw is! List) return const [];
    return raw.whereType<Map>().map((item) => Map<String, dynamic>.from(item)).toList();
  }

  Future<List<Map<String, dynamic>>> bookPages(int bookId, {int limit = 40, int offset = 0}) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/v1/public/library/books/$bookId/pages',
      queryParameters: {'limit': limit, 'offset': offset},
    );
    final raw = response.data?['items'];
    if (raw is! List) return const [];
    return raw.whereType<Map>().map((item) => Map<String, dynamic>.from(item)).toList();
  }
}

final libraryAssistantRepositoryProvider = Provider<LibraryAssistantRepository>(
  (ref) => LibraryAssistantRepository(ref.watch(apiProvider)),
);
