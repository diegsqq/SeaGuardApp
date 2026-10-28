import 'dart:math' as math;
import 'package:flutter/widgets.dart';

class Responsive {
  static double width(BuildContext context) => MediaQuery.of(context).size.width;

  static bool isSmall(BuildContext context) => width(context) < 360;
  static bool isTablet(BuildContext context) => width(context) >= 600;
  static bool isDesktop(BuildContext context) => width(context) >= 1024;

  static double pagePadding(BuildContext context) {
    final w = width(context);
    if (w < 360) return 12;
    if (w < 480) return 14;
    if (w < 768) return 16;
    if (w < 1024) return 20;
    return 24;
  }

  static double verticalSpace(BuildContext context) {
    final w = width(context);
    if (w < 360) return 12;
    if (w < 480) return 14;
    if (w < 768) return 16;
    if (w < 1024) return 18;
    return 20;
  }

  static double maxContentWidth(BuildContext context, {double maxWidth = 1100}) {
    return math.min(maxWidth, width(context));
  }

  static T value<T>(
    BuildContext context, {
    required T mobile,
    T? tablet,
    T? desktop,
  }) {
    if (isDesktop(context) && desktop != null) return desktop;
    if (isTablet(context) && tablet != null) return tablet;
    return mobile;
  }
}
