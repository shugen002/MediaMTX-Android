import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/utils/url_utils.dart';
import '../models/server_profile.dart';
import 'api_exception.dart';
import 'http_client_factory.dart';

class ApiClient {
  ApiClient({
    required String baseUrl,
    required this.authMethod,
    this.username = '',
    this.secret = '',
    this.allowBadCertificates = false,
    Duration timeout = const Duration(seconds: 12),
    http.Client? httpClient,
  }) : _baseUrl = normalizeBaseUrl(baseUrl),
       _timeout = timeout {
    _client =
        httpClient ??
        createHttpClient(
          allowBadCertificates: allowBadCertificates,
          timeout: timeout,
        );
  }

  final String _baseUrl;
  final ServerAuthMethod authMethod;
  final String username;
  final String secret;
  final bool allowBadCertificates;
  final Duration _timeout;
  late final http.Client _client;

  String get baseUrl => _baseUrl;

  Uri _resolve(String path, [Map<String, dynamic>? query]) {
    final base = Uri.parse(_baseUrl);
    var basePath = base.path;
    while (basePath.endsWith('/')) {
      basePath = basePath.substring(0, basePath.length - 1);
    }
    final parameters = <String, String>{};
    query?.forEach((key, value) {
      if (value != null) parameters[key] = value.toString();
    });
    return base.replace(
      path: '$basePath$path',
      queryParameters: parameters.isEmpty ? null : parameters,
    );
  }

  Map<String, String> get _headers {
    final headers = <String, String>{
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      'User-Agent': 'MTX-Console/1.0 (Flutter)',
    };
    switch (authMethod) {
      case ServerAuthMethod.none:
        break;
      case ServerAuthMethod.basic:
        final token = base64Encode(utf8.encode('$username:$secret'));
        headers['Authorization'] = 'Basic $token';
        break;
      case ServerAuthMethod.bearer:
        headers['Authorization'] = 'Bearer $secret';
    }
    return headers;
  }

  Future<Map<String, dynamic>> getMap(
    String path, {
    Map<String, dynamic>? query,
  }) async {
    final data = await _send('GET', path, query: query);
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    throw const ApiException('服务器返回了无法识别的数据', kind: ApiErrorKind.parse);
  }

  Future<dynamic> getJson(String path, {Map<String, dynamic>? query}) {
    return _send('GET', path, query: query);
  }

  Future<Map<String, dynamic>> postMap(
    String path, {
    Map<String, dynamic>? body,
    Map<String, dynamic>? query,
  }) async {
    final data = await _send('POST', path, body: body, query: query);
    if (data == null) return const {};
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    return const {};
  }

  Future<Map<String, dynamic>> patchMap(
    String path, {
    Map<String, dynamic>? body,
    Map<String, dynamic>? query,
  }) async {
    final data = await _send('PATCH', path, body: body, query: query);
    if (data == null) return const {};
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    return const {};
  }

  Future<void> delete(String path, {Map<String, dynamic>? query}) async {
    await _send('DELETE', path, query: query);
  }

  Future<List<Map<String, dynamic>>> getPagedItems(
    String path, {
    int perPage = 100,
    int maxPages = 20,
    Map<String, dynamic>? query,
  }) async {
    final items = <Map<String, dynamic>>[];
    var page = 0;
    while (page < maxPages) {
      final data = await getMap(
        path,
        query: {...?query, 'page': page, 'itemsPerPage': perPage},
      );
      final rawItems = data['items'];
      if (rawItems is! List) break;
      for (final item in rawItems.whereType<Map>()) {
        items.add(Map<String, dynamic>.from(item));
      }
      final pageCount = _asInt(data['pageCount']);
      page++;
      if (pageCount == null || page >= pageCount) break;
    }
    return items;
  }

  Future<dynamic> _send(
    String method,
    String path, {
    Map<String, dynamic>? query,
    Map<String, dynamic>? body,
  }) async {
    final uri = _resolve(path, query);
    try {
      final request = http.Request(method, uri);
      request.headers.addAll(_headers);
      if (body != null) {
        request.body = jsonEncode(body);
      }
      final streamed = await _client.send(request).timeout(_timeout);
      final response = await http.Response.fromStream(streamed)
          .timeout(_timeout);
      final text = _decode(response.bodyBytes);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        if (text.trim().isEmpty) return null;
        try {
          return jsonDecode(text);
        } on FormatException {
          throw const ApiException(
            '服务器返回了非 JSON 数据，请确认地址指向 MediaMTX API',
            kind: ApiErrorKind.parse,
          );
        }
      }
      String? serverMessage;
      try {
        final decoded = jsonDecode(text);
        if (decoded is Map) {
          serverMessage = (decoded['error'] ?? '').toString();
        }
      } on FormatException {
        serverMessage = text.length > 300 ? text.substring(0, 300) : text;
      }
      throw ApiException.fromStatus(response.statusCode, serverMessage);
    } on ApiException {
      rethrow;
    } on TimeoutException {
      throw const ApiException('连接超时，请检查地址、端口和网络', kind: ApiErrorKind.timeout);
    } on http.ClientException catch (error) {
      throw ApiException(
        '无法连接服务器，请检查地址和网络',
        kind: ApiErrorKind.network,
        detail: error.message,
      );
    } catch (error) {
      final message = error.toString();
      if (message.contains('SocketException') ||
          message.contains('Connection refused') ||
          message.contains('Failed host lookup') ||
          message.contains('XMLHttpRequest')) {
        throw ApiException(
          '无法连接服务器，请检查地址和网络',
          kind: ApiErrorKind.network,
          detail: message,
        );
      }
      if (message.contains('HandshakeException') ||
          message.contains('CERTIFICATE')) {
        throw ApiException(
          'HTTPS 证书校验失败，可在服务器设置中允许自签名证书',
          kind: ApiErrorKind.network,
          detail: message,
        );
      }
      throw ApiException(
        '请求发生未知错误',
        kind: ApiErrorKind.unknown,
        detail: message,
      );
    }
  }

  String _decode(List<int> bytes) {
    try {
      return utf8.decode(bytes);
    } on FormatException {
      return latin1.decode(bytes);
    }
  }

  void close() {
    _client.close();
  }

  static int? _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }
}
