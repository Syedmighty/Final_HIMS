import 'package:flutter/material.dart';
import '../../core/utils/responsive.dart';
import 'dashboard_desktop.dart';
import 'dashboard_mobile.dart';

/// Main dashboard screen - switches between desktop and mobile layouts
class DashboardScreen extends StatelessWidget {
  const DashboardScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Responsive(
      mobile: const DashboardMobile(),
      desktop: const DashboardDesktop(),
    );
  }
}
