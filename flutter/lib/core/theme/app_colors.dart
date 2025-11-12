import 'package:flutter/material.dart';

/// Application color palette
/// Following Material Design 3 principles
class AppColors {
  AppColors._();

  // Primary Colors
  static const Color primary = Color(0xFF1976D2); // Blue
  static const Color primaryLight = Color(0xFF42A5F5);
  static const Color primaryDark = Color(0xFF0D47A1);

  // Secondary Colors
  static const Color secondary = Color(0xFF26A69A); // Teal
  static const Color secondaryLight = Color(0xFF4DB6AC);
  static const Color secondaryDark = Color(0xFF00796B);

  // Background Colors
  static const Color background = Color(0xFFF5F7FA);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceVariant = Color(0xFFF0F4F8);

  // Status Colors
  static const Color success = Color(0xFF4CAF50);
  static const Color warning = Color(0xFFFF9800);
  static const Color error = Color(0xFFF44336);
  static const Color info = Color(0xFF2196F3);

  // Text Colors
  static const Color textPrimary = Color(0xFF1A1A1A);
  static const Color textSecondary = Color(0xFF757575);
  static const Color textDisabled = Color(0xFFBDBDBD);
  static const Color textOnPrimary = Color(0xFFFFFFFF);

  // Border and Divider
  static const Color border = Color(0xFFE0E0E0);
  static const Color divider = Color(0xFFEEEEEE);

  // Card Colors (for different modules)
  static const Color purchaseCard = Color(0xFFE3F2FD); // Light Blue
  static const Color issueCard = Color(0xFFFFF3E0); // Light Orange
  static const Color wastageCard = Color(0xFFFFEBEE); // Light Red
  static const Color stockCard = Color(0xFFE8F5E9); // Light Green
  static const Color invoiceCard = Color(0xFFF3E5F5); // Light Purple
  static const Color transferCard = Color(0xFFE1F5FE); // Light Cyan

  // Chart Colors
  static const List<Color> chartColors = [
    Color(0xFF1976D2),
    Color(0xFF26A69A),
    Color(0xFFFF9800),
    Color(0xFF9C27B0),
    Color(0xFF4CAF50),
    Color(0xFFF44336),
  ];

  // Gradient Colors
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [primary, primaryLight],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient successGradient = LinearGradient(
    colors: [success, Color(0xFF66BB6A)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // Shadow Colors
  static const Color shadowLight = Color(0x1A000000);
  static const Color shadowMedium = Color(0x33000000);
}
