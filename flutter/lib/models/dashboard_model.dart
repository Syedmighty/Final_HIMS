/// Dashboard data model
/// Maps to /api/reports/dashboard endpoint
class DashboardModel {
  final SalesToday salesToday;
  final SalesThisMonth salesThisMonth;
  final int lowStockAlerts;
  final PendingPurchases pendingPurchases;
  final double totalStockValue;
  final List<RecentActivity> recentActivities;

  DashboardModel({
    required this.salesToday,
    required this.salesThisMonth,
    required this.lowStockAlerts,
    required this.pendingPurchases,
    required this.totalStockValue,
    required this.recentActivities,
  });

  factory DashboardModel.fromJson(Map<String, dynamic> json) {
    return DashboardModel(
      salesToday: SalesToday.fromJson(json['sales_today'] ?? {}),
      salesThisMonth: SalesThisMonth.fromJson(json['sales_this_month'] ?? {}),
      lowStockAlerts: json['low_stock_alerts'] ?? 0,
      pendingPurchases: PendingPurchases.fromJson(json['pending_purchases'] ?? {}),
      totalStockValue: (json['total_stock_value'] ?? 0).toDouble(),
      recentActivities: (json['recent_activities'] as List?)
              ?.map((e) => RecentActivity.fromJson(e))
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'sales_today': salesToday.toJson(),
      'sales_this_month': salesThisMonth.toJson(),
      'low_stock_alerts': lowStockAlerts,
      'pending_purchases': pendingPurchases.toJson(),
      'total_stock_value': totalStockValue,
      'recent_activities': recentActivities.map((e) => e.toJson()).toList(),
    };
  }
}

class SalesToday {
  final int invoicesCount;
  final double totalRevenue;

  SalesToday({
    required this.invoicesCount,
    required this.totalRevenue,
  });

  factory SalesToday.fromJson(Map<String, dynamic> json) {
    return SalesToday(
      invoicesCount: json['invoices_count'] ?? 0,
      totalRevenue: (json['total_revenue'] ?? 0).toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'invoices_count': invoicesCount,
      'total_revenue': totalRevenue,
    };
  }
}

class SalesThisMonth {
  final int invoicesCount;
  final double totalRevenue;

  SalesThisMonth({
    required this.invoicesCount,
    required this.totalRevenue,
  });

  factory SalesThisMonth.fromJson(Map<String, dynamic> json) {
    return SalesThisMonth(
      invoicesCount: json['invoices_count'] ?? 0,
      totalRevenue: (json['total_revenue'] ?? 0).toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'invoices_count': invoicesCount,
      'total_revenue': totalRevenue,
    };
  }
}

class PendingPurchases {
  final int count;
  final double totalAmount;

  PendingPurchases({
    required this.count,
    required this.totalAmount,
  });

  factory PendingPurchases.fromJson(Map<String, dynamic> json) {
    return PendingPurchases(
      count: json['count'] ?? 0,
      totalAmount: (json['total_amount'] ?? 0).toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'count': count,
      'total_amount': totalAmount,
    };
  }
}

class RecentActivity {
  final String type;
  final String uuid;
  final String reference;
  final double amount;
  final String createdAt;

  RecentActivity({
    required this.type,
    required this.uuid,
    required this.reference,
    required this.amount,
    required this.createdAt,
  });

  factory RecentActivity.fromJson(Map<String, dynamic> json) {
    return RecentActivity(
      type: json['type'] ?? '',
      uuid: json['uuid'] ?? '',
      reference: json['reference'] ?? '',
      amount: (json['amount'] ?? 0).toDouble(),
      createdAt: json['created_at'] ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'type': type,
      'uuid': uuid,
      'reference': reference,
      'amount': amount,
      'created_at': createdAt,
    };
  }
}
