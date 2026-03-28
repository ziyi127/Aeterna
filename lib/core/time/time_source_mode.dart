enum TimeSourceMode { offlineManual, intranetSync, cloudPull }

extension TimeSourceModeLabel on TimeSourceMode {
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
}
