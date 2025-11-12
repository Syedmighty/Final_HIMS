import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/theme/app_theme.dart';
import 'controllers/navigation_controller.dart';
import 'screens/shared/responsive_scaffold.dart';
import 'screens/dashboard/dashboard_screen.dart';
import 'screens/inventory/inventory_screen.dart';
import 'screens/settings/settings_screen.dart';
import 'screens/reports/reports_screen.dart';

void main() {
  runApp(
    const ProviderScope(
      child: HIMSApp(),
    ),
  );
}

/// Main HIMS application
class HIMSApp extends StatelessWidget {
  const HIMSApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'HIMS - Hotel Inventory Management',
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.light,
      debugShowCheckedModeBanner: false,
      home: const MainScreen(),
    );
  }
}

/// Main screen with navigation
class MainScreen extends ConsumerWidget {
  const MainScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final navState = ref.watch(navigationControllerProvider);

    return ResponsiveScaffold(
      body: _getScreenForNavigationItem(navState.currentItem),
    );
  }

  /// Get the appropriate screen based on navigation item
  Widget _getScreenForNavigationItem(NavigationItem item) {
    switch (item) {
      case NavigationItem.dashboard:
        return const DashboardScreen();

      case NavigationItem.inventory:
        return const InventoryScreen();

      case NavigationItem.purchases:
        return const PurchasesScreen();

      case NavigationItem.issues:
        return const IssuesScreen();

      case NavigationItem.transfers:
        return const TransfersScreen();

      case NavigationItem.invoices:
        return const InvoicesScreen();

      case NavigationItem.wastage:
        return const WastageScreen();

      case NavigationItem.reports:
        return const ReportsScreen();

      case NavigationItem.settings:
        return const SettingsScreen();
    }
  }
}

// Placeholder screens for navigation items not yet implemented
class PurchasesScreen extends StatelessWidget {
  const PurchasesScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text('Purchases Screen - Coming Soon'),
    );
  }
}

class IssuesScreen extends StatelessWidget {
  const IssuesScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text('Issues Screen - Coming Soon'),
    );
  }
}

class TransfersScreen extends StatelessWidget {
  const TransfersScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text('Transfers Screen - Coming Soon'),
    );
  }
}

class InvoicesScreen extends StatelessWidget {
  const InvoicesScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text('Invoices Screen - Coming Soon'),
    );
  }
}

class WastageScreen extends StatelessWidget {
  const WastageScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text('Wastage Screen - Coming Soon'),
    );
  }
}
