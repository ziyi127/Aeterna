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

Future<void> _initializeWindowManager() async {
  try {
    await windowManager.ensureInitialized();
    
    // Linux has limited window_manager support; use minimal configuration
    if (Platform.isLinux) {
      const options = WindowOptions(
        center: true,
        minimumSize: Size(960, 600),
      );
      await windowManager.waitUntilReadyToShow(
        options,
        () async {
          try {
            await windowManager.show();
          } catch (e) {
            debugPrint('[Linux] Warning: Could not show window: $e');
          }
        },
      );
    } else {
      // Windows and macOS support more features
      const options = WindowOptions(
        center: true,
        minimumSize: Size(960, 600),
        titleBarStyle: TitleBarStyle.hidden,
      );
      await windowManager.waitUntilReadyToShow(
        options,
        () async {
          try {
            await windowManager.show();
            await windowManager.focus();
          } catch (e) {
            debugPrint('Error showing/focusing window: $e');
          }
        },
      );
    }
  } catch (e) {
    debugPrint('Warning: Window manager initialization failed: $e');
    // Continue running even if window manager fails
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
    await _initializeWindowManager();
  }

  runApp(const AeternaApp());
}
