import 'dart:convert';

import 'package:http/http.dart' as http;

class ReleaseException implements Exception {
  const ReleaseException(this.message);

  final String message;

  @override
  String toString() => message;
}

class GithubRelease {
  const GithubRelease({
    required this.version,
    required this.assets,
    this.publishedAt,
  });

  final String version;
  final Map<String, String> assets;
  final DateTime? publishedAt;

  String? assetUrl(String name) => assets[name];

  String? checksumsUrl() => assets['checksums.sha256'];

  factory GithubRelease.fromApi(Map<String, dynamic> json) {
    final tag = (json['tag_name'] ?? '').toString();
    final assets = <String, String>{};
    final rawAssets = json['assets'];
    if (rawAssets is List) {
      for (final item in rawAssets.whereType<Map>()) {
        final name = (item['name'] ?? '').toString();
        final url = (item['browser_download_url'] ?? '').toString();
        if (name.isNotEmpty && url.isNotEmpty) assets[name] = url;
      }
    }
    return GithubRelease(
      version: tag,
      assets: assets,
      publishedAt: DateTime.tryParse((json['published_at'] ?? '').toString()),
    );
  }

  factory GithubRelease.fromVersion(String version) {
    final base =
        'https://github.com/bluenviron/mediamtx/releases/download/$version';
    final assets = <String, String>{
      'checksums.sha256': '$base/checksums.sha256',
      for (final platform in [
        'linux_amd64',
        'linux_arm64',
        'linux_armv7',
        'linux_armv6',
      ])
        'mediamtx_${version}_$platform.tar.gz':
            '$base/mediamtx_${version}_$platform.tar.gz',
    };
    return GithubRelease(version: version, assets: assets);
  }

  static bool validVersion(String version) =>
      RegExp(r'^v\d+\.\d+\.\d+$').hasMatch(version.trim());
}

class GithubReleaseService {
  GithubReleaseService({http.Client? client})
    : _client = client ?? http.Client();

  final http.Client _client;
  GithubRelease? _cached;
  DateTime? _cachedAt;

  Future<GithubRelease> latest({bool force = false}) async {
    final cached = _cached;
    if (!force &&
        cached != null &&
        _cachedAt != null &&
        DateTime.now().difference(_cachedAt!) < const Duration(minutes: 10)) {
      return cached;
    }

    final apiUrl = Uri.parse(
      'https://api.github.com/repos/bluenviron/mediamtx/releases/latest',
    );
    try {
      final response = await _client
          .get(
            apiUrl,
            headers: const {
              'Accept': 'application/vnd.github+json',
              'User-Agent': 'MTX-Console/1.0',
            },
          )
          .timeout(const Duration(seconds: 20));
      if (response.statusCode == 200) {
        final decoded = jsonDecode(utf8.decode(response.bodyBytes));
        if (decoded is Map) {
          final release = GithubRelease.fromApi(
            Map<String, dynamic>.from(decoded),
          );
          if (GithubRelease.validVersion(release.version)) {
            _cached = release;
            _cachedAt = DateTime.now();
            return release;
          }
        }
      }
      if (response.statusCode == 403 || response.statusCode == 429) {
        // Rate limited. Fall back to the latest release redirect.
      }
    } catch (_) {
      // Fall through to the redirect method.
    }

    final version = await _versionFromRedirect();
    if (version == null) {
      throw const ReleaseException('无法获取最新版本信息，请检查网络或稍后重试');
    }
    final release = GithubRelease.fromVersion(version);
    _cached = release;
    _cachedAt = DateTime.now();
    return release;
  }

  Future<String?> _versionFromRedirect() async {
    try {
      final request = http.Request(
        'GET',
        Uri.parse('https://github.com/bluenviron/mediamtx/releases/latest'),
      )..followRedirects = false;
      request.headers['User-Agent'] = 'MTX-Console/1.0';
      final response = await _client
          .send(request)
          .timeout(const Duration(seconds: 20));
      final location = response.headers['location'];
      if (location == null) return null;
      final match = RegExp(r'/tag/(v\d+\.\d+\.\d+)').firstMatch(location);
      return match?.group(1);
    } catch (_) {
      return null;
    }
  }

  String withMirror(String url, String mirrorPrefix) {
    var prefix = mirrorPrefix.trim();
    if (prefix.isEmpty) return url;
    if (!prefix.startsWith('http://') && !prefix.startsWith('https://')) {
      prefix = 'https://$prefix';
    }
    if (!prefix.endsWith('/')) prefix = '$prefix/';
    return '$prefix$url';
  }

  void close() => _client.close();
}
