import 'package:flutter/material.dart';
import '../../core/utils/responsive.dart';
import 'inventory_desktop.dart';
import 'inventory_mobile.dart';

/// Main inventory screen - switches between desktop and mobile layouts
class InventoryScreen extends StatelessWidget {
  const InventoryScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Responsive(
      mobile: const InventoryMobile(),
      desktop: const InventoryDesktop(),
    );
  }
}
