import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

/// Section header widget for organizing content areas
/// Used throughout the dashboard and other screens
class SectionHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onViewAllTap;
  final EdgeInsetsGeometry? padding;

  const SectionHeader({
    Key? key,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onViewAllTap,
    this.padding,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding ??
          const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          // Title and subtitle
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTextStyles.titleLarge,
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    subtitle!,
                    style: AppTextStyles.bodySmall,
                  ),
                ],
              ],
            ),
          ),

          // Trailing widget or "View All" button
          if (trailing != null)
            trailing!
          else if (onViewAllTap != null)
            TextButton(
              onPressed: onViewAllTap,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'View All',
                    style: AppTextStyles.labelLarge.copyWith(
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(
                    Icons.arrow_forward_ios_rounded,
                    size: 14,
                    color: AppColors.primary,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Compact section header for cards and compact views
class SectionHeaderCompact extends StatelessWidget {
  final String title;
  final IconData? icon;
  final Color? iconColor;
  final Widget? trailing;

  const SectionHeaderCompact({
    Key? key,
    required this.title,
    this.icon,
    this.iconColor,
    this.trailing,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (icon != null) ...[
          Icon(
            icon,
            size: 20,
            color: iconColor ?? AppColors.primary,
          ),
          const SizedBox(width: 8),
        ],
        Expanded(
          child: Text(
            title,
            style: AppTextStyles.titleMedium,
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

/// Divider with label
class LabeledDivider extends StatelessWidget {
  final String label;
  final EdgeInsetsGeometry? padding;

  const LabeledDivider({
    Key? key,
    required this.label,
    this.padding,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding ?? const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        children: [
          Expanded(
            child: Divider(
              color: AppColors.divider,
              thickness: 1,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              label,
              style: AppTextStyles.labelSmall,
            ),
          ),
          Expanded(
            child: Divider(
              color: AppColors.divider,
              thickness: 1,
            ),
          ),
        ],
      ),
    );
  }
}
