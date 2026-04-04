import 'dart:async';
import 'dart:io';

import 'package:aeterna/app/app.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

final _memoryPressureObserver = _MemoryPressureObserver();

class _MemoryPressureObserver extends WidgetsBindingObserver {
  @override
  void didHaveMemoryPressure() {
    // Release cached images immediately when the OS signals memory pressure.
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
  }
}

Future<void> _initializeWindowManager() async {
  // Desktop startup should try to create and show a window in one guarded path.
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

String _initialRouteFromArgs(List<String> args) {
  // The watchdog restarts the app with a dedicated resume flag.
  if (args.any((arg) => arg == '--presentation-resume=monitor')) {
    return '/monitor';
  }
  return '/';
}

Future<void> main(List<String> args) async {
  // Keep the entire startup sequence inside a guarded zone so uncaught errors are logged.
  await runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      debugPrint('FlutterError caught: ${details.exceptionAsString()}');
    };

    PlatformDispatcher.instance.onError = (error, stack) {
      debugPrint('PlatformDispatcher error: $error');
      debugPrint('$stack');
      return true;
    };

    ErrorWidget.builder = (details) {
      // Fall back to a plain error surface if a widget tree fails to build.
      return Material(
        color: Colors.black,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              '界面组件异常，已进入安全显示模式。\n${details.exceptionAsString()}',
              style: const TextStyle(color: Colors.white),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    };

    // Cap image cache to avoid excessive memory growth across platforms.
    PaintingBinding.instance.imageCache.maximumSize = 80;
    PaintingBinding.instance.imageCache.maximumSizeBytes = 24 << 20;
    // Listen for OS memory pressure events so the cache can be trimmed promptly.
    WidgetsBinding.instance.addObserver(_memoryPressureObserver);

    // Initialize window manager for desktop platforms
    if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      await _initializeWindowManager();
    }

    // Launch the app with a resume-aware initial route.
    runApp(AeternaApp(initialRoute: _initialRouteFromArgs(args)));
  }, (error, stack) {
    debugPrint('Fatal zoned error: $error');
    debugPrint('$stack');
  });
}
