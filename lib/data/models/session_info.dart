import '../../core/utils/formatters.dart';

enum SessionProtocol { rtsp, rtmp, srt, webrtc, hls, moq }

extension SessionProtocolX on SessionProtocol {
  String get label => switch (this) {
    SessionProtocol.rtsp => 'RTSP',
    SessionProtocol.rtmp => 'RTMP',
    SessionProtocol.srt => 'SRT',
    SessionProtocol.webrtc => 'WebRTC',
    SessionProtocol.hls => 'HLS',
    SessionProtocol.moq => 'MoQ',
  };

  String get description => switch (this) {
    SessionProtocol.rtsp => '实时流传输协议会话',
    SessionProtocol.rtmp => 'RTMP / RTMPS 推拉流连接',
    SessionProtocol.srt => '低延迟安全可靠传输连接',
    SessionProtocol.webrtc => '浏览器实时通信会话',
    SessionProtocol.hls => 'HTTP 直播分发会话',
    SessionProtocol.moq => 'Media over QUIC 会话',
  };
}

class SessionInfo {
  const SessionInfo({
    required this.id,
    required this.protocol,
    required this.secure,
    required this.kickPath,
    required this.state,
    this.path = '',
    this.remoteAddr = '',
    this.user = '',
    this.userAgent = '',
    this.transport = '',
    this.query = '',
    this.created,
    this.expiresAt,
    this.inboundBytes = 0,
    this.outboundBytes = 0,
  });

  final String id;
  final SessionProtocol protocol;
  final bool secure;
  final String kickPath;
  final String state;
  final String path;
  final String remoteAddr;
  final String user;
  final String userAgent;
  final String transport;
  final String query;
  final DateTime? created;
  final DateTime? expiresAt;
  final int inboundBytes;
  final int outboundBytes;

  String get protocolLabel => secure ? '${protocol.label}S' : protocol.label;

  String get stateLabel {
    if (state == 'publish') return '推流中';
    if (state == 'read') return '读取中';
    if (state == 'idle') return '空闲';
    if (state.isEmpty) return '活跃';
    return state;
  }

  bool get isPublishing => state == 'publish';

  int get totalBytes => inboundBytes + outboundBytes;

  Duration? get duration {
    if (created == null) return null;
    return (expiresAt ?? DateTime.now()).difference(created!);
  }

  String get durationLabel =>
      duration == null ? '—' : formatDurationShort(duration!);

  factory SessionInfo.parse(
    Map<String, dynamic> json, {
    required SessionProtocol protocol,
    required bool secure,
  }) {
    final id = (json['id'] ?? '').toString();
    final base = switch (protocol) {
      SessionProtocol.rtsp => secure ? 'rtsps' : 'rtsp',
      SessionProtocol.rtmp => secure ? 'rtmps' : 'rtmp',
      SessionProtocol.srt => 'srt',
      SessionProtocol.webrtc => 'webrtc',
      SessionProtocol.hls => 'hls',
      SessionProtocol.moq => 'moq',
    };
    final kind =
        protocol == SessionProtocol.rtsp ||
            protocol == SessionProtocol.webrtc ||
            protocol == SessionProtocol.hls ||
            protocol == SessionProtocol.moq
        ? 'sessions'
        : 'conns';
    return SessionInfo(
      id: id,
      protocol: protocol,
      secure: secure,
      kickPath: '/v3/$base/$kind/kick/$id',
      state: (json['state'] ?? (protocol == SessionProtocol.hls ? 'read' : ''))
          .toString(),
      path: (json['path'] ?? '').toString(),
      remoteAddr: (json['remoteAddr'] ?? '').toString(),
      user: (json['user'] ?? '').toString(),
      userAgent: (json['userAgent'] ?? '').toString(),
      transport: (json['transport'] ?? json['tunnel'] ?? json['profile'] ?? '')
          .toString(),
      query: (json['query'] ?? '').toString(),
      created: DateTime.tryParse((json['created'] ?? '').toString()),
      expiresAt: DateTime.tryParse((json['expiresAt'] ?? '').toString()),
      inboundBytes:
          _asInt(json['inboundBytes']) ?? _asInt(json['bytesReceived']) ?? 0,
      outboundBytes:
          _asInt(json['outboundBytes']) ?? _asInt(json['bytesSent']) ?? 0,
    );
  }
}

class SessionCounts {
  const SessionCounts(this.counts);

  final Map<SessionProtocol, int> counts;

  int get total => counts.values.fold(0, (sum, value) => sum + value);

  int of(SessionProtocol protocol) => counts[protocol] ?? 0;

  static const empty = SessionCounts({});
}

int? _asInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}
