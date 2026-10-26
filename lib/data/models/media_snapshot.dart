import 'path_config.dart';
import 'runtime_path.dart';
import 'server_info.dart';
import 'session_info.dart';

class MediaSnapshot {
  const MediaSnapshot({
    required this.info,
    required this.paths,
    required this.configs,
    required this.fetchedAt,
  });

  final ServerInfo info;
  final List<RuntimePath> paths;
  final List<PathConfig> configs;
  final DateTime fetchedAt;

  int get onlinePaths => paths.where((path) => path.online).length;

  int get totalReaders =>
      paths.fold(0, (sum, path) => sum + path.readers.length);

  int get inboundBytes => paths.fold(0, (sum, path) => sum + path.inboundBytes);

  int get outboundBytes =>
      paths.fold(0, (sum, path) => sum + path.outboundBytes);

  /// Runtime paths merged with declarative configurations.
  List<PathView> get pathViews {
    final configsByName = {for (final config in configs) config.name: config};
    final runtimeByName = {for (final path in paths) path.name: path};
    final names =
        <String>{...configsByName.keys, ...runtimeByName.keys}
            .where(
              (name) => name != 'all_others' || runtimeByName.containsKey(name),
            )
            .toList()
          ..sort((a, b) {
            final left = runtimeByName[a];
            final right = runtimeByName[b];
            if (left?.online != right?.online) {
              return (right?.online ?? false) ? 1 : -1;
            }
            return a.toLowerCase().compareTo(b.toLowerCase());
          });
    return [
      for (final name in names)
        PathView(
          name: name,
          runtime: runtimeByName[name],
          config: configsByName[name],
        ),
    ];
  }

  MediaSnapshot copyWith({DateTime? fetchedAt}) => MediaSnapshot(
    info: info,
    paths: paths,
    configs: configs,
    fetchedAt: fetchedAt ?? this.fetchedAt,
  );
}

class PathView {
  const PathView({required this.name, this.runtime, this.config});

  final String name;
  final RuntimePath? runtime;
  final PathConfig? config;

  bool get online => runtime?.online ?? false;

  bool get hasConfig => config != null;

  String get sourceLabel =>
      runtime?.sourceLabel ??
      (config?.source.isNotEmpty == true ? config!.source : '仅配置');

  int get readers => runtime?.readers.length ?? 0;

  int get inboundBytes => runtime?.inboundBytes ?? 0;

  int get outboundBytes => runtime?.outboundBytes ?? 0;
}

class TrafficSample {
  const TrafficSample({
    required this.time,
    required this.inboundRate,
    required this.outboundRate,
    required this.totalInbound,
    required this.totalOutbound,
  });

  final DateTime time;
  final double inboundRate;
  final double outboundRate;
  final int totalInbound;
  final int totalOutbound;
}

class SessionSummary {
  const SessionSummary({required this.counts, required this.fetchedAt});

  final SessionCounts counts;
  final DateTime fetchedAt;

  static final empty = SessionSummary(
    counts: SessionCounts.empty,
    fetchedAt: DateTime(1970),
  );
}
