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

class DownloadedUpdatePackage {
  const DownloadedUpdatePackage({
    required this.version,
    required this.assetName,
    required this.archivePath,
    required this.targetDir,
    required this.appExecutableName,
    required this.downloadUrl,
    required this.releaseUrl,
  });

  final String version;
  final String assetName;
  final String archivePath;
  final String targetDir;
  final String appExecutableName;
  final String downloadUrl;
  final String releaseUrl;

  Map<String, String> toKeyValueLines() {
    return {
      'version': version,
      'assetName': assetName,
      'archivePath': archivePath,
      'targetDir': targetDir,
      'appExecutableName': appExecutableName,
      'downloadUrl': downloadUrl,
      'releaseUrl': releaseUrl,
    };
  }

  static DownloadedUpdatePackage fromKeyValueLines(
    Map<String, String> values,
  ) {
    return DownloadedUpdatePackage(
      version: values['version'] ?? '',
      assetName: values['assetName'] ?? '',
      archivePath: values['archivePath'] ?? '',
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
