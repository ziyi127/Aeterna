enum TimeSourceMode { offlineManual, intranetSync, cloudPull }

extension TimeSourceModeLabel on TimeSourceMode {
  String get key {
    switch (this) {
      case TimeSourceMode.offlineManual:
        return 'offline-manual';
      case TimeSourceMode.intranetSync:
        return 'intranet-sync';
      case TimeSourceMode.cloudPull:
        return 'cloud-pull';
    }
  }

  String get label {
    switch (this) {
      case TimeSourceMode.offlineManual:
        return '离线手动';
      case TimeSourceMode.intranetSync:
        return '内网同步';
      case TimeSourceMode.cloudPull:
        return '云端拉取';
    }
  }

  static TimeSourceMode fromKey(String key) {
    switch (key.trim()) {
      case 'intranet-sync':
        return TimeSourceMode.intranetSync;
      case 'cloud-pull':
        return TimeSourceMode.cloudPull;
      default:
        return TimeSourceMode.offlineManual;
    }
  }
}
