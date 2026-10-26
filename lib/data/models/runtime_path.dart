class PathReaderInfo {
  const PathReaderInfo({required this.id, required this.type});

  final String id;
  final String type;

  String get label => switch (type) {
    'hlsSession' => 'HLS 会话',
    'rtmpConn' => 'RTMP 连接',
    'rtmpsConn' => 'RTMPS 连接',
    'rtspConn' => 'RTSP 连接',
    'rtspSession' => 'RTSP 会话',
    'rtspsConn' => 'RTSPS 连接',
    'rtspsSession' => 'RTSPS 会话',
    'srtConn' => 'SRT 连接',
    'webRTCSession' => 'WebRTC 会话',
    'moqSession' => 'MoQ 会话',
    'hidden' => '内部读取',
    _ => type,
  };

  factory PathReaderInfo.fromJson(Map<String, dynamic> json) {
    return PathReaderInfo(
      id: (json['id'] ?? '').toString(),
      type: (json['type'] ?? '').toString(),
    );
  }
}

class PathSourceInfo {
  const PathSourceInfo({required this.id, required this.type});

  final String id;
  final String type;

  String get label => switch (type) {
    'hlsSource' => 'HLS 拉流',
    'redirect' => '重定向',
    'rpiCameraSource' => '树莓派摄像头',
    'rtmpConn' => 'RTMP 推流',
    'rtmpsConn' => 'RTMPS 推流',
    'rtmpSource' => 'RTMP 拉流',
    'rtspSession' => 'RTSP 推流',
    'rtspSource' => 'RTSP 拉流',
    'rtspsSession' => 'RTSPS 推流',
    'srtConn' => 'SRT 推流',
    'srtSource' => 'SRT 拉流',
    'mpegtsSource' => 'MPEG-TS 拉流',
    'rtpSource' => 'RTP 拉流',
    'webRTCSession' => 'WebRTC 推流',
    'webRTCSource' => 'WebRTC 拉流',
    'moqSource' => 'MoQ 拉流',
    'moqSession' => 'MoQ 推流',
    _ => '未知来源',
  };

  factory PathSourceInfo.fromJson(Map<String, dynamic> json) {
    return PathSourceInfo(
      id: (json['id'] ?? '').toString(),
      type: (json['type'] ?? '').toString(),
    );
  }
}

class PathTrackInfo {
  const PathTrackInfo({required this.codec, this.codecProps = const {}});

  final String codec;
  final Map<String, dynamic> codecProps;

  bool get isVideo => const {
    'AV1',
    'VP9',
    'VP8',
    'H265',
    'H264',
    'MPEG-4 Video',
    'MPEG-1/2 Video',
    'M-JPEG',
    'MPEG-TS',
  }.contains(codec);

  bool get isAudio => const {
    'Opus',
    'FLAC',
    'Vorbis',
    'MPEG-4 Audio',
    'MPEG-4 Audio LATM',
    'MPEG-1/2 Audio',
    'AC3',
    'Speex',
    'G726',
    'G722',
    'G711',
    'LPCM',
  }.contains(codec);

  bool get isMetadata => codec == 'KLV';

  String get label => switch (codec) {
    'H264' => 'H.264',
    'H265' => 'H.265',
    'AV1' => 'AV1',
    'VP9' => 'VP9',
    'VP8' => 'VP8',
    'MPEG-4 Video' => 'MPEG-4',
    'MPEG-4 Audio' => 'AAC',
    'MPEG-4 Audio LATM' => 'AAC LATM',
    'MPEG-1/2 Audio' => 'MP2',
    'MPEG-1/2 Video' => 'MPEG-2',
    'M-JPEG' => 'M-JPEG',
    'Opus' => 'Opus',
    'FLAC' => 'FLAC',
    'Vorbis' => 'Vorbis',
    'AC3' => 'AC-3',
    'G711' => 'G.711',
    'G722' => 'G.722',
    'G726' => 'G.726',
    'LPCM' => 'PCM',
    'MPEG-TS' => 'MPEG-TS',
    'KLV' => 'KLV',
    _ => codec,
  };

  factory PathTrackInfo.fromJson(Map<String, dynamic> json) {
    return PathTrackInfo(
      codec: (json['codec'] ?? '').toString(),
      codecProps: json['codecProps'] is Map
          ? Map<String, dynamic>.from(json['codecProps'] as Map)
          : const {},
    );
  }
}

class RuntimePath {
  const RuntimePath({
    required this.name,
    required this.online,
    required this.available,
    required this.inboundBytes,
    required this.outboundBytes,
    required this.readers,
    required this.tracks,
    this.confName = '',
    this.source,
    this.onlineTime,
    this.availableTime,
  });

  final String name;
  final String confName;
  final bool online;
  final bool available;
  final int inboundBytes;
  final int outboundBytes;
  final List<PathReaderInfo> readers;
  final List<PathTrackInfo> tracks;
  final PathSourceInfo? source;
  final DateTime? onlineTime;
  final DateTime? availableTime;

  bool get hasVideo => tracks.any((track) => track.isVideo);

  bool get hasAudio => tracks.any((track) => track.isAudio);

  String get sourceLabel => source?.label ?? '未发布';

  String get streamId => source?.id.isNotEmpty == true ? source!.id : name;

  factory RuntimePath.fromJson(Map<String, dynamic> json) {
    final rawReaders = json['readers'];
    final readers = rawReaders is List
        ? rawReaders
              .whereType<Map>()
              .map(
                (item) =>
                    PathReaderInfo.fromJson(Map<String, dynamic>.from(item)),
              )
              .toList(growable: false)
        : <PathReaderInfo>[];

    final tracks = <PathTrackInfo>[];
    final rawTracks2 = json['tracks2'];
    if (rawTracks2 is List) {
      for (final item in rawTracks2.whereType<Map>()) {
        tracks.add(PathTrackInfo.fromJson(Map<String, dynamic>.from(item)));
      }
    } else if (json['tracks'] is List) {
      for (final codec in (json['tracks'] as List)) {
        tracks.add(PathTrackInfo(codec: codec.toString()));
      }
    }

    return RuntimePath(
      name: (json['name'] ?? '').toString(),
      confName: (json['confName'] ?? '').toString(),
      online: json['online'] == true || json['ready'] == true,
      available: json['available'] == true || json['ready'] == true,
      inboundBytes:
          _asInt(json['inboundBytes']) ?? _asInt(json['bytesReceived']) ?? 0,
      outboundBytes:
          _asInt(json['outboundBytes']) ?? _asInt(json['bytesSent']) ?? 0,
      readers: readers,
      tracks: tracks,
      source: json['source'] is Map
          ? PathSourceInfo.fromJson(
              Map<String, dynamic>.from(json['source'] as Map),
            )
          : null,
      onlineTime:
          DateTime.tryParse((json['onlineTime'] ?? '').toString()) ??
          DateTime.tryParse((json['readyTime'] ?? '').toString()),
      availableTime: DateTime.tryParse(
        (json['availableTime'] ?? '').toString(),
      ),
    );
  }
}

int? _asInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}
