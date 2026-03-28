import 'package:aeterna/theme/design_tokens.dart';
import 'package:flutter/material.dart';

enum ThemePalette { emerald, cobalt, terracotta }

extension ThemePaletteLabel on ThemePalette {
  String get label {
    switch (this) {
      case ThemePalette.emerald:
        return '翡翠绿';
      case ThemePalette.cobalt:
        return '钴蓝';
      case ThemePalette.terracotta:
        return '陶土橙';
    }
  }

  Color get seed {
    switch (this) {
      case ThemePalette.emerald:
        return const Color(0xFF0B6E4F);
      case ThemePalette.cobalt:
        return const Color(0xFF1E5EFF);
      case ThemePalette.terracotta:
        return const Color(0xFFB9572A);
    }
  }

  String get key {
    switch (this) {
      case ThemePalette.emerald:
        return 'emerald';
      case ThemePalette.cobalt:
        return 'cobalt';
      case ThemePalette.terracotta:
        return 'terracotta';
    }
  }

  static ThemePalette fromKey(String key) {
    for (final value in ThemePalette.values) {
      if (value.key == key) {
        return value;
      }
    }
    return ThemePalette.emerald;
  }
}

abstract final class AppTheme {
  static ThemeData light(ThemePalette palette) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: palette.seed,
      brightness: Brightness.light,
    );
    return _buildTheme(
      colorScheme: colorScheme,
      scaffoldBackgroundColor: AeternaTokens.background,
    );
  }

  static ThemeData dark(ThemePalette palette) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: palette.seed,
      brightness: Brightness.dark,
    );
    return _buildTheme(
      colorScheme: colorScheme,
      scaffoldBackgroundColor: colorScheme.surface,
    );
  }

  static ThemeData _buildTheme({
    required ColorScheme colorScheme,
    required Color scaffoldBackgroundColor,
  }) {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: scaffoldBackgroundColor,
    );

    final text = base.textTheme.copyWith(
      displaySmall: base.textTheme.displaySmall?.copyWith(
        fontWeight: FontWeight.w800,
        letterSpacing: 0,
      ),
      displayLarge: base.textTheme.displayLarge?.copyWith(
        fontFamily: AeternaTokens.timeFontFamily,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.4,
      ),
    );

    return base.copyWith(
      textTheme: text,
      cardTheme: const CardThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(
            Radius.circular(AeternaTokens.superRadius),
          ),
        ),
        margin: EdgeInsets.zero,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(120, AeternaTokens.touchMinHeight),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AeternaTokens.superRadius),
          ),
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          minimumSize: WidgetStateProperty.all(
            const Size(120, AeternaTokens.touchMinHeight),
          ),
          shape: WidgetStateProperty.all(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AeternaTokens.superRadius),
            ),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AeternaTokens.superRadius),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: 18,
        ),
      ),
    );
  }
}
