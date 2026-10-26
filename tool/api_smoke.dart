import 'dart:io';

import 'package:mediamtx_manager/data/api/api_client.dart';
import 'package:mediamtx_manager/data/api/mediamtx_service.dart';
import 'package:mediamtx_manager/data/models/server_profile.dart';

Future<void> main(List<String> args) async {
  final base = args.isEmpty ? 'http://127.0.0.1:9997' : args.first;
  final client = ApiClient(
    baseUrl: base,
    authMethod: ServerAuthMethod.none,
    timeout: const Duration(seconds: 5),
  );
  try {
    final service = MediaMtxService(client);
    final info = await service.info();
    final paths = await service.paths();
    final configs = await service.pathConfigs();
    final counts = await service.sessionCounts();
    final global = await service.globalConfig();
    stdout.writeln('version=${info.version} uptime=${info.uptimeLabel}');
    stdout.writeln('paths=${paths.length} configs=${configs.length}');
    stdout.writeln('sessions=$counts counts=${counts.counts}');
    stdout.writeln('apiAddress=${global['apiAddress']}');
    for (final path in paths) {
      stdout.writeln(
        '${path.name}: online=${path.online} readers=${path.readers.length} '
        'tracks=${path.tracks.map((track) => track.label).join(',')}',
      );
    }
  } finally {
    client.close();
  }
}
