-- ============================================================================
-- HIMS DATABASE MIGRATION: v1.0.0 → v1.0.1 (Production Hardening) - CORRECTED
-- ============================================================================
-- Purpose: Apply critical production fixes for trigger safety, data integrity,
--          and JSON validation
-- Date: 2025-11-12
-- Version: 2 (CORRECTED - fixes timestamp trigger syntax and safety issues)
-- IMPORTANT: Backup your database before running this migration!
-- ============================================================================

-- ============================================================================
-- PRE-FLIGHT CHECKS
-- ============================================================================

-- Verify schema version before migration
SELECT 'Pre-migration check: Schema version' AS status,
  CASE
    WHEN EXISTS (SELECT 1 FROM schema_migrations WHERE version LIKE '1.0%')
    THEN 'OK - v1.0.x detected'
    ELSE 'ERROR - Unknown schema version'
  END AS result;

-- Check for critical tables
SELECT 'Pre-migration check: Core tables' AS status,
  CASE
    WHEN EXISTS (SELECT 1 FROM sqlite_master WHERE type='table' AND name='stock_levels')
    AND EXISTS (SELECT 1 FROM sqlite_master WHERE type='table' AND name='issues')
    AND EXISTS (SELECT 1 FROM sqlite_master WHERE type='table' AND name='stock_transfers')
    THEN 'OK - All core tables exist'
    ELSE 'ERROR - Missing core tables'
  END AS result;

PRAGMA foreign_keys = OFF; -- Temporarily disable for migration
BEGIN TRANSACTION;

-- ============================================================================
-- FIX 1: Drop and Recreate trg_after_issue_approved (CORRECTED)
-- ============================================================================
-- Problem: Uses SELECT instead of SUM() - fails with multiple items
-- Added: COALESCE for modified_by, NULL checks, safety conditions

DROP TRIGGER IF EXISTS trg_after_issue_approved;

CREATE TRIGGER trg_after_issue_approved
AFTER UPDATE OF status ON issues
WHEN NEW.status = 'issued'
  AND OLD.status != 'issued'
  AND NEW.from_location_id IS NOT NULL  -- Safety: Prevent NULL FK
  AND NEW.to_location_id IS NOT NULL
BEGIN
  -- Decrease stock from source location (FIXED: Now uses SUM + COALESCE)
  UPDATE stock_levels
  SET
    quantity = stock_levels.quantity - (
      SELECT COALESCE(SUM(ili.quantity), 0)
      FROM issue_line_items ili
      WHERE ili.issue_id = NEW.id AND ili.product_uuid = stock_levels.product_uuid
    ),
    last_updated = datetime('now'),
    updated_by = COALESCE(NEW.modified_by, 'system')  -- Safety: Handle NULL
  WHERE location_id = NEW.from_location_id
  AND product_uuid IN (SELECT product_uuid FROM issue_line_items WHERE issue_id = NEW.id);

  -- Increase stock at destination location (FIXED: Aggregates with GROUP BY)
  INSERT INTO stock_levels (product_uuid, location_id, quantity, unit_id, last_updated, updated_by)
  SELECT
    ili.product_uuid,
    NEW.to_location_id,
    SUM(ili.quantity),  -- FIXED: Aggregate multiple line items
    MAX(ili.unit_id),   -- Use MAX for unit_id (should be same per product)
    datetime('now'),
    COALESCE(NEW.modified_by, 'system')
  FROM issue_line_items ili
  WHERE ili.issue_id = NEW.id
  GROUP BY ili.product_uuid
  HAVING SUM(ili.quantity) > 0  -- Safety: Only insert if positive quantity
  ON CONFLICT(product_uuid, location_id) DO UPDATE SET
    quantity = stock_levels.quantity + excluded.quantity,
    last_updated = datetime('now'),
    updated_by = excluded.updated_by;

  -- Log stock adjustments for source location (FIXED: Uses SUM + GROUP BY)
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
    -SUM(ili.quantity),  -- FIXED: Aggregate
    (SELECT quantity FROM stock_levels WHERE product_uuid = ili.product_uuid AND location_id = NEW.from_location_id) + SUM(ili.quantity),
    (SELECT quantity FROM stock_levels WHERE product_uuid = ili.product_uuid AND location_id = NEW.from_location_id),
    MAX(ili.unit_id),
    'issue',
    NEW.id,
    datetime('now'),
    COALESCE(NEW.modified_by, 'system')
  FROM issue_line_items ili
  WHERE ili.issue_id = NEW.id
  GROUP BY ili.product_uuid
  HAVING SUM(ili.quantity) > 0;  -- Safety: Only log if quantity > 0

  -- Log stock adjustments for destination location (FIXED: Uses SUM + GROUP BY)
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
    SUM(ili.quantity),  -- FIXED: Aggregate
    COALESCE((SELECT quantity FROM stock_levels WHERE product_uuid = ili.product_uuid AND location_id = NEW.to_location_id), 0) - SUM(ili.quantity),
    COALESCE((SELECT quantity FROM stock_levels WHERE product_uuid = ili.product_uuid AND location_id = NEW.to_location_id), 0),
    MAX(ili.unit_id),
    'issue',
    NEW.id,
    datetime('now'),
    COALESCE(NEW.modified_by, 'system')
  FROM issue_line_items ili
  WHERE ili.issue_id = NEW.id
  GROUP BY ili.product_uuid
  HAVING SUM(ili.quantity) > 0;  -- Safety: Only log if quantity > 0
END;

-- ============================================================================
-- FIX 2: Add Missing Stock Transfer Validation Trigger (CORRECTED)
-- ============================================================================
-- Added: LIMIT 1 for performance optimization

DROP TRIGGER IF EXISTS trg_before_transfer_check_stock;

CREATE TRIGGER trg_before_transfer_check_stock
BEFORE UPDATE OF status ON stock_transfers
WHEN NEW.status = 'completed'
  AND OLD.status != 'completed'
  AND NEW.from_location_id IS NOT NULL  -- Safety: Prevent NULL FK
BEGIN
  SELECT CASE
    WHEN EXISTS (
      SELECT 1
      FROM stock_transfer_items sti
      LEFT JOIN stock_levels sl
        ON sti.product_uuid = sl.product_uuid AND sl.location_id = NEW.from_location_id
      WHERE sti.transfer_id = NEW.id
      AND (sl.quantity IS NULL OR sl.quantity < sti.quantity)
      LIMIT 1  -- Performance: Stop at first violation
    )
    THEN RAISE(ABORT, 'Insufficient stock for transfer')
  END;
END;

-- ============================================================================
-- FIX 3: Fix Stock Transfer Trigger to Use SUM() (CORRECTED)
-- ============================================================================
-- Added: COALESCE, NULL checks, HAVING clauses

DROP TRIGGER IF EXISTS trg_after_transfer_completed;

CREATE TRIGGER trg_after_transfer_completed
AFTER UPDATE OF status ON stock_transfers
WHEN NEW.status = 'completed'
  AND OLD.status != 'completed'
  AND NEW.from_location_id IS NOT NULL
  AND NEW.to_location_id IS NOT NULL
BEGIN
  -- Decrease stock from source (FIXED: Uses SUM + COALESCE)
  UPDATE stock_levels
  SET
    quantity = stock_levels.quantity - (
      SELECT COALESCE(SUM(sti.quantity), 0)
      FROM stock_transfer_items sti
      WHERE sti.transfer_id = NEW.id AND sti.product_uuid = stock_levels.product_uuid
    ),
    last_updated = datetime('now'),
    updated_by = COALESCE(NEW.modified_by, 'system')
  WHERE location_id = NEW.from_location_id
  AND product_uuid IN (SELECT product_uuid FROM stock_transfer_items WHERE transfer_id = NEW.id);

  -- Increase stock at destination (FIXED: Aggregates with GROUP BY + HAVING)
  INSERT INTO stock_levels (product_uuid, location_id, quantity, unit_id, last_updated, updated_by)
  SELECT
    sti.product_uuid,
    NEW.to_location_id,
    SUM(sti.quantity),  -- FIXED: Aggregate
    MAX(sti.unit_id),
    datetime('now'),
    COALESCE(NEW.modified_by, 'system')
  FROM stock_transfer_items sti
  WHERE sti.transfer_id = NEW.id
  GROUP BY sti.product_uuid
  HAVING SUM(sti.quantity) > 0  -- Safety: Only positive quantities
  ON CONFLICT(product_uuid, location_id) DO UPDATE SET
    quantity = stock_levels.quantity + excluded.quantity,
    last_updated = datetime('now'),
    updated_by = excluded.updated_by;

  -- Log adjustments for source location (FIXED: Uses SUM + GROUP BY + HAVING)
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
    -SUM(sti.quantity),  -- FIXED: Aggregate
    (SELECT quantity FROM stock_levels WHERE product_uuid = sti.product_uuid AND location_id = NEW.from_location_id) + SUM(sti.quantity),
    (SELECT quantity FROM stock_levels WHERE product_uuid = sti.product_uuid AND location_id = NEW.from_location_id),
    MAX(sti.unit_id),
    'transfer',
    NEW.id,
    datetime('now'),
    COALESCE(NEW.modified_by, 'system')
  FROM stock_transfer_items sti
  WHERE sti.transfer_id = NEW.id
  GROUP BY sti.product_uuid
  HAVING SUM(sti.quantity) > 0;  -- Safety: Only log positive changes

  -- Log adjustments for destination location (FIXED: Uses SUM + GROUP BY + HAVING)
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
    SUM(sti.quantity),  -- FIXED: Aggregate
    COALESCE((SELECT quantity FROM stock_levels WHERE product_uuid = sti.product_uuid AND location_id = NEW.to_location_id), 0) - SUM(sti.quantity),
    COALESCE((SELECT quantity FROM stock_levels WHERE product_uuid = sti.product_uuid AND location_id = NEW.to_location_id), 0),
    MAX(sti.unit_id),
    'transfer',
    NEW.id,
    datetime('now'),
    COALESCE(NEW.modified_by, 'system')
  FROM stock_transfer_items sti
  WHERE sti.transfer_id = NEW.id
  GROUP BY sti.product_uuid
  HAVING SUM(sti.quantity) > 0;  -- Safety: Only log positive changes
END;

-- ============================================================================
-- FIX 4: Add NULL Safety to Stock Alert Trigger (CORRECTED)
-- ============================================================================
-- Added: Check for negative quantities, improved EXISTS check

DROP TRIGGER IF EXISTS trg_after_stock_update_check_reorder;

CREATE TRIGGER trg_after_stock_update_check_reorder
AFTER UPDATE OF quantity ON stock_levels
WHEN NEW.quantity IS NOT NULL  -- FIXED: Prevent null crashes
  AND NEW.quantity >= 0  -- FIXED: Ignore negative quantities (data error)
BEGIN
  -- Insert reorder alert if below threshold
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
    LIMIT 1  -- Performance: Stop at first match
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
-- FIX 5: REMOVE Problematic Timestamp Triggers
-- ============================================================================
-- CRITICAL: SQLite doesn't support SELECT...INTO or SET in triggers
-- Attempting UPDATE inside BEFORE UPDATE trigger causes infinite recursion
-- SOLUTION: Application layer (Flutter/Node.js) MUST handle last_modified updates
--
-- IMPORTANT: Update your application code to set last_modified on every UPDATE

DROP TRIGGER IF EXISTS trg_products_update_timestamp;
DROP TRIGGER IF EXISTS trg_purchases_update_timestamp;
DROP TRIGGER IF EXISTS trg_issues_update_timestamp;

-- Document the removal
SELECT 'WARNING: Timestamp triggers removed' AS notice,
  'Application layer must set last_modified on UPDATE operations' AS action_required;

-- ============================================================================
-- FIX 6: Add System User for Referential Integrity (CORRECTED)
-- ============================================================================
-- Uses EXISTS check to prevent duplicate key errors

INSERT INTO users (uuid, username, password_hash, full_name, is_active, created_by)
SELECT 'system-user-000', 'system', 'N/A', 'System Account', 1, 'system'
WHERE NOT EXISTS (SELECT 1 FROM users WHERE username='system' LIMIT 1);

-- ============================================================================
-- FIX 7: Update Schema Version (CORRECTED)
-- ============================================================================
-- Don't UPDATE v1.0.0 - INSERT new record to preserve history

INSERT INTO schema_migrations (version, description, checksum)
VALUES (
  '1.0.1',
  'Production hardening: trigger fixes, validation, safety improvements',
  'SHA256_v1.0.1_corrected'
);

-- ============================================================================
-- FIX 8: Optional JSON Cleanup (Run if invalid data exists)
-- ============================================================================
-- WARNING: Only run if you're certain these records are duplicates/corrupted

-- Uncomment to clean invalid JSON (USE WITH CAUTION):
-- DELETE FROM sync_queue WHERE NOT json_valid(payload) AND synced = 1;
-- DELETE FROM conflict_logs WHERE (NOT json_valid(local_data) OR NOT json_valid(remote_data)) AND resolved = 1;

SELECT 'JSON Cleanup: Skipped (uncomment if needed)' AS status;

-- ============================================================================
-- COMMIT MIGRATION
-- ============================================================================

COMMIT;
PRAGMA foreign_keys = ON;

-- ============================================================================
-- POST-MIGRATION VERIFICATION (After COMMIT)
-- ============================================================================

SELECT '========================================' AS status;
SELECT '   POST-MIGRATION VERIFICATION' AS status;
SELECT '========================================' AS status;

-- Verify all triggers recreated successfully
SELECT 'Triggers created:' AS check,
  COUNT(*) AS count,
  'Expected: 15+' AS expected
FROM sqlite_master
WHERE type = 'trigger';

SELECT 'Critical triggers:' AS check,
  GROUP_CONCAT(name, ', ') AS triggers
FROM sqlite_master
WHERE type = 'trigger'
AND name IN (
  'trg_before_issue_check_stock',
  'trg_after_issue_approved',
  'trg_before_transfer_check_stock',
  'trg_after_transfer_completed',
  'trg_after_stock_update_check_reorder'
);

-- Verify system user exists
SELECT 'System user:' AS check,
  CASE WHEN COUNT(*) > 0 THEN 'EXISTS' ELSE 'MISSING' END AS status
FROM users
WHERE username = 'system';

-- Check for invalid JSON in sync_queue
SELECT 'Invalid JSON (sync_queue):' AS check,
  COUNT(*) AS count
FROM sync_queue
WHERE NOT json_valid(payload);

-- Check for invalid JSON in conflict_logs
SELECT 'Invalid JSON (conflict_logs):' AS check,
  COUNT(*) AS count
FROM conflict_logs
WHERE NOT json_valid(local_data) OR NOT json_valid(remote_data);

-- Verify schema version
SELECT 'Schema version:' AS check,
  version || ' - ' || description AS current_version
FROM schema_migrations
ORDER BY applied_at DESC
LIMIT 1;

-- Final integrity checks
PRAGMA integrity_check;

SELECT '========================================' AS status;
SELECT CASE
  WHEN (SELECT integrity_check FROM pragma_integrity_check) = 'ok'
  THEN '✅ Migration v1.0.0 → v1.0.1 completed successfully'
  ELSE '❌ Migration completed with warnings - run PRAGMA integrity_check'
END AS final_status;
SELECT '========================================' AS status;

-- ============================================================================
-- IMPORTANT NOTES FOR APPLICATION DEVELOPERS
-- ============================================================================

SELECT '' AS notice;
SELECT '⚠️  ACTION REQUIRED: Update application code' AS notice;
SELECT '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━' AS notice;
SELECT 'Timestamp triggers removed due to SQLite limitations.' AS notice;
SELECT '' AS notice;
SELECT 'Your application MUST now set last_modified on every UPDATE:' AS notice;
SELECT '' AS notice;
SELECT '  Python (SQLite3):' AS notice;
SELECT '    cursor.execute("UPDATE products SET ..., last_modified=datetime(''now'') WHERE ...")' AS notice;
SELECT '' AS notice;
SELECT '  Node.js (better-sqlite3):' AS notice;
SELECT '    db.prepare("UPDATE products SET ..., last_modified=datetime(''now'') WHERE ...").run()' AS notice;
SELECT '' AS notice;
SELECT '  Flutter (Drift):' AS notice;
SELECT '    await db.update(products).write(ProductsCompanion(' AS notice;
SELECT '      lastModified: Value(DateTime.now()),' AS notice;
SELECT '    ))' AS notice;
SELECT '' AS notice;
SELECT 'Failure to do this will break LAN sync functionality.' AS notice;
SELECT '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━' AS notice;

-- ============================================================================
-- END OF MIGRATION
-- ============================================================================
