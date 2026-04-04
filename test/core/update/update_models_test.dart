import 'package:aeterna/core/update/update_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DownloadedUpdatePackage manifest schema', () {
    test('writes squirrel feed payload with compatibility keys', () {
      const package = DownloadedUpdatePackage(
        packageType: UpdatePackageType.squirrelFeed,
        version: '1.2.3+4',
        assetName: 'aeterna-windows-squirrel-feed.tar.zst',
        packagePath:
            'C:/Temp/AeternaUpdate/aeterna-windows-squirrel-feed.tar.zst',
        downloadUrl:
            'https://example.com/aeterna-windows-squirrel-feed.tar.zst',
        releaseUrl: 'https://example.com/release',
      );

      final lines = package.toKeyValueLines();

      expect(lines['schemaVersion'], equals('2'));
      expect(lines['packageType'], equals('squirrelFeed'));
      expect(lines['packagePath'], equals(package.packagePath));
      expect(lines['squirrelFeedPath'], equals(package.packagePath));
      expect(lines.containsKey('installerPath'), isFalse);
      expect(lines.containsKey('archivePath'), isFalse);
    });

    test('writes installer payload with backward-compatible keys', () {
      const package = DownloadedUpdatePackage(
        packageType: UpdatePackageType.installer,
        version: '1.2.3+4',
        assetName: 'aeterna-setup.exe',
        packagePath: 'C:/Temp/AeternaUpdate/aeterna-setup.exe',
        downloadUrl: 'https://example.com/aeterna-setup.exe',
        releaseUrl: 'https://example.com/release',
      );

      final lines = package.toKeyValueLines();

      expect(lines['schemaVersion'], equals('2'));
      expect(lines['packageType'], equals('installer'));
      expect(lines['packagePath'], equals(package.packagePath));
      expect(lines['installerPath'], equals(package.packagePath));
      expect(lines.containsKey('archivePath'), isFalse);
    });

    test('writes archive payload with backward-compatible keys', () {
      const package = DownloadedUpdatePackage(
        packageType: UpdatePackageType.archive,
        version: '1.2.3+4',
        assetName: 'aeterna-windows-x64.tar.zst',
        packagePath: 'C:/Temp/AeternaUpdate/aeterna-windows-x64.tar.zst',
        targetDir: 'C:/Program Files/Aeterna',
        appExecutableName: 'aeterna.exe',
        downloadUrl: 'https://example.com/aeterna-windows-x64.tar.zst',
        releaseUrl: 'https://example.com/release',
      );

      final lines = package.toKeyValueLines();

      expect(lines['schemaVersion'], equals('2'));
      expect(lines['packageType'], equals('archive'));
      expect(lines['packagePath'], equals(package.packagePath));
      expect(lines['archivePath'], equals(package.packagePath));
      expect(lines.containsKey('installerPath'), isFalse);
    });

    test('parses new manifest format', () {
      final parsed = DownloadedUpdatePackage.fromKeyValueLines({
        'schemaVersion': '2',
        'packageType': 'installer',
        'version': '2.0.0+1',
        'assetName': 'aeterna-setup.exe',
        'packagePath': 'C:/Temp/AeternaUpdate/aeterna-setup.exe',
        'downloadUrl': 'https://example.com/aeterna-setup.exe',
        'releaseUrl': 'https://example.com/release',
      });

      expect(parsed.packageType, equals(UpdatePackageType.installer));
      expect(
        parsed.packagePath,
        equals('C:/Temp/AeternaUpdate/aeterna-setup.exe'),
      );
      expect(parsed.version, equals('2.0.0+1'));
    });

    test('parses legacy archive manifest format', () {
      final parsed = DownloadedUpdatePackage.fromKeyValueLines({
        'version': '2.0.0+1',
        'assetName': 'aeterna-windows-x64.tar.zst',
        'archivePath': 'C:/Temp/AeternaUpdate/aeterna-windows-x64.tar.zst',
        'targetDir': 'C:/Program Files/Aeterna',
        'appExecutableName': 'aeterna.exe',
        'downloadUrl': 'https://example.com/aeterna-windows-x64.tar.zst',
        'releaseUrl': 'https://example.com/release',
      });

      expect(parsed.packageType, equals(UpdatePackageType.archive));
      expect(
        parsed.packagePath,
        equals('C:/Temp/AeternaUpdate/aeterna-windows-x64.tar.zst'),
      );
      expect(parsed.targetDir, equals('C:/Program Files/Aeterna'));
    });

    test('parses squirrel feed manifest format', () {
      final parsed = DownloadedUpdatePackage.fromKeyValueLines({
        'schemaVersion': '2',
        'packageType': 'squirrelFeed',
        'version': '2.0.0+1',
        'assetName': 'aeterna-windows-squirrel-feed.tar.zst',
        'packagePath':
            'C:/Temp/AeternaUpdate/aeterna-windows-squirrel-feed.tar.zst',
        'downloadUrl':
            'https://example.com/aeterna-windows-squirrel-feed.tar.zst',
        'releaseUrl': 'https://example.com/release',
      });

      expect(parsed.packageType, equals(UpdatePackageType.squirrelFeed));
      expect(
        parsed.packagePath,
        equals('C:/Temp/AeternaUpdate/aeterna-windows-squirrel-feed.tar.zst'),
      );
    });
  });
}
