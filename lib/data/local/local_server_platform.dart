import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/local_server_models.dart';

class LocalServerPlatform {
  static const _channel = MethodChannel('io.mediamtx.console/local_server');

  bool get isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<String> abi() async {
    if (!isSupported) return 'x86_64';
    try {
      return await _channel.invokeMethod<String>('abi') ?? 'arm64-v8a';
    } on PlatformException {
      return 'arm64-v8a';
    }
  }

  Future<void> start({
    required String executable,
    required String workdir,
    required String config,
    required String log,
  }) async {
    if (!isSupported) {
      throw UnsupportedError('本机运行仅支持 Android');
    }
    await _channel.invokeMethod<bool>('start', {
      'executable': executable,
      'workdir': workdir,
      'config': config,
      'log': log,
    });
  }

  Future<void> stop() async {
    if (!isSupported) return;
    await _channel.invokeMethod<bool>('stop');
  }

  Future<LocalServerStatus> status() async {
    if (!isSupported) return LocalServerStatus.stopped;
    final map = await _channel.invokeMapMethod<String, dynamic>('status');
    return LocalServerStatus.fromMap(map);
  }

  Future<String?> lanIp() async {
    if (!isSupported) return null;
    try {
      return await _channel.invokeMethod<String>('lanIp');
    } catch (_) {
      return null;
    }
  }

  Future<bool> isIgnoringBatteryOptimizations() async {
    if (!isSupported) return true;
    try {
      return await _channel.invokeMethod<bool>(
            'isIgnoringBatteryOptimizations',
          ) ??
          false;
    } catch (_) {
      return false;
    }
  }

  Future<void> requestIgnoreBatteryOptimizations() async {
    if (!isSupported) return;
    await _channel.invokeMethod<bool>('requestIgnoreBatteryOptimizations');
  }

  Future<void> openAppSettings() async {
    if (!isSupported) return;
    await _channel.invokeMethod<bool>('openAppSettings');
  }

  Future<void> shareLog() async {
    if (!isSupported) return;
    await _channel.invokeMethod<bool>('shareLog');
  }

  Future<void> openDocuments() async {
    if (!isSupported) return;
    await _channel.invokeMethod<bool>('openDocuments');
  }

  Future<String> readLog({int maxBytes = 200000}) async {
    if (!isSupported) return '';
    return await _channel.invokeMethod<String>('readLog', {
          'maxBytes': maxBytes,
        }) ??
        '';
  }
}
