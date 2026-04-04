import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:aeterna/core/update/update_models.dart';
import 'package:flutter/foundation.dart';

class UpdateService {
  static const String _owner = 'ziyi127';
  static const String _repo = 'Aeterna';
  static const String _updateRootName = 'AeternaUpdate';
  static const List<String> _preferredWindowsSquirrelFeedAssetNames = <String>[
    'aeterna-windows-squirrel-feed.tar.zst',
  ];
  static const String _manifestFileName = 'pending_update.txt';
  static const String _successFileName = 'upgrade_success.txt';
  static const String _helperFileName = 'aeterna_updater_helper.exe';
  static const String _squirrelFeedSuffix = '.tar.zst';
  static const Duration _networkTimeout = Duration(seconds: 15);
  static const Duration _payloadDownloadTimeout = Duration(minutes: 20);

  static Directory get _rootDirectory => Directory(
    '${Directory.systemTemp.path}${Platform.pathSeparator}$_updateRootName',
  );

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

      if (!isNewerAppVersion(release.version, currentVersion)) {
        return UpdateCheckOutcome(
          platformSupported: true,
          currentVersion: currentVersion,
          latestVersion: release.version,
          message: '当前已经是最新版本 v$currentVersion。',
        );
      }

      final selectedAsset = _selectWindowsAsset(release.assets);
      if (selectedAsset == null) {
        return UpdateCheckOutcome(
          platformSupported: true,
          currentVersion: currentVersion,
          latestVersion: release.version,
          message: '找到新版本 v${release.version}，但没有找到可用的 Squirrel ZSTD 更新负载。',
        );
      }

      final cachedPackage = await _loadPendingPackageIfSameVersion(
        version: release.version,
      );
      if (cachedPackage != null &&
          cachedPackage.assetName == selectedAsset.asset.name &&
          cachedPackage.packageType == selectedAsset.packageType) {
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
        selectedAsset: selectedAsset,
      );
      return UpdateCheckOutcome(
        platformSupported: true,
        currentVersion: currentVersion,
        latestVersion: release.version,
        downloadedPackage: package,
        message: '已下载 v${release.version} 的 Squirrel 更新负载，确认后将自动退出并启动更新。',
      );
    } catch (error) {
      final cachedPackage = Platform.isWindows
          ? await _loadAnyPendingPackage()
          : null;
      if (cachedPackage != null) {
        return UpdateCheckOutcome(
          platformSupported: true,
          currentVersion: currentVersion,
          latestVersion: cachedPackage.version,
          downloadedPackage: cachedPackage,
          message: '在线检查失败，但检测到已下载的更新包 v${cachedPackage.version}，可直接安装。',
        );
      }
      return UpdateCheckOutcome(
        platformSupported: Platform.isWindows,
        currentVersion: currentVersion,
        message: '检查更新失败: $error',
      );
    }
  }

  static Future<bool> launchInstaller(DownloadedUpdatePackage package) async {
    try {
      if (!package.isSquirrelFeed) {
        debugPrint('launchInstaller rejected: unsupported package type');
        return false;
      }
      if (!_isSquirrelFeedPath(package.packagePath)) {
        debugPrint('launchInstaller rejected: invalid payload suffix');
        return false;
      }
      if (!File(package.packagePath).existsSync()) {
        debugPrint('launchInstaller rejected: payload file missing');
        return false;
      }
      if (await File(package.packagePath).length() <= 0) {
        debugPrint('launchInstaller rejected: payload file is empty');
        return false;
      }

      await _rootDirectory.create(recursive: true);
      await _writeKeyValueFile(_manifestFile, package.toKeyValueLines());
      final resolvedExecutable = File(Platform.resolvedExecutable);
      final helperPath =
          '${_rootDirectory.path}${Platform.pathSeparator}$_helperFileName';
      await resolvedExecutable.copy(helperPath);

      final process = await Process.start(
        helperPath,
        ['--install-update', '--parent-pid=$pid'],
        mode: ProcessStartMode.detached,
        runInShell: false,
      );
      unawaited(process.exitCode);
      return true;
    } catch (error) {
      if (await _manifestFile.exists()) {
        await _manifestFile.delete();
      }
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
    required _SelectedAsset selectedAsset,
  }) async {
    if (!_isSquirrelFeedPath(selectedAsset.asset.name)) {
      throw StateError(
        '仅支持 Squirrel ZSTD 负载，当前资产不合法: ${selectedAsset.asset.name}',
      );
    }

    final downloadDir = _rootDirectory;
    await downloadDir.create(recursive: true);
    final packagePath =
        '${downloadDir.path}${Platform.pathSeparator}${selectedAsset.asset.name}';
    final client = HttpClient();
    client.userAgent = 'AeternaUpdater/2.0';
    final request = await client.getUrl(
      Uri.parse(selectedAsset.asset.downloadUrl),
    );
    request.headers.add(HttpHeaders.acceptHeader, 'application/octet-stream');
    final response = await request.close().timeout(_networkTimeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('HTTP ${response.statusCode}');
    }
    final file = File(packagePath);
    final sink = file.openWrite();
    await response.pipe(sink).timeout(_payloadDownloadTimeout);
    await sink.flush();
    await sink.close();

    final downloadedBytes = await file.length();
    if (downloadedBytes <= 0) {
      throw StateError('下载文件为空: ${selectedAsset.asset.name}');
    }
    if (selectedAsset.asset.size > 0 && downloadedBytes != selectedAsset.asset.size) {
      throw StateError(
        '下载文件大小不匹配，expected=${selectedAsset.asset.size}, actual=$downloadedBytes',
      );
    }

    final package = DownloadedUpdatePackage(
      packageType: selectedAsset.packageType,
      version: release.version,
      assetName: selectedAsset.asset.name,
      packagePath: packagePath,
      downloadUrl: selectedAsset.asset.downloadUrl,
      releaseUrl: release.releaseUrl,
    );
    await _writeKeyValueFile(_manifestFile, package.toKeyValueLines());
    return package;
  }

  static Future<_GitHubRelease?> _fetchLatestRelease() async {
    final client = HttpClient();
    client.userAgent = 'AeternaUpdater/2.0';
    final request = await client.getUrl(
      Uri.https('api.github.com', '/repos/$_owner/$_repo/releases/latest'),
    );
    request.headers.set(
      HttpHeaders.acceptHeader,
      'application/vnd.github+json',
    );
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

  static _SelectedAsset? _selectWindowsAsset(List<_GitHubReleaseAsset> assets) {
    final normalized = assets
        .where((asset) => asset.name.trim().isNotEmpty)
        .toList(growable: false);
    if (normalized.isEmpty) {
      return null;
    }

    _GitHubReleaseAsset? findExact(List<String> names) {
      for (final expected in names) {
        final matched = normalized
            .where((asset) => asset.name.toLowerCase() == expected)
            .firstOrNull;
        if (matched != null) {
          return matched;
        }
      }
      return null;
    }

    final exactSquirrelFeed = findExact(
      _preferredWindowsSquirrelFeedAssetNames,
    );
    if (exactSquirrelFeed != null) {
      return _SelectedAsset(
        packageType: UpdatePackageType.squirrelFeed,
        asset: exactSquirrelFeed,
      );
    }

    final fuzzySquirrelFeed = normalized.where((asset) {
      final name = asset.name.toLowerCase();
      return name.endsWith(_squirrelFeedSuffix) &&
          name.contains('squirrel') &&
          name.contains('windows');
    }).firstOrNull;
    if (fuzzySquirrelFeed != null) {
      return _SelectedAsset(
        packageType: UpdatePackageType.squirrelFeed,
        asset: fuzzySquirrelFeed,
      );
    }

    return null;
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
    await file.writeAsString(buffer.toString(), encoding: utf8);
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

  static int compareAppVersions(String latest, String current) {
    final latestVersion = _Version.parse(latest);
    final currentVersion = _Version.parse(current);
    return latestVersion.compareTo(currentVersion);
  }

  static bool isNewerAppVersion(String latest, String current) {
    final latestVersion = _Version.parse(latest);
    final currentVersion = _Version.parse(current);
    return latestVersion.compareTo(currentVersion) > 0;
  }

  static Future<DownloadedUpdatePackage?> _loadPendingPackageIfSameVersion({
    required String version,
  }) async {
    final package = await _loadAnyPendingPackage();
    if (package == null || package.version != version) {
      return null;
    }
    return package;
  }

  static Future<DownloadedUpdatePackage?> _loadAnyPendingPackage() async {
    if (!await _manifestFile.exists()) {
      return null;
    }
    try {
      final lines = await _manifestFile.readAsLines();
      final values = _parseKeyValueLines(lines);
      if (values['schemaVersion'] != '2') {
        return null;
      }
      final package = DownloadedUpdatePackage.fromKeyValueLines(values);
      if (package.packagePath.isEmpty ||
          !File(package.packagePath).existsSync()) {
        return null;
      }
      if (!package.isSquirrelFeed ||
          !_isSquirrelFeedPath(package.packagePath)) {
        return null;
      }
      return package;
    } catch (_) {
      return null;
    }
  }

  static bool _isSquirrelFeedPath(String value) {
    return value.trim().toLowerCase().endsWith(_squirrelFeedSuffix);
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
          .map(
            (entry) =>
                _GitHubReleaseAsset.fromJson(Map<String, dynamic>.from(entry)),
          )
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
    required this.size,
  });

  factory _GitHubReleaseAsset.fromJson(Map<String, dynamic> json) {
    return _GitHubReleaseAsset(
      name: (json['name'] as String?) ?? '',
      downloadUrl: (json['browser_download_url'] as String?) ?? '',
      size: (json['size'] as num?)?.toInt() ?? 0,
    );
  }

  final String name;
  final String downloadUrl;
  final int size;
}

class _SelectedAsset {
  const _SelectedAsset({required this.packageType, required this.asset});

  final UpdatePackageType packageType;
  final _GitHubReleaseAsset asset;
}

class _Version implements Comparable<_Version> {
  const _Version({
    required this.major,
    required this.minor,
    required this.patch,
    required this.preRelease,
    required this.build,
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
      build: _parseBuildNumber(trimmed),
    );
  }

  final int major;
  final int minor;
  final int patch;
  final String preRelease;
  final int build;

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
    final preReleaseComparison = _comparePrerelease(
      preRelease,
      other.preRelease,
    );
    if (preReleaseComparison != 0) {
      return preReleaseComparison;
    }
    return build.compareTo(other.build);
  }

  static int _comparePrerelease(String left, String right) {
    final leftParts = left
        .split(RegExp(r'[.-]'))
        .where((part) => part.isNotEmpty)
        .toList();
    final rightParts = right
        .split(RegExp(r'[.-]'))
        .where((part) => part.isNotEmpty)
        .toList();
    final count = leftParts.length < rightParts.length
        ? leftParts.length
        : rightParts.length;
    for (var index = 0; index < count; index++) {
      final leftPart = leftParts[index];
      final rightPart = rightParts[index];
      final leftNumber = int.tryParse(leftPart);
      final rightNumber = int.tryParse(rightPart);
      if (leftNumber != null && rightNumber != null) {
        if (leftNumber != rightNumber) {
          return leftNumber.compareTo(rightNumber);
        }
        continue;
      }
      if (leftNumber != null && rightNumber == null) {
        return -1;
      }
      if (leftNumber == null && rightNumber != null) {
        return 1;
      }
      final textComparison = leftPart.compareTo(rightPart);
      if (textComparison != 0) {
        return textComparison;
      }
    }
    return leftParts.length.compareTo(rightParts.length);
  }

  static int _parseBuildNumber(String value) {
    final buildPart = value.split('+').skip(1).firstOrNull ?? '';
    if (buildPart.isEmpty) {
      return 0;
    }
    return int.tryParse(buildPart) ?? 0;
  }
}

bool isNewerAppVersion(String latest, String current) {
  return UpdateService.isNewerAppVersion(latest, current);
}

int compareAppVersions(String latest, String current) {
  return UpdateService.compareAppVersions(latest, current);
}

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull {
    if (isEmpty) {
      return null;
    }
    return first;
  }
}
