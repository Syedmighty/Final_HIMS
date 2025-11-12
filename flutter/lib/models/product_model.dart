/// Product data model
/// Maps to /api/products endpoints
class ProductModel {
  final String uuid;
  final String name;
  final String? sku;
  final int categoryId;
  final String? categoryName;
  final int defaultUnitId;
  final String? defaultUnit;
  final double reorderLevel;
  final double minStockLevel;
  final double costPrice;
  final double sellingPrice;
  final double gstRate;
  final bool isActive;
  final String createdAt;
  final String lastModified;
  final double? currentStock;

  ProductModel({
    required this.uuid,
    required this.name,
    this.sku,
    required this.categoryId,
    this.categoryName,
    required this.defaultUnitId,
    this.defaultUnit,
    required this.reorderLevel,
    required this.minStockLevel,
    required this.costPrice,
    required this.sellingPrice,
    required this.gstRate,
    required this.isActive,
    required this.createdAt,
    required this.lastModified,
    this.currentStock,
  });

  factory ProductModel.fromJson(Map<String, dynamic> json) {
    return ProductModel(
      uuid: json['uuid'] ?? '',
      name: json['name'] ?? '',
      sku: json['sku'],
      categoryId: json['category_id'] ?? 0,
      categoryName: json['category_name'],
      defaultUnitId: json['default_unit_id'] ?? 0,
      defaultUnit: json['default_unit'],
      reorderLevel: (json['reorder_level'] ?? 0).toDouble(),
      minStockLevel: (json['min_stock_level'] ?? 0).toDouble(),
      costPrice: (json['cost_price'] ?? 0).toDouble(),
      sellingPrice: (json['selling_price'] ?? 0).toDouble(),
      gstRate: (json['gst_rate'] ?? 0).toDouble(),
      isActive: json['is_active'] == 1,
      createdAt: json['created_at'] ?? '',
      lastModified: json['last_modified'] ?? '',
      currentStock: json['current_stock'] != null
          ? (json['current_stock'] as num).toDouble()
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'uuid': uuid,
      'name': name,
      'sku': sku,
      'category_id': categoryId,
      'category_name': categoryName,
      'default_unit_id': defaultUnitId,
      'default_unit': defaultUnit,
      'reorder_level': reorderLevel,
      'min_stock_level': minStockLevel,
      'cost_price': costPrice,
      'selling_price': sellingPrice,
      'gst_rate': gstRate,
      'is_active': isActive ? 1 : 0,
      'created_at': createdAt,
      'last_modified': lastModified,
      'current_stock': currentStock,
    };
  }

  /// Check if product is low stock
  bool get isLowStock {
    if (currentStock == null) return false;
    return currentStock! <= reorderLevel && currentStock! > 0;
  }

  /// Check if product is out of stock
  bool get isOutOfStock {
    if (currentStock == null) return false;
    return currentStock! <= 0;
  }

  /// Check if product is critically low
  bool get isCritical {
    if (currentStock == null) return false;
    return currentStock! <= minStockLevel && currentStock! > 0;
  }

  /// Get stock status
  String get stockStatus {
    if (currentStock == null) return 'Unknown';
    if (isOutOfStock) return 'Out of Stock';
    if (isCritical) return 'Critical';
    if (isLowStock) return 'Low Stock';
    return 'In Stock';
  }

  /// Get profit margin percentage
  double get profitMargin {
    if (sellingPrice == 0) return 0;
    return ((sellingPrice - costPrice) / sellingPrice) * 100;
  }
}

/// Product category model
class CategoryModel {
  final int id;
  final String name;
  final String? description;
  final bool isActive;

  CategoryModel({
    required this.id,
    required this.name,
    this.description,
    required this.isActive,
  });

  factory CategoryModel.fromJson(Map<String, dynamic> json) {
    return CategoryModel(
      id: json['id'] ?? 0,
      name: json['name'] ?? '',
      description: json['description'],
      isActive: json['is_active'] == 1,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'is_active': isActive ? 1 : 0,
    };
  }
}

/// Unit model
class UnitModel {
  final int id;
  final String name;
  final String abbreviation;
  final bool isActive;

  UnitModel({
    required this.id,
    required this.name,
    required this.abbreviation,
    required this.isActive,
  });

  factory UnitModel.fromJson(Map<String, dynamic> json) {
    return UnitModel(
      id: json['id'] ?? 0,
      name: json['name'] ?? '',
      abbreviation: json['abbreviation'] ?? '',
      isActive: json['is_active'] == 1,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'abbreviation': abbreviation,
      'is_active': isActive ? 1 : 0,
    };
  }
}
