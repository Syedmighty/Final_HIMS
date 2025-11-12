import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/product_model.dart';
import '../services/api_service.dart';

/// Inventory state
class InventoryState {
  final List<ProductModel> products;
  final List<CategoryModel> categories;
  final List<UnitModel> units;
  final bool isLoading;
  final String? error;
  final String? searchQuery;
  final int? selectedCategoryId;

  InventoryState({
    this.products = const [],
    this.categories = const [],
    this.units = const [],
    this.isLoading = false,
    this.error,
    this.searchQuery,
    this.selectedCategoryId,
  });

  InventoryState copyWith({
    List<ProductModel>? products,
    List<CategoryModel>? categories,
    List<UnitModel>? units,
    bool? isLoading,
    String? error,
    String? searchQuery,
    int? selectedCategoryId,
  }) {
    return InventoryState(
      products: products ?? this.products,
      categories: categories ?? this.categories,
      units: units ?? this.units,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      searchQuery: searchQuery ?? this.searchQuery,
      selectedCategoryId: selectedCategoryId ?? this.selectedCategoryId,
    );
  }

  bool get hasError => error != null;
  bool get hasData => products.isNotEmpty;

  /// Get filtered products
  List<ProductModel> get filteredProducts {
    var filtered = products;

    // Filter by category
    if (selectedCategoryId != null) {
      filtered = filtered
          .where((p) => p.categoryId == selectedCategoryId)
          .toList();
    }

    // Filter by search query
    if (searchQuery != null && searchQuery!.isNotEmpty) {
      final query = searchQuery!.toLowerCase();
      filtered = filtered.where((p) {
        return p.name.toLowerCase().contains(query) ||
            (p.sku?.toLowerCase().contains(query) ?? false);
      }).toList();
    }

    return filtered;
  }

  /// Get low stock products
  List<ProductModel> get lowStockProducts {
    return products.where((p) => p.isLowStock).toList();
  }

  /// Get out of stock products
  List<ProductModel> get outOfStockProducts {
    return products.where((p) => p.isOutOfStock).toList();
  }

  /// Get critical products
  List<ProductModel> get criticalProducts {
    return products.where((p) => p.isCritical).toList();
  }
}

/// Inventory controller
class InventoryController extends StateNotifier<InventoryState> {
  final ApiService _apiService;

  InventoryController(this._apiService) : super(InventoryState());

  /// Load inventory data
  Future<void> loadInventory() async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      // Fetch products, categories, and units in parallel
      final results = await Future.wait([
        _apiService.getProducts(),
        _apiService.getCategories(),
        _apiService.getUnits(),
      ]);

      state = state.copyWith(
        products: results[0] as List<ProductModel>,
        categories: results[1] as List<CategoryModel>,
        units: results[2] as List<UnitModel>,
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
      );
    }
  }

  /// Search products
  void search(String query) {
    state = state.copyWith(searchQuery: query);
  }

  /// Filter by category
  void filterByCategory(int? categoryId) {
    state = state.copyWith(selectedCategoryId: categoryId);
  }

  /// Clear filters
  void clearFilters() {
    state = state.copyWith(
      searchQuery: '',
      selectedCategoryId: null,
    );
  }

  /// Refresh inventory
  Future<void> refresh() async {
    await loadInventory();
  }

  /// Clear error
  void clearError() {
    state = state.copyWith(error: null);
  }

  /// Get product by UUID
  ProductModel? getProduct(String uuid) {
    try {
      return state.products.firstWhere((p) => p.uuid == uuid);
    } catch (e) {
      return null;
    }
  }
}

/// Inventory controller provider
final inventoryControllerProvider =
    StateNotifierProvider<InventoryController, InventoryState>((ref) {
  final apiService = ref.watch(apiServiceProvider);
  return InventoryController(apiService);
});
