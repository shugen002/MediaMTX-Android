import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/api/api_client.dart';
import '../data/api/api_exception.dart';
import '../data/api/mediamtx_service.dart';
import '../data/models/media_snapshot.dart';
import '../data/models/path_config.dart';
import '../data/models/runtime_path.dart';
import '../data/models/server_profile.dart';
import '../data/repositories/server_store.dart';

enum ServerConnectionStatus { idle, connecting, online, offline }

class AppState extends ChangeNotifier {
  AppState({ServerStore? store, this.autoConnect = true})
    : _store = store ?? ServerStore();

  final ServerStore _store;
  final bool autoConnect;

  final List<ServerProfile> _servers = [];
  ServerProfile? _active;
  ApiClient? _api;
  MediaMtxService? _service;
  ServerConnectionStatus _status = ServerConnectionStatus.idle;
  String? _error;
  MediaSnapshot? _snapshot;
  SessionSummary _sessions = SessionSummary.empty;
  Map<String, dynamic>? _globalConfig;
  final List<TrafficSample> _traffic = [];
  Timer? _timer;
  bool _refreshing = false;
  bool _disposed = false;
  bool _booting = true;
  bool _showServerList = false;
  int _refreshTick = 0;
  int _generation = 0;
  int _refreshSeconds = 10;

  ThemeMode _themeMode = ThemeMode.system;

  bool get isBooting => _booting;
  bool get showServerList => _showServerList;
  List<ServerProfile> get servers => List.unmodifiable(_servers);
  ServerProfile? get active => _active;
  ServerConnectionStatus get status => _status;
  String? get error => _error;
  MediaSnapshot? get snapshot => _snapshot;
  SessionSummary get sessions => _sessions;
  Map<String, dynamic>? get globalConfig => _globalConfig;
  List<TrafficSample> get traffic => List.unmodifiable(_traffic);
  int get refreshSeconds => _refreshSeconds;
  ThemeMode get themeMode => _themeMode;
  bool get isConnected =>
      _active != null &&
      _snapshot != null &&
      _status != ServerConnectionStatus.offline;
  MediaMtxService? get service => _service;
  MediaMtxService get requireService {
    final value = _service;
    if (value == null) {
      throw const ApiException('尚未连接到服务器', kind: ApiErrorKind.network);
    }
    return value;
  }

  double get inboundRate => _traffic.isEmpty ? 0 : _traffic.last.inboundRate;

  double get outboundRate => _traffic.isEmpty ? 0 : _traffic.last.outboundRate;

  Future<void> initialize() async {
    try {
      _servers
        ..clear()
        ..addAll(await _store.loadProfiles());
      _refreshSeconds = await _store.readRefreshSeconds();
      _themeMode = _modeFromString(await _store.readThemeMode());
      if (autoConnect) {
        final lastId = await _store.readLastServerId();
        if (lastId != null) {
          final profile = _serverById(lastId);
          if (profile != null) {
            await connect(profile, silent: true);
          }
        }
      }
    } finally {
      _booting = false;
      _safeNotify();
    }
  }

  ServerProfile? _serverById(String id) {
    for (final server in _servers) {
      if (server.id == id) return server;
    }
    return null;
  }

  Future<bool> connect(ServerProfile profile, {bool silent = false}) async {
    _generation++;
    _showServerList = false;
    _timer?.cancel();
    _api?.close();
    _api = null;
    _service = null;
    _active = profile;
    _status = ServerConnectionStatus.connecting;
    _error = null;
    _snapshot = null;
    _globalConfig = null;
    _traffic.clear();
    _sessions = SessionSummary.empty;
    if (!silent) _safeNotify();

    final secret = profile.authMethod == ServerAuthMethod.none
        ? ''
        : await _store.readSecret(profile.id) ?? '';

    final api = ApiClient(
      baseUrl: profile.baseUrl,
      authMethod: profile.authMethod,
      username: profile.username,
      secret: secret,
      allowBadCertificates: profile.allowSelfSigned,
    );
    final service = MediaMtxService(api);

    try {
      final info = await service.info();
      final results = await Future.wait([
        service.paths(),
        service.pathConfigs(),
      ]);
      final paths = results[0] as List<RuntimePath>;
      final configs = results[1] as List<PathConfig>;
      Map<String, dynamic>? global;
      try {
        global = await service.globalConfig();
      } on ApiException {
        global = null;
      }

      _api = api;
      _service = service;
      _globalConfig = global;
      _snapshot = MediaSnapshot(
        info: info,
        paths: paths,
        configs: configs,
        fetchedAt: DateTime.now(),
      );
      _traffic
        ..clear()
        ..add(
          TrafficSample(
            time: DateTime.now(),
            inboundRate: 0,
            outboundRate: 0,
            totalInbound: _snapshot!.inboundBytes,
            totalOutbound: _snapshot!.outboundBytes,
          ),
        );
      _status = ServerConnectionStatus.online;
      _error = null;
      _refreshTick = 0;
      final index = _servers.indexWhere((server) => server.id == profile.id);
      if (index >= 0) {
        _servers[index] = _servers[index].copyWith(
          lastConnectedAt: DateTime.now(),
        );
        _active = _servers[index];
      }
      await _store.saveProfiles(_servers);
      await _store.saveLastServerId(profile.id);
      _startTimer();
      _safeNotify();
      unawaited(refreshSessionCounts());
      return true;
    } on ApiException catch (error) {
      api.close();
      _status = ServerConnectionStatus.offline;
      _error = error.friendlyMessage;
      _safeNotify();
      return false;
    } catch (error) {
      api.close();
      _status = ServerConnectionStatus.offline;
      _error = '连接失败：$error';
      _safeNotify();
      return false;
    }
  }

  Future<void> refresh({bool silent = false, bool withSessions = false}) async {
    final service = _service;
    if (service == null || _refreshing) return;
    final generation = _generation;
    _refreshing = true;
    try {
      final info = await service.info();
      final results = await Future.wait([
        service.paths(),
        service.pathConfigs(),
      ]);
      if (generation != _generation) return;
      final fetchedAt = DateTime.now();
      _snapshot = MediaSnapshot(
        info: info,
        paths: results[0] as List<RuntimePath>,
        configs: results[1] as List<PathConfig>,
        fetchedAt: fetchedAt,
      );
      _recordTraffic(fetchedAt);
      _status = ServerConnectionStatus.online;
      _error = null;
      _refreshTick++;
      if (withSessions || _refreshTick % 3 == 0) {
        unawaited(refreshSessionCounts());
      }
      _safeNotify();
    } on ApiException catch (error) {
      _status = ServerConnectionStatus.offline;
      _error = error.friendlyMessage;
      _safeNotify();
    } catch (error) {
      _status = ServerConnectionStatus.offline;
      _error = '刷新失败：$error';
      _safeNotify();
    } finally {
      _refreshing = false;
    }
  }

  Future<void> refreshSessionCounts() async {
    final service = _service;
    if (service == null) return;
    final generation = _generation;
    try {
      final counts = await service.sessionCounts();
      if (generation != _generation) return;
      _sessions = SessionSummary(counts: counts, fetchedAt: DateTime.now());
      _safeNotify();
    } on ApiException {
      // Session statistics are supplementary; keep the last known values.
    }
  }

  Future<void> loadGlobalConfig() async {
    final service = _service;
    if (service == null) return;
    final generation = _generation;
    final config = await service.globalConfig();
    if (generation != _generation) return;
    _globalConfig = config;
    _safeNotify();
  }

  void _recordTraffic(DateTime now) {
    final snapshot = _snapshot;
    if (snapshot == null) return;
    final totalIn = snapshot.inboundBytes;
    final totalOut = snapshot.outboundBytes;
    final previous = _traffic.isEmpty ? null : _traffic.last;
    var rateIn = 0.0;
    var rateOut = 0.0;
    if (previous != null) {
      final seconds = now.difference(previous.time).inMilliseconds / 1000;
      if (seconds > 0.2) {
        rateIn = math.max(0, totalIn - previous.totalInbound) / seconds;
        rateOut = math.max(0, totalOut - previous.totalOutbound) / seconds;
      }
    }
    _traffic.add(
      TrafficSample(
        time: now,
        inboundRate: rateIn,
        outboundRate: rateOut,
        totalInbound: totalIn,
        totalOutbound: totalOut,
      ),
    );
    if (_traffic.length > 30) {
      _traffic.removeRange(0, _traffic.length - 30);
    }
  }

  void _startTimer() {
    _timer?.cancel();
    if (_refreshSeconds <= 0) return;
    _timer = Timer.periodic(Duration(seconds: _refreshSeconds), (_) {
      unawaited(refresh(silent: true));
    });
  }

  Future<void> setRefreshSeconds(int seconds) async {
    _refreshSeconds = seconds;
    await _store.saveRefreshSeconds(seconds);
    if (isConnected) _startTimer();
    _safeNotify();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    await _store.saveThemeMode(mode.name);
    _safeNotify();
  }

  Future<void> saveServer(ServerProfile profile, {String? secret}) async {
    final index = _servers.indexWhere((server) => server.id == profile.id);
    if (index >= 0) {
      _servers[index] = profile;
    } else {
      _servers.add(profile);
    }
    if (profile.authMethod == ServerAuthMethod.none) {
      await _store.deleteSecret(profile.id);
    } else if (secret != null) {
      await _store.writeSecret(profile.id, secret);
    }
    await _store.saveProfiles(_servers);
    if (_active?.id == profile.id) {
      _active = profile;
    }
    _safeNotify();
  }

  Future<void> deleteServer(ServerProfile profile) async {
    _servers.removeWhere((server) => server.id == profile.id);
    await _store.deleteSecret(profile.id);
    await _store.saveProfiles(_servers);
    if (_active?.id == profile.id) {
      await disconnect();
    }
    _safeNotify();
  }

  Future<void> disconnect() async {
    _generation++;
    _showServerList = false;
    _timer?.cancel();
    _api?.close();
    _api = null;
    _service = null;
    _active = null;
    _snapshot = null;
    _globalConfig = null;
    _traffic.clear();
    _sessions = SessionSummary.empty;
    _status = ServerConnectionStatus.idle;
    _error = null;
    await _store.saveLastServerId(null);
    _safeNotify();
  }

  Future<String?> readSecret(String profileId) => _store.readSecret(profileId);

  Future<void> updateLocalProfile({
    required String baseUrl,
    required String username,
    required String secret,
  }) async {
    final existing = _servers.where((server) => server.isLocal).toList();
    final profile = existing.isNotEmpty
        ? existing.first.copyWith(
            name: '本机 MediaMTX',
            baseUrl: baseUrl,
            username: username,
            authMethod: ServerAuthMethod.basic,
          )
        : ServerProfile(
            id: ServerProfile.newId(),
            name: '本机 MediaMTX',
            baseUrl: baseUrl,
            username: username,
            authMethod: ServerAuthMethod.basic,
            isLocal: true,
            createdAt: DateTime.now(),
          );
    await saveServer(profile, secret: secret);
    for (final duplicate in existing.skip(1)) {
      await deleteServer(duplicate);
    }
  }

  Future<void> connectToProfileId(String id) async {
    final profile = _serverById(id);
    if (profile != null) await connect(profile);
  }

  Future<bool> connectToLocalServer({
    required String baseUrl,
    required String username,
    required String secret,
  }) async {
    await updateLocalProfile(
      baseUrl: baseUrl,
      username: username,
      secret: secret,
    );
    ServerProfile? profile;
    for (final server in _servers) {
      if (server.isLocal) {
        profile = server;
        break;
      }
    }
    if (profile == null) return false;
    return connect(profile);
  }

  void showServers() {
    if (_showServerList) return;
    _showServerList = true;
    _safeNotify();
  }

  void resumeShell() {
    if (!_showServerList) return;
    _showServerList = false;
    _safeNotify();
  }

  void clearError() {
    if (_error == null) return;
    _error = null;
    _safeNotify();
  }

  ThemeMode _modeFromString(String value) {
    return switch (value) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
  }

  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _api?.close();
    super.dispose();
  }
}
