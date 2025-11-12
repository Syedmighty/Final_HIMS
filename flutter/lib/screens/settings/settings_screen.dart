import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/responsive.dart';
import '../../core/widgets/section_header.dart';

/// Settings screen
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDesktop = Responsive.isDesktop(context);

    return SingleChildScrollView(
      padding: EdgeInsets.all(isDesktop ? 24 : 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isDesktop) ...[
            const SectionHeader(
              title: 'Settings',
              subtitle: 'Manage your application preferences',
            ),
            const SizedBox(height: 24),
          ],

          // Company Settings
          _buildSettingsSection(
            context: context,
            title: 'Company Settings',
            icon: Icons.business,
            children: [
              _buildSettingsTile(
                icon: Icons.store,
                title: 'Company Profile',
                subtitle: 'Manage company information',
                onTap: () {
                  // TODO: Navigate to company profile
                },
              ),
              _buildSettingsTile(
                icon: Icons.location_on,
                title: 'Locations',
                subtitle: 'Manage warehouses and locations',
                onTap: () {
                  // TODO: Navigate to locations management
                },
              ),
              _buildSettingsTile(
                icon: Icons.category,
                title: 'Categories & Units',
                subtitle: 'Manage product categories and units',
                onTap: () {
                  // TODO: Navigate to categories management
                },
              ),
            ],
          ),

          const SizedBox(height: 24),

          // User Settings
          _buildSettingsSection(
            context: context,
            title: 'User Settings',
            icon: Icons.person,
            children: [
              _buildSettingsTile(
                icon: Icons.account_circle,
                title: 'Account',
                subtitle: 'Manage your account details',
                onTap: () {
                  // TODO: Navigate to account settings
                },
              ),
              _buildSettingsTile(
                icon: Icons.lock,
                title: 'Change Password',
                subtitle: 'Update your password',
                onTap: () {
                  // TODO: Show change password dialog
                },
              ),
              _buildSettingsTile(
                icon: Icons.people,
                title: 'User Management',
                subtitle: 'Manage users and permissions',
                onTap: () {
                  // TODO: Navigate to user management
                },
              ),
            ],
          ),

          const SizedBox(height: 24),

          // Appearance
          _buildSettingsSection(
            context: context,
            title: 'Appearance',
            icon: Icons.palette,
            children: [
              _buildSettingsTile(
                icon: Icons.dark_mode,
                title: 'Theme',
                subtitle: 'Light mode',
                trailing: Switch(
                  value: false,
                  onChanged: (value) {
                    // TODO: Implement theme switching
                  },
                ),
              ),
              _buildSettingsTile(
                icon: Icons.language,
                title: 'Language',
                subtitle: 'English',
                onTap: () {
                  // TODO: Show language picker
                },
              ),
            ],
          ),

          const SizedBox(height: 24),

          // Data & Sync
          _buildSettingsSection(
            context: context,
            title: 'Data & Sync',
            icon: Icons.sync,
            children: [
              _buildSettingsTile(
                icon: Icons.cloud_sync,
                title: 'Sync Now',
                subtitle: 'Last synced: Never',
                onTap: () {
                  // TODO: Trigger sync
                },
              ),
              _buildSettingsTile(
                icon: Icons.backup,
                title: 'Backup & Restore',
                subtitle: 'Manage data backups',
                onTap: () {
                  // TODO: Navigate to backup settings
                },
              ),
              _buildSettingsTile(
                icon: Icons.delete_sweep,
                title: 'Clear Cache',
                subtitle: 'Free up storage space',
                onTap: () {
                  // TODO: Show clear cache confirmation
                },
              ),
            ],
          ),

          const SizedBox(height: 24),

          // About
          _buildSettingsSection(
            context: context,
            title: 'About',
            icon: Icons.info,
            children: [
              _buildSettingsTile(
                icon: Icons.info_outline,
                title: 'Version',
                subtitle: '1.0.0',
              ),
              _buildSettingsTile(
                icon: Icons.description,
                title: 'Terms of Service',
                onTap: () {
                  // TODO: Show terms of service
                },
              ),
              _buildSettingsTile(
                icon: Icons.privacy_tip,
                title: 'Privacy Policy',
                onTap: () {
                  // TODO: Show privacy policy
                },
              ),
              _buildSettingsTile(
                icon: Icons.help_outline,
                title: 'Help & Support',
                onTap: () {
                  // TODO: Navigate to help
                },
              ),
            ],
          ),

          const SizedBox(height: 24),

          // Logout
          Center(
            child: OutlinedButton.icon(
              onPressed: () {
                _showLogoutDialog(context);
              },
              icon: const Icon(Icons.logout, color: AppColors.error),
              label: Text(
                'Logout',
                style: AppTextStyles.labelLarge.copyWith(color: AppColors.error),
              ),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: AppColors.error),
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 16,
                ),
              ),
            ),
          ),

          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildSettingsSection({
    required BuildContext context,
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(icon, color: AppColors.primary, size: 20),
                const SizedBox(width: 12),
                Text(
                  title,
                  style: AppTextStyles.titleMedium.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          ...children,
        ],
      ),
    );
  }

  Widget _buildSettingsTile({
    required IconData icon,
    required String title,
    String? subtitle,
    Widget? trailing,
    VoidCallback? onTap,
  }) {
    return ListTile(
      leading: Icon(icon, color: AppColors.textSecondary),
      title: Text(title, style: AppTextStyles.labelLarge),
      subtitle: subtitle != null
          ? Text(subtitle, style: AppTextStyles.bodySmall)
          : null,
      trailing: trailing ??
          (onTap != null
              ? const Icon(Icons.chevron_right, color: AppColors.textSecondary)
              : null),
      onTap: onTap,
    );
  }

  void _showLogoutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Logout'),
          content: const Text('Are you sure you want to logout?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                // TODO: Implement logout
                Navigator.pop(context);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.error,
              ),
              child: const Text('Logout'),
            ),
          ],
        );
      },
    );
  }
}
