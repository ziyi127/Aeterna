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
    const options = WindowOptions(
      center: true,
      minimumSize: Size(960, 600),
    );
    await windowManager.waitUntilReadyToShow(
      options,
      () async {
        await windowManager.show();
        if (!Platform.isLinux) {
          await windowManager.focus();
        }
      },
    );
  } catch (e) {
    debugPrint('Warning: window_manager init failed, fallback to show only: $e');
    try {
      await windowManager.show();
      if (!Platform.isLinux) {
        await windowManager.focus();
      }
    } catch (fallbackError) {
      debugPrint('Warning: window_manager fallback show failed: $fallbackError');
    }
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
