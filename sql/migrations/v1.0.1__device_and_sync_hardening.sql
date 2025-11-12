-- ============================================================================
-- HIMS DATABASE MIGRATION v1.0.1 - Device Management & Sync Hardening
-- ============================================================================
-- Description: Adds device registration, limits, and enhanced sync controls
-- Version: 1.0.1
-- Prerequisites: v1.0.0 schema must be applied
-- Target Release: Q1 2026
-- ============================================================================

PRAGMA foreign_keys = OFF;

BEGIN IMMEDIATE TRANSACTION;

-- ============================================================================
-- SECTION 1: BACKUP VERIFICATION
-- ============================================================================
-- CRITICAL: Before running this migration, backup your database!
-- Command: cp hims.db hims.db.backup_$(date +%Y%m%d_%H%M%S)
-- ============================================================================

-- ============================================================================
-- SECTION 2: DEVICE REGISTRATION TABLE
-- ============================================================================

CREATE TABLE IF NOT EXISTS device_registrations (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  uuid TEXT NOT NULL UNIQUE,
  device_name TEXT NOT NULL,
  device_type TEXT CHECK (device_type IN ('desktop', 'tablet', 'mobile', 'server')),
  os_info TEXT, -- OS version, platform info
  app_version TEXT, -- HIMS client version
  last_heartbeat TEXT NOT NULL DEFAULT (datetime('now')),
  registered_at TEXT NOT NULL DEFAULT (datetime('now')),
  registered_by TEXT NOT NULL,
  is_active INTEGER NOT NULL DEFAULT 1 CHECK (is_active IN (0, 1)),
  deactivated_at TEXT,
  deactivated_by TEXT,
  deactivation_reason TEXT,
  metadata TEXT, -- JSON for additional device info
  FOREIGN KEY (registered_by) REFERENCES users(uuid) ON DELETE RESTRICT,
  FOREIGN KEY (deactivated_by) REFERENCES users(uuid) ON DELETE SET NULL
);

CREATE INDEX IF NOT EXISTS idx_device_registrations_uuid ON device_registrations(uuid);
CREATE INDEX IF NOT EXISTS idx_device_registrations_active ON device_registrations(is_active) WHERE is_active = 1;
CREATE INDEX IF NOT EXISTS idx_device_registrations_heartbeat ON device_registrations(last_heartbeat);

-- ============================================================================
-- SECTION 3: DEVICE LIMIT ENFORCEMENT TRIGGER (LOCAL POLICY)
-- ============================================================================
-- NOTE: This is a LOCAL guard. The Node.js server MUST be the authoritative
-- enforcement point for device limits across the LAN.
-- Default MAX_DEVICES = 5
-- ============================================================================

CREATE TRIGGER IF NOT EXISTS trg_before_device_register
BEFORE INSERT ON device_registrations
BEGIN
  SELECT CASE
    WHEN (SELECT COUNT(*) FROM device_registrations WHERE is_active = 1) >= 5
    THEN RAISE(ABORT, 'Maximum device limit reached (5). Please contact administrator to deactivate inactive devices.')
  END;
END;

-- ============================================================================
-- SECTION 4: DEVICE SYNC SESSIONS
-- ============================================================================
-- Tracks individual sync sessions for monitoring and debugging

CREATE TABLE IF NOT EXISTS device_sync_sessions (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  uuid TEXT NOT NULL UNIQUE,
  device_uuid TEXT NOT NULL,
  sync_type TEXT NOT NULL CHECK (sync_type IN ('push', 'pull', 'full')),
  started_at TEXT NOT NULL DEFAULT (datetime('now')),
  completed_at TEXT,
  status TEXT NOT NULL DEFAULT 'in_progress' CHECK (status IN ('in_progress', 'completed', 'failed', 'partial')),
  records_pushed INTEGER DEFAULT 0,
  records_pulled INTEGER DEFAULT 0,
  conflicts_detected INTEGER DEFAULT 0,
  errors_count INTEGER DEFAULT 0,
  error_details TEXT, -- JSON
  duration_ms INTEGER,
  FOREIGN KEY (device_uuid) REFERENCES device_registrations(uuid) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_device_sync_sessions_device ON device_sync_sessions(device_uuid);
CREATE INDEX IF NOT EXISTS idx_device_sync_sessions_started ON device_sync_sessions(started_at);
CREATE INDEX IF NOT EXISTS idx_device_sync_sessions_status ON device_sync_sessions(status);

-- ============================================================================
-- SECTION 5: ENHANCED SYNC QUEUE
-- ============================================================================
-- Add device_uuid tracking to sync_queue

ALTER TABLE sync_queue ADD COLUMN device_uuid TEXT;
CREATE INDEX IF NOT EXISTS idx_sync_queue_device ON sync_queue(device_uuid);

-- Add priority field for critical syncs
ALTER TABLE sync_queue ADD COLUMN priority INTEGER DEFAULT 5 CHECK (priority BETWEEN 1 AND 10);
CREATE INDEX IF NOT EXISTS idx_sync_queue_priority ON sync_queue(priority DESC, created_at ASC) WHERE synced = 0;

-- ============================================================================
-- SECTION 6: ENHANCED CONFLICT LOGS
-- ============================================================================
-- Add device tracking to conflicts

ALTER TABLE conflict_logs ADD COLUMN local_device_uuid TEXT;
ALTER TABLE conflict_logs ADD COLUMN remote_device_uuid TEXT;
CREATE INDEX IF NOT EXISTS idx_conflict_logs_local_device ON conflict_logs(local_device_uuid);
CREATE INDEX IF NOT EXISTS idx_conflict_logs_remote_device ON conflict_logs(remote_device_uuid);

-- ============================================================================
-- SECTION 7: SYNC STATISTICS VIEW
-- ============================================================================

CREATE VIEW IF NOT EXISTS v_device_sync_stats AS
SELECT
  dr.uuid AS device_uuid,
  dr.device_name,
  dr.is_active,
  dr.last_heartbeat,
  COUNT(DISTINCT dss.id) AS total_sync_sessions,
  SUM(CASE WHEN dss.status = 'completed' THEN 1 ELSE 0 END) AS successful_syncs,
  SUM(CASE WHEN dss.status = 'failed' THEN 1 ELSE 0 END) AS failed_syncs,
  SUM(COALESCE(dss.records_pushed, 0)) AS total_records_pushed,
  SUM(COALESCE(dss.records_pulled, 0)) AS total_records_pulled,
  SUM(COALESCE(dss.conflicts_detected, 0)) AS total_conflicts,
  MAX(dss.started_at) AS last_sync_time,
  AVG(dss.duration_ms) AS avg_sync_duration_ms
FROM device_registrations dr
LEFT JOIN device_sync_sessions dss ON dss.device_uuid = dr.uuid
GROUP BY dr.uuid, dr.device_name, dr.is_active, dr.last_heartbeat;

-- ============================================================================
-- SECTION 8: ACTIVE DEVICES VIEW
-- ============================================================================

CREATE VIEW IF NOT EXISTS v_active_devices AS
SELECT
  dr.uuid,
  dr.device_name,
  dr.device_type,
  dr.registered_at,
  dr.registered_by,
  dr.last_heartbeat,
  u.full_name AS registered_by_name,
  CAST((julianday('now') - julianday(dr.last_heartbeat)) * 24 * 60 AS INTEGER) AS minutes_since_heartbeat,
  CASE
    WHEN (julianday('now') - julianday(dr.last_heartbeat)) * 24 < 1 THEN 'online'
    WHEN (julianday('now') - julianday(dr.last_heartbeat)) * 24 < 24 THEN 'idle'
    ELSE 'stale'
  END AS device_status
FROM device_registrations dr
LEFT JOIN users u ON u.uuid = dr.registered_by
WHERE dr.is_active = 1
ORDER BY dr.last_heartbeat DESC;

-- ============================================================================
-- SECTION 9: UNRESOLVED CONFLICTS VIEW
-- ============================================================================

CREATE VIEW IF NOT EXISTS v_unresolved_conflicts AS
SELECT
  cl.id,
  cl.table_name,
  cl.record_uuid,
  cl.local_last_modified,
  cl.remote_last_modified,
  cl.created_at,
  ld.device_name AS local_device,
  rd.device_name AS remote_device,
  CAST((julianday('now') - julianday(cl.created_at)) * 24 AS INTEGER) AS hours_pending
FROM conflict_logs cl
LEFT JOIN device_registrations ld ON ld.uuid = cl.local_device_uuid
LEFT JOIN device_registrations rd ON rd.uuid = cl.remote_device_uuid
WHERE cl.resolved = 0
ORDER BY cl.created_at ASC;

-- ============================================================================
-- SECTION 10: STALE DEVICE AUTO-DEACTIVATION TRIGGER
-- ============================================================================
-- Automatically mark devices as inactive if no heartbeat for 30 days
-- This is a safety measure; server should handle this proactively

CREATE TRIGGER IF NOT EXISTS trg_mark_stale_devices
AFTER INSERT ON device_registrations
BEGIN
  UPDATE device_registrations
  SET
    is_active = 0,
    deactivated_at = datetime('now'),
    deactivation_reason = 'Auto-deactivated: No heartbeat for 30+ days'
  WHERE is_active = 1
  AND (julianday('now') - julianday(last_heartbeat)) > 30
  AND deactivated_at IS NULL;
END;

-- ============================================================================
-- SECTION 11: MIGRATION METADATA
-- ============================================================================

INSERT INTO schema_migrations (version, description, checksum, applied_by)
VALUES (
  '1.0.1',
  'Device management and sync hardening',
  'DEVICE_MGMT_v1.0.1',
  'system'
);

-- ============================================================================
-- SECTION 12: VERIFICATION QUERIES
-- ============================================================================

-- Check that device_registrations table exists
SELECT CASE
  WHEN NOT EXISTS (SELECT 1 FROM sqlite_master WHERE type='table' AND name='device_registrations')
  THEN RAISE(ABORT, 'Migration verification failed: device_registrations table not created')
END;

-- Check that device limit trigger exists
SELECT CASE
  WHEN NOT EXISTS (SELECT 1 FROM sqlite_master WHERE type='trigger' AND name='trg_before_device_register')
  THEN RAISE(ABORT, 'Migration verification failed: device limit trigger not created')
END;

-- Check views created
SELECT CASE
  WHEN NOT EXISTS (SELECT 1 FROM sqlite_master WHERE type='view' AND name='v_device_sync_stats')
  THEN RAISE(ABORT, 'Migration verification failed: v_device_sync_stats view not created')
END;

COMMIT;

-- ============================================================================
-- SECTION 13: POST-MIGRATION VERIFICATION
-- ============================================================================
-- Run these commands after migration completes:
--
-- sqlite3 hims.db "PRAGMA foreign_key_check;"
-- sqlite3 hims.db "PRAGMA integrity_check;"
-- sqlite3 hims.db "SELECT COUNT(*) FROM device_registrations;"
-- sqlite3 hims.db "SELECT * FROM schema_migrations WHERE version='1.0.1';"
-- sqlite3 hims.db "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='device_registrations';"
--
-- Expected results:
-- - foreign_key_check: empty (no errors)
-- - integrity_check: ok
-- - device_registrations count: 0 (empty initially)
-- - schema_migrations: 1 row with version 1.0.1
-- - device_registrations table: 1 (exists)
-- ============================================================================

PRAGMA foreign_keys = ON;

-- ============================================================================
-- END OF MIGRATION
-- ============================================================================
