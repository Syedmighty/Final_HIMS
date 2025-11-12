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

/// Dashboard desktop layout
class DashboardDesktop extends ConsumerStatefulWidget {
  const DashboardDesktop({Key? key}) : super(key: key);

  @override
  ConsumerState<DashboardDesktop> createState() => _DashboardDesktopState();
}

class _DashboardDesktopState extends ConsumerState<DashboardDesktop> {
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
            ),
            const SizedBox(height: 8),
            Text(
              dashboardState.error ?? 'Unknown error',
              style: AppTextStyles.bodySmall,
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
      );
    }

    final dashboard = dashboardState.dashboard!;
    final alerts = dashboardState.alerts;

    return RefreshIndicator(
      onRefresh: () =>
          ref.read(dashboardControllerProvider.notifier).refresh(),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Quick Actions Row
            _buildQuickActions(),
            const SizedBox(height: 24),

            // Stats Cards Grid (2x2)
            _buildStatsCards(dashboard),
            const SizedBox(height: 24),

            // Live Alerts
            if (alerts != null && alerts.allAlerts.isNotEmpty) ...[
              _buildLiveAlerts(alerts),
              const SizedBox(height: 24),
            ],

            // Recent Transactions
            _buildRecentTransactions(dashboard),
          ],
        ),
      ),
    );
  }

  /// Build quick actions row
  Widget _buildQuickActions() {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        QuickActionButton(
          icon: Icons.add_shopping_cart,
          label: 'New Purchase',
          onTap: () {
            // TODO: Navigate to purchase screen
          },
          color: AppColors.primary,
        ),
        QuickActionButton(
          icon: Icons.receipt_long,
          label: 'New Invoice',
          onTap: () {
            // TODO: Navigate to invoice screen
          },
          color: AppColors.success,
        ),
        QuickActionButton(
          icon: Icons.output,
          label: 'Issue Stock',
          onTap: () {
            // TODO: Navigate to issue screen
          },
          color: AppColors.warning,
        ),
        QuickActionButton(
          icon: Icons.swap_horiz,
          label: 'Transfer',
          onTap: () {
            // TODO: Navigate to transfer screen
          },
          color: AppColors.info,
        ),
      ],
    );
  }

  /// Build stats cards grid
  Widget _buildStatsCards(dashboard) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = constraints.maxWidth > 1200 ? 4 : 2;

        return GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: crossAxisCount,
          childAspectRatio: 1.5,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
          children: [
            DashboardCard(
              icon: Icons.shopping_cart_outlined,
              title: 'Today\'s Sales',
              value: _currencyFormat.format(dashboard.salesToday.totalRevenue),
              subtitle: '${dashboard.salesToday.invoicesCount} invoices',
              color: AppColors.primary,
              backgroundColor: AppColors.purchaseCard,
            ),
            DashboardCard(
              icon: Icons.trending_up,
              title: 'This Month',
              value: _currencyFormat
                  .format(dashboard.salesThisMonth.totalRevenue),
              subtitle: '${dashboard.salesThisMonth.invoicesCount} invoices',
              color: AppColors.success,
              backgroundColor: AppColors.stockCard,
            ),
            DashboardCard(
              icon: Icons.warning_amber_rounded,
              title: 'Low Stock Alerts',
              value: '${dashboard.lowStockAlerts}',
              subtitle: 'Items need reorder',
              color: AppColors.warning,
              backgroundColor: AppColors.issueCard,
            ),
            DashboardCard(
              icon: Icons.inventory_2,
              title: 'Stock Value',
              value: _currencyFormat.format(dashboard.totalStockValue),
              subtitle: 'Total inventory',
              color: AppColors.info,
              backgroundColor: AppColors.invoiceCard,
            ),
          ],
        );
      },
    );
  }

  /// Build live alerts section
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
          // TODO: Navigate to product details
        },
      );
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: 'Live Alerts',
          subtitle: '${alerts.summary.totalAlerts} total alerts',
          padding: EdgeInsets.zero,
        ),
        const SizedBox(height: 12),
        AlertChipList(
          alerts: alertsList,
          padding: EdgeInsets.zero,
        ),
      ],
    );
  }

  /// Build recent transactions section
  Widget _buildRecentTransactions(dashboard) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: 'Recent Transactions',
          subtitle: 'Last 10 transactions',
          padding: EdgeInsets.zero,
        ),
        const SizedBox(height: 12),
        Card(
          child: dashboard.recentActivities.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(48),
                  child: Center(
                    child: Column(
                      children: [
                        Icon(
                          Icons.inbox_outlined,
                          size: 48,
                          color: AppColors.textDisabled,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No recent transactions',
                          style: AppTextStyles.bodyMedium.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    columns: [
                      DataColumn(
                        label: Text('Type', style: AppTextStyles.labelLarge),
                      ),
                      DataColumn(
                        label: Text('Reference', style: AppTextStyles.labelLarge),
                      ),
                      DataColumn(
                        label: Text('Amount', style: AppTextStyles.labelLarge),
                      ),
                      DataColumn(
                        label: Text('Date', style: AppTextStyles.labelLarge),
                      ),
                    ],
                    rows: dashboard.recentActivities.map<DataRow>((activity) {
                      return DataRow(
                        cells: [
                          DataCell(
                            Chip(
                              label: Text(
                                activity.type.toUpperCase(),
                                style: AppTextStyles.labelSmall,
                              ),
                              backgroundColor: activity.type == 'invoice'
                                  ? AppColors.success.withOpacity(0.1)
                                  : AppColors.primary.withOpacity(0.1),
                            ),
                          ),
                          DataCell(Text(
                            activity.reference,
                            style: AppTextStyles.bodyMedium,
                          )),
                          DataCell(Text(
                            _currencyFormat.format(activity.amount),
                            style: AppTextStyles.bodyMedium.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          )),
                          DataCell(Text(
                            _formatDateTime(activity.createdAt),
                            style: AppTextStyles.bodySmall,
                          )),
                        ],
                      );
                    }).toList(),
                  ),
                ),
        ),
      ],
    );
  }

  String _formatDateTime(String dateTime) {
    try {
      final date = DateTime.parse(dateTime);
      final now = DateTime.now();
      final difference = now.difference(date);

      if (difference.inDays == 0) {
        return DateFormat('HH:mm').format(date);
      } else if (difference.inDays < 7) {
        return DateFormat('EEE HH:mm').format(date);
      } else {
        return DateFormat('dd MMM').format(date);
      }
    } catch (e) {
      return dateTime;
    }
  }
}
