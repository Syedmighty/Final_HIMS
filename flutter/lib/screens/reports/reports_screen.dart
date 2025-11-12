import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/responsive.dart';
import '../../core/widgets/section_header.dart';
import '../../core/widgets/alert_chip.dart';
import '../../controllers/dashboard_controller.dart';

/// Reports screen
class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({Key? key}) : super(key: key);

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  int _selectedReportIndex = 0;
  final _currencyFormat = NumberFormat.currency(symbol: '₹', decimalDigits: 2);

  final List<_ReportTab> _reportTabs = const [
    _ReportTab(
      label: 'Overview',
      icon: Icons.dashboard_outlined,
    ),
    _ReportTab(
      label: 'Sales',
      icon: Icons.trending_up,
    ),
    _ReportTab(
      label: 'Stock',
      icon: Icons.inventory_2_outlined,
    ),
    _ReportTab(
      label: 'Low Stock',
      icon: Icons.warning_amber_rounded,
    ),
  ];

  @override
  void initState() {
    super.initState();
    // Load dashboard data for reports
    Future.microtask(() {
      ref.read(dashboardControllerProvider.notifier).loadDashboard();
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = Responsive.isDesktop(context);

    if (isDesktop) {
      return _buildDesktopLayout();
    } else {
      return _buildMobileLayout();
    }
  }

  Widget _buildDesktopLayout() {
    return Row(
      children: [
        // Sidebar with report types
        Container(
          width: 240,
          decoration: BoxDecoration(
            color: AppColors.surface,
            border: Border(
              right: BorderSide(color: AppColors.border, width: 1),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Reports',
                  style: AppTextStyles.titleLarge,
                ),
              ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: _reportTabs.length,
                  itemBuilder: (context, index) {
                    final tab = _reportTabs[index];
                    final isSelected = _selectedReportIndex == index;

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: ListTile(
                        leading: Icon(
                          tab.icon,
                          color: isSelected
                              ? AppColors.primary
                              : AppColors.textSecondary,
                        ),
                        title: Text(
                          tab.label,
                          style: isSelected
                              ? AppTextStyles.labelLarge.copyWith(
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.w600,
                                )
                              : AppTextStyles.labelLarge,
                        ),
                        selected: isSelected,
                        selectedTileColor: AppColors.primary.withOpacity(0.1),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        onTap: () {
                          setState(() {
                            _selectedReportIndex = index;
                          });
                        },
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),

        // Main content
        Expanded(
          child: _buildReportContent(),
        ),
      ],
    );
  }

  Widget _buildMobileLayout() {
    return Column(
      children: [
        // Tab bar
        Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            border: Border(
              bottom: BorderSide(color: AppColors.border, width: 1),
            ),
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: _reportTabs.asMap().entries.map((entry) {
                final index = entry.key;
                final tab = entry.value;
                final isSelected = _selectedReportIndex == index;

                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(tab.icon, size: 16),
                        const SizedBox(width: 6),
                        Text(tab.label),
                      ],
                    ),
                    selected: isSelected,
                    onSelected: (selected) {
                      setState(() {
                        _selectedReportIndex = index;
                      });
                    },
                  ),
                );
              }).toList(),
            ),
          ),
        ),

        // Content
        Expanded(
          child: _buildReportContent(),
        ),
      ],
    );
  }

  Widget _buildReportContent() {
    return SingleChildScrollView(
      padding: EdgeInsets.all(Responsive.isDesktop(context) ? 24 : 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (Responsive.isDesktop(context)) ...[
            SectionHeader(
              title: _reportTabs[_selectedReportIndex].label,
              subtitle: _getReportSubtitle(),
            ),
            const SizedBox(height: 24),
          ],

          // Report content based on selected index
          _buildSelectedReport(),
        ],
      ),
    );
  }

  String _getReportSubtitle() {
    switch (_selectedReportIndex) {
      case 0:
        return 'Business overview and key metrics';
      case 1:
        return 'Sales performance and trends';
      case 2:
        return 'Stock levels and inventory value';
      case 3:
        return 'Products requiring attention';
      default:
        return '';
    }
  }

  Widget _buildSelectedReport() {
    switch (_selectedReportIndex) {
      case 0:
        return _buildOverviewReport();
      case 1:
        return _buildSalesReport();
      case 2:
        return _buildStockReport();
      case 3:
        return _buildLowStockReport();
      default:
        return const SizedBox();
    }
  }

  Widget _buildOverviewReport() {
    final dashboardState = ref.watch(dashboardControllerProvider);

    if (dashboardState.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (dashboardState.error != null) {
      return _buildErrorWidget(dashboardState.error!);
    }

    final dashboard = dashboardState.dashboard;
    if (dashboard == null) {
      return const Center(child: Text('No data available'));
    }

    return Column(
      children: [
        // Key metrics grid
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: Responsive.isDesktop(context) ? 4 : 2,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
          childAspectRatio: 1.5,
          children: [
            _buildMetricCard(
              title: 'Today\'s Sales',
              value: _currencyFormat.format(dashboard.salesToday.totalRevenue),
              subtitle: '${dashboard.salesToday.invoicesCount} invoices',
              icon: Icons.receipt_long,
              color: AppColors.success,
            ),
            _buildMetricCard(
              title: 'This Month',
              value: _currencyFormat.format(dashboard.salesThisMonth.totalRevenue),
              subtitle: '${dashboard.salesThisMonth.invoicesCount} invoices',
              icon: Icons.calendar_month,
              color: AppColors.primary,
            ),
            _buildMetricCard(
              title: 'Stock Value',
              value: _currencyFormat.format(dashboard.totalStockValue),
              subtitle: 'Total inventory',
              icon: Icons.inventory_2,
              color: AppColors.info,
            ),
            _buildMetricCard(
              title: 'Low Stock',
              value: '${dashboard.lowStockAlerts}',
              subtitle: 'Products',
              icon: Icons.warning,
              color: AppColors.warning,
            ),
          ],
        ),

        const SizedBox(height: 32),

        // Recent activity
        const SectionHeader(
          title: 'Recent Activity',
          subtitle: 'Latest transactions',
        ),

        const SizedBox(height: 16),

        _buildRecentActivityList(dashboard.recentActivities),
      ],
    );
  }

  Widget _buildMetricCard({
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color color,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, color: color, size: 20),
                ),
                const Spacer(),
              ],
            ),
            const Spacer(),
            Text(
              title,
              style: AppTextStyles.labelMedium,
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: AppTextStyles.displaySmall.copyWith(
                fontSize: 24,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: AppTextStyles.labelSmall,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecentActivityList(List activities) {
    if (activities.isEmpty) {
      return const Center(child: Text('No recent activity'));
    }

    return Card(
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: activities.length,
        separatorBuilder: (context, index) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final activity = activities[index];
          return ListTile(
            leading: CircleAvatar(
              backgroundColor: _getActivityColor(activity.type).withOpacity(0.1),
              child: Icon(
                _getActivityIcon(activity.type),
                color: _getActivityColor(activity.type),
                size: 20,
              ),
            ),
            title: Text(
              activity.reference,
              style: AppTextStyles.labelLarge,
            ),
            subtitle: Text(
              _formatActivityType(activity.type),
              style: AppTextStyles.bodySmall,
            ),
            trailing: Text(
              _currencyFormat.format(activity.amount),
              style: AppTextStyles.titleSmall.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSalesReport() {
    return Column(
      children: [
        AlertChip.info(
          label: 'Sales analytics coming soon',
        ),
        const SizedBox(height: 16),
        const Center(
          child: Text('Detailed sales reports will be available here'),
        ),
      ],
    );
  }

  Widget _buildStockReport() {
    final dashboardState = ref.watch(dashboardControllerProvider);
    final dashboard = dashboardState.dashboard;

    return Column(
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Total Stock Value',
                          style: AppTextStyles.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _currencyFormat.format(dashboard?.totalStockValue ?? 0),
                          style: AppTextStyles.displayMedium.copyWith(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.inventory_2,
                        color: AppColors.primary,
                        size: 32,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        AlertChip.info(
          label: 'Detailed stock analytics coming soon',
        ),
      ],
    );
  }

  Widget _buildLowStockReport() {
    final dashboardState = ref.watch(dashboardControllerProvider);

    if (dashboardState.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (dashboardState.error != null) {
      return _buildErrorWidget(dashboardState.error!);
    }

    final alerts = dashboardState.alerts;
    if (alerts == null) {
      return const Center(child: Text('No data available'));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Summary cards
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: Responsive.isDesktop(context) ? 3 : 2,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
          childAspectRatio: Responsive.isDesktop(context) ? 1.5 : 1.2,
          children: [
            _buildMetricCard(
              title: 'Out of Stock',
              value: '${alerts.summary.outOfStock}',
              subtitle: 'Products',
              icon: Icons.error,
              color: AppColors.error,
            ),
            _buildMetricCard(
              title: 'Critical Stock',
              value: '${alerts.summary.criticalStock}',
              subtitle: 'Products',
              icon: Icons.warning,
              color: AppColors.warning,
            ),
            _buildMetricCard(
              title: 'Low Stock',
              value: '${alerts.summary.totalLowStock}',
              subtitle: 'Products',
              icon: Icons.info,
              color: AppColors.info,
            ),
          ],
        ),

        const SizedBox(height: 32),

        const SectionHeader(
          title: 'Products Requiring Attention',
          subtitle: 'Click on a product to view details',
        ),

        const SizedBox(height: 16),

        // Alert items
        if (alerts.allAlerts.isEmpty)
          const Center(child: Text('No low stock alerts'))
        else
          ...alerts.allAlerts.take(10).map((alert) {
            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: _getAlertColor(alert.type).withOpacity(0.1),
                  child: Icon(
                    _getAlertIcon(alert.type),
                    color: _getAlertColor(alert.type),
                  ),
                ),
                title: Text(alert.productName),
                subtitle: Text(
                  '${alert.locationName} • ${alert.currentStock} ${alert.unit}',
                ),
                trailing: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      alert.type.name.toUpperCase(),
                      style: AppTextStyles.labelSmall.copyWith(
                        color: _getAlertColor(alert.type),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      'Short: ${alert.shortage.toStringAsFixed(0)}',
                      style: AppTextStyles.labelSmall,
                    ),
                  ],
                ),
              ),
            );
          }),
      ],
    );
  }

  Widget _buildErrorWidget(String error) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 48, color: AppColors.error),
          const SizedBox(height: 16),
          Text(
            'Error loading report',
            style: AppTextStyles.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            error,
            style: AppTextStyles.bodySmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () {
              ref.read(dashboardControllerProvider.notifier).loadDashboard();
            },
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  IconData _getActivityIcon(String type) {
    switch (type.toLowerCase()) {
      case 'purchase':
        return Icons.add_shopping_cart;
      case 'invoice':
        return Icons.receipt_long;
      case 'issue':
        return Icons.output;
      case 'transfer':
        return Icons.swap_horiz;
      default:
        return Icons.description;
    }
  }

  Color _getActivityColor(String type) {
    switch (type.toLowerCase()) {
      case 'purchase':
        return AppColors.primary;
      case 'invoice':
        return AppColors.success;
      case 'issue':
        return AppColors.warning;
      case 'transfer':
        return AppColors.info;
      default:
        return AppColors.textSecondary;
    }
  }

  String _formatActivityType(String type) {
    return type[0].toUpperCase() + type.substring(1);
  }

  IconData _getAlertIcon(type) {
    switch (type.name) {
      case 'outOfStock':
        return Icons.error;
      case 'critical':
        return Icons.warning;
      case 'lowStock':
        return Icons.info;
      default:
        return Icons.info;
    }
  }

  Color _getAlertColor(type) {
    switch (type.name) {
      case 'outOfStock':
        return AppColors.error;
      case 'critical':
        return AppColors.warning;
      case 'lowStock':
        return AppColors.info;
      default:
        return AppColors.info;
    }
  }
}

class _ReportTab {
  final String label;
  final IconData icon;

  const _ReportTab({
    required this.label,
    required this.icon,
  });
}
