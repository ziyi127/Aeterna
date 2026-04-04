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
        payloadSize: 123456,
        payloadSha256:
          '58cbb0d78f92f2f66fd16d5396caf031d567abb3da4373f20a610a13fb758729',
      );

      final lines = package.toKeyValueLines();

      expect(lines['schemaVersion'], equals('2'));
      expect(lines['packageType'], equals('squirrelFeed'));
      expect(lines['packagePath'], equals(package.packagePath));
      expect(lines['squirrelFeedPath'], equals(package.packagePath));
      expect(lines['payloadSize'], equals('123456'));
      expect(
        lines['payloadSha256'],
        equals(
          '58cbb0d78f92f2f66fd16d5396caf031d567abb3da4373f20a610a13fb758729',
        ),
      );
      expect(lines.length, equals(10));
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
        'payloadSize': '2048',
        'payloadSha256':
          '58cbb0d78f92f2f66fd16d5396caf031d567abb3da4373f20a610a13fb758729',
      });

      expect(parsed.packageType, equals(UpdatePackageType.squirrelFeed));
      expect(
        parsed.packagePath,
        equals('C:/Temp/AeternaUpdate/aeterna-windows-squirrel-feed.tar.zst'),
      );
      expect(parsed.version, equals('2.0.0+1'));
      expect(parsed.payloadSize, equals(2048));
      expect(
        parsed.payloadSha256,
        equals(
          '58cbb0d78f92f2f66fd16d5396caf031d567abb3da4373f20a610a13fb758729',
        ),
      );
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
        'payloadSize': '1024',
        'payloadSha256':
          '58cbb0d78f92f2f66fd16d5396caf031d567abb3da4373f20a610a13fb758729',
      });

      expect(parsed.packageType, equals(UpdatePackageType.squirrelFeed));
      expect(
        parsed.packagePath,
        equals('C:/Temp/AeternaUpdate/aeterna-windows-squirrel-feed.tar.zst'),
      );
      expect(parsed.payloadSize, equals(1024));
    });
  });
}
