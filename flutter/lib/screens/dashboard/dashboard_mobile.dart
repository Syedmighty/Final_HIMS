import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/dashboard_card.dart';
import '../../core/widgets/quick_action_button.dart';
import '../../core/widgets/section_header.dart';
import '../../core/widgets/alert_chip.dart';
import '../../controllers/dashboard_controller.dart';

/// Dashboard mobile layout
class DashboardMobile extends ConsumerStatefulWidget {
  const DashboardMobile({Key? key}) : super(key: key);

  @override
  ConsumerState<DashboardMobile> createState() => _DashboardMobileState();
}

class _DashboardMobileState extends ConsumerState<DashboardMobile> {
  final _currencyFormat = NumberFormat.currency(symbol: '₹', decimalDigits: 0);

  @override
  void initState() {
    super.initState();
    // Load dashboard data on init
    Future.microtask(() {
      ref.read(dashboardControllerProvider.notifier).loadDashboard();
    });
  }

  @override
  Widget build(BuildContext context) {
    final dashboardState = ref.watch(dashboardControllerProvider);

    if (dashboardState.isLoading && !dashboardState.hasData) {
      return const Center(child: CircularProgressIndicator());
    }

    if (dashboardState.hasError) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.error_outline,
                size: 64,
                color: AppColors.error,
              ),
              const SizedBox(height: 16),
              Text(
                'Failed to load dashboard',
                style: AppTextStyles.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                dashboardState.error ?? 'Unknown error',
                style: AppTextStyles.bodySmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: () {
                  ref.read(dashboardControllerProvider.notifier).refresh();
                },
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    final dashboard = dashboardState.dashboard!;
    final alerts = dashboardState.alerts;

    return RefreshIndicator(
      onRefresh: () =>
          ref.read(dashboardControllerProvider.notifier).refresh(),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Quick Actions Grid
            _buildQuickActions(),
            const SizedBox(height: 20),

            // Stats Cards (2x2 grid)
            _buildStatsCards(dashboard),
            const SizedBox(height: 20),

            // Live Alerts
            if (alerts != null && alerts.allAlerts.isNotEmpty) ...[
              _buildLiveAlerts(alerts),
              const SizedBox(height: 20),
            ],

            // Recent Transactions
            _buildRecentTransactions(dashboard),
            const SizedBox(height: 80), // Space for bottom nav
          ],
        ),
      ),
    );
  }

  /// Build quick actions grid (4 circular buttons)
  Widget _buildQuickActions() {
    final actions = [
      QuickActionData(
        icon: Icons.add_shopping_cart,
        label: 'Purchase',
        onTap: () {
          // TODO: Navigate to purchase
        },
        color: AppColors.primary,
      ),
      QuickActionData(
        icon: Icons.receipt_long,
        label: 'Invoice',
        onTap: () {
          // TODO: Navigate to invoice
        },
        color: AppColors.success,
      ),
      QuickActionData(
        icon: Icons.output,
        label: 'Issue',
        onTap: () {
          // TODO: Navigate to issue
        },
        color: AppColors.warning,
      ),
      QuickActionData(
        icon: Icons.swap_horiz,
        label: 'Transfer',
        onTap: () {
          // TODO: Navigate to transfer
        },
        color: AppColors.info,
      ),
    ];

    return QuickActionsGrid(actions: actions);
  }

  /// Build stats cards (2x2 grid)
  Widget _buildStatsCards(dashboard) {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      childAspectRatio: 1.0,
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      children: [
        DashboardCard(
          icon: Icons.shopping_cart_outlined,
          title: 'Today',
          value: _currencyFormat.format(dashboard.salesToday.totalRevenue),
          subtitle: '${dashboard.salesToday.invoicesCount} sales',
          color: AppColors.primary,
          backgroundColor: AppColors.purchaseCard,
        ),
        DashboardCard(
          icon: Icons.trending_up,
          title: 'Month',
          value: _formatCompactCurrency(
              dashboard.salesThisMonth.totalRevenue),
          subtitle: '${dashboard.salesThisMonth.invoicesCount} sales',
          color: AppColors.success,
          backgroundColor: AppColors.stockCard,
        ),
        DashboardCard(
          icon: Icons.warning_amber_rounded,
          title: 'Alerts',
          value: '${dashboard.lowStockAlerts}',
          subtitle: 'Low stock',
          color: AppColors.warning,
          backgroundColor: AppColors.issueCard,
        ),
        DashboardCard(
          icon: Icons.inventory_2,
          title: 'Stock',
          value: _formatCompactCurrency(dashboard.totalStockValue),
          subtitle: 'Total value',
          color: AppColors.info,
          backgroundColor: AppColors.invoiceCard,
        ),
      ],
    );
  }

  /// Build live alerts
  Widget _buildLiveAlerts(alerts) {
    final alertsList = alerts.allAlerts.take(5).map((alert) {
      return AlertChipData(
        label: alert.shortMessage,
        icon: alert.type == AlertType.outOfStock
            ? Icons.error_outline
            : Icons.warning_amber_rounded,
        color: alert.type == AlertType.outOfStock
            ? AppColors.error
            : AppColors.warning,
        onTap: () {
          // TODO: Navigate to product
        },
      );
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: 'Live Alerts',
          subtitle: '${alerts.summary.totalAlerts} alerts',
          padding: EdgeInsets.zero,
        ),
        const SizedBox(height: 8),
        AlertChipList(
          alerts: alertsList,
          padding: EdgeInsets.zero,
        ),
      ],
    );
  }

  /// Build recent transactions (mobile list view)
  Widget _buildRecentTransactions(dashboard) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: 'Recent',
          subtitle: 'Last transactions',
          padding: EdgeInsets.zero,
        ),
        const SizedBox(height: 8),
        if (dashboard.recentActivities.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Center(
                child: Column(
                  children: [
                    Icon(
                      Icons.inbox_outlined,
                      size: 48,
                      color: AppColors.textDisabled,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'No transactions yet',
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          )
        else
          ...dashboard.recentActivities.take(5).map((activity) {
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: activity.type == 'invoice'
                      ? AppColors.success.withOpacity(0.2)
                      : AppColors.primary.withOpacity(0.2),
                  child: Icon(
                    activity.type == 'invoice'
                        ? Icons.receipt_long
                        : Icons.shopping_cart,
                    color: activity.type == 'invoice'
                        ? AppColors.success
                        : AppColors.primary,
                    size: 20,
                  ),
                ),
                title: Text(
                  activity.reference,
                  style: AppTextStyles.labelLarge,
                ),
                subtitle: Text(
                  _formatDateTime(activity.createdAt),
                  style: AppTextStyles.labelSmall,
                ),
                trailing: Text(
                  _currencyFormat.format(activity.amount),
                  style: AppTextStyles.titleSmall.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            );
          }).toList(),
      ],
    );
  }

  /// Format currency in compact form (e.g., 1.5K, 2.3M)
  String _formatCompactCurrency(double amount) {
    if (amount >= 10000000) {
      return '₹${(amount / 10000000).toStringAsFixed(1)}Cr';
    } else if (amount >= 100000) {
      return '₹${(amount / 100000).toStringAsFixed(1)}L';
    } else if (amount >= 1000) {
      return '₹${(amount / 1000).toStringAsFixed(1)}K';
    } else {
      return _currencyFormat.format(amount);
    }
  }

  String _formatDateTime(String dateTime) {
    try {
      final date = DateTime.parse(dateTime);
      final now = DateTime.now();
      final difference = now.difference(date);

      if (difference.inMinutes < 60) {
        return '${difference.inMinutes}m ago';
      } else if (difference.inHours < 24) {
        return '${difference.inHours}h ago';
      } else if (difference.inDays < 7) {
        return '${difference.inDays}d ago';
      } else {
        return DateFormat('dd MMM').format(date);
      }
    } catch (e) {
      return dateTime;
    }
  }
}
