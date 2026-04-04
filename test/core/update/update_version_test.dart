import 'package:aeterna/core/update/update_service_io.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('update version comparison', () {
    test('treats higher build metadata as newer', () {
      expect(
        compareAppVersions('1.0.0-test.12+14', '1.0.0-test.12+13'),
        greaterThan(0),
      );
      expect(
        isNewerAppVersion('1.0.0-test.12+14', '1.0.0-test.12+13'),
        isTrue,
      );
    });

    test('keeps equal build metadata as not newer', () {
      expect(
        compareAppVersions('1.0.0-test.12+14', '1.0.0-test.12+14'),
        equals(0),
      );
      expect(
        isNewerAppVersion('1.0.0-test.12+14', '1.0.0-test.12+14'),
        isFalse,
      );
    });

    test('treats stable release as newer than prerelease with same core', () {
      expect(
        compareAppVersions('1.0.0+14', '1.0.0-test.12+14'),
        greaterThan(0),
      );
      expect(
        isNewerAppVersion('1.0.0+14', '1.0.0-test.12+14'),
        isTrue,
      );
    });

    test('compares prerelease numeric segments numerically', () {
      expect(
        compareAppVersions('1.0.0-test.10+14', '1.0.0-test.9+99'),
        greaterThan(0),
      );
      expect(
        isNewerAppVersion('1.0.0-test.10+14', '1.0.0-test.9+99'),
        isTrue,
      );
    });
  });
}
