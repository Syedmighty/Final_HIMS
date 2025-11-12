
# Device Management System - Implementation Guide

## Overview

This document provides complete implementation guidance for the **Device Management & Sync Control** system introduced in HIMS v2.0.

**Purpose:**
- Limit concurrent devices (default: 5 per hotel)
- Track device connections and sync activity
- Enforce license tiers
- Prevent sync overload on LAN
- Maintain audit trail of all devices

**Status:** ✅ Schema Ready | 🚧 API Implementation Needed | 🚧 Flutter UI Needed

---

## Architecture

```
┌──────────────────────────────────────────────────────────────┐
│                    Central Node.js Server                     │
│  ┌────────────────────────────────────────────────────────┐  │
│  │  Device Registry (SQLite Master DB)                    │  │
│  │  - devices table (max 5 active)                        │  │
│  │  - system_settings (license tier: basic)               │  │
│  │  - device_sessions (track all syncs)                   │  │
│  └────────────────────────────────────────────────────────┘  │
└──────────────────────┬───────────────────────────────────────┘
                       │
          ┌────────────┼────────────┬─────────────┐
          │            │            │             │
     Device 1      Device 2    Device 3      Device 4 (pending)
     ✅ Active    ✅ Active   ✅ Active    ⏳ Needs approval

     Device 5     Device 6 (REJECTED - limit reached)
     ✅ Active    ❌ "Max 5 devices allowed"
```

---

## Database Schema

### Core Tables

| Table | Purpose | Key Fields |
|-------|---------|------------|
| `devices` | Device registry | device_uuid, status, last_seen |
| `system_settings` | Global config (single row) | max_devices, license_tier |
| `device_sessions` | Sync session tracking | session_token, metrics |
| `license_tiers` | Feature limits per tier | max_devices, features |

**Views:**
- `vw_active_devices` - All currently active devices
- `vw_device_capacity` - Current/max device counts
- `vw_device_health` - Device connectivity status
- `vw_recent_sync_activity` - Last 100 sync sessions

---

## Implementation: Node.js Sync Server

### 1. Device Registration Endpoint

```javascript
// routes/devices.js
const express = require('express');
const router = express.Router();
const db = require('../db');  // better-sqlite3 instance

/**
 * POST /api/devices/register
 * Register a new device or update existing
 */
router.post('/register', async (req, res) => {
  const { device_uuid, device_name, device_type, ip_address } = req.body;

  // Validate input
  if (!device_uuid || !device_name) {
    return res.status(400).json({
      error: 'INVALID_INPUT',
      message: 'device_uuid and device_name are required'
    });
  }

  try {
    // Check eligibility
    const eligibility = db.prepare(`
      SELECT
        CASE
          WHEN (SELECT COUNT(*) FROM devices WHERE status = 'active')
               >= (SELECT max_devices FROM system_settings WHERE id = 1)
          THEN 'MAX_DEVICE_LIMIT_REACHED'
          WHEN (SELECT allow_new_registrations FROM system_settings WHERE id = 1) = 0
          THEN 'REGISTRATIONS_DISABLED'
          ELSE 'ELIGIBLE'
        END AS status,
        (SELECT max_devices FROM system_settings WHERE id = 1) AS max_allowed,
        (SELECT COUNT(*) FROM devices WHERE status = 'active') AS current_active
    `).get();

    // Check if device already exists
    const existing = db.prepare('SELECT * FROM devices WHERE device_uuid = ?').get(device_uuid);

    if (existing) {
      // Update last_seen for existing device
      db.prepare(`
        UPDATE devices
        SET last_seen = datetime('now'), ip_address = ?
        WHERE device_uuid = ?
      `).run(ip_address, device_uuid);

      return res.json({
        status: 'ALREADY_REGISTERED',
        device_status: existing.status,
        message: existing.status === 'active'
          ? 'Device is active and ready to sync'
          : `Device is ${existing.status}. Contact administrator for activation.`
      });
    }

    // Check capacity for new devices
    if (eligibility.status !== 'ELIGIBLE') {
      return res.status(403).json({
        error: eligibility.status,
        message: eligibility.status === 'MAX_DEVICE_LIMIT_REACHED'
          ? `Maximum ${eligibility.max_allowed} devices allowed. ${eligibility.current_active} currently active.`
          : 'New device registrations are currently disabled.',
        max_allowed: eligibility.max_allowed,
        current_active: eligibility.current_active,
        available_slots: eligibility.max_allowed - eligibility.current_active
      });
    }

    // Register new device as 'pending' (requires admin approval)
    const result = db.prepare(`
      INSERT INTO devices (device_uuid, device_name, device_type, ip_address, status, registered_by)
      VALUES (?, ?, ?, ?, 'pending', 'system')
    `).run(device_uuid, device_name, device_type || 'mobile', ip_address);

    // Log the registration
    db.prepare(`
      INSERT INTO audit_logs (user_uuid, action, table_name, record_id, new_values)
      VALUES ('system', 'create', 'devices', ?, ?)
    `).run(result.lastInsertRowid, JSON.stringify({ device_uuid, device_name, status: 'pending' }));

    res.status(201).json({
      status: 'REGISTERED',
      device_status: 'pending',
      message: 'Device registered successfully. Awaiting administrator approval.',
      device_id: result.lastInsertRowid
    });

  } catch (error) {
    console.error('Device registration error:', error);
    res.status(500).json({
      error: 'REGISTRATION_FAILED',
      message: 'Failed to register device',
      details: error.message
    });
  }
});

module.exports = router;
```

### 2. Device Activation (Admin Endpoint)

```javascript
/**
 * POST /api/devices/:device_uuid/activate
 * Admin activates a pending device
 * Requires: Admin authentication
 */
router.post('/:device_uuid/activate', requireAdmin, (req, res) => {
  const { device_uuid } = req.params;
  const admin_user_uuid = req.user.uuid;  // From auth middleware

  try {
    const device = db.prepare('SELECT * FROM devices WHERE device_uuid = ?').get(device_uuid);

    if (!device) {
      return res.status(404).json({ error: 'DEVICE_NOT_FOUND' });
    }

    if (device.status === 'active') {
      return res.json({ message: 'Device is already active' });
    }

    // Check if there's capacity
    const capacity = db.prepare('SELECT * FROM vw_device_capacity').get();

    if (capacity.is_at_capacity) {
      return res.status(403).json({
        error: 'MAX_CAPACITY',
        message: `Cannot activate. Maximum ${capacity.max_devices} devices allowed.`,
        suggestion: 'Deactivate another device first or upgrade license.'
      });
    }

    // Activate device
    db.prepare(`
      UPDATE devices
      SET
        status = 'active',
        activated_at = datetime('now'),
        activated_by = ?,
        last_modified = datetime('now')
      WHERE device_uuid = ?
    `).run(admin_user_uuid, device_uuid);

    // Log activation
    db.prepare(`
      INSERT INTO audit_logs (user_uuid, action, table_name, record_uuid, new_values)
      VALUES (?, 'update', 'devices', ?, ?)
    `).run(admin_user_uuid, device.uuid, JSON.stringify({ status: 'active' }));

    res.json({
      status: 'ACTIVATED',
      message: 'Device activated successfully',
      device_name: device.device_name
    });

  } catch (error) {
    res.status(500).json({ error: 'ACTIVATION_FAILED', details: error.message });
  }
});
```

### 3. Sync Handshake with Device Verification

```javascript
/**
 * POST /api/sync/handshake
 * Verify device and create sync session
 */
router.post('/sync/handshake', (req, res) => {
  const { device_uuid, client_version } = req.body;
  const client_ip = req.ip;

  try {
    // Verify device is active
    const device = db.prepare(`
      SELECT * FROM devices
      WHERE device_uuid = ? AND status = 'active'
    `).get(device_uuid);

    if (!device) {
      return res.status(403).json({
        error: 'DEVICE_NOT_AUTHORIZED',
        message: 'Device is not registered or not active',
        action_required: 'Register device or contact administrator'
      });
    }

    // Check last sync time (rate limiting)
    const settings = db.prepare('SELECT * FROM system_settings WHERE id = 1').get();
    const secondsSinceLastSync = device.last_sync
      ? (Date.now() - new Date(device.last_sync).getTime()) / 1000
      : Infinity;

    if (secondsSinceLastSync < settings.max_sync_frequency_seconds) {
      return res.status(429).json({
        error: 'SYNC_TOO_FREQUENT',
        message: `Please wait ${settings.max_sync_frequency_seconds}s between syncs`,
        retry_after: settings.max_sync_frequency_seconds - secondsSinceLastSync
      });
    }

    // Update device heartbeat
    db.prepare('UPDATE devices SET last_seen = datetime(\'now\') WHERE id = ?').run(device.id);

    // Create sync session
    const session_token = crypto.randomBytes(32).toString('hex');
    const serverVersion = process.env.SERVER_VERSION || '1.0.0';

    const session = db.prepare(`
      INSERT INTO device_sessions (
        device_id, session_token, client_ip, client_version, server_version
      ) VALUES (?, ?, ?, ?, ?)
    `).run(device.id, session_token, client_ip, client_version, serverVersion);

    res.json({
      status: 'HANDSHAKE_SUCCESS',
      session_token,
      server_version: serverVersion,
      sync_config: {
        batch_size: settings.sync_batch_size,
        max_frequency: settings.max_sync_frequency_seconds
      },
      device_info: {
        device_name: device.device_name,
        total_syncs: device.total_syncs,
        last_sync: device.last_sync
      }
    });

  } catch (error) {
    res.status(500).json({ error: 'HANDSHAKE_FAILED', details: error.message });
  }
});
```

### 4. Sync Session Completion

```javascript
/**
 * POST /api/sync/complete
 * Mark sync session as completed
 */
router.post('/sync/complete', (req, res) => {
  const {
    session_token,
    records_pulled,
    records_pushed,
    conflicts_detected,
    errors_count
  } = req.body;

  try {
    const session = db.prepare(`
      SELECT * FROM device_sessions WHERE session_token = ? AND status = 'active'
    `).get(session_token);

    if (!session) {
      return res.status(404).json({ error: 'SESSION_NOT_FOUND' });
    }

    // End session
    db.prepare(`
      UPDATE device_sessions
      SET
        ended_at = datetime('now'),
        duration_seconds = CAST((julianday(datetime('now')) - julianday(started_at)) * 86400 AS INTEGER),
        records_pulled = ?,
        records_pushed = ?,
        conflicts_detected = ?,
        errors_count = ?,
        status = ?
      WHERE session_token = ?
    `).run(
      records_pulled || 0,
      records_pushed || 0,
      conflicts_detected || 0,
      errors_count || 0,
      errors_count > 0 ? 'failed' : 'completed',
      session_token
    );

    // Trigger will auto-update device stats

    res.json({
      status: 'SYNC_COMPLETED',
      session_id: session.uuid,
      duration_seconds: Math.floor((Date.now() - new Date(session.started_at).getTime()) / 1000)
    });

  } catch (error) {
    res.status(500).json({ error: 'COMPLETION_FAILED', details: error.message });
  }
});
```

---

## Implementation: Flutter App

### 1. Device Registration on First Launch

```dart
// services/device_service.dart
import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:uuid/uuid.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DeviceService {
  static const String _keyDeviceUuid = 'device_uuid';
  static const String _keyDeviceStatus = 'device_status';

  /// Get or create device UUID
  Future<String> getDeviceUuid() async {
    final prefs = await SharedPreferences.getInstance();
    String? uuid = prefs.getString(_keyDeviceUuid);

    if (uuid == null) {
      uuid = const Uuid().v4();
      await prefs.setString(_keyDeviceUuid, uuid);
    }

    return uuid;
  }

  /// Register device with sync server
  Future<DeviceRegistrationResult> registerDevice() async {
    final deviceUuid = await getDeviceUuid();
    final deviceInfo = DeviceInfoPlugin();
    String deviceName;
    String deviceType = 'mobile';

    if (Platform.isAndroid) {
      final androidInfo = await deviceInfo.androidInfo;
      deviceName = '${androidInfo.brand} ${androidInfo.model}';
      deviceType = 'mobile';
    } else if (Platform.isIOS) {
      final iosInfo = await deviceInfo.iosInfo;
      deviceName = '${iosInfo.name} (${iosInfo.model})';
      deviceType = 'mobile';
    } else {
      deviceName = Platform.operatingSystem;
      deviceType = 'desktop';
    }

    try {
      final response = await http.post(
        Uri.parse('${apiBaseUrl}/api/devices/register'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'device_uuid': deviceUuid,
          'device_name': deviceName,
          'device_type': deviceType,
          'ip_address': await _getLocalIP(),
        }),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 201 || response.statusCode == 200) {
        // Registered successfully
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_keyDeviceStatus, data['device_status']);

        return DeviceRegistrationResult(
          success: true,
          status: data['device_status'],
          message: data['message'],
        );
      } else if (response.statusCode == 403) {
        // Max devices reached
        return DeviceRegistrationResult(
          success: false,
          status: 'rejected',
          message: data['message'],
          errorCode: data['error'],
        );
      } else {
        throw Exception('Registration failed: ${data['message']}');
      }
    } catch (e) {
      return DeviceRegistrationResult(
        success: false,
        status: 'error',
        message: 'Failed to register device: $e',
      );
    }
  }

  /// Check device status before sync
  Future<bool> isDeviceAuthorized() async {
    final prefs = await SharedPreferences.getInstance();
    final status = prefs.getString(_keyDeviceStatus);
    return status == 'active';
  }

  Future<String> _getLocalIP() async {
    try {
      for (var interface in await NetworkInterface.list()) {
        for (var addr in interface.addresses) {
          if (addr.type == InternetAddressType.IPv4 && !addr.isLoopback) {
            return addr.address;
          }
        }
      }
    } catch (e) {
      // Ignore
    }
    return 'unknown';
  }
}

class DeviceRegistrationResult {
  final bool success;
  final String status;
  final String message;
  final String? errorCode;

  DeviceRegistrationResult({
    required this.success,
    required this.status,
    required this.message,
    this.errorCode,
  });
}
```

### 2. Device Registration Screen

```dart
// screens/device_registration_screen.dart
import 'package:flutter/material.dart';

class DeviceRegistrationScreen extends StatefulWidget {
  @override
  _DeviceRegistrationScreenState createState() => _DeviceRegistrationScreenState();
}

class _DeviceRegistrationScreenState extends State<DeviceRegistrationScreen> {
  final DeviceService _deviceService = DeviceService();
  bool _isRegistering = false;
  String? _deviceUuid;
  String? _statusMessage;
  DeviceRegistrationResult? _result;

  @override
  void initState() {
    super.initState();
    _loadDeviceInfo();
  }

  Future<void> _loadDeviceInfo() async {
    final uuid = await _deviceService.getDeviceUuid();
    setState(() {
      _deviceUuid = uuid;
    });
  }

  Future<void> _register() async {
    setState(() {
      _isRegistering = true;
      _statusMessage = 'Registering device...';
    });

    final result = await _deviceService.registerDevice();

    setState(() {
      _isRegistering = false;
      _result = result;
      _statusMessage = result.message;
    });

    if (result.success && result.status == 'active') {
      // Device is active, proceed to main app
      Navigator.pushReplacementNamed(context, '/home');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Device Registration')),
      body: Padding(
        padding: EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Icon(Icons.devices, size: 80, color: Colors.blue),
            SizedBox(height: 24),
            Text(
              'Register This Device',
              style: Theme.of(context).textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 16),
            if (_deviceUuid != null)
              Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Text('Device ID:', style: TextStyle(fontSize: 12, color: Colors.grey)),
                      SizedBox(height: 4),
                      Text(_deviceUuid!, style: TextStyle(fontFamily: 'monospace', fontSize: 10)),
                    ],
                  ),
                ),
              ),
            SizedBox(height: 24),
            if (_result != null)
              Card(
                color: _result!.success ? Colors.green.shade50 : Colors.red.shade50,
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Icon(
                        _result!.success ? Icons.check_circle : Icons.error,
                        color: _result!.success ? Colors.green : Colors.red,
                        size: 48,
                      ),
                      SizedBox(height: 8),
                      Text(
                        _result!.status.toUpperCase(),
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      SizedBox(height: 4),
                      Text(
                        _statusMessage ?? '',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 14),
                      ),
                      if (_result!.errorCode == 'MAX_DEVICE_LIMIT_REACHED')
                        Padding(
                          padding: EdgeInsets.only(top: 12),
                          child: Text(
                            'Contact your administrator to activate this device.',
                            style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            SizedBox(height: 24),
            ElevatedButton(
              onPressed: _isRegistering ? null : _register,
              child: _isRegistering
                  ? CircularProgressIndicator(color: Colors.white)
                  : Text('Register Device'),
            ),
            if (_result?.status == 'pending')
              Padding(
                padding: EdgeInsets.only(top: 16),
                child: OutlinedButton(
                  onPressed: _register,
                  child: Text('Check Status'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
```

### 3. Sync Service with Device Verification

```dart
// services/sync_service.dart
class SyncService {
  final DeviceService _deviceService = DeviceService();

  Future<SyncResult> performSync() async {
    // Check device authorization
    final isAuthorized = await _deviceService.isDeviceAuthorized();

    if (!isAuthorized) {
      // Try to re-register or check status
      final regResult = await _deviceService.registerDevice();

      if (!regResult.success || regResult.status != 'active') {
        return SyncResult(
          success: false,
          error: 'Device not authorized',
          message: regResult.message,
        );
      }
    }

    // Proceed with handshake
    final deviceUuid = await _deviceService.getDeviceUuid();

    try {
      // Handshake
      final handshakeResponse = await http.post(
        Uri.parse('${apiBaseUrl}/api/sync/handshake'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'device_uuid': deviceUuid,
          'client_version': packageInfo.version,
        }),
      );

      if (handshakeResponse.statusCode != 200) {
        final error = jsonDecode(handshakeResponse.body);
        return SyncResult(
          success: false,
          error: error['error'],
          message: error['message'],
        );
      }

      final handshake = jsonDecode(handshakeResponse.body);
      final sessionToken = handshake['session_token'];

      // Perform actual sync
      final syncStats = await _doSync(sessionToken, handshake['sync_config']);

      // Complete session
      await http.post(
        Uri.parse('${apiBaseUrl}/api/sync/complete'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'session_token': sessionToken,
          'records_pulled': syncStats.pulled,
          'records_pushed': syncStats.pushed,
          'conflicts_detected': syncStats.conflicts,
          'errors_count': syncStats.errors,
        }),
      );

      return SyncResult(success: true, stats: syncStats);

    } catch (e) {
      return SyncResult(
        success: false,
        error: 'SYNC_FAILED',
        message: e.toString(),
      );
    }
  }

  Future<SyncStats> _doSync(String sessionToken, Map<String, dynamic> config) async {
    // Actual sync logic here
    // ...
  }
}
```

---

## Admin UI (Flutter)

### Device Management Screen

```dart
// screens/admin/device_management_screen.dart
class DeviceManagementScreen extends StatefulWidget {
  @override
  _DeviceManagementScreenState createState() => _DeviceManagementScreenState();
}

class _DeviceManagementScreenState extends State<DeviceManagementScreen> {
  List<Device> _devices = [];
  DeviceCapacity? _capacity;

  @override
  void initState() {
    super.initState();
    _loadDevices();
  }

  Future<void> _loadDevices() async {
    // Fetch from API
    final response = await http.get(Uri.parse('${apiBaseUrl}/api/devices'));
    final capacityResponse = await http.get(Uri.parse('${apiBaseUrl}/api/devices/capacity'));

    if (response.statusCode == 200) {
      setState(() {
        _devices = (jsonDecode(response.body) as List)
            .map((json) => Device.fromJson(json))
            .toList();
        _capacity = DeviceCapacity.fromJson(jsonDecode(capacityResponse.body));
      });
    }
  }

  Future<void> _activateDevice(String deviceUuid) async {
    // Activate via API
    final response = await http.post(
      Uri.parse('${apiBaseUrl}/api/devices/$deviceUuid/activate'),
      headers: {'Authorization': 'Bearer $authToken'},
    );

    if (response.statusCode == 200) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Device activated successfully')),
      );
      _loadDevices();
    } else {
      final error = jsonDecode(response.body);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error['message']), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Device Management'),
        actions: [
          if (_capacity != null)
            Padding(
              padding: EdgeInsets.all(16),
              child: Chip(
                label: Text('${_capacity!.activeDevices}/${_capacity!.maxDevices}'),
                backgroundColor: _capacity!.isAtCapacity ? Colors.red : Colors.green,
              ),
            ),
        ],
      ),
      body: ListView.builder(
        itemCount: _devices.length,
        itemBuilder: (context, index) {
          final device = _devices[index];
          return Card(
            margin: EdgeInsets.all(8),
            child: ListTile(
              leading: Icon(
                _getDeviceIcon(device.deviceType),
                size: 40,
                color: _getStatusColor(device.status),
              ),
              title: Text(device.deviceName),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('IP: ${device.ipAddress ?? "Unknown"}'),
                  Text('Last seen: ${_formatTimestamp(device.lastSeen)}'),
                  Text('Syncs: ${device.totalSyncs} (${device.failedSyncs} failed)'),
                ],
              ),
              trailing: _buildActionButton(device),
            ),
          );
        },
      ),
    );
  }

  Widget _buildActionButton(Device device) {
    switch (device.status) {
      case 'pending':
        return ElevatedButton(
          onPressed: () => _activateDevice(device.deviceUuid),
          child: Text('Activate'),
        );
      case 'active':
        return PopupMenuButton(
          itemBuilder: (context) => [
            PopupMenuItem(child: Text('Block'), value: 'block'),
            PopupMenuItem(child: Text('View Details'), value: 'details'),
          ],
        );
      case 'blocked':
        return TextButton(
          onPressed: () => _activateDevice(device.deviceUuid),
          child: Text('Unblock'),
        );
      default:
        return SizedBox.shrink();
    }
  }

  IconData _getDeviceIcon(String type) {
    switch (type) {
      case 'mobile':
        return Icons.phone_android;
      case 'tablet':
        return Icons.tablet;
      case 'desktop':
        return Icons.computer;
      default:
        return Icons.device_unknown;
    }
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'active':
        return Colors.green;
      case 'pending':
        return Colors.orange;
      case 'blocked':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  String _formatTimestamp(String timestamp) {
    final dt = DateTime.parse(timestamp);
    final now = DateTime.now();
    final diff = now.difference(dt);

    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}
```

---

## Testing

### 1. Test Device Registration

```bash
# Test with curl
curl -X POST http://localhost:3000/api/devices/register \
  -H "Content-Type: application/json" \
  -d '{
    "device_uuid": "test-device-001",
    "device_name": "Test Device 1",
    "device_type": "mobile",
    "ip_address": "192.168.1.100"
  }'

# Expected: 201 Created with status "pending"
```

### 2. Test Max Device Limit

```bash
# Register 5 devices
for i in {1..5}; do
  curl -X POST http://localhost:3000/api/devices/register \
    -H "Content-Type: application/json" \
    -d "{\"device_uuid\": \"device-$i\", \"device_name\": \"Device $i\", \"device_type\": \"mobile\"}"
done

# Activate all 5
for i in {1..5}; do
  curl -X POST http://localhost:3000/api/devices/device-$i/activate \
    -H "Authorization: Bearer $ADMIN_TOKEN"
done

# Try to register 6th device
curl -X POST http://localhost:3000/api/devices/register \
  -H "Content-Type: application/json" \
  -d '{"device_uuid": "device-6", "device_name": "Device 6", "device_type": "mobile"}'

# Expected: 403 Forbidden with error "MAX_DEVICE_LIMIT_REACHED"
```

### 3. Test Sync Handshake

```bash
# Handshake with registered device
curl -X POST http://localhost:3000/api/sync/handshake \
  -H "Content-Type: application/json" \
  -d '{
    "device_uuid": "device-1",
    "client_version": "1.0.0"
  }'

# Expected: 200 OK with session_token
```

---

## Configuration

### Environment Variables

```bash
# .env file for Node.js server
MAX_DEVICES=5
LICENSE_TIER=basic
INACTIVE_DEVICE_DAYS=7
AUTO_DEACTIVATE_INACTIVE=true
MAX_SYNC_FREQUENCY_SECONDS=300
SYNC_BATCH_SIZE=1000
```

### System Settings UI

Allow admin to change settings via API:

```javascript
// PUT /api/settings
router.put('/settings', requireAdmin, (req, res) => {
  const { max_devices, license_tier, inactive_device_days } = req.body;

  db.prepare(`
    UPDATE system_settings
    SET
      max_devices = COALESCE(?, max_devices),
      license_tier = COALESCE(?, license_tier),
      inactive_device_days = COALESCE(?, inactive_device_days),
      last_modified = datetime('now'),
      modified_by = ?
    WHERE id = 1
  `).run(max_devices, license_tier, inactive_device_days, req.user.uuid);

  res.json({ status: 'SETTINGS_UPDATED' });
});
```

---

## Monitoring & Analytics

### 1. Device Health Dashboard

Query to show device health:

```sql
SELECT * FROM vw_device_health;
```

### 2. Sync Performance Metrics

```sql
SELECT
  date(started_at) AS sync_date,
  COUNT(*) AS total_syncs,
  AVG(duration_seconds) AS avg_duration,
  SUM(records_pulled) AS total_pulled,
  SUM(records_pushed) AS total_pushed,
  SUM(conflicts_detected) AS total_conflicts
FROM device_sessions
WHERE started_at >= date('now', '-30 days')
GROUP BY date(started_at)
ORDER BY sync_date DESC;
```

### 3. Device Activity Heatmap

```sql
SELECT
  device_name,
  COUNT(*) AS sync_count,
  MIN(started_at) AS first_sync,
  MAX(started_at) AS last_sync,
  SUM(CASE WHEN status = 'failed' THEN 1 ELSE 0 END) AS failures
FROM device_sessions ds
JOIN devices d ON ds.device_id = d.id
WHERE ds.started_at >= date('now', '-7 days')
GROUP BY device_name
ORDER BY sync_count DESC;
```

---

## Troubleshooting

### Issue 1: "Max device limit reached" but devices show inactive

**Solution:**
```sql
-- Check inactive devices
SELECT * FROM devices WHERE status = 'inactive';

-- Delete truly unused devices
DELETE FROM devices WHERE status = 'inactive'
AND last_seen < date('now', '-30 days');
```

### Issue 2: Device stuck in "pending" status

**Solution:**
```sql
-- Manually activate device
UPDATE devices
SET status = 'active', activated_at = datetime('now'), activated_by = 'admin-uuid'
WHERE device_uuid = 'stuck-device-uuid';
```

### Issue 3: Sync handshake fails with "Device not authorized"

**Checklist:**
1. Check device status: `SELECT * FROM devices WHERE device_uuid = ?`
2. Verify device is active
3. Check if device was auto-deactivated for inactivity
4. Check audit_logs for any blocking actions

---

## Roadmap

### v2.0 (Current)
- ✅ Device registry with max limit
- ✅ License tier support
- ✅ Auto-deactivation of inactive devices
- ✅ Sync session tracking

### v2.1 (Planned)
- [ ] Device token authentication
- [ ] Location-scoped device limits (per branch)
- [ ] Push notifications when nearing limit
- [ ] Device transfer between hotels
- [ ] Bulk device import/export

### v2.2 (Future)
- [ ] AI-based anomaly detection
- [ ] Predictive device failure alerts
- [ ] Multi-tenant architecture
- [ ] Cloud sync option (hybrid mode)

---

**Status:** 📚 Documentation Complete | 🔨 Ready for Implementation
**Next Steps:** Implement Node.js endpoints, then Flutter UI
**Estimated Dev Time:** 2-3 weeks (backend + mobile)

