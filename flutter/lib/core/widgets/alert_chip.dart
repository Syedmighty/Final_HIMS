import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

/// Alert chip widget for displaying live alerts
/// Color-coded pills with icons and labels
class AlertChip extends StatelessWidget {
  final String label;
  final IconData? icon;
  final Color color;
  final VoidCallback? onTap;
  final bool showDismiss;
  final VoidCallback? onDismiss;

  const AlertChip({
    Key? key,
    required this.label,
    this.icon,
    required this.color,
    this.onTap,
    this.showDismiss = false,
    this.onDismiss,
  }) : super(key: key);

  /// Factory constructors for common alert types
  factory AlertChip.warning({
    required String label,
    IconData? icon,
    VoidCallback? onTap,
    bool showDismiss = false,
    VoidCallback? onDismiss,
  }) {
    return AlertChip(
      label: label,
      icon: icon ?? Icons.warning_amber_rounded,
      color: AppColors.warning,
      onTap: onTap,
      showDismiss: showDismiss,
      onDismiss: onDismiss,
    );
  }

  factory AlertChip.error({
    required String label,
    IconData? icon,
    VoidCallback? onTap,
    bool showDismiss = false,
    VoidCallback? onDismiss,
  }) {
    return AlertChip(
      label: label,
      icon: icon ?? Icons.error_outline_rounded,
      color: AppColors.error,
      onTap: onTap,
      showDismiss: showDismiss,
      onDismiss: onDismiss,
    );
  }

  factory AlertChip.info({
    required String label,
    IconData? icon,
    VoidCallback? onTap,
    bool showDismiss = false,
    VoidCallback? onDismiss,
  }) {
    return AlertChip(
      label: label,
      icon: icon ?? Icons.info_outline_rounded,
      color: AppColors.info,
      onTap: onTap,
      showDismiss: showDismiss,
      onDismiss: onDismiss,
    );
  }

  factory AlertChip.success({
    required String label,
    IconData? icon,
    VoidCallback? onTap,
    bool showDismiss = false,
    VoidCallback? onDismiss,
  }) {
    return AlertChip(
      label: label,
      icon: icon ?? Icons.check_circle_outline_rounded,
      color: AppColors.success,
      onTap: onTap,
      showDismiss: showDismiss,
      onDismiss: onDismiss,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: color.withOpacity(0.3),
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Icon
              if (icon != null) ...[
                Icon(
                  icon,
                  size: 16,
                  color: color,
                ),
                const SizedBox(width: 6),
              ],

              // Label
              Flexible(
                child: Text(
                  label,
                  style: AppTextStyles.labelMedium.copyWith(
                    color: color,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),

              // Dismiss button
              if (showDismiss && onDismiss != null) ...[
                const SizedBox(width: 6),
                InkWell(
                  onTap: onDismiss,
                  borderRadius: BorderRadius.circular(10),
                  child: Icon(
                    Icons.close_rounded,
                    size: 16,
                    color: color,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Horizontal scrollable list of alert chips
class AlertChipList extends StatelessWidget {
  final List<AlertChipData> alerts;
  final EdgeInsetsGeometry? padding;

  const AlertChipList({
    Key? key,
    required this.alerts,
    this.padding,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (alerts.isEmpty) {
      return const SizedBox.shrink();
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: padding ?? const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          for (int i = 0; i < alerts.length; i++) ...[
            AlertChip(
              label: alerts[i].label,
              icon: alerts[i].icon,
              color: alerts[i].color,
              onTap: alerts[i].onTap,
              showDismiss: alerts[i].showDismiss,
              onDismiss: alerts[i].onDismiss,
            ),
            if (i < alerts.length - 1) const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }
}

/// Alert chip data model
class AlertChipData {
  final String label;
  final IconData? icon;
  final Color color;
  final VoidCallback? onTap;
  final bool showDismiss;
  final VoidCallback? onDismiss;

  AlertChipData({
    required this.label,
    this.icon,
    required this.color,
    this.onTap,
    this.showDismiss = false,
    this.onDismiss,
  });

  // Factory methods for common alert types
  factory AlertChipData.lowStock({
    required String productName,
    VoidCallback? onTap,
  }) {
    return AlertChipData(
      label: 'Low Stock: $productName',
      icon: Icons.warning_amber_rounded,
      color: AppColors.warning,
      onTap: onTap,
    );
  }

  factory AlertChipData.outOfStock({
    required String productName,
    VoidCallback? onTap,
  }) {
    return AlertChipData(
      label: 'Out of Stock: $productName',
      icon: Icons.error_outline_rounded,
      color: AppColors.error,
      onTap: onTap,
    );
  }

  factory AlertChipData.pendingPurchase({
    required int count,
    VoidCallback? onTap,
  }) {
    return AlertChipData(
      label: '$count Pending Purchases',
      icon: Icons.shopping_cart_outlined,
      color: AppColors.info,
      onTap: onTap,
    );
  }

  factory AlertChipData.syncIssue({
    VoidCallback? onTap,
  }) {
    return AlertChipData(
      label: 'Sync Issue',
      icon: Icons.sync_problem_rounded,
      color: AppColors.error,
      onTap: onTap,
    );
  }
}
