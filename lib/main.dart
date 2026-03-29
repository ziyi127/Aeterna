import 'dart:io';

import 'package:aeterna/app/app.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

final _memoryPressureObserver = _MemoryPressureObserver();

class _MemoryPressureObserver extends WidgetsBindingObserver {
  @override
  void didHaveMemoryPressure() {
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Cap image cache to avoid excessive memory growth across platforms.
  PaintingBinding.instance.imageCache.maximumSize = 80;
  PaintingBinding.instance.imageCache.maximumSizeBytes = 24 << 20;
  WidgetsBinding.instance.addObserver(_memoryPressureObserver);

  // Initialize window manager for desktop platforms
  if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
    try {
      await windowManager.ensureInitialized();
      const options = WindowOptions(
        center: true,
        minimumSize: Size(960, 600),
        titleBarStyle: TitleBarStyle.hidden,
      );
      await windowManager.waitUntilReadyToShow(options, () async {
        try {
          await windowManager.show();
          await windowManager.focus();
        } catch (e) {
          debugPrint('Error showing/focusing window: $e');
        }
      });
    } catch (e) {
      debugPrint('Error initializing window manager: $e');
      // Continue running even if window manager initialization fails
    }
  }

  runApp(const AeternaApp());
}
