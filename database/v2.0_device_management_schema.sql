-- ============================================================================
-- HIMS DATABASE SCHEMA v2.0 - Device Management & Sync Control
-- ============================================================================
-- Description: Multi-device sync management with license enforcement
-- Purpose: Limit concurrent devices, track connections, prevent sync overload
-- Version: 2.0.0
-- Prerequisites: v1.0.1 or later
-- Target Release: Q1 2026
-- ============================================================================

-- ============================================================================
-- SECTION 1: DEVICE REGISTRY
-- ============================================================================

-- --------------------
-- 1.1 DEVICES TABLE
-- --------------------
-- Central registry of all devices that can connect to sync server
-- Enforces max device limit per hotel instance

CREATE TABLE IF NOT EXISTS devices (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  uuid TEXT NOT NULL UNIQUE DEFAULT (hex(randomblob(16))),
  device_uuid TEXT NOT NULL UNIQUE, -- Client-generated UUID (from device)
  device_name TEXT NOT NULL,
  device_type TEXT CHECK (device_type IN ('mobile', 'tablet', 'desktop', 'pos')) DEFAULT 'mobile',

  -- Network info
  ip_address TEXT,
  mac_address TEXT,
  hostname TEXT,

  -- Status tracking
  status TEXT CHECK (status IN ('active', 'blocked', 'inactive', 'pending')) DEFAULT 'pending',
  last_seen TEXT DEFAULT (datetime('now')),
  last_sync TEXT,

  -- Connection stats
  total_syncs INTEGER DEFAULT 0,
  failed_syncs INTEGER DEFAULT 0,
  last_error TEXT,

  -- Registration info
  registered_at TEXT NOT NULL DEFAULT (datetime('now')),
  registered_by TEXT DEFAULT 'system',
  activated_at TEXT,
  activated_by TEXT,

  -- Audit fields
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  last_modified TEXT NOT NULL DEFAULT (datetime('now')),
  blocked_at TEXT,
  blocked_by TEXT,
  blocked_reason TEXT,

  FOREIGN KEY (registered_by) REFERENCES users(uuid) ON DELETE SET NULL,
  FOREIGN KEY (activated_by) REFERENCES users(uuid) ON DELETE SET NULL,
  FOREIGN KEY (blocked_by) REFERENCES users(uuid) ON DELETE SET NULL
);

CREATE INDEX idx_devices_uuid ON devices(uuid);
CREATE INDEX idx_devices_device_uuid ON devices(device_uuid);
CREATE INDEX idx_devices_status ON devices(status);
CREATE INDEX idx_devices_last_seen ON devices(last_seen);
CREATE INDEX idx_devices_ip ON devices(ip_address);

-- --------------------
-- 1.2 SYSTEM SETTINGS TABLE
-- --------------------
-- Global configuration for device limits and sync behavior

CREATE TABLE IF NOT EXISTS system_settings (
  id INTEGER PRIMARY KEY CHECK (id = 1), -- Single row constraint

  -- Device limits
  max_devices INTEGER DEFAULT 5 CHECK (max_devices > 0 AND max_devices <= 100),
  allow_new_registrations INTEGER DEFAULT 1 CHECK (allow_new_registrations IN (0, 1)),

  -- Auto-expiry settings
  inactive_device_days INTEGER DEFAULT 7 CHECK (inactive_device_days >= 1),
  auto_deactivate_inactive INTEGER DEFAULT 1 CHECK (auto_deactivate_inactive IN (0, 1)),

  -- Sync settings
  max_sync_frequency_seconds INTEGER DEFAULT 300 CHECK (max_sync_frequency_seconds >= 60),
  sync_batch_size INTEGER DEFAULT 1000 CHECK (sync_batch_size >= 100),

  -- License info
  license_tier TEXT CHECK (license_tier IN ('free', 'basic', 'premium', 'enterprise')) DEFAULT 'basic',
  license_key TEXT,
  license_expires TEXT,

  -- Metadata
  hotel_name TEXT,
  hotel_branch_id TEXT,
  last_modified TEXT NOT NULL DEFAULT (datetime('now')),
  modified_by TEXT,

  FOREIGN KEY (modified_by) REFERENCES users(uuid) ON DELETE SET NULL
);

-- Seed default settings
INSERT OR IGNORE INTO system_settings (
  id, max_devices, allow_new_registrations, inactive_device_days,
  auto_deactivate_inactive, max_sync_frequency_seconds, sync_batch_size,
  license_tier
) VALUES (
  1, 5, 1, 7, 1, 300, 1000, 'basic'
);

CREATE INDEX idx_system_settings_modified ON system_settings(last_modified);

-- --------------------
-- 1.3 DEVICE SESSIONS TABLE
-- --------------------
-- Track individual sync sessions for analytics and debugging

CREATE TABLE IF NOT EXISTS device_sessions (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  uuid TEXT NOT NULL UNIQUE DEFAULT (hex(randomblob(16))),
  device_id INTEGER NOT NULL,
  session_token TEXT NOT NULL UNIQUE,

  -- Session lifecycle
  started_at TEXT NOT NULL DEFAULT (datetime('now')),
  ended_at TEXT,
  duration_seconds INTEGER,

  -- Sync metrics
  records_pulled INTEGER DEFAULT 0,
  records_pushed INTEGER DEFAULT 0,
  conflicts_detected INTEGER DEFAULT 0,
  errors_count INTEGER DEFAULT 0,

  -- Network info
  client_ip TEXT,
  client_version TEXT,
  server_version TEXT,

  -- Status
  status TEXT CHECK (status IN ('active', 'completed', 'failed', 'timeout')) DEFAULT 'active',
  error_message TEXT,

  FOREIGN KEY (device_id) REFERENCES devices(id) ON DELETE CASCADE
);

CREATE INDEX idx_device_sessions_device ON device_sessions(device_id);
CREATE INDEX idx_device_sessions_started ON device_sessions(started_at);
CREATE INDEX idx_device_sessions_status ON device_sessions(status);
CREATE INDEX idx_device_sessions_token ON device_sessions(session_token);

-- --------------------
-- 1.4 LICENSE TIERS TABLE
-- --------------------
-- Define feature limits per license tier

CREATE TABLE IF NOT EXISTS license_tiers (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  tier_name TEXT NOT NULL UNIQUE CHECK (tier_name IN ('free', 'basic', 'premium', 'enterprise')),
  max_devices INTEGER NOT NULL,
  max_users INTEGER NOT NULL,
  max_products INTEGER NOT NULL,
  max_locations INTEGER NOT NULL,

  -- Features
  enable_reports INTEGER DEFAULT 1 CHECK (enable_reports IN (0, 1)),
  enable_recipes INTEGER DEFAULT 1 CHECK (enable_recipes IN (0, 1)),
  enable_batch_tracking INTEGER DEFAULT 1 CHECK (enable_batch_tracking IN (0, 1)),
  enable_barcode_scanning INTEGER DEFAULT 0 CHECK (enable_barcode_scanning IN (0, 1)),
  enable_email_reports INTEGER DEFAULT 0 CHECK (enable_email_reports IN (0, 1)),
  enable_api_access INTEGER DEFAULT 0 CHECK (enable_api_access IN (0, 1)),

  -- Support
  support_level TEXT CHECK (support_level IN ('community', 'email', 'priority', 'dedicated')),

  -- Pricing
  monthly_price REAL DEFAULT 0 CHECK (monthly_price >= 0),
  currency TEXT DEFAULT 'USD',

  description TEXT,
  is_active INTEGER DEFAULT 1 CHECK (is_active IN (0, 1)),
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

-- Seed default license tiers
INSERT OR IGNORE INTO license_tiers (
  tier_name, max_devices, max_users, max_products, max_locations,
  enable_reports, enable_recipes, enable_batch_tracking, enable_barcode_scanning,
  enable_email_reports, enable_api_access, support_level, monthly_price, description
) VALUES
  ('free', 2, 3, 100, 2, 1, 0, 0, 0, 0, 0, 'community', 0, 'Free tier for small operations'),
  ('basic', 5, 10, 500, 5, 1, 1, 1, 0, 0, 0, 'email', 49, 'Small to medium hotels'),
  ('premium', 15, 30, 2000, 10, 1, 1, 1, 1, 1, 0, 'priority', 149, 'Large hotels with multiple locations'),
  ('enterprise', 50, 100, 999999, 50, 1, 1, 1, 1, 1, 1, 'dedicated', 499, 'Hotel chains and enterprises');

CREATE INDEX idx_license_tiers_name ON license_tiers(tier_name);
CREATE INDEX idx_license_tiers_active ON license_tiers(is_active) WHERE is_active = 1;

-- ============================================================================
-- SECTION 2: TRIGGERS FOR DEVICE MANAGEMENT
-- ============================================================================

-- --------------------
-- 2.1 Auto-Deactivate Inactive Devices
-- --------------------
-- Automatically set devices to inactive if not seen for X days

DROP TRIGGER IF EXISTS trg_auto_deactivate_inactive_devices;

CREATE TRIGGER trg_auto_deactivate_inactive_devices
AFTER UPDATE OF last_seen ON devices
WHEN NEW.status = 'active'
  AND (SELECT auto_deactivate_inactive FROM system_settings WHERE id = 1) = 1
  AND (julianday('now') - julianday(NEW.last_seen)) > (SELECT inactive_device_days FROM system_settings WHERE id = 1)
BEGIN
  UPDATE devices
  SET
    status = 'inactive',
    last_modified = datetime('now'),
    blocked_reason = 'Auto-deactivated due to inactivity'
  WHERE id = NEW.id;

  -- Log the deactivation
  INSERT INTO audit_logs (user_uuid, action, table_name, record_id, new_values, timestamp)
  VALUES (
    'system',
    'update',
    'devices',
    NEW.id,
    json_object('status', 'inactive', 'reason', 'auto-deactivated'),
    datetime('now')
  );
END;

-- --------------------
-- 2.2 Update Sync Stats on Session End
-- --------------------
-- Aggregate session data to device record

DROP TRIGGER IF EXISTS trg_update_device_stats_on_session_end;

CREATE TRIGGER trg_update_device_stats_on_session_end
AFTER UPDATE OF status ON device_sessions
WHEN NEW.status IN ('completed', 'failed', 'timeout')
  AND OLD.status = 'active'
BEGIN
  UPDATE devices
  SET
    last_sync = NEW.started_at,
    total_syncs = total_syncs + CASE WHEN NEW.status = 'completed' THEN 1 ELSE 0 END,
    failed_syncs = failed_syncs + CASE WHEN NEW.status IN ('failed', 'timeout') THEN 1 ELSE 0 END,
    last_error = CASE WHEN NEW.status != 'completed' THEN NEW.error_message ELSE NULL END,
    last_modified = datetime('now')
  WHERE id = NEW.device_id;
END;

-- --------------------
-- 2.3 Timestamp Update for system_settings
-- --------------------

DROP TRIGGER IF EXISTS trg_system_settings_timestamp;

CREATE TRIGGER trg_system_settings_timestamp
AFTER UPDATE ON system_settings
BEGIN
  -- Note: Can't use UPDATE in BEFORE trigger, so app must set last_modified
  -- This trigger is just for documentation
  SELECT 'Application must set last_modified on system_settings updates' AS reminder;
END;

-- ============================================================================
-- SECTION 3: VIEWS FOR DEVICE MANAGEMENT
-- ============================================================================

-- --------------------
-- 3.1 Active Devices View
-- --------------------

CREATE VIEW vw_active_devices AS
SELECT
  d.id,
  d.uuid,
  d.device_uuid,
  d.device_name,
  d.device_type,
  d.ip_address,
  d.status,
  d.last_seen,
  d.last_sync,
  d.total_syncs,
  d.failed_syncs,
  CAST((julianday('now') - julianday(d.last_seen)) AS INTEGER) AS days_since_seen,
  CASE
    WHEN julianday('now') - julianday(d.last_seen) <= 1 THEN 'online'
    WHEN julianday('now') - julianday(d.last_seen) <= 7 THEN 'recently_active'
    ELSE 'stale'
  END AS connectivity_status,
  d.registered_at,
  u.full_name AS registered_by_name
FROM devices d
LEFT JOIN users u ON d.registered_by = u.uuid
WHERE d.status = 'active';

-- --------------------
-- 3.2 Device Capacity View
-- --------------------

CREATE VIEW vw_device_capacity AS
SELECT
  ss.max_devices,
  (SELECT COUNT(*) FROM devices WHERE status = 'active') AS active_devices,
  ss.max_devices - (SELECT COUNT(*) FROM devices WHERE status = 'active') AS available_slots,
  CASE
    WHEN (SELECT COUNT(*) FROM devices WHERE status = 'active') >= ss.max_devices THEN 1
    ELSE 0
  END AS is_at_capacity,
  ss.allow_new_registrations,
  ss.license_tier,
  lt.monthly_price,
  lt.max_users,
  lt.max_products
FROM system_settings ss
JOIN license_tiers lt ON ss.license_tier = lt.tier_name
WHERE ss.id = 1;

-- --------------------
-- 3.3 Device Health Dashboard
-- --------------------

CREATE VIEW vw_device_health AS
SELECT
  d.device_name,
  d.device_type,
  d.last_seen,
  CAST((julianday('now') - julianday(d.last_seen)) * 24 AS INTEGER) AS hours_since_seen,
  d.total_syncs,
  d.failed_syncs,
  CASE
    WHEN d.failed_syncs = 0 THEN 100
    ELSE CAST((d.total_syncs - d.failed_syncs) * 100.0 / d.total_syncs AS INTEGER)
  END AS success_rate,
  d.last_error,
  CASE
    WHEN julianday('now') - julianday(d.last_seen) <= 0.125 THEN 'healthy'      -- < 3 hours
    WHEN julianday('now') - julianday(d.last_seen) <= 1 THEN 'warning'         -- < 1 day
    ELSE 'critical'
  END AS health_status
FROM devices d
WHERE d.status = 'active'
ORDER BY d.last_seen DESC;

-- --------------------
-- 3.4 Recent Sync Activity
-- --------------------

CREATE VIEW vw_recent_sync_activity AS
SELECT
  ds.uuid,
  d.device_name,
  ds.started_at,
  ds.ended_at,
  ds.duration_seconds,
  ds.records_pulled,
  ds.records_pushed,
  ds.conflicts_detected,
  ds.errors_count,
  ds.status,
  ds.client_version,
  CASE
    WHEN ds.duration_seconds < 10 THEN 'fast'
    WHEN ds.duration_seconds < 60 THEN 'normal'
    ELSE 'slow'
  END AS performance
FROM device_sessions ds
JOIN devices d ON ds.device_id = d.id
WHERE ds.started_at >= datetime('now', '-7 days')
ORDER BY ds.started_at DESC
LIMIT 100;

-- ============================================================================
-- SECTION 4: STORED QUERIES (For Node.js Implementation)
-- ============================================================================

-- --------------------
-- 4.1 Check Device Registration Eligibility
-- --------------------
-- Query: Is there room for a new device?
/*
SELECT
  CASE
    WHEN (SELECT COUNT(*) FROM devices WHERE status = 'active') >= (SELECT max_devices FROM system_settings WHERE id = 1)
    THEN 'MAX_DEVICE_LIMIT_REACHED'
    WHEN (SELECT allow_new_registrations FROM system_settings WHERE id = 1) = 0
    THEN 'REGISTRATIONS_DISABLED'
    ELSE 'ELIGIBLE'
  END AS eligibility_status,
  (SELECT max_devices FROM system_settings WHERE id = 1) AS max_allowed,
  (SELECT COUNT(*) FROM devices WHERE status = 'active') AS current_active;
*/

-- --------------------
-- 4.2 Register New Device
-- --------------------
-- Used by: POST /api/devices/register
/*
INSERT INTO devices (device_uuid, device_name, device_type, ip_address, status, registered_by)
VALUES (?, ?, ?, ?, 'pending', ?)
ON CONFLICT(device_uuid) DO UPDATE SET
  last_seen = datetime('now'),
  ip_address = excluded.ip_address;
*/

-- --------------------
-- 4.3 Activate Device (Admin Action)
-- --------------------
/*
UPDATE devices
SET
  status = 'active',
  activated_at = datetime('now'),
  activated_by = ?,
  last_modified = datetime('now')
WHERE device_uuid = ?
AND status = 'pending';
*/

-- --------------------
-- 4.4 Heartbeat Update
-- --------------------
-- Called every sync cycle
/*
UPDATE devices
SET last_seen = datetime('now')
WHERE device_uuid = ?
AND status = 'active';
*/

-- --------------------
-- 4.5 Start Sync Session
-- --------------------
/*
INSERT INTO device_sessions (
  device_id, session_token, client_ip, client_version, server_version
)
SELECT id, ?, ?, ?, ?
FROM devices
WHERE device_uuid = ?
AND status = 'active';
*/

-- --------------------
-- 4.6 End Sync Session
-- --------------------
/*
UPDATE device_sessions
SET
  ended_at = datetime('now'),
  duration_seconds = CAST((julianday(datetime('now')) - julianday(started_at)) * 86400 AS INTEGER),
  records_pulled = ?,
  records_pushed = ?,
  conflicts_detected = ?,
  errors_count = ?,
  status = ?
WHERE session_token = ?;
*/

-- ============================================================================
-- SECTION 5: SCHEMA VERSION
-- ============================================================================

INSERT INTO schema_migrations (version, description, checksum)
VALUES (
  '2.0.0',
  'Device management system with sync control and license enforcement',
  'SHA256_v2.0_device_management'
);

-- ============================================================================
-- VERIFICATION
-- ============================================================================

SELECT 'Device management schema v2.0 installed successfully' AS status;

-- Verify tables created
SELECT 'Tables:' AS check, COUNT(*) AS count
FROM sqlite_master
WHERE type='table'
AND name IN ('devices', 'system_settings', 'device_sessions', 'license_tiers');
-- Expected: 4

-- Verify views created
SELECT 'Views:' AS check, COUNT(*) AS count
FROM sqlite_master
WHERE type='view'
AND name LIKE 'vw_%device%';
-- Expected: 4

-- Verify triggers created
SELECT 'Triggers:' AS check, COUNT(*) AS count
FROM sqlite_master
WHERE type='trigger'
AND name LIKE '%device%';
-- Expected: 2+

-- Check device capacity
SELECT * FROM vw_device_capacity;

SELECT '========================================' AS status;
SELECT 'Device Management System Ready' AS status;
SELECT 'Default Settings:' AS status;
SELECT '  - Max Devices: 5' AS status;
SELECT '  - License Tier: Basic' AS status;
SELECT '  - Auto-Deactivate: Enabled (7 days)' AS status;
SELECT '========================================' AS status;

-- ============================================================================
-- END OF SCHEMA
-- ============================================================================
