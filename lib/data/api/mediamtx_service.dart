import 'dart:async';

import '../models/path_config.dart';
import '../models/runtime_path.dart';
import '../models/server_info.dart';
import '../models/session_info.dart';
import 'api_client.dart';
import 'api_exception.dart';

class MediaMtxService {
  MediaMtxService(this.client);

  final ApiClient client;

  Future<ServerInfo> info() async {
    final json = await client.getMap('/v3/info');
    return ServerInfo.fromJson(json);
  }

  Future<List<RuntimePath>> paths() async {
    final items = await client.getPagedItems('/v3/paths/list', perPage: 200);
    return items.map(RuntimePath.fromJson).toList(growable: false);
  }

  Future<RuntimePath> path(String name) async {
    final json = await client.getMap('/v3/paths/get/${encodePath(name)}');
    return RuntimePath.fromJson(json);
  }

  Future<List<PathConfig>> pathConfigs() async {
    final items = await client.getPagedItems(
      '/v3/config/paths/list',
      perPage: 200,
    );
    return items.map(PathConfig.fromJson).toList(growable: false);
  }

  Future<Map<String, dynamic>> pathConfig(String name) async {
    return client.getMap('/v3/config/paths/get/${encodePath(name)}');
  }

  Future<void> addPath(String name, Map<String, dynamic> config) async {
    final body = Map<String, dynamic>.from(config)..remove('name');
    await client.postMap(
      '/v3/config/paths/add/${encodePath(name)}',
      body: body,
    );
  }

  Future<void> patchPath(String name, Map<String, dynamic> patch) async {
    final body = Map<String, dynamic>.from(patch)..remove('name');
    await client.patchMap(
      '/v3/config/paths/patch/${encodePath(name)}',
      body: body,
    );
  }

  Future<void> deletePath(String name) async {
    await client.delete('/v3/config/paths/delete/${encodePath(name)}');
  }

  Future<Map<String, dynamic>> globalConfig() {
    return client.getMap('/v3/config/global/get');
  }

  Future<void> patchGlobalConfig(Map<String, dynamic> patch) async {
    await client.patchMap('/v3/config/global/patch', body: patch);
  }

  Future<Map<String, dynamic>> pathDefaults() {
    return client.getMap('/v3/config/path-defaults/get');
  }

  Future<void> patchPathDefaults(Map<String, dynamic> patch) async {
    await client.patchMap('/v3/config/path-defaults/patch', body: patch);
  }

  Future<List<Map<String, dynamic>>> internalUsers() {
    return client.getPagedItems('/v3/config/internal-users/list', perPage: 200);
  }

  Future<Map<String, dynamic>> addInternalUser(Map<String, dynamic> user) {
    return client.postMap('/v3/config/internal-users/add', body: user);
  }

  Future<void> deleteInternalUser(String id) async {
    await client.delete('/v3/config/internal-users/delete/${encodePath(id)}');
  }

  Future<List<Recording>> recordings() async {
    final items = await client.getPagedItems(
      '/v3/recordings/list',
      perPage: 200,
    );
    return items.map(Recording.fromJson).toList(growable: false);
  }

  Future<void> deleteRecordingSegment({
    required String path,
    required DateTime start,
  }) async {
    await client.delete(
      '/v3/recordings/segments/delete',
      query: {'path': path, 'start': start.toUtc().toIso8601String()},
    );
  }

  Future<List<SessionInfo>> sessions(SessionProtocol protocol) async {
    final sources = switch (protocol) {
      SessionProtocol.rtsp => const [
        (path: '/v3/rtsp/sessions/list', secure: false),
        (path: '/v3/rtsps/sessions/list', secure: true),
      ],
      SessionProtocol.rtmp => const [
        (path: '/v3/rtmp/conns/list', secure: false),
        (path: '/v3/rtmps/conns/list', secure: true),
      ],
      SessionProtocol.srt => const [
        (path: '/v3/srt/conns/list', secure: false),
      ],
      SessionProtocol.webrtc => const [
        (path: '/v3/webrtc/sessions/list', secure: false),
      ],
      SessionProtocol.hls => const [
        (path: '/v3/hls/sessions/list', secure: false),
      ],
      SessionProtocol.moq => const [
        (path: '/v3/moq/sessions/list', secure: false),
      ],
    };

    final result = <SessionInfo>[];
    for (final source in sources) {
      try {
        final items = await client.getPagedItems(source.path, perPage: 200);
        result.addAll(
          items.map(
            (item) => SessionInfo.parse(
              item,
              protocol: protocol,
              secure: source.secure,
            ),
          ),
        );
      } on ApiException catch (error) {
        if (error.kind == ApiErrorKind.notFound ||
            error.kind == ApiErrorKind.unsupported) {
          continue;
        }
        rethrow;
      }
    }
    result.sort((a, b) {
      final left = a.created ?? DateTime(1970);
      final right = b.created ?? DateTime(1970);
      return right.compareTo(left);
    });
    return result;
  }

  Future<SessionCounts> sessionCounts() async {
    final entries = await Future.wait(
      SessionProtocol.values.map((protocol) async {
        try {
          final list = await sessions(protocol);
          return MapEntry(protocol, list.length);
        } on ApiException {
          return MapEntry(protocol, 0);
        }
      }),
    );
    return SessionCounts(Map.fromEntries(entries));
  }

  Future<void> kick(SessionInfo session) async {
    await client.postMap(session.kickPath);
  }

  Future<void> refreshJwks() async {
    await client.postMap('/v3/auth/jwks/refresh');
  }
}

class Recording {
  const Recording({required this.name, required this.segments});

  final String name;
  final List<RecordingSegment> segments;

  Duration get totalDuration => Duration(
    milliseconds: segments.fold(
      0,
      (sum, segment) => sum + ((segment.duration?.inMilliseconds ?? 0)),
    ),
  );

  DateTime? get latest => segments.isEmpty ? null : segments.last.start;

  factory Recording.fromJson(Map<String, dynamic> json) {
    final rawSegments = json['segments'];
    return Recording(
      name: (json['name'] ?? '').toString(),
      segments: rawSegments is List
          ? rawSegments
                .whereType<Map>()
                .map(
                  (item) => RecordingSegment.fromJson(
                    Map<String, dynamic>.from(item),
                  ),
                )
                .toList(growable: false)
          : const [],
    );
  }
}

class RecordingSegment {
  const RecordingSegment({required this.start, this.duration});

  final DateTime start;
  final Duration? duration;

  factory RecordingSegment.fromJson(Map<String, dynamic> json) {
    final rawDuration = json['duration'];
    return RecordingSegment(
      start:
          DateTime.tryParse((json['start'] ?? '').toString()) ??
          DateTime.fromMillisecondsSinceEpoch(0),
      duration: rawDuration is num
          ? Duration(milliseconds: (rawDuration * 1000).round())
          : null,
    );
  }
}

String encodePath(String value) => Uri.encodeComponent(value);
