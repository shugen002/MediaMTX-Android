import '../../core/utils/formatters.dart';

class ServerInfo {
  const ServerInfo({required this.version, required this.started});

  final String version;
  final DateTime started;

  Duration get uptime => DateTime.now().difference(started);

  String get uptimeLabel => formatUptime(uptime);

  factory ServerInfo.fromJson(Map<String, dynamic> json) {
    return ServerInfo(
      version: (json['version'] ?? '未知版本').toString(),
      started:
          DateTime.tryParse((json['started'] ?? '').toString()) ??
          DateTime.now(),
    );
  }
}
