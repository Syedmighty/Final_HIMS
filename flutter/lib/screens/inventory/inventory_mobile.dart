import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../controllers/inventory_controller.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../models/product_model.dart';

/// Mobile inventory screen
class InventoryMobile extends ConsumerStatefulWidget {
  const InventoryMobile({Key? key}) : super(key: key);

  @override
  ConsumerState<InventoryMobile> createState() => _InventoryMobileState();
}

class _InventoryMobileState extends ConsumerState<InventoryMobile> {
  final _searchController = TextEditingController();
  final _currencyFormat = NumberFormat.currency(symbol: '₹', decimalDigits: 2);

  @override
  void initState() {
    super.initState();
    // Load inventory on init
    Future.microtask(() {
      ref.read(inventoryControllerProvider.notifier).loadProducts();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final inventoryState = ref.watch(inventoryControllerProvider);
    final controller = ref.read(inventoryControllerProvider.notifier);

    return Column(
      children: [
        // Search and filters
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surface,
            border: Border(
              bottom: BorderSide(color: AppColors.border, width: 1),
            ),
          ),
          child: Column(
            children: [
              // Search bar
              TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Search products...',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            _searchController.clear();
                            controller.setSearchQuery('');
                          },
                        )
                      : null,
                ),
                onChanged: controller.setSearchQuery,
              ),

              const SizedBox(height: 12),

              // Filter chips
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    // Category filter
                    _buildCategoryChip(controller, inventoryState),

                    const SizedBox(width: 8),

                    // Stock status filters
                    FilterChip(
                      label: const Text('Low Stock'),
                      selected: inventoryState.stockStatusFilter == 'low',
                      onSelected: (selected) {
                        controller.setStockStatusFilter(selected ? 'low' : null);
                      },
                      avatar: const Icon(Icons.warning_amber, size: 16),
                    ),

                    const SizedBox(width: 8),

                    FilterChip(
                      label: const Text('Out of Stock'),
                      selected: inventoryState.stockStatusFilter == 'out',
                      onSelected: (selected) {
                        controller.setStockStatusFilter(selected ? 'out' : null);
                      },
                      avatar: const Icon(Icons.error_outline, size: 16),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // Products list
        Expanded(
          child: _buildProductsList(inventoryState),
        ),
      ],
    );
  }

  Widget _buildCategoryChip(
    InventoryController controller,
    InventoryState state,
  ) {
    if (state.categories.isEmpty) {
      return const SizedBox();
    }

    return ActionChip(
      label: Text(
        state.selectedCategoryId == null
            ? 'All Categories'
            : state.categories
                    .firstWhere((c) => c.id == state.selectedCategoryId)
                    .name,
      ),
      avatar: const Icon(Icons.category, size: 16),
      onPressed: () {
        _showCategoryPicker(controller, state);
      },
    );
  }

  void _showCategoryPicker(
    InventoryController controller,
    InventoryState state,
  ) {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.category),
                title: const Text('All Categories'),
                selected: state.selectedCategoryId == null,
                onTap: () {
                  controller.setCategoryFilter(null);
                  Navigator.pop(context);
                },
              ),
              ...state.categories.map((category) {
                return ListTile(
                  leading: const Icon(Icons.label),
                  title: Text(category.name),
                  selected: state.selectedCategoryId == category.id,
                  onTap: () {
                    controller.setCategoryFilter(category.id);
                    Navigator.pop(context);
                  },
                );
              }),
            ],
          ),
        );
      },
    );
  }

  Widget _buildProductsList(InventoryState state) {
    if (state.isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (state.error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 48, color: AppColors.error),
              const SizedBox(height: 16),
              Text(
                'Error loading products',
                style: AppTextStyles.titleMedium.copyWith(color: AppColors.error),
              ),
              const SizedBox(height: 8),
              Text(
                state.error!,
                style: AppTextStyles.bodySmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () {
                  ref.read(inventoryControllerProvider.notifier).loadProducts();
                },
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (state.filteredProducts.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.inventory_2_outlined,
                size: 64,
                color: AppColors.textSecondary.withOpacity(0.5),
              ),
              const SizedBox(height: 16),
              Text(
                'No products found',
                style: AppTextStyles.titleMedium.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Try adjusting your filters',
                style: AppTextStyles.bodyMedium.copyWith(
                  color: AppColors.textSecondary,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () async {
        await ref.read(inventoryControllerProvider.notifier).loadProducts();
      },
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: state.filteredProducts.length,
        itemBuilder: (context, index) {
          return _ProductListTile(
            product: state.filteredProducts[index],
            currencyFormat: _currencyFormat,
          );
        },
      ),
    );
  }
}

/// Product list tile for mobile
class _ProductListTile extends StatelessWidget {
  final ProductModel product;
  final NumberFormat currencyFormat;

  const _ProductListTile({
    Key? key,
    required this.product,
    required this.currencyFormat,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () {
          // TODO: Show product details
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header row
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          product.name,
                          style: AppTextStyles.titleMedium,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (product.sku != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            'SKU: ${product.sku}',
                            style: AppTextStyles.labelSmall,
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  _buildStockStatusIcon(),
                ],
              ),

              const SizedBox(height: 12),

              // Stock and category
              Row(
                children: [
                  // Stock level
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: _getStockColor().withOpacity(0.1),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: _getStockColor(), width: 1),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.inventory_2,
                          size: 14,
                          color: _getStockColor(),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${product.currentStock ?? 0} ${product.defaultUnit ?? ''}',
                          style: AppTextStyles.labelSmall.copyWith(
                            color: _getStockColor(),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(width: 8),

                  // Category
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.primaryLight.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      product.categoryName ?? 'Uncategorized',
                      style: AppTextStyles.labelSmall.copyWith(
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 12),

              // Pricing row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Cost price
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Cost Price',
                        style: AppTextStyles.labelSmall,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        currencyFormat.format(product.costPrice),
                        style: AppTextStyles.bodyMedium.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),

                  // Selling price
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'Selling Price',
                        style: AppTextStyles.labelSmall,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        currencyFormat.format(product.sellingPrice),
                        style: AppTextStyles.bodyMedium.copyWith(
                          fontWeight: FontWeight.w600,
                          color: AppColors.success,
                        ),
                      ),
                    ],
                  ),

                  // Profit margin
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.success.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '${product.profitMargin.toStringAsFixed(1)}%',
                      style: AppTextStyles.labelSmall.copyWith(
                        color: AppColors.success,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStockStatusIcon() {
    IconData icon;
    Color color;

    if (product.isOutOfStock) {
      icon = Icons.error;
      color = AppColors.error;
    } else if (product.isCritical) {
      icon = Icons.warning;
      color = AppColors.warning;
    } else if (product.isLowStock) {
      icon = Icons.info;
      color = AppColors.info;
    } else {
      icon = Icons.check_circle;
      color = AppColors.success;
    }

    return Icon(icon, color: color, size: 28);
  }

  Color _getStockColor() {
    if (product.isOutOfStock) return AppColors.error;
    if (product.isCritical) return AppColors.warning;
    if (product.isLowStock) return AppColors.info;
    return AppColors.success;
  }
}
