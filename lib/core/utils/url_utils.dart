import '../../data/models/server_profile.dart';

/// Normalizes a user-entered address into a MediaMTX API base URL.
///
/// Accepts `host:port`, strips a trailing `/`, and removes a trailing `/v3`
/// because the API client appends versioned paths itself.
String normalizeBaseUrl(String input) {
  var value = input.trim();
  if (value.isEmpty) return value;
  if (!value.contains('://')) {
    value = 'http://$value';
  }
  final uri = Uri.tryParse(value);
  if (uri == null) return value;
  var path = uri.path;
  while (path.endsWith('/')) {
    path = path.substring(0, path.length - 1);
  }
  if (path == '/v3') path = '';
  if (path.endsWith('/v3')) {
    path = path.substring(0, path.length - 3);
  }
  return uri.replace(path: path, query: null, fragment: null).toString();
}

String? validateBaseUrl(String input) {
  if (input.trim().isEmpty) return '请输入服务器地址';
  if (input.contains(RegExp(r'\s'))) return '地址不能包含空格';
  final normalized = normalizeBaseUrl(input);
  final uri = Uri.tryParse(normalized);
  if (uri == null || uri.host.isEmpty) return '地址格式不正确';
  if (uri.scheme != 'http' && uri.scheme != 'https') {
    return '仅支持 http:// 或 https://';
  }
  if (uri.hasQuery || uri.hasFragment) return '地址不能包含参数或锚点';
  final port = uri.hasPort ? uri.port : null;
  if (port != null && (port < 1 || port > 65535)) return '端口超出范围';
  return null;
}

String hostOf(ServerProfile profile) {
  final uri = Uri.tryParse(normalizeBaseUrl(profile.baseUrl));
  if (uri == null || uri.host.isEmpty) return profile.baseUrl;
  return uri.host;
}

String hostWithPort(ServerProfile profile) {
  final uri = Uri.tryParse(normalizeBaseUrl(profile.baseUrl));
  if (uri == null) return profile.baseUrl;
  final host = uri.host.contains(':') ? '[${uri.host}]' : uri.host;
  if (uri.hasPort) return '$host:${uri.port}';
  if (uri.scheme == 'https') return '$host:443';
  return host;
}

int _portFromAddress(String? address, int fallback, {String? scheme}) {
  if (address == null || address.trim().isEmpty) return fallback;
  var value = address.trim();
  if (scheme != null && value.startsWith('$scheme://')) {
    value = value.substring(scheme.length + 3);
  }
  final match = RegExp(r':(\d+)\s*$').firstMatch(value);
  if (match == null) return fallback;
  return int.tryParse(match.group(1)!) ?? fallback;
}

class StreamEndpoint {
  const StreamEndpoint({
    required this.protocol,
    required this.label,
    required this.publishUrl,
    required this.readUrl,
    required this.iconName,
  });

  final String protocol;
  final String label;
  final String publishUrl;
  final String readUrl;
  final String iconName;
}

/// Derives human-usable publish/read URLs from the API host and global config.
List<StreamEndpoint> buildStreamEndpoints(
  ServerProfile profile,
  String pathName,
  Map<String, dynamic>? globalConfig, {
  String? hostOverride,
}) {
  final apiUri = Uri.tryParse(normalizeBaseUrl(profile.baseUrl));
  if (apiUri == null) return const [];
  final host = hostOverride?.trim().isNotEmpty == true
      ? hostOverride!.trim()
      : apiUri.host;
  final authority = host.contains(':') ? '[$host]' : host;

  final rtspPort = _portFromAddress(
    globalConfig?['rtspAddress'] as String?,
    8554,
  );
  final rtmpPort = _portFromAddress(
    globalConfig?['rtmpAddress'] as String?,
    1935,
  );
  final hlsPort = _portFromAddress(
    globalConfig?['hlsAddress'] as String?,
    8888,
  );
  final webrtcPort = _portFromAddress(
    globalConfig?['webrtcAddress'] as String?,
    8889,
  );
  final srtPort = _portFromAddress(
    globalConfig?['srtAddress'] as String?,
    8890,
  );
  final rtspScheme =
      (globalConfig?['rtspEncryption'] as String?) == 'yes' ||
          (globalConfig?['rtspEncryption'] as String?) == 'strict'
      ? 'rtsps'
      : 'rtsp';
  final rtmpScheme =
      (globalConfig?['rtmpEncryption'] as String?) == 'yes' ||
          (globalConfig?['rtmpEncryption'] as String?) == 'strict'
      ? 'rtmps'
      : 'rtmp';
  final hlsScheme = (globalConfig?['hlsEncryption'] as bool?) == true
      ? 'https'
      : 'http';
  final webrtcScheme = (globalConfig?['webrtcEncryption'] as bool?) == true
      ? 'https'
      : 'http';

  final encoded = Uri.encodeComponent(pathName);
  return [
    StreamEndpoint(
      protocol: 'RTSP',
      label: 'RTSP',
      publishUrl: '$rtspScheme://$authority:$rtspPort/$pathName',
      readUrl: '$rtspScheme://$authority:$rtspPort/$pathName',
      iconName: 'rtsp',
    ),
    StreamEndpoint(
      protocol: 'RTMP',
      label: 'RTMP',
      publishUrl: '$rtmpScheme://$authority:$rtmpPort/$pathName',
      readUrl: '$rtmpScheme://$authority:$rtmpPort/$pathName',
      iconName: 'rtmp',
    ),
    StreamEndpoint(
      protocol: 'HLS',
      label: 'HLS',
      publishUrl: '',
      readUrl: '$hlsScheme://$authority:$hlsPort/$encoded/index.m3u8',
      iconName: 'hls',
    ),
    StreamEndpoint(
      protocol: 'WebRTC',
      label: 'WebRTC',
      publishUrl: '$webrtcScheme://$authority:$webrtcPort/$encoded/publish',
      readUrl: '$webrtcScheme://$authority:$webrtcPort/$encoded',
      iconName: 'webrtc',
    ),
    StreamEndpoint(
      protocol: 'SRT',
      label: 'SRT',
      publishUrl: 'srt://$authority:$srtPort?streamid=publish:$pathName',
      readUrl: 'srt://$authority:$srtPort?streamid=read:$pathName',
      iconName: 'srt',
    ),
  ];
}
