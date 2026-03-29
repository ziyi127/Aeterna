import 'dart:io';

import 'package:aeterna/app/app.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Cap image cache to avoid excessive memory growth across platforms.
  PaintingBinding.instance.imageCache.maximumSize = 180;
  PaintingBinding.instance.imageCache.maximumSizeBytes = 48 << 20;

  if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
    await windowManager.ensureInitialized();
    const options = WindowOptions(
      center: true,
      minimumSize: Size(960, 600),
      titleBarStyle: TitleBarStyle.hidden,
    );
    await windowManager.waitUntilReadyToShow(options, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }

  runApp(const AeternaApp());
}
