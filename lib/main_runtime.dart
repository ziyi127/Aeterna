import 'dart:io';

import 'package:aeterna/app/runtime_app.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

final _memoryPressureObserver = _RuntimeMemoryPressureObserver();

class _RuntimeMemoryPressureObserver extends WidgetsBindingObserver {
  @override
  void didHaveMemoryPressure() {
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Runtime-only mode: stricter cache limits for lower memory footprint.
  PaintingBinding.instance.imageCache.maximumSize = 60;
  PaintingBinding.instance.imageCache.maximumSizeBytes = 16 << 20;
  WidgetsBinding.instance.addObserver(_memoryPressureObserver);

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

  runApp(const AeternaRuntimeApp());
}
