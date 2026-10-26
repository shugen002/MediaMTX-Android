import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mediamtx_manager/data/api/api_client.dart';
import 'package:mediamtx_manager/data/api/api_exception.dart';
import 'package:mediamtx_manager/data/api/mediamtx_service.dart';
import 'package:mediamtx_manager/data/models/server_profile.dart';

void main() {
  test('sends basic auth and resolves the API path', () async {
    late http.Request captured;
    final client = ApiClient(
      baseUrl: 'http://example.test:9997/prefix/v3',
      authMethod: ServerAuthMethod.basic,
      username: 'admin',
      secret: 'secret',
      httpClient: MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode({'version': 'v1.2.3', 'started': '2026-01-01T00:00:00Z'}),
          200,
        );
      }),
    );
    final info = await MediaMtxService(client).info();
    expect(info.version, 'v1.2.3');
    expect(captured.url.toString(), 'http://example.test:9997/prefix/v3/info');
    expect(captured.headers['Authorization'], startsWith('Basic '));
  });

  test('translates 401 into an auth error', () async {
    final client = ApiClient(
      baseUrl: 'http://example.test:9997',
      authMethod: ServerAuthMethod.basic,
      username: 'admin',
      secret: 'wrong',
      httpClient: MockClient(
        (_) async => http.Response(
          jsonEncode({'status': 'error', 'error': 'authentication error'}),
          401,
        ),
      ),
    );
    await expectLater(
      client.getMap('/v3/info'),
      throwsA(
        isA<ApiException>().having(
          (error) => error.kind,
          'kind',
          ApiErrorKind.unauthorized,
        ),
      ),
    );
  });

  test('collects paginated paths', () async {
    final client = ApiClient(
      baseUrl: 'http://example.test:9997',
      authMethod: ServerAuthMethod.none,
      httpClient: MockClient((request) async {
        final page = request.url.queryParameters['page'];
        final items = page == '0'
            ? [
                {'name': 'a', 'online': true},
              ]
            : [
                {'name': 'b', 'online': false},
              ];
        return http.Response(
          jsonEncode({'itemCount': 2, 'pageCount': 2, 'items': items}),
          200,
        );
      }),
    );
    final paths = await MediaMtxService(client).paths();
    expect(paths.map((path) => path.name), ['a', 'b']);
  });
}
