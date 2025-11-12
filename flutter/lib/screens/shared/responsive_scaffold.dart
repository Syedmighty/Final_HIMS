import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/responsive.dart';
import '../../controllers/navigation_controller.dart';

/// Responsive scaffold with sidebar (desktop) and bottom nav (mobile)
class ResponsiveScaffold extends ConsumerWidget {
  final Widget body;
  final String? title;
  final List<Widget>? actions;
  final Widget? floatingActionButton;

  const ResponsiveScaffold({
    Key? key,
    required this.body,
    this.title,
    this.actions,
    this.floatingActionButton,
  }) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final navState = ref.watch(navigationControllerProvider);
    final currentTitle = title ?? ref.watch(currentPageTitleProvider);

    if (Responsive.isDesktop(context)) {
      // Desktop layout with sidebar
      return Scaffold(
        body: Row(
          children: [
            // Sidebar
            const _DesktopSidebar(),

            // Main content
            Expanded(
              child: Column(
                children: [
                  // Header
                  _DesktopHeader(
                    title: currentTitle,
                    actions: actions,
                  ),

                  // Body
                  Expanded(
                    child: body,
                  ),
                ],
              ),
            ),
          ],
        ),
        floatingActionButton: floatingActionButton,
      );
    } else {
      // Mobile/Tablet layout with bottom nav
      return Scaffold(
        appBar: AppBar(
          title: Text(currentTitle),
          actions: actions,
        ),
        drawer: const _MobileDrawer(),
        body: body,
        bottomNavigationBar: const _BottomNavigation(),
        floatingActionButton: floatingActionButton,
      );
    }
  }
}

/// Desktop sidebar
class _DesktopSidebar extends ConsumerWidget {
  const _DesktopSidebar({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final navController = ref.read(navigationControllerProvider.notifier);
    final currentItem = ref.watch(navigationControllerProvider).currentItem;

    return Container(
      width: 260,
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(
          right: BorderSide(
            color: AppColors.border,
            width: 1,
          ),
        ),
      ),
      child: Column(
        children: [
          // Logo/Brand
          Container(
            height: 64,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.inventory_2,
                    color: AppColors.textOnPrimary,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  'HIMS',
                  style: AppTextStyles.titleLarge.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),

          const Divider(height: 1),

          // Navigation items
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: navigationItems.map((item) {
                final isActive = currentItem == item.item;

                return _SidebarItem(
                  icon: isActive && item.activeIcon != null
                      ? item.activeIcon!
                      : item.icon,
                  label: item.label,
                  isActive: isActive,
                  onTap: () => navController.navigateTo(item.item),
                );
              }).toList(),
            ),
          ),

          // User profile section
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: AppColors.primaryLight,
                  child: Text(
                    'A',
                    style: AppTextStyles.titleMedium.copyWith(
                      color: AppColors.textOnPrimary,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Admin User',
                        style: AppTextStyles.labelLarge,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        'Administrator',
                        style: AppTextStyles.labelSmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Sidebar navigation item
class _SidebarItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _SidebarItem({
    Key? key,
    required this.icon,
    required this.label,
    required this.isActive,
    required this.onTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              color: isActive
                  ? AppColors.primary.withOpacity(0.1)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 24,
                  color: isActive ? AppColors.primary : AppColors.textSecondary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    style: isActive
                        ? AppTextStyles.navLabelActive
                        : AppTextStyles.navLabel.copyWith(
                            color: AppColors.textSecondary,
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Desktop header
class _DesktopHeader extends StatelessWidget {
  final String title;
  final List<Widget>? actions;

  const _DesktopHeader({
    Key? key,
    required this.title,
    this.actions,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(
          bottom: BorderSide(
            color: AppColors.border,
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          Text(
            title,
            style: AppTextStyles.titleLarge,
          ),
          const Spacer(),
          if (actions != null) ...actions!,
        ],
      ),
    );
  }
}

/// Bottom navigation for mobile
class _BottomNavigation extends ConsumerWidget {
  const _BottomNavigation({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final navController = ref.read(navigationControllerProvider.notifier);
    final navState = ref.watch(navigationControllerProvider);
    final currentIndex = navState.bottomNavIndex;

    return BottomNavigationBar(
      currentIndex: currentIndex >= 0 ? currentIndex : 0,
      onTap: navController.navigateToIndex,
      type: BottomNavigationBarType.fixed,
      selectedItemColor: AppColors.primary,
      unselectedItemColor: AppColors.textSecondary,
      selectedLabelStyle: AppTextStyles.labelSmall,
      unselectedLabelStyle: AppTextStyles.labelSmall,
      items: bottomNavigationItems.map((item) {
        final isActive = navState.currentItem == item.item;
        return BottomNavigationBarItem(
          icon: Icon(item.icon),
          activeIcon: Icon(item.activeIcon ?? item.icon),
          label: item.label,
        );
      }).toList(),
    );
  }
}

/// Mobile drawer
class _MobileDrawer extends ConsumerWidget {
  const _MobileDrawer({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final navController = ref.read(navigationControllerProvider.notifier);
    final currentItem = ref.watch(navigationControllerProvider).currentItem;

    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(24),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.inventory_2,
                      color: AppColors.textOnPrimary,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'HIMS',
                        style: AppTextStyles.titleLarge.copyWith(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        'Hotel Inventory',
                        style: AppTextStyles.labelSmall,
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const Divider(height: 1),

            // Navigation items
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: navigationItems.map((item) {
                  final isActive = currentItem == item.item;

                  return ListTile(
                    leading: Icon(
                      isActive && item.activeIcon != null
                          ? item.activeIcon!
                          : item.icon,
                      color: isActive
                          ? AppColors.primary
                          : AppColors.textSecondary,
                    ),
                    title: Text(
                      item.label,
                      style: isActive
                          ? AppTextStyles.labelLarge.copyWith(
                              color: AppColors.primary,
                            )
                          : AppTextStyles.labelLarge,
                    ),
                    selected: isActive,
                    selectedTileColor: AppColors.primary.withOpacity(0.1),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    onTap: () {
                      navController.navigateTo(item.item);
                      Navigator.pop(context);
                    },
                  );
                }).toList(),
              ),
            ),

            // User profile
            const Divider(height: 1),
            ListTile(
              leading: CircleAvatar(
                backgroundColor: AppColors.primaryLight,
                child: Text(
                  'A',
                  style: AppTextStyles.titleMedium.copyWith(
                    color: AppColors.textOnPrimary,
                  ),
                ),
              ),
              title: Text(
                'Admin User',
                style: AppTextStyles.labelLarge,
              ),
              subtitle: Text(
                'Administrator',
                style: AppTextStyles.labelSmall,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
