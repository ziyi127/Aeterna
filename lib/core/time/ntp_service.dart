import 'package:aeterna/core/time/time_source_mode.dart';
import 'package:ntp/ntp.dart';

class NtpService {
  Future<DateTime> fetchNetworkTime({
    required TimeSourceMode mode,
    required String address,
  }) async {
    switch (mode) {
      case TimeSourceMode.offlineManual:
        return DateTime.now();
      case TimeSourceMode.intranetSync:
      case TimeSourceMode.cloudPull:
        final host = _resolveHost(mode, address);
        return NTP.now(
          lookUpAddress: host,
          timeout: const Duration(milliseconds: 900),
        );
    }
  }

  String _resolveHost(TimeSourceMode mode, String address) {
    if (address.trim().isNotEmpty) {
      return address.trim();
    }
    switch (mode) {
      case TimeSourceMode.offlineManual:
        return 'localhost';
      case TimeSourceMode.intranetSync:
        return 'time.google.com';
      case TimeSourceMode.cloudPull:
        return 'pool.ntp.org';
    }
  }
}
