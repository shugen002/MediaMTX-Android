import 'dart:convert';

class LocalServerPorts {
  const LocalServerPorts({
    this.api = 9997,
    this.rtsp = 8554,
    this.rtp = 8000,
    this.rtcp = 8001,
    this.rtmp = 1935,
    this.hls = 8888,
    this.webrtc = 8889,
    this.webrtcUdp = 8189,
    this.srt = 8890,
  });

  final int api;
  final int rtsp;
  final int rtp;
  final int rtcp;
  final int rtmp;
  final int hls;
  final int webrtc;
  final int webrtcUdp;
  final int srt;

  static const defaults = LocalServerPorts();

  LocalServerPorts copyWith({
    int? api,
    int? rtsp,
    int? rtp,
    int? rtcp,
    int? rtmp,
    int? hls,
    int? webrtc,
    int? webrtcUdp,
    int? srt,
  }) {
    return LocalServerPorts(
      api: api ?? this.api,
      rtsp: rtsp ?? this.rtsp,
      rtp: rtp ?? this.rtp,
      rtcp: rtcp ?? this.rtcp,
      rtmp: rtmp ?? this.rtmp,
      hls: hls ?? this.hls,
      webrtc: webrtc ?? this.webrtc,
      webrtcUdp: webrtcUdp ?? this.webrtcUdp,
      srt: srt ?? this.srt,
    );
  }

  Map<String, int> toJson() => {
    'api': api,
    'rtsp': rtsp,
    'rtp': rtp,
    'rtcp': rtcp,
    'rtmp': rtmp,
    'hls': hls,
    'webrtc': webrtc,
    'webrtcUdp': webrtcUdp,
    'srt': srt,
  };

  String encode() => jsonEncode(toJson());

  factory LocalServerPorts.fromJson(Map<String, dynamic> json) {
    int read(String key, int fallback) {
      final value = json[key];
      if (value is num) return value.toInt();
      return int.tryParse('$value') ?? fallback;
    }

    return LocalServerPorts(
      api: read('api', 9997),
      rtsp: read('rtsp', 8554),
      rtp: read('rtp', 8000),
      rtcp: read('rtcp', 8001),
      rtmp: read('rtmp', 1935),
      hls: read('hls', 8888),
      webrtc: read('webrtc', 8889),
      webrtcUdp: read('webrtcUdp', 8189),
      srt: read('srt', 8890),
    );
  }

  String? validate() {
    final values = <String, int>{
      'API': api,
      'RTSP': rtsp,
      'RTP': rtp,
      'RTCP': rtcp,
      'RTMP': rtmp,
      'HLS': hls,
      'WebRTC': webrtc,
      'WebRTC ICE': webrtcUdp,
      'SRT': srt,
    };
    for (final entry in values.entries) {
      if (entry.value < 1024 || entry.value > 65535) {
        return '${entry.key} 端口需在 1024–65535 之间';
      }
    }
    final seen = <int, String>{};
    for (final entry in values.entries) {
      final duplicate = seen[entry.value];
      if (duplicate != null) {
        return '${entry.key} 与 $duplicate 使用了相同端口';
      }
      seen[entry.value] = entry.key;
    }
    return null;
  }
}

class LocalInstall {
  const LocalInstall({
    required this.version,
    required this.directory,
    required this.abi,
    required this.asset,
    required this.installedAt,
  });

  final String version;
  final String directory;
  final String abi;
  final String asset;
  final DateTime installedAt;

  Map<String, dynamic> toJson() => {
    'version': version,
    'directory': directory,
    'abi': abi,
    'asset': asset,
    'installedAt': installedAt.toIso8601String(),
  };

  factory LocalInstall.fromJson(Map<String, dynamic> json) {
    return LocalInstall(
      version: (json['version'] ?? '').toString(),
      directory: (json['directory'] ?? '').toString(),
      abi: (json['abi'] ?? '').toString(),
      asset: (json['asset'] ?? '').toString(),
      installedAt:
          DateTime.tryParse((json['installedAt'] ?? '').toString()) ??
          DateTime.now(),
    );
  }
}

class LocalCredentials {
  const LocalCredentials({required this.user, required this.pass});

  final String user;
  final String pass;

  String encode() => jsonEncode({'user': user, 'pass': pass});

  static LocalCredentials? decode(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final value = jsonDecode(raw);
      if (value is Map) {
        final user = (value['user'] ?? '').toString();
        final pass = (value['pass'] ?? '').toString();
        if (user.isNotEmpty && pass.isNotEmpty) {
          return LocalCredentials(user: user, pass: pass);
        }
      }
    } catch (_) {}
    return null;
  }
}

class LocalServerStatus {
  const LocalServerStatus({
    required this.running,
    this.pid,
    this.startedAt,
    this.startedAtLabel,
  });

  final bool running;
  final int? pid;
  final DateTime? startedAt;
  final String? startedAtLabel;

  static const stopped = LocalServerStatus(running: false);

  factory LocalServerStatus.fromMap(Map<dynamic, dynamic>? map) {
    if (map == null) return stopped;
    final rawDate = map['startedAt'];
    return LocalServerStatus(
      running: map['running'] == true,
      pid: (map['pid'] as num?)?.toInt(),
      startedAt: rawDate is num
          ? DateTime.fromMillisecondsSinceEpoch(rawDate.toInt())
          : DateTime.tryParse((rawDate ?? '').toString()),
      startedAtLabel: map['startedAtLabel']?.toString(),
    );
  }
}
