// ignore_for_file: prefer_initializing_formals
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../api/api_client.dart';
import '../api/api_exception.dart';
import '../api/github_release_service.dart';
import '../models/local_server_models.dart';
import '../models/server_profile.dart';
import '../repositories/server_store.dart';
import 'local_release_installer.dart';
import 'local_server_platform.dart';

enum LocalPhase {
  unsupported,
  idle,
  stopped,
  checking,
  downloading,
  installing,
  starting,
  running,
  stopping,
  error,
}

extension LocalPhaseX on LocalPhase {
  bool get busy => const {
    LocalPhase.checking,
    LocalPhase.downloading,
    LocalPhase.installing,
    LocalPhase.starting,
    LocalPhase.stopping,
  }.contains(this);

  String get label => switch (this) {
    LocalPhase.unsupported => '当前平台不支持',
    LocalPhase.idle => '尚未安装',
    LocalPhase.stopped => '已停止',
    LocalPhase.checking => '检查版本中',
    LocalPhase.downloading => '下载中',
    LocalPhase.installing => '安装中',
    LocalPhase.starting => '启动中',
    LocalPhase.running => '运行中',
    LocalPhase.stopping => '停止中',
    LocalPhase.error => '异常',
  };
}

class LocalServerController extends ChangeNotifier {
  LocalServerController({
    required ServerStore store,
    LocalServerPlatform? platform,
    LocalReleaseInstaller? installer,
    GithubReleaseService? releaseService,
  }) : _store = store,
       _platform = platform ?? LocalServerPlatform(),
       _installer = installer ?? LocalReleaseInstaller(),
       _releaseService = releaseService ?? GithubReleaseService();

  final ServerStore _store;
  final LocalServerPlatform _platform;
  final LocalReleaseInstaller _installer;
  final GithubReleaseService _releaseService;

  LocalInstall? _install;
  LocalServerPorts _ports = LocalServerPorts.defaults;
  LocalCredentials? _credentials;
  GithubRelease? _latest;
  LocalServerStatus _status = LocalServerStatus.stopped;
  LocalPhase _phase = LocalPhase.idle;
  String? _error;
  String? _latestError;
  String _logs = '';
  bool _busy = false;
  bool _cancelled = false;
  bool _initialized = false;
  bool _mirrorEnabled = true;
  String _mirrorPrefix = 'https://ghfast.top/';
  double _progress = 0;
  int _received = 0;
  int _total = 0;
  String? _abi;
  String? _lanAddress;
  bool _ignoringBatteryOptimizations = false;
  Timer? _eventTimer;
  String _lastLogTail = '';
  String? _lastEvent;
  int _eventRevision = 0;
  bool _pollingEvents = false;
  bool _batteryPromptShown = false;
  Directory? _baseDirectory;

  LocalInstall? get install => _install;
  LocalServerPorts get ports => _ports;
  LocalCredentials? get credentials => _credentials;
  GithubRelease? get latest => _latest;
  LocalServerStatus get status => _status;
  LocalPhase get phase => _phase;
  String? get error => _error;
  String? get latestError => _latestError;
  String get logs => _logs;
  bool get busy => _busy;
  bool get initialized => _initialized;
  bool get supported => _platform.isSupported;
  bool get mirrorEnabled => _mirrorEnabled;
  String get mirrorPrefix => _mirrorPrefix;
  double get progress => _progress;
  int get receivedBytes => _received;
  int get totalBytes => _total;
  String? get abi => _abi;
  String? get lanAddress => _lanAddress;
  bool get ignoringBatteryOptimizations => _ignoringBatteryOptimizations;
  String? get lastEvent => _lastEvent;
  int get eventRevision => _eventRevision;
  bool get isRunning => _status.running || _phase == LocalPhase.running;

  String get installedVersion => _install?.version ?? '未安装';
  String get latestVersion => _latest?.version ?? '—';

  bool get updateAvailable {
    final install = _install;
    final latest = _latest;
    if (install == null || latest == null) return false;
    return _versionNumber(install.version) < _versionNumber(latest.version);
  }

  String get apiBaseUrl => 'http://127.0.0.1:${_ports.api}';

  String get executablePath =>
      _install == null ? '' : '${_install!.directory}/mediamtx';

  String get configPath =>
      _install == null ? '' : '${_install!.directory}/mediamtx.yml';

  String get logPath =>
      _install == null ? '' : '${_install!.directory}/server.log';

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    _mirrorEnabled = await _store.readMirrorEnabled();
    _mirrorPrefix = await _store.readMirrorPrefix();
    final rawPorts = await _store.readLocalPorts();
    if (rawPorts != null) _ports = LocalServerPorts.fromJson(rawPorts);
    final rawInstall = await _store.readLocalInstall();
    if (rawInstall != null) {
      try {
        _install = LocalInstall.fromJson(rawInstall);
      } catch (_) {
        _install = null;
      }
    }
    _credentials = LocalCredentials.decode(await _store.readLocalCredentials());
    _batteryPromptShown = await _store.readBatteryPromptShown();
    if (!supported) {
      _phase = LocalPhase.unsupported;
      notifyListeners();
      return;
    }
    _abi = await _platform.abi();
    _lanAddress = await _platform.lanIp();
    _ignoringBatteryOptimizations = await _platform
        .isIgnoringBatteryOptimizations();
    await refreshStatus();
    if (_status.running) {
      await _startEventWatcher();
    }
  }

  Future<void> refreshStatus() async {
    if (!supported) {
      _phase = LocalPhase.unsupported;
      notifyListeners();
      return;
    }
    try {
      _status = await _platform.status();
      if (_status.running) {
        _phase = LocalPhase.running;
        if (_eventTimer == null) unawaited(_startEventWatcher());
      } else if (_install != null) {
        _phase = LocalPhase.stopped;
      } else {
        _phase = LocalPhase.idle;
      }
    } catch (_) {
      if (_install != null) _phase = LocalPhase.stopped;
    }
    notifyListeners();
  }

  Future<GithubRelease?> checkLatest({bool force = false}) async {
    if (!supported) return null;
    _phase = LocalPhase.checking;
    _latestError = null;
    notifyListeners();
    try {
      _latest = await _releaseService.latest(force: force);
      _error = null;
    } on ReleaseException catch (error) {
      _latestError = error.message;
    } catch (error) {
      _latestError = '检查版本失败：$error';
    } finally {
      if (!_status.running) {
        _phase = _install == null ? LocalPhase.idle : LocalPhase.stopped;
      } else {
        _phase = LocalPhase.running;
      }
      notifyListeners();
    }
    return _latest;
  }

  Future<bool> downloadAndStart() async {
    if (!supported || _busy) return false;
    _busy = true;
    _cancelled = false;
    _error = null;
    _logs = '';
    notifyListeners();
    try {
      var release = _latest;
      release ??= await checkLatest(force: true);
      if (release == null) {
        throw InstallException(_latestError ?? '无法获取最新版本');
      }
      final abi = _abi ?? await _platform.abi();
      _abi = abi;
      _phase = LocalPhase.downloading;
      _progress = 0;
      _received = 0;
      _total = 0;
      notifyListeners();

      final base = await _baseDir();
      final bundle = await _installer.install(
        release: release,
        abi: abi,
        baseDirectory: base,
        useMirror: _mirrorEnabled,
        mirrorPrefix: _mirrorPrefix,
        onProgress: (received, total) {
          if (received < 0) {
            _phase = LocalPhase.installing;
            _progress = 1;
            notifyListeners();
            return;
          }
          _received = received;
          _total = total;
          _progress = total > 0 ? received / total : 0;
          notifyListeners();
        },
        isCancelled: () => _cancelled,
      );
      if (_cancelled) throw const _InstallCancelled();

      _phase = LocalPhase.installing;
      notifyListeners();
      final credentials = _credentials ?? _generateCredentials();
      final config = buildConfig(ports: _ports, credentials: credentials);
      final configFile = File('${bundle.directory}/mediamtx.yml');
      await configFile.writeAsString(config, flush: true);
      final oldInstall = _install;
      _credentials = credentials;
      _install = bundle.install;
      await _store.writeLocalCredentials(credentials.encode());
      await _store.saveLocalInstall(bundle.install.toJson());
      await _store.saveLocalPorts(_ports.toJson());

      if (_status.running) {
        await _platform.stop();
        await Future<void>.delayed(const Duration(milliseconds: 600));
      }

      _phase = LocalPhase.starting;
      notifyListeners();
      await _startNative(bundle.install);
      final reachable = await _waitForApi(credentials);
      if (!reachable) {
        _status = await _platform.status();
        _logs = await _platform.readLog();
        _phase = LocalPhase.error;
        _error = _status.running
            ? '进程已启动，但 API 在 ${_ports.api} 端口没有响应。请检查端口冲突或查看日志。'
            : 'MediaMTX 进程启动后立即退出，请查看日志了解原因。';
        notifyListeners();
        return false;
      }
      _lanAddress = await _platform.lanIp();
      _status = await _platform.status();
      _phase = LocalPhase.running;
      _error = null;
      _progress = 1;
      unawaited(_startEventWatcher());
      notifyListeners();
      if (oldInstall != null &&
          oldInstall.directory != bundle.install.directory) {
        unawaited(() async {
          try {
            await _installer.deleteVersion(oldInstall);
          } catch (_) {}
        }());
      }
      return true;
    } on _InstallCancelled {
      _phase = _install == null ? LocalPhase.idle : LocalPhase.stopped;
      _progress = 0;
      notifyListeners();
      return false;
    } on InstallException catch (error) {
      _phase = LocalPhase.error;
      _error = error.message;
      notifyListeners();
      return false;
    } catch (error) {
      if (_cancelled) {
        _phase = _install == null ? LocalPhase.idle : LocalPhase.stopped;
        _progress = 0;
        _error = null;
      } else {
        _phase = LocalPhase.error;
        _error = '安装失败：$error';
      }
      notifyListeners();
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<bool> start() async {
    if (!supported || _busy) return false;
    final install = _install;
    if (install == null) {
      _error = '尚未安装 MediaMTX';
      notifyListeners();
      return false;
    }
    _busy = true;
    _error = null;
    _phase = LocalPhase.starting;
    notifyListeners();
    try {
      final credentials = _credentials ?? _generateCredentials();
      _credentials = credentials;
      final configFile = File('${install.directory}/mediamtx.yml');
      if (!await configFile.exists()) {
        await configFile.writeAsString(
          buildConfig(ports: _ports, credentials: credentials),
          flush: true,
        );
      }
      await _store.writeLocalCredentials(credentials.encode());
      await _startNative(install);
      final reachable = await _waitForApi(credentials);
      _status = await _platform.status();
      if (!reachable) {
        _logs = await _platform.readLog();
        _phase = LocalPhase.error;
        _error = _status.running
            ? '服务进程正在运行，但 API 未响应，请查看日志。'
            : '服务进程启动失败，请查看日志。';
        return false;
      }
      _phase = LocalPhase.running;
      unawaited(_startEventWatcher());
      return true;
    } catch (error) {
      _phase = LocalPhase.error;
      _error = '启动失败：$error';
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<void> _startNative(LocalInstall install) async {
    final configFile = File('${install.directory}/mediamtx.yml');
    if (!await configFile.exists()) {
      final credentials = _credentials ?? _generateCredentials();
      _credentials = credentials;
      await configFile.writeAsString(
        buildConfig(ports: _ports, credentials: credentials),
        flush: true,
      );
    }
    await _platform.start(
      executable: '${install.directory}/mediamtx',
      workdir: install.directory,
      config: configFile.path,
      log: '${install.directory}/server.log',
    );
  }

  Future<bool> _waitForApi(LocalCredentials credentials) async {
    for (var attempt = 0; attempt < 24; attempt++) {
      final client = ApiClient(
        baseUrl: apiBaseUrl,
        authMethod: ServerAuthMethod.basic,
        username: credentials.user,
        secret: credentials.pass,
        timeout: const Duration(seconds: 2),
      );
      try {
        await client.getMap('/v3/info');
        return true;
      } on ApiException {
        final running = await _platform.status();
        if (!running.running && attempt > 2) return false;
        await Future<void>.delayed(const Duration(milliseconds: 600));
      } finally {
        client.close();
      }
    }
    return false;
  }

  Future<void> stop() async {
    if (_busy || !supported) return;
    _stopEventWatcher();
    _busy = true;
    _phase = LocalPhase.stopping;
    notifyListeners();
    try {
      await _platform.stop();
      for (var i = 0; i < 8; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 350));
        _status = await _platform.status();
        if (!_status.running) break;
      }
      if (_status.running) {
        _phase = LocalPhase.error;
        _error = '服务没有在预期时间内停止，请稍后重试';
      } else {
        _phase = _install == null ? LocalPhase.idle : LocalPhase.stopped;
        _error = null;
      }
    } catch (error) {
      _error = '停止失败：$error';
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<void> restart() async {
    await stop();
    await start();
  }

  Future<void> loadLogs() async {
    if (!supported) return;
    try {
      _logs = await _platform.readLog();
      notifyListeners();
    } catch (_) {}
  }

  Future<void> savePorts(LocalServerPorts ports) async {
    final error = ports.validate();
    if (error != null) throw InstallException(error);
    final changed = jsonEncode(ports.toJson()) != jsonEncode(_ports.toJson());
    _ports = ports;
    await _store.saveLocalPorts(ports.toJson());
    if (changed && _install != null) {
      final credentials = _credentials ?? _generateCredentials();
      _credentials = credentials;
      await File('${_install!.directory}/mediamtx.yml').writeAsString(
        buildConfig(ports: _ports, credentials: credentials),
        flush: true,
      );
      await _store.writeLocalCredentials(credentials.encode());
      if (_status.running) {
        await restart();
      }
    }
    notifyListeners();
  }

  Future<bool> consumeBatteryPrompt() async {
    if (!supported || _batteryPromptShown) return false;
    if (_ignoringBatteryOptimizations) return false;
    _batteryPromptShown = true;
    await _store.saveBatteryPromptShown();
    return true;
  }

  Future<void> refreshBatteryOptimizationStatus() async {
    if (!supported) return;
    _ignoringBatteryOptimizations = await _platform
        .isIgnoringBatteryOptimizations();
    notifyListeners();
  }

  Future<void> requestBatteryOptimizationExemption() async {
    await _platform.requestIgnoreBatteryOptimizations();
    await Future<void>.delayed(const Duration(seconds: 1));
    await refreshBatteryOptimizationStatus();
  }

  Future<void> openAppSettings() => _platform.openAppSettings();

  Future<void> shareLog() => _platform.shareLog();

  Future<void> openDocuments() => _platform.openDocuments();

  Future<void> setMirror({required bool enabled, String? prefix}) async {
    _mirrorEnabled = enabled;
    if (prefix != null && prefix.trim().isNotEmpty) {
      _mirrorPrefix = prefix.trim();
      await _store.saveMirrorPrefix(_mirrorPrefix);
    }
    await _store.saveMirrorEnabled(enabled);
    notifyListeners();
  }

  Future<void> uninstall() async {
    await stop();
    final install = _install;
    if (install != null) {
      await _installer.deleteVersion(install);
    }
    _install = null;
    _status = LocalServerStatus.stopped;
    _phase = LocalPhase.idle;
    _logs = '';
    await _store.saveLocalInstall(null);
    await _store.deleteLocalCredentials();
    _credentials = null;
    notifyListeners();
  }

  void cancelDownload() {
    if (_phase == LocalPhase.downloading) {
      _cancelled = true;
      notifyListeners();
    }
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  Future<void> _startEventWatcher() async {
    if (!supported) return;
    _eventTimer?.cancel();
    _lastLogTail = await _platform.readLog(maxBytes: 24000);
    _eventTimer = Timer.periodic(const Duration(milliseconds: 1400), (_) {
      unawaited(_pollEvents());
    });
  }

  void _stopEventWatcher() {
    _eventTimer?.cancel();
    _eventTimer = null;
    _lastLogTail = '';
  }

  Future<void> resetEventBaseline() async {
    if (!supported) return;
    _lastLogTail = await _platform.readLog(maxBytes: 24000);
    _lastEvent = null;
  }

  Future<void> _pollEvents() async {
    if (_pollingEvents || !_status.running) return;
    _pollingEvents = true;
    try {
      final current = await _platform.readLog(maxBytes: 24000);
      if (current.isEmpty || current == _lastLogTail) return;
      final appended = current.startsWith(_lastLogTail)
          ? current.substring(_lastLogTail.length)
          : current;
      _lastLogTail = current;
      for (final line in const LineSplitter().convert(appended)) {
        final event = _parseEvent(line);
        if (event != null) {
          _lastEvent = event;
          _eventRevision++;
          notifyListeners();
        }
      }
    } catch (_) {
    } finally {
      _pollingEvents = false;
    }
  }

  String? _parseEvent(String line) {
    if (line.contains('[HLS]')) return null;
    final pathMatch = RegExp(r"path '([^']+)'").firstMatch(line);
    final path = pathMatch?.group(1);
    if (line.contains('is publishing to path') && path != null) {
      return '开始推流 · $path';
    }
    if (line.contains('is reading from path') && path != null) {
      return '新增观看 · $path';
    }
    if (line.contains('stream is offline')) {
      final offline = RegExp(r'\[path ([^\]]+)\]').firstMatch(line);
      if (offline != null) return '流已离线 · ${offline.group(1)}';
    }
    if (line.contains('] closed')) return '一个媒体会话已断开';
    return null;
  }

  String buildConfig({
    required LocalServerPorts ports,
    required LocalCredentials credentials,
  }) {
    return '''
# Generated by MTX Console. This file is managed by the app.
logLevel: info
logDestinations: [stdout]

api: yes
apiAddress: 0.0.0.0:${ports.api}
apiAllowOrigins: ['*']

metrics: no
playback: no
moq: no

rtsp: yes
rtspAddress: 0.0.0.0:${ports.rtsp}
rtpAddress: 0.0.0.0:${ports.rtp}
rtcpAddress: 0.0.0.0:${ports.rtcp}

rtmp: yes
rtmpAddress: 0.0.0.0:${ports.rtmp}

hls: yes
hlsAddress: 0.0.0.0:${ports.hls}

webrtc: yes
webrtcAddress: 0.0.0.0:${ports.webrtc}
webrtcLocalUDPAddress: 0.0.0.0:${ports.webrtcUdp}

srt: yes
srtAddress: 0.0.0.0:${ports.srt}

authMethod: internal
authInternalUsers:
  - user: ${_yaml(credentials.user)}
    pass: ${_yaml(credentials.pass)}
    permissions:
      - action: api
  - user: any
    pass:
    permissions:
      - action: publish
      - action: read

paths:
  all_others:
''';
  }

  String _yaml(String value) {
    if (RegExp(r'^[A-Za-z0-9_.-]+$').hasMatch(value)) return value;
    return "'${value.replaceAll("'", "''")}'";
  }

  LocalCredentials _generateCredentials() {
    const alphabet =
        'abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final random = Random.secure();
    return LocalCredentials(
      user: 'mtxadmin',
      pass: List.generate(
        20,
        (_) => alphabet[random.nextInt(alphabet.length)],
      ).join(),
    );
  }

  Future<Directory> _baseDir() async {
    final cached = _baseDirectory;
    if (cached != null) return cached;
    final support = await getApplicationSupportDirectory();
    final dir = Directory('${support.path}/mediamtx');
    await dir.create(recursive: true);
    _baseDirectory = dir;
    return dir;
  }

  num _versionNumber(String version) {
    final parts = version
        .replaceFirst('v', '')
        .split('.')
        .map((part) => int.tryParse(part.replaceAll(RegExp(r'\D'), '')) ?? 0)
        .toList();
    while (parts.length < 3) {
      parts.add(0);
    }
    return parts[0] * 1000000 + parts[1] * 1000 + parts[2];
  }

  @override
  void dispose() {
    _stopEventWatcher();
    _releaseService.close();
    super.dispose();
  }
}

class _InstallCancelled implements Exception {
  const _InstallCancelled();
}
