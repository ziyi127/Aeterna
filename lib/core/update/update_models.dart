class UpdateCheckOutcome {
  const UpdateCheckOutcome({
    required this.platformSupported,
    required this.currentVersion,
    required this.message,
    this.latestVersion,
    this.downloadedPackage,
  });

  final bool platformSupported;
  final String currentVersion;
  final String message;
  final String? latestVersion;
  final DownloadedUpdatePackage? downloadedPackage;

  bool get hasUpdate => downloadedPackage != null;
}

enum UpdatePackageType { squirrelFeed, installer, archive }

extension UpdatePackageTypeCodec on UpdatePackageType {
  String get wireValue {
    switch (this) {
      case UpdatePackageType.squirrelFeed:
        return 'squirrelFeed';
      case UpdatePackageType.installer:
        return 'installer';
      case UpdatePackageType.archive:
        return 'archive';
    }
  }

  static UpdatePackageType? fromWireValue(String? value) {
    switch (value?.trim().toLowerCase()) {
      case 'squirrelfeed':
        return UpdatePackageType.squirrelFeed;
      case 'installer':
        return UpdatePackageType.installer;
      case 'archive':
        return UpdatePackageType.archive;
      default:
        return null;
    }
  }
}

class DownloadedUpdatePackage {
  const DownloadedUpdatePackage({
    required this.packageType,
    required this.version,
    required this.assetName,
    required this.packagePath,
    required this.downloadUrl,
    required this.releaseUrl,
    this.targetDir = '',
    this.appExecutableName = 'aeterna.exe',
  });

  final UpdatePackageType packageType;
  final String version;
  final String assetName;
  final String packagePath;
  final String targetDir;
  final String appExecutableName;
  final String downloadUrl;
  final String releaseUrl;

  bool get isInstaller => packageType == UpdatePackageType.installer;

  bool get isArchive => packageType == UpdatePackageType.archive;

  bool get isSquirrelFeed => packageType == UpdatePackageType.squirrelFeed;

  Map<String, String> toKeyValueLines() {
    final values = <String, String>{
      'schemaVersion': '2',
      'packageType': packageType.wireValue,
      'version': version,
      'assetName': assetName,
      'packagePath': packagePath,
      'targetDir': targetDir,
      'appExecutableName': appExecutableName,
      'downloadUrl': downloadUrl,
      'releaseUrl': releaseUrl,
    };

    // Keep old keys for backward compatibility with helper binaries.
    if (isArchive) {
      values['archivePath'] = packagePath;
    }
    if (isInstaller) {
      values['installerPath'] = packagePath;
    }
    if (isSquirrelFeed) {
      values['squirrelFeedPath'] = packagePath;
    }

    return values;
  }

  static DownloadedUpdatePackage fromKeyValueLines(Map<String, String> values) {
    final packagePath =
        (values['packagePath'] ??
                values['squirrelFeedPath'] ??
                values['installerPath'] ??
                values['archivePath'] ??
                '')
            .trim();
    final inferredType = values.containsKey('squirrelFeedPath')
        ? UpdatePackageType.squirrelFeed
        : (values.containsKey('installerPath')
              ? UpdatePackageType.installer
              : UpdatePackageType.archive);
    final packageType =
        UpdatePackageTypeCodec.fromWireValue(values['packageType']) ??
        inferredType;

    return DownloadedUpdatePackage(
      packageType: packageType,
      version: values['version'] ?? '',
      assetName: values['assetName'] ?? '',
      packagePath: packagePath,
      targetDir: values['targetDir'] ?? '',
      appExecutableName: values['appExecutableName'] ?? 'aeterna.exe',
      downloadUrl: values['downloadUrl'] ?? '',
      releaseUrl: values['releaseUrl'] ?? '',
    );
  }
}

class UpgradeSuccessNotice {
  const UpgradeSuccessNotice({
    required this.version,
    required this.installedAtIso,
  });

  final String version;
  final String installedAtIso;

  String get message => '已成功升级到 v$version';
}
