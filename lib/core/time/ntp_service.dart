import 'package:aeterna/core/time/time_source_mode.dart';
import 'package:ntp/ntp.dart';

class NtpSyncResult {
  const NtpSyncResult({required this.networkTime, required this.server});

  final DateTime networkTime;
  final String server;
}

class NtpService {
  Future<NtpSyncResult> fetchNetworkTime({
    required TimeSourceMode mode,
    required List<String> addresses,
  }) async {
    switch (mode) {
      case TimeSourceMode.offlineManual:
        return NtpSyncResult(networkTime: DateTime.now(), server: 'local');
      case TimeSourceMode.intranetSync:
      case TimeSourceMode.cloudPull:
        final hosts = _resolveHosts(mode, addresses);
        for (final host in hosts) {
          try {
            final networkTime = await NTP.now(
              lookUpAddress: host,
              timeout: const Duration(milliseconds: 1200),
            );
            return NtpSyncResult(networkTime: networkTime, server: host);
          } catch (_) {
            // Try next server.
          }
        }
        throw StateError('所有时间服务器均不可用，请检查网络或更换时间源。');
    }
  }

  List<String> _resolveHosts(TimeSourceMode mode, List<String> addresses) {
    final cleaned = addresses
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList(growable: false);
    if (cleaned.isNotEmpty) {
      return cleaned;
    }
    switch (mode) {
      case TimeSourceMode.offlineManual:
        return const ['localhost'];
      case TimeSourceMode.intranetSync:
        return const ['time.google.com', 'time.windows.com'];
      case TimeSourceMode.cloudPull:
        return const ['pool.ntp.org', 'time.cloudflare.com', 'ntp.aliyun.com'];
    }
  }
}
