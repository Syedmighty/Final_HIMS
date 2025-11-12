import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/dashboard_model.dart';
import '../models/alert_model.dart';
import '../services/api_service.dart';

/// Dashboard state
class DashboardState {
  final DashboardModel? dashboard;
  final LowStockReport? alerts;
  final bool isLoading;
  final String? error;
  final DateTime? lastUpdated;

  DashboardState({
    this.dashboard,
    this.alerts,
    this.isLoading = false,
    this.error,
    this.lastUpdated,
  });

  DashboardState copyWith({
    DashboardModel? dashboard,
    LowStockReport? alerts,
    bool? isLoading,
    String? error,
    DateTime? lastUpdated,
  }) {
    return DashboardState(
      dashboard: dashboard ?? this.dashboard,
      alerts: alerts ?? this.alerts,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      lastUpdated: lastUpdated ?? this.lastUpdated,
    );
  }

  bool get hasError => error != null;
  bool get hasData => dashboard != null;
}

/// Dashboard controller
class DashboardController extends StateNotifier<DashboardState> {
  final ApiService _apiService;

  DashboardController(this._apiService) : super(DashboardState());

  /// Load dashboard data
  Future<void> loadDashboard() async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      // Fetch dashboard and alerts in parallel
      final results = await Future.wait([
        _apiService.getDashboardSummary(),
        _apiService.getLowStockAlerts(),
      ]);

      state = state.copyWith(
        dashboard: results[0] as DashboardModel,
        alerts: results[1] as LowStockReport,
        isLoading: false,
        lastUpdated: DateTime.now(),
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
      );
    }
  }

  /// Refresh dashboard
  Future<void> refresh() async {
    await loadDashboard();
  }

  /// Clear error
  void clearError() {
    state = state.copyWith(error: null);
  }
}

/// Dashboard controller provider
final dashboardControllerProvider =
    StateNotifierProvider<DashboardController, DashboardState>((ref) {
  final apiService = ref.watch(apiServiceProvider);
  return DashboardController(apiService);
});

/// API service provider
final apiServiceProvider = Provider<ApiService>((ref) {
  return ApiService();
});

/// Auto-refresh dashboard every 5 minutes
final dashboardAutoRefreshProvider = StreamProvider<int>((ref) {
  return Stream.periodic(
    const Duration(minutes: 5),
    (count) => count,
  );
});

/// Listen to auto-refresh and trigger dashboard reload
final dashboardAutoRefreshListenerProvider = Provider<void>((ref) {
  ref.listen(dashboardAutoRefreshProvider, (previous, next) {
    if (next.hasValue) {
      ref.read(dashboardControllerProvider.notifier).refresh();
    }
  });
});
