import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/dashboard_model.dart';
import '../models/product_model.dart';
import '../models/alert_model.dart';

/// API Service for backend communication
/// Connects to Node.js HIMS backend APIs
class ApiService {
  static const String _baseUrl = 'http://localhost:3000/api';
  static const Duration _timeout = Duration(seconds: 30);

  String? _authToken;

  /// Set authentication token
  void setAuthToken(String token) {
    _authToken = token;
  }

  /// Get common headers
  Map<String, String> get _headers {
    final headers = {
      'Content-Type': 'application/json',
    };

    if (_authToken != null) {
      headers['Authorization'] = 'Bearer $_authToken';
    }

    return headers;
  }

  /// Handle HTTP response
  Map<String, dynamic> _handleResponse(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return json.decode(response.body);
    } else {
      final error = json.decode(response.body);
      throw ApiException(
        message: error['error'] ?? 'Unknown error',
        statusCode: response.statusCode,
      );
    }
  }

  // ============================================================================
  // AUTHENTICATION
  // ============================================================================

  /// Login
  Future<Map<String, dynamic>> login(String username, String password) async {
    try {
      final response = await http
          .post(
            Uri.parse('$_baseUrl/auth/login'),
            headers: _headers,
            body: json.encode({
              'username': username,
              'password': password,
            }),
          )
          .timeout(_timeout);

      final data = _handleResponse(response);

      if (data['success'] == true && data['token'] != null) {
        _authToken = data['token'];
      }

      return data;
    } catch (e) {
      throw _handleError(e);
    }
  }

  /// Logout
  void logout() {
    _authToken = null;
  }

  // ============================================================================
  // DASHBOARD
  // ============================================================================

  /// Get dashboard summary
  Future<DashboardModel> getDashboardSummary() async {
    try {
      final response = await http
          .get(
            Uri.parse('$_baseUrl/reports/dashboard'),
            headers: _headers,
          )
          .timeout(_timeout);

      final data = _handleResponse(response);
      return DashboardModel.fromJson(data);
    } catch (e) {
      throw _handleError(e);
    }
  }

  // ============================================================================
  // PRODUCTS
  // ============================================================================

  /// Get all products
  Future<List<ProductModel>> getProducts({
    String? search,
    int? categoryId,
    bool activeOnly = true,
  }) async {
    try {
      final queryParams = <String, String>{};

      if (search != null) queryParams['search'] = search;
      if (categoryId != null) queryParams['category_id'] = categoryId.toString();
      if (activeOnly) queryParams['active_only'] = 'true';

      final uri = Uri.parse('$_baseUrl/products').replace(
        queryParameters: queryParams.isEmpty ? null : queryParams,
      );

      final response = await http
          .get(uri, headers: _headers)
          .timeout(_timeout);

      final data = _handleResponse(response);

      if (data['success'] == true && data['products'] != null) {
        return (data['products'] as List)
            .map((e) => ProductModel.fromJson(e))
            .toList();
      }

      return [];
    } catch (e) {
      throw _handleError(e);
    }
  }

  /// Get single product
  Future<ProductModel> getProduct(String uuid) async {
    try {
      final response = await http
          .get(
            Uri.parse('$_baseUrl/products/$uuid'),
            headers: _headers,
          )
          .timeout(_timeout);

      final data = _handleResponse(response);

      if (data['success'] == true && data['product'] != null) {
        return ProductModel.fromJson(data['product']);
      }

      throw ApiException(message: 'Product not found');
    } catch (e) {
      throw _handleError(e);
    }
  }

  /// Get categories
  Future<List<CategoryModel>> getCategories() async {
    try {
      final response = await http
          .get(
            Uri.parse('$_baseUrl/products/categories'),
            headers: _headers,
          )
          .timeout(_timeout);

      final data = _handleResponse(response);

      if (data['success'] == true && data['categories'] != null) {
        return (data['categories'] as List)
            .map((e) => CategoryModel.fromJson(e))
            .toList();
      }

      return [];
    } catch (e) {
      throw _handleError(e);
    }
  }

  /// Get units
  Future<List<UnitModel>> getUnits() async {
    try {
      final response = await http
          .get(
            Uri.parse('$_baseUrl/products/units'),
            headers: _headers,
          )
          .timeout(_timeout);

      final data = _handleResponse(response);

      if (data['success'] == true && data['units'] != null) {
        return (data['units'] as List)
            .map((e) => UnitModel.fromJson(e))
            .toList();
      }

      return [];
    } catch (e) {
      throw _handleError(e);
    }
  }

  // ============================================================================
  // ALERTS & REPORTS
  // ============================================================================

  /// Get low stock alerts
  Future<LowStockReport> getLowStockAlerts({String? locationUuid}) async {
    try {
      final queryParams = <String, String>{};
      if (locationUuid != null) queryParams['location_uuid'] = locationUuid;

      final uri = Uri.parse('$_baseUrl/reports/low-stock').replace(
        queryParameters: queryParams.isEmpty ? null : queryParams,
      );

      final response = await http
          .get(uri, headers: _headers)
          .timeout(_timeout);

      final data = _handleResponse(response);

      if (data['success'] == true) {
        return LowStockReport.fromJson(data);
      }

      throw ApiException(message: 'Failed to fetch alerts');
    } catch (e) {
      throw _handleError(e);
    }
  }

  /// Get sales report
  Future<Map<String, dynamic>> getSalesReport({
    String? fromDate,
    String? toDate,
  }) async {
    try {
      final queryParams = <String, String>{};
      if (fromDate != null) queryParams['from_date'] = fromDate;
      if (toDate != null) queryParams['to_date'] = toDate;

      final uri = Uri.parse('$_baseUrl/reports/sales').replace(
        queryParameters: queryParams.isEmpty ? null : queryParams,
      );

      final response = await http
          .get(uri, headers: _headers)
          .timeout(_timeout);

      return _handleResponse(response);
    } catch (e) {
      throw _handleError(e);
    }
  }

  /// Get stock valuation
  Future<Map<String, dynamic>> getStockValuation({String? locationUuid}) async {
    try {
      final queryParams = <String, String>{};
      if (locationUuid != null) queryParams['location_uuid'] = locationUuid;

      final uri = Uri.parse('$_baseUrl/reports/stock-valuation').replace(
        queryParameters: queryParams.isEmpty ? null : queryParams,
      );

      final response = await http
          .get(uri, headers: _headers)
          .timeout(_timeout);

      return _handleResponse(response);
    } catch (e) {
      throw _handleError(e);
    }
  }

  // ============================================================================
  // HEALTH CHECK
  // ============================================================================

  /// Check API health
  Future<bool> checkHealth() async {
    try {
      final response = await http
          .get(
            Uri.parse('$_baseUrl/health'),
            headers: _headers,
          )
          .timeout(_timeout);

      final data = _handleResponse(response);
      return data['status'] == 'healthy';
    } catch (e) {
      return false;
    }
  }

  // ============================================================================
  // ERROR HANDLING
  // ============================================================================

  Exception _handleError(dynamic error) {
    if (error is ApiException) {
      return error;
    } else if (error is http.ClientException) {
      return ApiException(
        message: 'Network error. Please check your connection.',
      );
    } else {
      return ApiException(
        message: error.toString(),
      );
    }
  }
}

/// API Exception
class ApiException implements Exception {
  final String message;
  final int? statusCode;

  ApiException({
    required this.message,
    this.statusCode,
  });

  @override
  String toString() => message;
}
