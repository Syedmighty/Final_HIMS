import 'package:flutter/material.dart';

/// Responsive utility class for breakpoint-based layouts
/// Breakpoints: Mobile (<700px), Tablet (700-1100px), Desktop (>1100px)
class Responsive extends StatelessWidget {
  final Widget mobile;
  final Widget? tablet;
  final Widget desktop;

  const Responsive({
    Key? key,
    required this.mobile,
    this.tablet,
    required this.desktop,
  }) : super(key: key);

  /// Check if screen is mobile
  static bool isMobile(BuildContext context) =>
      MediaQuery.of(context).size.width < 700;

  /// Check if screen is tablet
  static bool isTablet(BuildContext context) =>
      MediaQuery.of(context).size.width >= 700 &&
      MediaQuery.of(context).size.width < 1100;

  /// Check if screen is desktop
  static bool isDesktop(BuildContext context) =>
      MediaQuery.of(context).size.width >= 1100;

  /// Get screen width
  static double width(BuildContext context) =>
      MediaQuery.of(context).size.width;

  /// Get screen height
  static double height(BuildContext context) =>
      MediaQuery.of(context).size.height;

  /// Get responsive value based on screen size
  static T value<T>(
    BuildContext context, {
    required T mobile,
    T? tablet,
    required T desktop,
  }) {
    if (isDesktop(context)) {
      return desktop;
    } else if (isTablet(context)) {
      return tablet ?? mobile;
    } else {
      return mobile;
    }
  }

  /// Get grid columns count based on screen size
  static int gridColumns(BuildContext context) {
    if (isDesktop(context)) {
      return 3; // 3 columns on desktop
    } else if (isTablet(context)) {
      return 2; // 2 columns on tablet
    } else {
      return 1; // 1 column on mobile
    }
  }

  /// Get card cross-axis count for dashboard
  static int dashboardCardColumns(BuildContext context) {
    if (isDesktop(context)) {
      return 4; // 4 cards per row on desktop
    } else if (isTablet(context)) {
      return 2; // 2 cards per row on tablet
    } else {
      return 2; // 2 cards per row on mobile
    }
  }

  /// Get horizontal padding based on screen size
  static double horizontalPadding(BuildContext context) {
    if (isDesktop(context)) {
      return 24.0;
    } else if (isTablet(context)) {
      return 16.0;
    } else {
      return 16.0;
    }
  }

  /// Get vertical padding based on screen size
  static double verticalPadding(BuildContext context) {
    if (isDesktop(context)) {
      return 24.0;
    } else if (isTablet(context)) {
      return 16.0;
    } else {
      return 12.0;
    }
  }

  /// Get sidebar width for desktop
  static double sidebarWidth(BuildContext context) {
    return isDesktop(context) ? 260.0 : 0.0;
  }

  /// Check if sidebar should be visible
  static bool showSidebar(BuildContext context) => isDesktop(context);

  /// Check if bottom navigation should be visible
  static bool showBottomNav(BuildContext context) => !isDesktop(context);

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    if (size.width >= 1100) {
      return desktop;
    } else if (size.width >= 700 && tablet != null) {
      return tablet!;
    } else {
      return mobile;
    }
  }
}

/// Extension for responsive values
extension ResponsiveExtension on BuildContext {
  bool get isMobile => Responsive.isMobile(this);
  bool get isTablet => Responsive.isTablet(this);
  bool get isDesktop => Responsive.isDesktop(this);

  double get screenWidth => Responsive.width(this);
  double get screenHeight => Responsive.height(this);

  int get gridColumns => Responsive.gridColumns(this);
  int get dashboardColumns => Responsive.dashboardCardColumns(this);

  double get horizontalPadding => Responsive.horizontalPadding(this);
  double get verticalPadding => Responsive.verticalPadding(this);

  bool get showSidebar => Responsive.showSidebar(this);
  bool get showBottomNav => Responsive.showBottomNav(this);
}
