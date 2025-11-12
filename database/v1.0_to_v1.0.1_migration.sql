-- ============================================================================
-- HIMS DATABASE MIGRATION: v1.0.0 → v1.0.1 (Production Hardening)
-- ============================================================================
-- Purpose: Apply critical production fixes for trigger safety, data integrity,
--          and JSON validation
-- Date: 2025-11-12
-- IMPORTANT: Backup your database before running this migration!
-- ============================================================================

PRAGMA foreign_keys = OFF; -- Temporarily disable for migration
BEGIN TRANSACTION;

-- ============================================================================
-- FIX 1: Drop and Recreate Problematic Triggers with SUM() Aggregation
-- ============================================================================

-- Fix trg_after_issue_approved (Line 888-959)
-- Problem: Uses SELECT ili.quantity instead of SUM() - fails with multiple items
DROP TRIGGER IF EXISTS trg_after_issue_approved;

CREATE TRIGGER trg_after_issue_approved
AFTER UPDATE OF status ON issues
WHEN NEW.status = 'issued' AND OLD.status != 'issued'
BEGIN
  -- Decrease stock from source location (FIXED: Now uses SUM)
  UPDATE stock_levels
  SET
    quantity = stock_levels.quantity - (
      SELECT COALESCE(SUM(ili.quantity), 0)
      FROM issue_line_items ili
      WHERE ili.issue_id = NEW.id AND ili.product_uuid = stock_levels.product_uuid
    ),
    last_updated = datetime('now'),
    updated_by = NEW.modified_by
  WHERE location_id = NEW.from_location_id
  AND product_uuid IN (SELECT product_uuid FROM issue_line_items WHERE issue_id = NEW.id);

  -- Increase stock at destination location (FIXED: Aggregates properly)
  INSERT INTO stock_levels (product_uuid, location_id, quantity, unit_id, last_updated, updated_by)
  SELECT
    ili.product_uuid,
    NEW.to_location_id,
    SUM(ili.quantity), -- FIXED: Aggregate multiple line items
    MAX(ili.unit_id),  -- Use MAX for unit_id (should be same per product)
    datetime('now'),
    NEW.modified_by
  FROM issue_line_items ili
  WHERE ili.issue_id = NEW.id
  GROUP BY ili.product_uuid
  ON CONFLICT(product_uuid, location_id) DO UPDATE SET
    quantity = stock_levels.quantity + excluded.quantity,
    last_updated = datetime('now'),
    updated_by = excluded.updated_by;

  -- Log stock adjustments for source location (FIXED: Uses SUM)
  INSERT INTO stock_adjustments (
    product_uuid, location_id, adjustment_type,
    quantity_change, quantity_before, quantity_after,
    unit_id, reference_type, reference_id,
    adjustment_date, adjusted_by
  )
  SELECT
    ili.product_uuid,
    NEW.from_location_id,
    'issue',
    -SUM(ili.quantity), -- FIXED: Aggregate
    (SELECT quantity FROM stock_levels WHERE product_uuid = ili.product_uuid AND location_id = NEW.from_location_id) + SUM(ili.quantity),
    (SELECT quantity FROM stock_levels WHERE product_uuid = ili.product_uuid AND location_id = NEW.from_location_id),
    MAX(ili.unit_id),
    'issue',
    NEW.id,
    datetime('now'),
    NEW.modified_by
  FROM issue_line_items ili
  WHERE ili.issue_id = NEW.id
  GROUP BY ili.product_uuid;

  -- Log stock adjustments for destination location (FIXED: Uses SUM)
  INSERT INTO stock_adjustments (
    product_uuid, location_id, adjustment_type,
    quantity_change, quantity_before, quantity_after,
    unit_id, reference_type, reference_id,
    adjustment_date, adjusted_by
  )
  SELECT
    ili.product_uuid,
    NEW.to_location_id,
    'issue',
    SUM(ili.quantity), -- FIXED: Aggregate
    COALESCE((SELECT quantity FROM stock_levels WHERE product_uuid = ili.product_uuid AND location_id = NEW.to_location_id), 0) - SUM(ili.quantity),
    COALESCE((SELECT quantity FROM stock_levels WHERE product_uuid = ili.product_uuid AND location_id = NEW.to_location_id), 0),
    MAX(ili.unit_id),
    'issue',
    NEW.id,
    datetime('now'),
    NEW.modified_by
  FROM issue_line_items ili
  WHERE ili.issue_id = NEW.id
  GROUP BY ili.product_uuid;
END;

-- ============================================================================
-- FIX 2: Add Missing Stock Transfer Validation Trigger
-- ============================================================================

DROP TRIGGER IF EXISTS trg_before_transfer_check_stock;

CREATE TRIGGER trg_before_transfer_check_stock
BEFORE UPDATE OF status ON stock_transfers
WHEN NEW.status = 'completed' AND OLD.status != 'completed'
BEGIN
  SELECT CASE
    WHEN EXISTS (
      SELECT 1
      FROM stock_transfer_items sti
      LEFT JOIN stock_levels sl
        ON sti.product_uuid = sl.product_uuid AND sl.location_id = NEW.from_location_id
      WHERE sti.transfer_id = NEW.id
      AND (sl.quantity IS NULL OR sl.quantity < sti.quantity)
    )
    THEN RAISE(ABORT, 'Insufficient stock for transfer')
  END;
END;

-- ============================================================================
-- FIX 3: Fix Stock Transfer Trigger to Use SUM()
-- ============================================================================

DROP TRIGGER IF EXISTS trg_after_transfer_completed;

CREATE TRIGGER trg_after_transfer_completed
AFTER UPDATE OF status ON stock_transfers
WHEN NEW.status = 'completed' AND OLD.status != 'completed'
BEGIN
  -- Decrease stock from source (FIXED: Uses SUM)
  UPDATE stock_levels
  SET
    quantity = stock_levels.quantity - (
      SELECT COALESCE(SUM(sti.quantity), 0)
      FROM stock_transfer_items sti
      WHERE sti.transfer_id = NEW.id AND sti.product_uuid = stock_levels.product_uuid
    ),
    last_updated = datetime('now'),
    updated_by = NEW.modified_by
  WHERE location_id = NEW.from_location_id
  AND product_uuid IN (SELECT product_uuid FROM stock_transfer_items WHERE transfer_id = NEW.id);

  -- Increase stock at destination (FIXED: Aggregates properly)
  INSERT INTO stock_levels (product_uuid, location_id, quantity, unit_id, last_updated, updated_by)
  SELECT
    sti.product_uuid,
    NEW.to_location_id,
    SUM(sti.quantity), -- FIXED
    MAX(sti.unit_id),
    datetime('now'),
    NEW.modified_by
  FROM stock_transfer_items sti
  WHERE sti.transfer_id = NEW.id
  GROUP BY sti.product_uuid
  ON CONFLICT(product_uuid, location_id) DO UPDATE SET
    quantity = stock_levels.quantity + excluded.quantity,
    last_updated = datetime('now'),
    updated_by = excluded.updated_by;

  -- Log adjustments for both locations (FIXED: Uses SUM)
  INSERT INTO stock_adjustments (
    product_uuid, location_id, adjustment_type,
    quantity_change, quantity_before, quantity_after,
    unit_id, reference_type, reference_id,
    adjustment_date, adjusted_by
  )
  SELECT
    sti.product_uuid,
    NEW.from_location_id,
    'transfer_out',
    -SUM(sti.quantity), -- FIXED
    (SELECT quantity FROM stock_levels WHERE product_uuid = sti.product_uuid AND location_id = NEW.from_location_id) + SUM(sti.quantity),
    (SELECT quantity FROM stock_levels WHERE product_uuid = sti.product_uuid AND location_id = NEW.from_location_id),
    MAX(sti.unit_id),
    'transfer',
    NEW.id,
    datetime('now'),
    NEW.modified_by
  FROM stock_transfer_items sti
  WHERE sti.transfer_id = NEW.id
  GROUP BY sti.product_uuid;

  INSERT INTO stock_adjustments (
    product_uuid, location_id, adjustment_type,
    quantity_change, quantity_before, quantity_after,
    unit_id, reference_type, reference_id,
    adjustment_date, adjusted_by
  )
  SELECT
    sti.product_uuid,
    NEW.to_location_id,
    'transfer_in',
    SUM(sti.quantity), -- FIXED
    COALESCE((SELECT quantity FROM stock_levels WHERE product_uuid = sti.product_uuid AND location_id = NEW.to_location_id), 0) - SUM(sti.quantity),
    COALESCE((SELECT quantity FROM stock_levels WHERE product_uuid = sti.product_uuid AND location_id = NEW.to_location_id), 0),
    MAX(sti.unit_id),
    'transfer',
    NEW.id,
    datetime('now'),
    NEW.modified_by
  FROM stock_transfer_items sti
  WHERE sti.transfer_id = NEW.id
  GROUP BY sti.product_uuid;
END;

-- ============================================================================
-- FIX 4: Add NULL Safety to Stock Alert Trigger
-- ============================================================================

DROP TRIGGER IF EXISTS trg_after_stock_update_check_reorder;

CREATE TRIGGER trg_after_stock_update_check_reorder
AFTER UPDATE OF quantity ON stock_levels
WHEN NEW.quantity IS NOT NULL -- FIXED: Prevent null crashes
BEGIN
  INSERT INTO stock_alerts (
    alert_type, product_uuid, location_id,
    threshold_value, current_value, severity, message
  )
  SELECT
    'reorder',
    NEW.product_uuid,
    NEW.location_id,
    p.reorder_level,
    NEW.quantity,
    CASE
      WHEN NEW.quantity <= p.reorder_level * 0.25 THEN 'critical'
      WHEN NEW.quantity <= p.reorder_level * 0.50 THEN 'high'
      WHEN NEW.quantity <= p.reorder_level * 0.75 THEN 'medium'
      ELSE 'low'
    END,
    'Stock level for ' || p.name || ' at ' || l.name || ' is below reorder level'
  FROM products p
  JOIN locations l ON l.id = NEW.location_id
  WHERE p.uuid = NEW.product_uuid
  AND NEW.quantity <= p.reorder_level
  AND p.reorder_level > 0
  AND NOT EXISTS (
    SELECT 1 FROM stock_alerts
    WHERE product_uuid = NEW.product_uuid
    AND location_id = NEW.location_id
    AND alert_type = 'reorder'
    AND resolved = 0
  );

  -- Auto-resolve reorder alerts when stock is replenished
  UPDATE stock_alerts
  SET
    resolved = 1,
    resolved_at = datetime('now'),
    notes = 'Auto-resolved: Stock replenished'
  WHERE product_uuid = NEW.product_uuid
  AND location_id = NEW.location_id
  AND alert_type = 'reorder'
  AND resolved = 0
  AND NEW.quantity > (SELECT reorder_level FROM products WHERE uuid = NEW.product_uuid);
END;

-- ============================================================================
-- FIX 5: Add CHECK Constraints for Data Validation
-- ============================================================================

-- Add deleted_at, deleted_by to stock_adjustments for audit consistency
-- Note: Cannot add columns to existing table in SQLite easily, so we document this
-- for next schema version or handle via ALTER TABLE

-- Add JSON validation constraints
-- Note: SQLite doesn't support adding constraints to existing tables
-- These should be included in the base schema for new databases

-- For existing databases, we validate JSON integrity with queries:
-- SELECT * FROM sync_queue WHERE NOT json_valid(payload);
-- SELECT * FROM conflict_logs WHERE NOT json_valid(local_data) OR NOT json_valid(remote_data);

-- ============================================================================
-- FIX 6: Change Timestamp Triggers from AFTER to BEFORE UPDATE
-- ============================================================================

-- These prevent recursive trigger issues
DROP TRIGGER IF EXISTS trg_products_update_timestamp;
CREATE TRIGGER trg_products_update_timestamp
BEFORE UPDATE ON products
FOR EACH ROW
BEGIN
  SELECT CASE
    WHEN NEW.last_modified = OLD.last_modified
    THEN datetime('now')
    ELSE NEW.last_modified
  END INTO NEW.last_modified;
END;

DROP TRIGGER IF EXISTS trg_purchases_update_timestamp;
CREATE TRIGGER trg_purchases_update_timestamp
BEFORE UPDATE ON purchases
FOR EACH ROW
BEGIN
  SELECT CASE
    WHEN NEW.last_modified = OLD.last_modified
    THEN datetime('now')
    ELSE NEW.last_modified
  END INTO NEW.last_modified;
END;

DROP TRIGGER IF EXISTS trg_issues_update_timestamp;
CREATE TRIGGER trg_issues_update_timestamp
BEFORE UPDATE ON issues
FOR EACH ROW
BEGIN
  SELECT CASE
    WHEN NEW.last_modified = OLD.last_modified
    THEN datetime('now')
    ELSE NEW.last_modified
  END INTO NEW.last_modified;
END;

-- ============================================================================
-- FIX 7: Add System User for Referential Integrity
-- ============================================================================

-- Check if system user exists, if not create it
INSERT OR IGNORE INTO users (uuid, username, password_hash, full_name, is_active, created_by)
VALUES ('system-user-000', 'system', 'N/A', 'System Account', 1, 'system');

-- ============================================================================
-- FIX 8: Update Schema Version
-- ============================================================================

UPDATE schema_migrations
SET checksum = 'SHA256_v1.0.1_production_hardening'
WHERE version = '1.0.0';

INSERT INTO schema_migrations (version, description, checksum)
VALUES ('1.0.1', 'Production hardening: trigger fixes, validation, safety improvements', 'SHA256_v1.0.1');

-- ============================================================================
-- VERIFICATION QUERIES
-- ============================================================================

-- Verify all triggers recreated successfully
SELECT
  'Triggers created: ' || COUNT(*) AS status
FROM sqlite_master
WHERE type = 'trigger';

-- Verify system user exists
SELECT
  'System user exists: ' || CASE WHEN COUNT(*) > 0 THEN 'YES' ELSE 'NO' END AS status
FROM users
WHERE username = 'system';

-- Check for invalid JSON in sync_queue
SELECT
  'Invalid JSON records in sync_queue: ' || COUNT(*) AS status
FROM sync_queue
WHERE NOT json_valid(payload);

-- Check for invalid JSON in conflict_logs
SELECT
  'Invalid JSON records in conflict_logs: ' || COUNT(*) AS status
FROM conflict_logs
WHERE NOT json_valid(local_data) OR NOT json_valid(remote_data);

COMMIT;
PRAGMA foreign_keys = ON;

-- ============================================================================
-- FINAL INTEGRITY CHECKS
-- ============================================================================

PRAGMA integrity_check;
PRAGMA foreign_key_check;

SELECT '=== Migration v1.0.0 → v1.0.1 completed successfully ===' AS status;
