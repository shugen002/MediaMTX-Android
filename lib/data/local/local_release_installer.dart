import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import '../api/github_release_service.dart';
import '../models/local_server_models.dart';

class InstallException implements Exception {
  const InstallException(this.message);

  final String message;

  @override
  String toString() => message;
}

class _Cancelled implements Exception {
  const _Cancelled();
}

class InstallBundle {
  const InstallBundle({
    required this.install,
    required this.executablePath,
    required this.directory,
  });

  final LocalInstall install;
  final String executablePath;
  final String directory;
}

class LocalReleaseInstaller {
  LocalReleaseInstaller({
    http.Client? client,
    GithubReleaseService? releaseService,
  }) : _client = client ?? http.Client(),
       _releaseService = releaseService ?? GithubReleaseService();

  final http.Client _client;
  final GithubReleaseService _releaseService;

  String platformForAbi(String abi) {
    final value = abi.toLowerCase();
    if (value.contains('arm64') || value == 'aarch64') return 'linux_arm64';
    if (value.contains('armeabi-v7a') || value == 'armv7l') {
      return 'linux_armv7';
    }
    if (value.contains('armeabi') || value == 'armv6l') return 'linux_armv6';
    if (value.contains('x86_64') || value == 'amd64') return 'linux_amd64';
    throw InstallException('当前设备架构（$abi）没有可用的 MediaMTX 构建');
  }

  String assetName(GithubRelease release, String abi) {
    return 'mediamtx_${release.version}_${platformForAbi(abi)}.tar.gz';
  }

  Future<InstallBundle> install({
    required GithubRelease release,
    required String abi,
    required Directory baseDirectory,
    required bool useMirror,
    required String mirrorPrefix,
    required void Function(int received, int total) onProgress,
    bool Function()? isCancelled,
  }) async {
    final platform = platformForAbi(abi);
    final asset = assetName(release, abi);
    final sourceUrl =
        release.assetUrl(asset) ??
        'https://github.com/bluenviron/mediamtx/releases/download/${release.version}/$asset';
    final workDir = Directory('${baseDirectory.path}/work');
    await workDir.create(recursive: true);
    final archiveFile = File('${workDir.path}/$asset');
    final partial = File('${archiveFile.path}.part');

    final urls = <String>[
      if (useMirror) _releaseService.withMirror(sourceUrl, mirrorPrefix),
      sourceUrl,
    ];
    Object? lastError;
    var downloaded = false;
    for (final url in urls) {
      try {
        if (await partial.exists()) await partial.delete();
        await _download(
          url: url,
          target: partial,
          onProgress: onProgress,
          isCancelled: isCancelled,
        );
        downloaded = true;
        break;
      } catch (error) {
        lastError = error;
        if (error is _Cancelled) rethrow;
        if (await partial.exists()) await partial.delete();
      }
    }
    if (!downloaded) {
      throw InstallException('下载安装包失败：$lastError');
    }
    if (await archiveFile.exists()) await archiveFile.delete();
    await partial.rename(archiveFile.path);
    if (isCancelled?.call() == true) {
      await archiveFile.delete();
      throw const _Cancelled();
    }

    onProgress(-1, 0);
    await _verifyChecksum(
      release: release,
      asset: asset,
      file: archiveFile,
      useMirror: useMirror,
      mirrorPrefix: mirrorPrefix,
    );
    if (isCancelled?.call() == true) {
      await archiveFile.delete();
      throw const _Cancelled();
    }

    final versionDir = Directory(
      '${baseDirectory.path}/versions/${release.version}_$platform',
    );
    await versionDir.create(recursive: true);
    final executable = File('${versionDir.path}/mediamtx');
    final tmpExecutable = File('${versionDir.path}/mediamtx.tmp');
    final bytes = await archiveFile.readAsBytes();
    final tarBytes = GZipDecoder().decodeBytes(bytes);
    final archive = TarDecoder().decodeBytes(tarBytes, verify: true);
    ArchiveFile? binary;
    for (final file in archive.files) {
      if (file.isFile && file.name.split('/').last == 'mediamtx') {
        binary = file;
        break;
      }
    }
    if (binary == null) {
      throw const InstallException('安装包中未找到 mediamtx 可执行文件');
    }
    final binaryBytes = binary.readBytes();
    if (binaryBytes == null || binaryBytes.length < 1024 * 1024) {
      throw const InstallException('安装包中的可执行文件无效');
    }
    await tmpExecutable.writeAsBytes(binaryBytes, flush: true);
    if (await executable.exists()) await executable.delete();
    await tmpExecutable.rename(executable.path);
    await archiveFile.delete();
    await workDir.delete(recursive: true).catchError((_) => workDir);

    return InstallBundle(
      install: LocalInstall(
        version: release.version,
        directory: versionDir.path,
        abi: abi,
        asset: asset,
        installedAt: DateTime.now(),
      ),
      executablePath: executable.path,
      directory: versionDir.path,
    );
  }

  Future<void> _download({
    required String url,
    required File target,
    required void Function(int received, int total) onProgress,
    bool Function()? isCancelled,
  }) async {
    final request = http.Request('GET', Uri.parse(url));
    request.headers['User-Agent'] = 'MTX-Console/1.0';
    final response = await _client
        .send(request)
        .timeout(const Duration(seconds: 30));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw InstallException('下载服务器返回 ${response.statusCode}');
    }
    final total = response.contentLength ?? 0;
    final sink = target.openWrite();
    var received = 0;
    try {
      await for (final chunk in response.stream) {
        if (isCancelled?.call() == true) {
          throw const _Cancelled();
        }
        sink.add(chunk);
        received += chunk.length;
        onProgress(received, total);
      }
      await sink.flush();
    } finally {
      await sink.close();
    }
    if (total > 0 && received != total) {
      throw const InstallException('安装包下载不完整');
    }
  }

  Future<void> _verifyChecksum({
    required GithubRelease release,
    required String asset,
    required File file,
    required bool useMirror,
    required String mirrorPrefix,
  }) async {
    final checksumUrl =
        release.checksumsUrl() ??
        'https://github.com/bluenviron/mediamtx/releases/download/${release.version}/checksums.sha256';
    final candidates = <String>[
      if (useMirror) _releaseService.withMirror(checksumUrl, mirrorPrefix),
      checksumUrl,
    ];
    String? expected;
    Object? lastError;
    for (final url in candidates) {
      try {
        final response = await _client
            .get(
              Uri.parse(url),
              headers: const {'User-Agent': 'MTX-Console/1.0'},
            )
            .timeout(const Duration(seconds: 25));
        if (response.statusCode != 200) {
          throw InstallException('校验文件返回 ${response.statusCode}');
        }
        final lines = const LineSplitter().convert(
          utf8.decode(response.bodyBytes),
        );
        for (final line in lines) {
          final parts = line.trim().split(RegExp(r'\s+'));
          if (parts.length >= 2 && parts.last.replaceFirst('*', '') == asset) {
            expected = parts.first.toLowerCase();
            break;
          }
        }
        if (expected != null) break;
        throw const InstallException('校验文件中没有当前安装包');
      } catch (error) {
        lastError = error;
      }
    }
    if (expected == null) {
      throw InstallException('无法获取安装包校验值，已中止安装：$lastError');
    }
    final digest = await sha256.bind(file.openRead()).first;
    final actual = digest.toString().toLowerCase();
    if (actual != expected) {
      await file.delete();
      throw const InstallException('安装包 SHA-256 校验失败，文件可能已损坏');
    }
  }

  Future<void> deleteVersion(LocalInstall install) async {
    final directory = Directory(install.directory);
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  }

  void close() {
    _client.close();
    _releaseService.close();
  }
}
