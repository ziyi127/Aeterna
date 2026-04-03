import 'package:aeterna/core/update/update_models.dart';

class UpdateService {
  static Future<UpdateCheckOutcome> checkAndDownloadLatest({
    required String currentVersion,
  }) async {
    return UpdateCheckOutcome(
      platformSupported: false,
      currentVersion: currentVersion,
      message: '当前平台暂不支持自动更新。',
    );
  }

  static Future<bool> launchInstaller(DownloadedUpdatePackage package) async {
    return false;
  }

  static Future<UpgradeSuccessNotice?> consumeSuccessNotice() async {
    return null;
  }
}
