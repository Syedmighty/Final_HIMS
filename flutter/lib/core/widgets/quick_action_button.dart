import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

/// Quick action button for dashboard
/// Desktop: Horizontal button with icon + label
/// Mobile: Circular button with centered icon + label below
class QuickActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;
  final bool isCompact;

  const QuickActionButton({
    Key? key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
    this.isCompact = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (isCompact) {
      return _buildCompactButton(context);
    } else {
      return _buildExpandedButton(context);
    }
  }

  /// Expanded button (for desktop)
  Widget _buildExpandedButton(BuildContext context) {
    final buttonColor = color ?? AppColors.primary;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: buttonColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: buttonColor.withOpacity(0.3),
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                color: buttonColor,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: AppTextStyles.labelLarge.copyWith(
                  color: buttonColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Compact button (for mobile)
  Widget _buildCompactButton(BuildContext context) {
    final buttonColor = color ?? AppColors.primary;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Circular icon button
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: buttonColor.withOpacity(0.1),
                shape: BoxShape.circle,
                border: Border.all(
                  color: buttonColor.withOpacity(0.3),
                  width: 1.5,
                ),
              ),
              child: Icon(
                icon,
                color: buttonColor,
                size: 24,
              ),
            ),
            const SizedBox(height: 8),

            // Label
            Text(
              label,
              style: AppTextStyles.labelSmall.copyWith(
                color: buttonColor,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

/// Floating action button variant for mobile
class QuickActionFAB extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? backgroundColor;

  const QuickActionFAB({
    Key? key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.backgroundColor,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton.extended(
      onPressed: onTap,
      backgroundColor: backgroundColor ?? AppColors.primary,
      icon: Icon(icon),
      label: Text(
        label,
        style: AppTextStyles.button.copyWith(
          color: AppColors.textOnPrimary,
        ),
      ),
    );
  }
}

/// Quick action grid for mobile dashboard
class QuickActionsGrid extends StatelessWidget {
  final List<QuickActionData> actions;

  const QuickActionsGrid({
    Key? key,
    required this.actions,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        childAspectRatio: 0.85,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: actions.length,
      itemBuilder: (context, index) {
        final action = actions[index];
        return QuickActionButton(
          icon: action.icon,
          label: action.label,
          onTap: action.onTap,
          color: action.color,
          isCompact: true,
        );
      },
    );
  }
}

/// Quick action data model
class QuickActionData {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  QuickActionData({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
  });
}
