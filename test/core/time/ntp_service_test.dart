import 'package:aeterna/core/time/ntp_service.dart';
import 'package:aeterna/core/time/time_source_mode.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('NtpService', () {
    test('offlineManual returns local server without network call', () async {
      var called = false;
      final service = NtpService(
        nowFetcher: ({required lookUpAddress, required timeout}) async {
          called = true;
          return DateTime(2026, 4, 4, 10, 0, 0);
        },
      );

      final result = await service.fetchNetworkTime(
        mode: TimeSourceMode.offlineManual,
        addresses: const <String>[],
      );

      expect(result.server, 'local');
      expect(called, isFalse);
    });

    test('falls back to next host when first host fails', () async {
      final queriedHosts = <String>[];
      final service = NtpService(
        nowFetcher: ({required lookUpAddress, required timeout}) async {
          queriedHosts.add(lookUpAddress);
          if (lookUpAddress == 'time.google.com') {
            throw StateError('host down');
          }
          return DateTime(2026, 4, 4, 12, 0, 0);
        },
      );

      final result = await service.fetchNetworkTime(
        mode: TimeSourceMode.intranetSync,
        addresses: const <String>[],
      );

      expect(queriedHosts, <String>['time.google.com', 'time.windows.com']);
      expect(result.server, 'time.windows.com');
      expect(result.networkTime, DateTime(2026, 4, 4, 12, 0, 0));
    });

    test('uses provided custom addresses before defaults', () async {
      final queriedHosts = <String>[];
      final service = NtpService(
        nowFetcher: ({required lookUpAddress, required timeout}) async {
          queriedHosts.add(lookUpAddress);
          return DateTime(2026, 4, 4, 13, 0, 0);
        },
      );

      final result = await service.fetchNetworkTime(
        mode: TimeSourceMode.cloudPull,
        addresses: const <String>[' ntp.custom.local ', ''],
      );

      expect(queriedHosts, <String>['ntp.custom.local']);
      expect(result.server, 'ntp.custom.local');
    });

    test('throws StateError when all hosts fail', () async {
      final service = NtpService(
        nowFetcher: ({required lookUpAddress, required timeout}) async {
          throw StateError('always fail');
        },
      );

      expect(
        () => service.fetchNetworkTime(
          mode: TimeSourceMode.cloudPull,
          addresses: const <String>['a', 'b'],
        ),
        throwsA(isA<StateError>()),
      );
    });
  });
}
