import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:aeterna/core/update/update_models.dart';
import 'package:flutter/foundation.dart';

class UpdateService {
  static const String _owner = 'ziyi127';
  static const String _repo = 'Aeterna';
  static const String _windowsAssetName = 'aeterna-windows-x64.tar.zst';
  static const String _manifestFileName = 'pending_update.txt';
  static const String _successFileName = 'upgrade_success.txt';
  static const String _helperFileName = 'aeterna_updater_helper.exe';
  static const Duration _networkTimeout = Duration(seconds: 15);
  static const Duration _payloadDownloadTimeout = Duration(minutes: 20);

  static Directory get _rootDirectory =>
      Directory('${Directory.systemTemp.path}${Platform.pathSeparator}aeterna_update');

  static File get _manifestFile =>
      File('${_rootDirectory.path}${Platform.pathSeparator}$_manifestFileName');

  static File get _successFile =>
      File('${_rootDirectory.path}${Platform.pathSeparator}$_successFileName');

  static Future<UpdateCheckOutcome> checkAndDownloadLatest({
    required String currentVersion,
  }) async {
    try {
      if (!Platform.isWindows) {
        return UpdateCheckOutcome(
          platformSupported: false,
          currentVersion: currentVersion,
          message: '当前平台暂不支持自动安装，仅 Windows 支持一键更新。',
        );
      }

      final release = await _fetchLatestRelease();
      if (release == null) {
        return UpdateCheckOutcome(
          platformSupported: true,
          currentVersion: currentVersion,
          message: '没有获取到可用的发布信息。',
        );
      }

      if (!_isNewerVersion(release.version, currentVersion)) {
        return UpdateCheckOutcome(
          platformSupported: true,
          currentVersion: currentVersion,
          latestVersion: release.version,
          message: '当前已经是最新版本 v$currentVersion。',
        );
      }

      final asset = release.assets.where((entry) => entry.name == _windowsAssetName).firstOrNull;
      if (asset == null) {
        return UpdateCheckOutcome(
          platformSupported: true,
          currentVersion: currentVersion,
          latestVersion: release.version,
          message: '找到新版本 v${release.version}，但没有可下载的 Windows 更新包。',
        );
      }

      final cachedPackage = await _loadPendingPackageIfSameVersion(
        version: release.version,
      );
      if (cachedPackage != null) {
        return UpdateCheckOutcome(
          platformSupported: true,
          currentVersion: currentVersion,
          latestVersion: release.version,
          downloadedPackage: cachedPackage,
          message: '检测到已下载的 v${release.version} 更新包，可直接安装。',
        );
      }

      final package = await _downloadAndPreparePackage(
        release: release,
        asset: asset,
      );
      return UpdateCheckOutcome(
        platformSupported: true,
        currentVersion: currentVersion,
        latestVersion: release.version,
        downloadedPackage: package,
        message: '已下载 v${release.version} 更新包，安装后下次启动会自动进入升级后的欢迎页。',
      );
    } catch (error) {
      return UpdateCheckOutcome(
        platformSupported: Platform.isWindows,
        currentVersion: currentVersion,
        message: '检查更新失败: $error',
      );
    }
  }

  static Future<bool> launchInstaller(DownloadedUpdatePackage package) async {
    try {
      await _rootDirectory.create(recursive: true);
      await _writeKeyValueFile(_manifestFile, package.toKeyValueLines());
      final resolvedExecutable = File(Platform.resolvedExecutable);
      final helperPath =
          '${_rootDirectory.path}${Platform.pathSeparator}$_helperFileName';
      await resolvedExecutable.copy(helperPath);

      final process = await Process.start(
        helperPath,
        ['--install-update'],
        mode: ProcessStartMode.detached,
        runInShell: false,
      );
      unawaited(process.exitCode);
      return true;
    } catch (error) {
      debugPrint('launchInstaller failed: $error');
      return false;
    }
  }

  static Future<UpgradeSuccessNotice?> consumeSuccessNotice() async {
    if (!await _successFile.exists()) {
      return null;
    }
    try {
      final lines = await _successFile.readAsLines();
      await _successFile.delete();
      final values = _parseKeyValueLines(lines);
      final version = values['version'] ?? '';
      final installedAtIso = values['installedAtIso'] ?? '';
      if (version.isEmpty) {
        return null;
      }
      return UpgradeSuccessNotice(
        version: version,
        installedAtIso: installedAtIso,
      );
    } catch (_) {
      return null;
    }
  }

  static Future<DownloadedUpdatePackage> _downloadAndPreparePackage({
    required _GitHubRelease release,
    required _GitHubReleaseAsset asset,
  }) async {
    final downloadDir = Directory(
      '${Directory.systemTemp.path}${Platform.pathSeparator}aeterna_update',
    );
    await downloadDir.create(recursive: true);
    final archivePath =
        '${downloadDir.path}${Platform.pathSeparator}${asset.name}';
    final client = HttpClient();
    client.userAgent = 'AeternaUpdater/1.0';
    final request = await client.getUrl(Uri.parse(asset.downloadUrl));
    request.headers.add(HttpHeaders.acceptHeader, 'application/octet-stream');
    final response = await request.close().timeout(_networkTimeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('HTTP ${response.statusCode}');
    }
    final file = File(archivePath);
    final sink = file.openWrite();
    await response.pipe(sink).timeout(_payloadDownloadTimeout);
    await sink.flush();
    await sink.close();

    final targetDir = File(Platform.resolvedExecutable).parent.path;
    final package = DownloadedUpdatePackage(
      version: release.version,
      assetName: asset.name,
      archivePath: archivePath,
      targetDir: targetDir,
      appExecutableName: 'aeterna.exe',
      downloadUrl: asset.downloadUrl,
      releaseUrl: release.releaseUrl,
    );
    await _writeKeyValueFile(_manifestFile, package.toKeyValueLines());
    return package;
  }

  static Future<_GitHubRelease?> _fetchLatestRelease() async {
    final client = HttpClient();
    client.userAgent = 'AeternaUpdater/1.0';
    final request = await client.getUrl(
      Uri.https('api.github.com', '/repos/$_owner/$_repo/releases/latest'),
    );
    request.headers.set(HttpHeaders.acceptHeader, 'application/vnd.github+json');
    final response = await request.close().timeout(_networkTimeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('GitHub API returned ${response.statusCode}');
    }
    final body = await response
      .transform(utf8.decoder)
      .join()
      .timeout(_networkTimeout);
    final jsonData = jsonDecode(body) as Map<String, dynamic>;
    return _GitHubRelease.fromJson(jsonData);
  }

  static Future<void> _writeKeyValueFile(
    File file,
    Map<String, String> values,
  ) async {
    await file.parent.create(recursive: true);
    final buffer = StringBuffer();
    for (final entry in values.entries) {
      buffer.writeln('${entry.key}=${entry.value}');
    }
    await file.writeAsString(buffer.toString());
  }

  static Map<String, String> _parseKeyValueLines(List<String> lines) {
    final values = <String, String>{};
    for (final rawLine in lines) {
      final line = rawLine.trim();
      if (line.isEmpty || line.startsWith('#')) {
        continue;
      }
      final index = line.indexOf('=');
      if (index <= 0) {
        continue;
      }
      final key = line.substring(0, index).trim();
      final value = line.substring(index + 1);
      values[key] = value;
    }
    return values;
  }

  static bool _isNewerVersion(String latest, String current) {
    final latestVersion = _Version.parse(latest);
    final currentVersion = _Version.parse(current);
    return latestVersion.compareTo(currentVersion) > 0;
  }

  static Future<DownloadedUpdatePackage?> _loadPendingPackageIfSameVersion({
    required String version,
  }) async {
    if (!await _manifestFile.exists()) {
      return null;
    }
    try {
      final lines = await _manifestFile.readAsLines();
      final values = _parseKeyValueLines(lines);
      final package = DownloadedUpdatePackage.fromKeyValueLines(values);
      if (package.version != version) {
        return null;
      }
      if (package.archivePath.isEmpty || !File(package.archivePath).existsSync()) {
        return null;
      }
      return package;
    } catch (_) {
      return null;
    }
  }
}

class _GitHubRelease {
  const _GitHubRelease({
    required this.version,
    required this.releaseUrl,
    required this.assets,
  });

  factory _GitHubRelease.fromJson(Map<String, dynamic> json) {
    final tag = (json['tag_name'] as String?) ?? '';
    final assetsRaw = (json['assets'] as List?) ?? const [];
    return _GitHubRelease(
      version: tag.replaceFirst(RegExp(r'^[vV]'), ''),
      releaseUrl: (json['html_url'] as String?) ?? '',
      assets: assetsRaw
          .whereType<Map>()
          .map((entry) => _GitHubReleaseAsset.fromJson(Map<String, dynamic>.from(entry)))
          .toList(),
    );
  }

  final String version;
  final String releaseUrl;
  final List<_GitHubReleaseAsset> assets;
}

class _GitHubReleaseAsset {
  const _GitHubReleaseAsset({
    required this.name,
    required this.downloadUrl,
  });

  factory _GitHubReleaseAsset.fromJson(Map<String, dynamic> json) {
    return _GitHubReleaseAsset(
      name: (json['name'] as String?) ?? '',
      downloadUrl: (json['browser_download_url'] as String?) ?? '',
    );
  }

  final String name;
  final String downloadUrl;
}

class _Version implements Comparable<_Version> {
  const _Version({
    required this.major,
    required this.minor,
    required this.patch,
    required this.preRelease,
  });

  factory _Version.parse(String value) {
    final trimmed = value.trim().replaceFirst(RegExp(r'^[vV]'), '');
    final coreAndBuild = trimmed.split('+').first;
    final coreParts = coreAndBuild.split('-');
    final numeric = coreParts.first.split('.');
    int parsePart(int index) {
      if (index >= numeric.length) {
        return 0;
      }
      return int.tryParse(numeric[index]) ?? 0;
    }

    return _Version(
      major: parsePart(0),
      minor: parsePart(1),
      patch: parsePart(2),
      preRelease: coreParts.length > 1 ? coreParts.sublist(1).join('-') : '',
    );
  }

  final int major;
  final int minor;
  final int patch;
  final String preRelease;

  @override
  int compareTo(_Version other) {
    if (major != other.major) {
      return major.compareTo(other.major);
    }
    if (minor != other.minor) {
      return minor.compareTo(other.minor);
    }
    if (patch != other.patch) {
      return patch.compareTo(other.patch);
    }
    if (preRelease.isEmpty && other.preRelease.isNotEmpty) {
      return 1;
    }
    if (preRelease.isNotEmpty && other.preRelease.isEmpty) {
      return -1;
    }
    return preRelease.compareTo(other.preRelease);
  }
}

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull {
    if (isEmpty) {
      return null;
    }
    return first;
  }
}
