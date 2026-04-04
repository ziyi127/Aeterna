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
      expect(lines.length, equals(8));
    });

    test('parses new manifest format', () {
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
      expect(parsed.version, equals('2.0.0+1'));
    });

    test('parses squirrelFeedPath compatibility key', () {
      final parsed = DownloadedUpdatePackage.fromKeyValueLines({
        'version': '2.0.0+1',
        'assetName': 'aeterna-windows-squirrel-feed.tar.zst',
        'squirrelFeedPath':
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
