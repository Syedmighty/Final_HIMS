import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../controllers/inventory_controller.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/section_header.dart';
import '../../models/product_model.dart';

/// Desktop inventory screen
class InventoryDesktop extends ConsumerStatefulWidget {
  const InventoryDesktop({Key? key}) : super(key: key);

  @override
  ConsumerState<InventoryDesktop> createState() => _InventoryDesktopState();
}

class _InventoryDesktopState extends ConsumerState<InventoryDesktop> {
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

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Filters and search
          _buildFiltersSection(controller, inventoryState),

          const SizedBox(height: 24),

          // Products grid
          Expanded(
            child: _buildProductsGrid(inventoryState),
          ),
        ],
      ),
    );
  }

  Widget _buildFiltersSection(
    InventoryController controller,
    InventoryState state,
  ) {
    return Row(
      children: [
        // Search
        SizedBox(
          width: 320,
          child: TextField(
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
        ),

        const SizedBox(width: 16),

        // Category filter
        _buildCategoryDropdown(controller, state),

        const SizedBox(width: 16),

        // Stock status filter
        _buildStockStatusFilter(controller, state),

        const Spacer(),

        // Add product button
        ElevatedButton.icon(
          onPressed: () {
            // TODO: Show add product dialog
          },
          icon: const Icon(Icons.add),
          label: const Text('Add Product'),
        ),
      ],
    );
  }

  Widget _buildCategoryDropdown(
    InventoryController controller,
    InventoryState state,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: DropdownButton<int?>(
        value: state.selectedCategoryId,
        hint: const Text('All Categories'),
        underline: const SizedBox(),
        items: [
          const DropdownMenuItem(
            value: null,
            child: Text('All Categories'),
          ),
          ...state.categories.map((category) {
            return DropdownMenuItem(
              value: category.id,
              child: Text(category.name),
            );
          }),
        ],
        onChanged: controller.setCategoryFilter,
      ),
    );
  }

  Widget _buildStockStatusFilter(
    InventoryController controller,
    InventoryState state,
  ) {
    return SegmentedButton<String?>(
      segments: const [
        ButtonSegment(
          value: null,
          label: Text('All'),
        ),
        ButtonSegment(
          value: 'low',
          label: Text('Low Stock'),
          icon: Icon(Icons.warning_amber, size: 16),
        ),
        ButtonSegment(
          value: 'out',
          label: Text('Out of Stock'),
          icon: Icon(Icons.error_outline, size: 16),
        ),
      ],
      selected: {state.stockStatusFilter},
      onSelectionChanged: (Set<String?> selected) {
        controller.setStockStatusFilter(selected.first);
      },
    );
  }

  Widget _buildProductsGrid(InventoryState state) {
    if (state.isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (state.error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: AppColors.error),
            const SizedBox(height: 16),
            Text(
              'Error: ${state.error}',
              style: AppTextStyles.bodyLarge.copyWith(color: AppColors.error),
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
      );
    }

    if (state.filteredProducts.isEmpty) {
      return Center(
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
            ),
          ],
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = constraints.maxWidth > 1400 ? 4 : 3;

        return GridView.builder(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
            childAspectRatio: 1.1,
          ),
          itemCount: state.filteredProducts.length,
          itemBuilder: (context, index) {
            return _ProductCard(
              product: state.filteredProducts[index],
              currencyFormat: _currencyFormat,
            );
          },
        );
      },
    );
  }
}

/// Product card for grid view
class _ProductCard extends StatelessWidget {
  final ProductModel product;
  final NumberFormat currencyFormat;

  const _ProductCard({
    Key? key,
    required this.product,
    required this.currencyFormat,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: () {
          // TODO: Show product details dialog
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header with status
              Row(
                children: [
                  Expanded(
                    child: Text(
                      product.name,
                      style: AppTextStyles.titleMedium,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  _buildStockStatusBadge(),
                ],
              ),

              if (product.sku != null) ...[
                const SizedBox(height: 4),
                Text(
                  'SKU: ${product.sku}',
                  style: AppTextStyles.labelSmall,
                ),
              ],

              const SizedBox(height: 8),

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

              const Spacer(),

              // Stock info
              Row(
                children: [
                  Icon(
                    Icons.inventory_2_outlined,
                    size: 16,
                    color: _getStockColor(),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '${product.currentStock ?? 0} ${product.defaultUnit ?? ''}',
                    style: AppTextStyles.titleSmall.copyWith(
                      color: _getStockColor(),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 8),

              // Pricing
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Cost',
                        style: AppTextStyles.labelSmall,
                      ),
                      Text(
                        currencyFormat.format(product.costPrice),
                        style: AppTextStyles.bodySmall.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'Selling',
                        style: AppTextStyles.labelSmall,
                      ),
                      Text(
                        currencyFormat.format(product.sellingPrice),
                        style: AppTextStyles.bodySmall.copyWith(
                          fontWeight: FontWeight.w600,
                          color: AppColors.success,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStockStatusBadge() {
    if (product.isOutOfStock) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: AppColors.error,
          borderRadius: BorderRadius.circular(4),
        ),
        child: const Icon(
          Icons.error,
          size: 16,
          color: Colors.white,
        ),
      );
    } else if (product.isCritical) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: AppColors.warning,
          borderRadius: BorderRadius.circular(4),
        ),
        child: const Icon(
          Icons.warning,
          size: 16,
          color: Colors.white,
        ),
      );
    } else if (product.isLowStock) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: AppColors.info,
          borderRadius: BorderRadius.circular(4),
        ),
        child: const Icon(
          Icons.info,
          size: 16,
          color: Colors.white,
        ),
      );
    }
    return const SizedBox();
  }

  Color _getStockColor() {
    if (product.isOutOfStock) return AppColors.error;
    if (product.isCritical) return AppColors.warning;
    if (product.isLowStock) return AppColors.info;
    return AppColors.success;
  }
}
