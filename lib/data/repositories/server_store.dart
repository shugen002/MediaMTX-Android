// ignore_for_file: prefer_initializing_formals
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/server_profile.dart';

abstract class SecretVault {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class SecureSecretVault implements SecretVault {
  SecureSecretVault({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;
  final Map<String, String> _fallback = {};

  @override
  Future<String?> read(String key) async {
    try {
      return await _storage.read(key: key);
    } catch (_) {
      return _fallback[key];
    }
  }

  @override
  Future<void> write(String key, String value) async {
    _fallback[key] = value;
    try {
      await _storage.write(key: key, value: value);
    } catch (_) {
      // Keep the in-memory copy; the UI will still work for this session.
    }
  }

  @override
  Future<void> delete(String key) async {
    _fallback.remove(key);
    try {
      await _storage.delete(key: key);
    } catch (_) {
      // Ignore platform keystore errors.
    }
  }
}

class MemorySecretVault implements SecretVault {
  final Map<String, String> _values = {};

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async => _values[key] = value;

  @override
  Future<void> delete(String key) async => _values.remove(key);
}

class ServerStore {
  ServerStore({SecretVault? vault, SharedPreferences? preferences})
    : _vault = vault ?? SecureSecretVault(),
      _preferences = preferences;

  static const _profilesKey = 'mtx.profiles.v1';
  static const _themeKey = 'mtx.theme';
  static const _refreshKey = 'mtx.refreshSeconds';
  static const _lastServerKey = 'mtx.lastServer';
  static const _mirrorKey = 'mtx.githubMirror';
  static const _mirrorEnabledKey = 'mtx.githubMirrorEnabled';
  static const _localPortsKey = 'mtx.localPorts';
  static const _localInstallKey = 'mtx.localInstall';
  static const _batteryPromptKey = 'mtx.batteryPromptShown';

  final SecretVault _vault;
  SharedPreferences? _preferences;

  Future<SharedPreferences> get _prefs async =>
      _preferences ??= await SharedPreferences.getInstance();

  Future<List<ServerProfile>> loadProfiles() async {
    final prefs = await _prefs;
    final raw = prefs.getString(_profilesKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return decoded
          .whereType<Map>()
          .map(
            (item) => ServerProfile.fromJson(Map<String, dynamic>.from(item)),
          )
          .where((profile) => profile.id.isNotEmpty)
          .toList(growable: true);
    } catch (_) {
      return [];
    }
  }

  Future<void> saveProfiles(List<ServerProfile> profiles) async {
    final prefs = await _prefs;
    await prefs.setString(
      _profilesKey,
      jsonEncode(profiles.map((profile) => profile.toJson()).toList()),
    );
  }

  Future<String?> readSecret(String profileId) {
    return _vault.read('mtx.secret.$profileId');
  }

  Future<void> writeSecret(String profileId, String secret) {
    return _vault.write('mtx.secret.$profileId', secret);
  }

  Future<void> deleteSecret(String profileId) {
    return _vault.delete('mtx.secret.$profileId');
  }

  Future<String?> readLastServerId() async {
    return (await _prefs).getString(_lastServerKey);
  }

  Future<void> saveLastServerId(String? id) async {
    final prefs = await _prefs;
    if (id == null) {
      await prefs.remove(_lastServerKey);
    } else {
      await prefs.setString(_lastServerKey, id);
    }
  }

  Future<String> readThemeMode() async {
    return (await _prefs).getString(_themeKey) ?? 'system';
  }

  Future<void> saveThemeMode(String mode) async {
    await (await _prefs).setString(_themeKey, mode);
  }

  Future<int> readRefreshSeconds() async {
    return (await _prefs).getInt(_refreshKey) ?? 10;
  }

  Future<void> saveRefreshSeconds(int seconds) async {
    await (await _prefs).setInt(_refreshKey, seconds);
  }

  Future<bool> readMirrorEnabled() async {
    return (await _prefs).getBool(_mirrorEnabledKey) ?? true;
  }

  Future<void> saveMirrorEnabled(bool enabled) async {
    await (await _prefs).setBool(_mirrorEnabledKey, enabled);
  }

  Future<String> readMirrorPrefix() async {
    return (await _prefs).getString(_mirrorKey) ?? 'https://ghfast.top/';
  }

  Future<void> saveMirrorPrefix(String value) async {
    await (await _prefs).setString(_mirrorKey, value);
  }

  Future<Map<String, dynamic>?> readLocalPorts() async {
    final raw = (await _prefs).getString(_localPortsKey);
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {}
    return null;
  }

  Future<void> saveLocalPorts(Map<String, dynamic> ports) async {
    await (await _prefs).setString(_localPortsKey, jsonEncode(ports));
  }

  Future<String?> readLocalCredentials() {
    return _vault.read('mtx.localCredentials');
  }

  Future<void> writeLocalCredentials(String value) {
    return _vault.write('mtx.localCredentials', value);
  }

  Future<void> deleteLocalCredentials() {
    return _vault.delete('mtx.localCredentials');
  }

  Future<bool> readBatteryPromptShown() async {
    return (await _prefs).getBool(_batteryPromptKey) ?? false;
  }

  Future<void> saveBatteryPromptShown() async {
    await (await _prefs).setBool(_batteryPromptKey, true);
  }

  Future<Map<String, dynamic>?> readLocalInstall() async {
    final raw = (await _prefs).getString(_localInstallKey);
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {}
    return null;
  }

  Future<void> saveLocalInstall(Map<String, dynamic>? install) async {
    final prefs = await _prefs;
    if (install == null) {
      await prefs.remove(_localInstallKey);
    } else {
      await prefs.setString(_localInstallKey, jsonEncode(install));
    }
  }
}
