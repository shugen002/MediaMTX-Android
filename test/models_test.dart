import 'package:flutter_test/flutter_test.dart';
import 'package:mediamtx_manager/core/utils/url_utils.dart';
import 'package:mediamtx_manager/data/models/local_server_models.dart';
import 'package:mediamtx_manager/data/models/runtime_path.dart';
import 'package:mediamtx_manager/data/models/server_profile.dart';
import 'package:mediamtx_manager/data/models/session_info.dart';

void main() {
  group('URL helpers', () {
    test('normalizes host-only and /v3 URLs', () {
      expect(normalizeBaseUrl('192.168.1.2:9997'), 'http://192.168.1.2:9997');
      expect(
        normalizeBaseUrl('https://demo.example/mediamtx/v3/'),
        'https://demo.example/mediamtx',
      );
      expect(validateBaseUrl('not a url'), isNotNull);
      expect(validateBaseUrl('http://host:9997'), isNull);
    });

    test('builds stream endpoints from global ports', () {
      final profile = ServerProfile(
        id: '1',
        name: 'demo',
        baseUrl: 'http://10.0.0.2:9997',
        createdAt: DateTime(2026),
      );
      final endpoints = buildStreamEndpoints(profile, 'live', {
        'rtspAddress': ':9554',
        'rtmpAddress': ':9935',
        'hlsAddress': ':9888',
        'webrtcAddress': ':9889',
        'srtAddress': ':9890',
      });
      final rtsp = endpoints.firstWhere((item) => item.protocol == 'RTSP');
      expect(rtsp.readUrl, 'rtsp://10.0.0.2:9554/live');
      final srt = endpoints.firstWhere((item) => item.protocol == 'SRT');
      expect(srt.publishUrl, contains('streamid=publish:live'));
    });
  });

  group('RuntimePath', () {
    test('parses tracks, readers and byte counters', () {
      final path = RuntimePath.fromJson({
        'name': 'cam',
        'online': true,
        'inboundBytes': 100,
        'outboundBytes': 200,
        'readers': [
          {'id': 'r1', 'type': 'hlsSession'},
        ],
        'tracks2': [
          {
            'codec': 'H264',
            'codecProps': {'width': 1920, 'height': 1080},
          },
          {'codec': 'Opus'},
        ],
      });
      expect(path.online, isTrue);
      expect(path.readers.single.label, 'HLS 会话');
      expect(path.tracks.first.isVideo, isTrue);
      expect(path.tracks.first.label, 'H.264');
      expect(path.outboundBytes, 200);
    });
  });

  group('SessionInfo', () {
    test('derives kick path and state labels', () {
      final session = SessionInfo.parse(
        {
          'id': 'abc',
          'path': 'live',
          'state': 'publish',
          'inboundBytes': 10,
          'outboundBytes': 20,
        },
        protocol: SessionProtocol.rtsp,
        secure: true,
      );
      expect(session.kickPath, '/v3/rtsps/sessions/kick/abc');
      expect(session.stateLabel, '推流中');
      expect(session.totalBytes, 30);
    });
  });

  group('LocalServerPorts', () {
    test('rejects duplicate and privileged ports', () {
      expect(const LocalServerPorts().validate(), isNull);
      expect(const LocalServerPorts(api: 8554).validate(), contains('相同端口'));
      expect(const LocalServerPorts(api: 80).validate(), contains('1024'));
    });
  });
}
