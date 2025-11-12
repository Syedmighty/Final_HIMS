/// Alert data model for low stock and other alerts
/// Maps to /api/reports/low-stock endpoint
class AlertModel {
  final String productUuid;
  final String productName;
  final String? sku;
  final String locationName;
  final double currentStock;
  final double reorderLevel;
  final double minStockLevel;
  final String unit;
  final double shortage;
  final AlertType type;

  AlertModel({
    required this.productUuid,
    required this.productName,
    this.sku,
    required this.locationName,
    required this.currentStock,
    required this.reorderLevel,
    required this.minStockLevel,
    required this.unit,
    required this.shortage,
    required this.type,
  });

  factory AlertModel.fromJson(Map<String, dynamic> json) {
    final currentStock = (json['current_stock'] ?? 0).toDouble();
    final minLevel = (json['min_stock_level'] ?? 0).toDouble();

    AlertType type;
    if (currentStock <= 0) {
      type = AlertType.outOfStock;
    } else if (currentStock <= minLevel) {
      type = AlertType.critical;
    } else {
      type = AlertType.lowStock;
    }

    return AlertModel(
      productUuid: json['product_uuid'] ?? '',
      productName: json['product_name'] ?? '',
      sku: json['sku'],
      locationName: json['location_name'] ?? '',
      currentStock: currentStock,
      reorderLevel: (json['reorder_level'] ?? 0).toDouble(),
      minStockLevel: minLevel,
      unit: json['unit'] ?? '',
      shortage: (json['shortage'] ?? 0).toDouble(),
      type: type,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'product_uuid': productUuid,
      'product_name': productName,
      'sku': sku,
      'location_name': locationName,
      'current_stock': currentStock,
      'reorder_level': reorderLevel,
      'min_stock_level': minStockLevel,
      'unit': unit,
      'shortage': shortage,
      'type': type.name,
    };
  }

  /// Get alert message
  String get message {
    switch (type) {
      case AlertType.outOfStock:
        return 'Out of Stock: $productName';
      case AlertType.critical:
        return 'Critical: $productName ($currentStock $unit left)';
      case AlertType.lowStock:
        return 'Low Stock: $productName ($currentStock $unit)';
    }
  }

  /// Get short message for chips
  String get shortMessage {
    switch (type) {
      case AlertType.outOfStock:
        return 'Out: $productName';
      case AlertType.critical:
        return 'Critical: $productName';
      case AlertType.lowStock:
        return 'Low: $productName';
    }
  }
}

/// Alert type enum
enum AlertType {
  outOfStock,
  critical,
  lowStock,
}

/// Low stock report model
/// Maps to /api/reports/low-stock response
class LowStockReport {
  final LowStockSummary summary;
  final List<AlertModel> lowStockItems;
  final List<AlertModel> criticalStockItems;
  final List<OutOfStockItem> outOfStockItems;

  LowStockReport({
    required this.summary,
    required this.lowStockItems,
    required this.criticalStockItems,
    required this.outOfStockItems,
  });

  factory LowStockReport.fromJson(Map<String, dynamic> json) {
    return LowStockReport(
      summary: LowStockSummary.fromJson(json['summary'] ?? {}),
      lowStockItems: (json['low_stock_items'] as List?)
              ?.map((e) => AlertModel.fromJson(e))
              .toList() ??
          [],
      criticalStockItems: (json['critical_stock_items'] as List?)
              ?.map((e) => AlertModel.fromJson(e))
              .toList() ??
          [],
      outOfStockItems: (json['out_of_stock_items'] as List?)
              ?.map((e) => OutOfStockItem.fromJson(e))
              .toList() ??
          [],
    );
  }

  /// Get all alerts as a single list
  List<AlertModel> get allAlerts {
    return [
      ...outOfStockItems.map((item) => AlertModel(
            productUuid: item.productUuid,
            productName: item.productName,
            sku: item.sku,
            locationName: item.locationName,
            currentStock: 0,
            reorderLevel: item.reorderLevel,
            minStockLevel: 0,
            unit: item.unit,
            shortage: item.reorderLevel,
            type: AlertType.outOfStock,
          )),
      ...criticalStockItems,
      ...lowStockItems,
    ];
  }
}

/// Low stock summary
class LowStockSummary {
  final int totalLowStock;
  final int criticalStock;
  final int outOfStock;
  final int totalAlerts;
  final double estimatedReorderCost;

  LowStockSummary({
    required this.totalLowStock,
    required this.criticalStock,
    required this.outOfStock,
    required this.totalAlerts,
    required this.estimatedReorderCost,
  });

  factory LowStockSummary.fromJson(Map<String, dynamic> json) {
    return LowStockSummary(
      totalLowStock: json['total_low_stock'] ?? 0,
      criticalStock: json['critical_stock'] ?? 0,
      outOfStock: json['out_of_stock'] ?? 0,
      totalAlerts: json['total_alerts'] ?? 0,
      estimatedReorderCost: (json['estimated_reorder_cost'] ?? 0).toDouble(),
    );
  }
}

/// Out of stock item model
class OutOfStockItem {
  final String productUuid;
  final String productName;
  final String? sku;
  final String locationName;
  final double reorderLevel;
  final String unit;
  final double estimatedReorderCost;

  OutOfStockItem({
    required this.productUuid,
    required this.productName,
    this.sku,
    required this.locationName,
    required this.reorderLevel,
    required this.unit,
    required this.estimatedReorderCost,
  });

  factory OutOfStockItem.fromJson(Map<String, dynamic> json) {
    return OutOfStockItem(
      productUuid: json['product_uuid'] ?? '',
      productName: json['product_name'] ?? '',
      sku: json['sku'],
      locationName: json['location_name'] ?? '',
      reorderLevel: (json['reorder_level'] ?? 0).toDouble(),
      unit: json['unit'] ?? '',
      estimatedReorderCost: (json['estimated_reorder_cost'] ?? 0).toDouble(),
    );
  }
}
