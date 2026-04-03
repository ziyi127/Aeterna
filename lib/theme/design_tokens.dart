import 'package:flutter/material.dart';

abstract final class AeternaTokens {
  static const Color background = Color(0xFFF6F6F8);
  static const Color primary = Color(0xFF0B6E4F);
  static const Color secondary = Color(0xFF1479FF);
  static const Color countdownBackground = Color(0xFF103B73);
  static const Color countdownForeground = Color(0xFFFFFFFF);

  static const double superRadius = 24;
  static const double controlRadius = 16;
  static const double compactRadius = 12;
  static const double touchMinHeight = 56;
  static const double wideProgressHeight = 12;

  static const EdgeInsets pagePadding = EdgeInsets.all(24);
  static const EdgeInsets sectionGap = EdgeInsets.all(16);
  static const double sectionSpacing = 16;

  static const String timeFontFamily = 'monospace';

  // Global motion tokens for consistent app-wide animation rhythm.
  static const Duration motionDurationFast = Duration(milliseconds: 180);
  static const Duration motionDurationNormal = Duration(milliseconds: 280);
  static const Duration motionDurationSlow = Duration(milliseconds: 420);

  static const Curve motionCurveStandard = Curves.easeOutCubic;
  static const Curve motionCurveEmphasized = Curves.easeOutQuart;

  static BorderRadius get radiusSurface => BorderRadius.circular(superRadius);
  static BorderRadius get radiusControl => BorderRadius.circular(controlRadius);
  static BorderRadius get radiusCompact => BorderRadius.circular(compactRadius);

  static EdgeInsets pagePaddingFor(double width) {
    if (width >= 2200) {
      return const EdgeInsets.all(40);
    }
    if (width >= 1400) {
      return const EdgeInsets.all(28);
    }
    if (width <= 700) {
      return const EdgeInsets.all(14);
    }
    return pagePadding;
  }
}
