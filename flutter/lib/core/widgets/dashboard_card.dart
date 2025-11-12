import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

/// Dashboard card widget for displaying stats
/// Responsive design with icons, title, value, and optional subtitle
class DashboardCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;
  final String? subtitle;
  final Color? color;
  final Color? backgroundColor;
  final VoidCallback? onTap;

  const DashboardCard({
    Key? key,
    required this.icon,
    required this.title,
    required this.value,
    this.subtitle,
    this.color,
    this.backgroundColor,
    this.onTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final cardColor = backgroundColor ?? AppColors.surface;
    final iconColor = color ?? AppColors.primary;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: AppColors.border.withOpacity(0.5),
          width: 1,
        ),
      ),
      color: cardColor,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Icon and Title Row
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: iconColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      icon,
                      color: iconColor,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      title,
                      style: AppTextStyles.cardTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Value
              Text(
                value,
                style: AppTextStyles.cardValue.copyWith(
                  color: iconColor,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),

              // Subtitle (if provided)
              if (subtitle != null) ...[
                const SizedBox(height: 8),
                Text(
                  subtitle!,
                  style: AppTextStyles.cardSubtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Horizontal dashboard card variant for mobile
class DashboardCardHorizontal extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;
  final Color? color;
  final VoidCallback? onTap;

  const DashboardCardHorizontal({
    Key? key,
    required this.icon,
    required this.title,
    required this.value,
    this.color,
    this.onTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final iconColor = color ?? AppColors.primary;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: AppColors.border.withOpacity(0.5),
          width: 1,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              // Icon
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: iconColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  icon,
                  color: iconColor,
                  size: 28,
                ),
              ),
              const SizedBox(width: 16),

              // Title and Value
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: AppTextStyles.cardTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      value,
                      style: AppTextStyles.titleLarge.copyWith(
                        color: iconColor,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),

              // Arrow icon
              Icon(
                Icons.arrow_forward_ios_rounded,
                color: AppColors.textDisabled,
                size: 16,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
