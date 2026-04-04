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

enum UpdatePackageType { squirrelFeed }

extension UpdatePackageTypeCodec on UpdatePackageType {
  String get wireValue {
    switch (this) {
      case UpdatePackageType.squirrelFeed:
        return 'squirrelFeed';
    }
  }

  static UpdatePackageType? fromWireValue(String? value) {
    switch (value?.trim().toLowerCase()) {
      case 'squirrelfeed':
        return UpdatePackageType.squirrelFeed;
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
  });

  final UpdatePackageType packageType;
  final String version;
  final String assetName;
  final String packagePath;
  final String downloadUrl;
  final String releaseUrl;

  bool get isSquirrelFeed => packageType == UpdatePackageType.squirrelFeed;

  Map<String, String> toKeyValueLines() {
    final values = <String, String>{
      'schemaVersion': '2',
      'packageType': packageType.wireValue,
      'version': version,
      'assetName': assetName,
      'packagePath': packagePath,
      'downloadUrl': downloadUrl,
      'releaseUrl': releaseUrl,
      'squirrelFeedPath': packagePath,
    };
    return values;
  }

  static DownloadedUpdatePackage fromKeyValueLines(Map<String, String> values) {
    final packagePath =
        (values['packagePath'] ?? values['squirrelFeedPath'] ?? '').trim();
    final inferredType = UpdatePackageType.squirrelFeed;
    final packageType =
        UpdatePackageTypeCodec.fromWireValue(values['packageType']) ??
        inferredType;

    return DownloadedUpdatePackage(
      packageType: packageType,
      version: values['version'] ?? '',
      assetName: values['assetName'] ?? '',
      packagePath: packagePath,
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
