/// HIMS Sync Service for Flutter/Drift
/// Handles bidirectional sync with Node.js server
/// Implements push/pull with conflict detection

import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

const int MAX_SYNC_BATCH_SIZE = 200;
const int MAX_RETRY_ATTEMPTS = 3;
const int RETRY_DELAY_MS = 2000;

class SyncService {
  final String serverUrl;
  final String deviceUuid;
  final http.Client _httpClient;

  String? _lastSyncTimestamp;
  bool _isSyncing = false;

  SyncService({
    required this.serverUrl,
    required this.deviceUuid,
    http.Client? httpClient,
  }) : _httpClient = httpClient ?? http.Client();

  /// Initialize sync service
  /// Loads last sync timestamp from preferences
  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    _lastSyncTimestamp = prefs.getString('last_sync_timestamp');
  }

  /// Push local changes to server
  /// Returns number of successfully synced records
  Future<SyncResult> pushChanges(List<SyncQueueItem> items) async {
    if (_isSyncing) {
      throw SyncException('Sync already in progress');
    }

    _isSyncing = true;

    try {
      // Split into batches if needed
      final batches = _splitIntoBatches(items, MAX_SYNC_BATCH_SIZE);

      int totalPushed = 0;
      int totalConflicts = 0;
      int totalErrors = 0;
      final List<SyncItemResult> allResults = [];

      for (final batch in batches) {
        final result = await _pushBatch(batch);
        totalPushed += result.pushed;
        totalConflicts += result.conflicts;
        totalErrors += result.errors;
        allResults.addAll(result.itemResults);
      }

      return SyncResult(
        success: totalErrors == 0,
        pushed: totalPushed,
        pulled: 0,
        conflicts: totalConflicts,
        errors: totalErrors,
        itemResults: allResults,
      );
    } catch (e) {
      throw SyncException('Push failed: $e');
    } finally {
      _isSyncing = false;
    }
  }

  /// Push a single batch to server
  Future<SyncResult> _pushBatch(List<SyncQueueItem> items) async {
    final payload = {
      'device_uuid': deviceUuid,
      'items': items.map((item) => item.toJson()).toList(),
    };

    final response = await _makeRequest(
      'POST',
      '/api/sync/push',
      body: payload,
    );

    final data = jsonDecode(response.body);

    if (!data['success']) {
      throw SyncException('Server rejected push: ${data['error']}');
    }

    final summary = data['summary'];
    final results = (data['results'] as List)
        .map((r) => SyncItemResult.fromJson(r))
        .toList();

    return SyncResult(
      success: summary['errors'] == 0,
      pushed: summary['pushed'],
      pulled: 0,
      conflicts: summary['conflicts'],
      errors: summary['errors'],
      itemResults: results,
    );
  }

  /// Pull changes from server
  /// Returns list of changes to apply locally
  Future<SyncResult> pullChanges({
    List<String>? tables,
    int? limit,
  }) async {
    if (_isSyncing) {
      throw SyncException('Sync already in progress');
    }

    _isSyncing = true;

    try {
      final queryParams = {
        'device_uuid': deviceUuid,
        if (_lastSyncTimestamp != null) 'since': _lastSyncTimestamp!,
        if (tables != null) 'tables': tables.join(','),
        if (limit != null) 'limit': limit.toString(),
      };

      final response = await _makeRequest(
        'GET',
        '/api/sync/pull',
        queryParams: queryParams,
      );

      final data = jsonDecode(response.body);

      if (!data['success']) {
        throw SyncException('Server rejected pull: ${data['error']}');
      }

      final changes = data['changes'] as Map<String, dynamic>;
      final summary = data['summary'];

      // Update last sync timestamp
      final newTimestamp = data['summary']['timestamp'] as String;
      await _saveLastSyncTimestamp(newTimestamp);

      return SyncResult(
        success: true,
        pushed: 0,
        pulled: summary['total_records'],
        conflicts: 0,
        errors: 0,
        changes: changes,
      );
    } catch (e) {
      throw SyncException('Pull failed: $e');
    } finally {
      _isSyncing = false;
    }
  }

  /// Perform full bidirectional sync
  Future<SyncResult> fullSync(List<SyncQueueItem> localChanges) async {
    // Push local changes first
    final pushResult = await pushChanges(localChanges);

    // Then pull server changes
    final pullResult = await pullChanges();

    return SyncResult(
      success: pushResult.success && pullResult.success,
      pushed: pushResult.pushed,
      pulled: pullResult.pulled,
      conflicts: pushResult.conflicts,
      errors: pushResult.errors,
      changes: pullResult.changes,
    );
  }

  /// Register device with server
  Future<bool> registerDevice({
    required String deviceName,
    required String deviceType,
    required String userUuid,
    String? osInfo,
    String? appVersion,
    Map<String, dynamic>? metadata,
  }) async {
    final payload = {
      'device_uuid': deviceUuid,
      'device_name': deviceName,
      'device_type': deviceType,
      'user_uuid': userUuid,
      if (osInfo != null) 'os_info': osInfo,
      if (appVersion != null) 'app_version': appVersion,
      if (metadata != null) 'metadata': metadata,
    };

    final response = await _makeRequest(
      'POST',
      '/api/devices/register',
      body: payload,
    );

    final data = jsonDecode(response.body);
    return data['success'] == true;
  }

  /// Send heartbeat to server
  Future<bool> sendHeartbeat() async {
    try {
      final payload = {'device_uuid': deviceUuid};

      final response = await _makeRequest(
        'POST',
        '/api/devices/heartbeat',
        body: payload,
      );

      final data = jsonDecode(response.body);
      return data['success'] == true;
    } catch (e) {
      // Heartbeat failures should not throw
      print('Heartbeat failed: $e');
      return false;
    }
  }

  /// Make HTTP request with retry logic
  Future<http.Response> _makeRequest(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? queryParams,
  }) async {
    final uri = Uri.parse('$serverUrl$path').replace(
      queryParameters: queryParams,
    );

    for (int attempt = 1; attempt <= MAX_RETRY_ATTEMPTS; attempt++) {
      try {
        http.Response response;

        if (method == 'GET') {
          response = await _httpClient
              .get(uri, headers: _getHeaders())
              .timeout(Duration(seconds: 30));
        } else if (method == 'POST') {
          response = await _httpClient
              .post(
                uri,
                headers: _getHeaders(),
                body: jsonEncode(body),
              )
              .timeout(Duration(seconds: 30));
        } else {
          throw UnsupportedError('HTTP method $method not supported');
        }

        if (response.statusCode >= 200 && response.statusCode < 300) {
          return response;
        }

        // If server returns 4xx, don't retry
        if (response.statusCode >= 400 && response.statusCode < 500) {
          throw SyncException(
            'Server error: ${response.statusCode} - ${response.body}',
          );
        }

        // Retry on 5xx errors
        if (attempt < MAX_RETRY_ATTEMPTS) {
          await Future.delayed(
            Duration(milliseconds: RETRY_DELAY_MS * attempt),
          );
          continue;
        }

        throw SyncException(
          'Server error after $MAX_RETRY_ATTEMPTS attempts: ${response.statusCode}',
        );
      } on SocketException catch (e) {
        if (attempt < MAX_RETRY_ATTEMPTS) {
          await Future.delayed(
            Duration(milliseconds: RETRY_DELAY_MS * attempt),
          );
          continue;
        }
        throw SyncException('Network error: $e');
      } on http.ClientException catch (e) {
        if (attempt < MAX_RETRY_ATTEMPTS) {
          await Future.delayed(
            Duration(milliseconds: RETRY_DELAY_MS * attempt),
          );
          continue;
        }
        throw SyncException('HTTP client error: $e');
      }
    }

    throw SyncException('Request failed after $MAX_RETRY_ATTEMPTS attempts');
  }

  Map<String, String> _getHeaders() {
    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
  }

  /// Split items into batches
  List<List<SyncQueueItem>> _splitIntoBatches(
    List<SyncQueueItem> items,
    int batchSize,
  ) {
    final batches = <List<SyncQueueItem>>[];
    for (int i = 0; i < items.length; i += batchSize) {
      batches.add(
        items.sublist(
          i,
          i + batchSize > items.length ? items.length : i + batchSize,
        ),
      );
    }
    return batches;
  }

  /// Save last sync timestamp to preferences
  Future<void> _saveLastSyncTimestamp(String timestamp) async {
    _lastSyncTimestamp = timestamp;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('last_sync_timestamp', timestamp);
  }

  /// Get last sync timestamp
  String? get lastSyncTimestamp => _lastSyncTimestamp;

  /// Check if sync is in progress
  bool get isSyncing => _isSyncing;

  /// Close HTTP client
  void dispose() {
    _httpClient.close();
  }
}

/// Represents an item in the sync queue
class SyncQueueItem {
  final String tableName;
  final String operation; // 'insert', 'update', 'delete'
  final String recordUuid;
  final Map<String, dynamic> payload;
  final String lastModified;

  SyncQueueItem({
    required this.tableName,
    required this.operation,
    required this.recordUuid,
    required this.payload,
    required this.lastModified,
  });

  Map<String, dynamic> toJson() {
    return {
      'table_name': tableName,
      'operation': operation,
      'record_uuid': recordUuid,
      'payload': payload,
      'last_modified': lastModified,
    };
  }
}

/// Sync result summary
class SyncResult {
  final bool success;
  final int pushed;
  final int pulled;
  final int conflicts;
  final int errors;
  final List<SyncItemResult>? itemResults;
  final Map<String, dynamic>? changes;

  SyncResult({
    required this.success,
    required this.pushed,
    required this.pulled,
    required this.conflicts,
    required this.errors,
    this.itemResults,
    this.changes,
  });
}

/// Individual sync item result
class SyncItemResult {
  final String recordUuid;
  final bool success;
  final String? error;
  final bool? conflict;

  SyncItemResult({
    required this.recordUuid,
    required this.success,
    this.error,
    this.conflict,
  });

  factory SyncItemResult.fromJson(Map<String, dynamic> json) {
    return SyncItemResult(
      recordUuid: json['record_uuid'],
      success: json['success'],
      error: json['error'],
      conflict: json['conflict'],
    );
  }
}

/// Sync exception
class SyncException implements Exception {
  final String message;

  SyncException(this.message);

  @override
  String toString() => 'SyncException: $message';
}
