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
        try {
          return NTP.now(
            lookUpAddress: host,
            timeout: const Duration(milliseconds: 900),
          );
        } catch (error) {
          // Keep sync errors short and stable for UI rendering.
          final message = error.toString();
          if (_looksLikeServerReferenceError(message)) {
            throw StateError('时间服务器拒绝请求（服务器参照错误），请更换时间源或稍后重试。');
          }
          throw StateError('时间同步失败，请检查网络或时间源地址。');
        }
    }
  }

  bool _looksLikeServerReferenceError(String message) {
    final lower = message.toLowerCase();
    return lower.contains('reference') ||
        lower.contains('ref #') ||
        lower.contains('request blocked') ||
        lower.contains('access denied');
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
