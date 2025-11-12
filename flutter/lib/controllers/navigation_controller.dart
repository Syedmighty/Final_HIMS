import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Navigation items
enum NavigationItem {
  dashboard,
  inventory,
  purchases,
  issues,
  transfers,
  invoices,
  wastage,
  reports,
  settings,
}

/// Navigation item data
class NavItemData {
  final NavigationItem item;
  final String label;
  final IconData icon;
  final IconData? activeIcon;

  const NavItemData({
    required this.item,
    required this.label,
    required this.icon,
    this.activeIcon,
  });
}

/// Navigation items list
const List<NavItemData> navigationItems = [
  NavItemData(
    item: NavigationItem.dashboard,
    label: 'Dashboard',
    icon: Icons.dashboard_outlined,
    activeIcon: Icons.dashboard,
  ),
  NavItemData(
    item: NavigationItem.inventory,
    label: 'Inventory',
    icon: Icons.inventory_2_outlined,
    activeIcon: Icons.inventory_2,
  ),
  NavItemData(
    item: NavigationItem.purchases,
    label: 'Purchases',
    icon: Icons.shopping_cart_outlined,
    activeIcon: Icons.shopping_cart,
  ),
  NavItemData(
    item: NavigationItem.issues,
    label: 'Issues',
    icon: Icons.output_outlined,
    activeIcon: Icons.output,
  ),
  NavItemData(
    item: NavigationItem.transfers,
    label: 'Transfers',
    icon: Icons.swap_horiz_outlined,
    activeIcon: Icons.swap_horiz,
  ),
  NavItemData(
    item: NavigationItem.invoices,
    label: 'Invoices',
    icon: Icons.receipt_long_outlined,
    activeIcon: Icons.receipt_long,
  ),
  NavItemData(
    item: NavigationItem.wastage,
    label: 'Wastage',
    icon: Icons.delete_outline,
    activeIcon: Icons.delete,
  ),
  NavItemData(
    item: NavigationItem.reports,
    label: 'Reports',
    icon: Icons.analytics_outlined,
    activeIcon: Icons.analytics,
  ),
  NavItemData(
    item: NavigationItem.settings,
    label: 'Settings',
    icon: Icons.settings_outlined,
    activeIcon: Icons.settings,
  ),
];

/// Bottom navigation items (subset for mobile)
const List<NavItemData> bottomNavigationItems = [
  NavItemData(
    item: NavigationItem.dashboard,
    label: 'Home',
    icon: Icons.home_outlined,
    activeIcon: Icons.home,
  ),
  NavItemData(
    item: NavigationItem.inventory,
    label: 'Inventory',
    icon: Icons.inventory_2_outlined,
    activeIcon: Icons.inventory_2,
  ),
  NavItemData(
    item: NavigationItem.invoices,
    label: 'Sales',
    icon: Icons.receipt_long_outlined,
    activeIcon: Icons.receipt_long,
  ),
  NavItemData(
    item: NavigationItem.reports,
    label: 'Reports',
    icon: Icons.analytics_outlined,
    activeIcon: Icons.analytics,
  ),
];

/// Navigation state
class NavigationState {
  final NavigationItem currentItem;
  final bool isDrawerOpen;

  NavigationState({
    this.currentItem = NavigationItem.dashboard,
    this.isDrawerOpen = false,
  });

  NavigationState copyWith({
    NavigationItem? currentItem,
    bool? isDrawerOpen,
  }) {
    return NavigationState(
      currentItem: currentItem ?? this.currentItem,
      isDrawerOpen: isDrawerOpen ?? this.isDrawerOpen,
    );
  }

  /// Get current item index for bottom nav
  int get bottomNavIndex {
    return bottomNavigationItems.indexWhere(
      (item) => item.item == currentItem,
    );
  }
}

/// Navigation controller
class NavigationController extends StateNotifier<NavigationState> {
  NavigationController() : super(NavigationState());

  /// Navigate to item
  void navigateTo(NavigationItem item) {
    state = state.copyWith(currentItem: item);
  }

  /// Navigate to index (for bottom nav)
  void navigateToIndex(int index) {
    if (index >= 0 && index < bottomNavigationItems.length) {
      state = state.copyWith(
        currentItem: bottomNavigationItems[index].item,
      );
    }
  }

  /// Toggle drawer
  void toggleDrawer() {
    state = state.copyWith(isDrawerOpen: !state.isDrawerOpen);
  }

  /// Close drawer
  void closeDrawer() {
    state = state.copyWith(isDrawerOpen: false);
  }

  /// Open drawer
  void openDrawer() {
    state = state.copyWith(isDrawerOpen: true);
  }

  /// Get nav item data
  NavItemData? getNavItemData(NavigationItem item) {
    try {
      return navigationItems.firstWhere((nav) => nav.item == item);
    } catch (e) {
      return null;
    }
  }

  /// Check if item is active
  bool isActive(NavigationItem item) {
    return state.currentItem == item;
  }
}

/// Navigation controller provider
final navigationControllerProvider =
    StateNotifierProvider<NavigationController, NavigationState>((ref) {
  return NavigationController();
});

/// Current page title provider
final currentPageTitleProvider = Provider<String>((ref) {
  final navState = ref.watch(navigationControllerProvider);
  final itemData = navigationItems.firstWhere(
    (item) => item.item == navState.currentItem,
    orElse: () => navigationItems.first,
  );
  return itemData.label;
});
