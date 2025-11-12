-- ============================================================================
-- HIMS DATABASE TRIGGERS v1.0.0 - Stock Automation & Validation
-- ============================================================================
-- Description: Automated triggers for stock management and data integrity
-- Purpose: Auto-update stock levels, create adjustments, enforce constraints
-- Version: 1.0.0
-- IMPORTANT: Application MUST set last_modified. Triggers handle stock logic only.
-- ============================================================================

-- ============================================================================
-- SECTION 1: PURCHASE TRIGGERS
-- ============================================================================

-- Trigger: After purchase is marked as 'received', update stock levels
-- Uses SUM() aggregation to handle multiple items correctly
CREATE TRIGGER IF NOT EXISTS trg_after_purchase_received
AFTER UPDATE OF status ON purchases
WHEN NEW.status = 'received' AND OLD.status != 'received'
BEGIN
  -- Create stock adjustments and update stock_levels for each purchase item
  INSERT INTO stock_adjustments (
    uuid,
    product_uuid,
    location_uuid,
    adjustment_type,
    quantity_change,
    quantity_before,
    quantity_after,
    unit_id,
    conversion_factor,
    reference_type,
    reference_uuid,
    reason,
    created_by
  )
  SELECT
    'adj_' || hex(randomblob(16)),
    pi.product_uuid,
    NEW.location_uuid,
    'purchase',
    COALESCE(SUM(pi.quantity), 0), -- aggregate quantity per product
    COALESCE((SELECT quantity FROM stock_levels WHERE product_uuid = pi.product_uuid AND location_uuid = NEW.location_uuid), 0),
    COALESCE((SELECT quantity FROM stock_levels WHERE product_uuid = pi.product_uuid AND location_uuid = NEW.location_uuid), 0) + COALESCE(SUM(pi.quantity), 0),
    pi.unit_id,
    1.0,
    'purchase',
    NEW.uuid,
    'Purchase received: ' || NEW.purchase_number,
    NEW.approved_by
  FROM purchase_items pi
  WHERE pi.purchase_uuid = NEW.uuid
  GROUP BY pi.product_uuid, pi.unit_id;

  -- Update or insert stock_levels
  INSERT INTO stock_levels (product_uuid, location_uuid, quantity, last_modified)
  SELECT
    pi.product_uuid,
    NEW.location_uuid,
    COALESCE(SUM(pi.quantity), 0),
    datetime('now')
  FROM purchase_items pi
  WHERE pi.purchase_uuid = NEW.uuid
  GROUP BY pi.product_uuid
  ON CONFLICT(product_uuid, location_uuid) DO UPDATE SET
    quantity = quantity + excluded.quantity,
    last_modified = excluded.last_modified;
END;

-- ============================================================================
-- SECTION 2: ISSUE TRIGGERS
-- ============================================================================

-- Trigger: Before issue is marked as 'issued', check sufficient stock
CREATE TRIGGER IF NOT EXISTS trg_before_issue_check_stock
BEFORE UPDATE OF status ON issues
WHEN NEW.status = 'issued' AND OLD.status != 'issued'
BEGIN
  SELECT
    CASE
      WHEN EXISTS (
        SELECT 1
        FROM issue_items ii
        LEFT JOIN stock_levels sl ON sl.product_uuid = ii.product_uuid AND sl.location_uuid = NEW.from_location_uuid
        WHERE ii.issue_uuid = NEW.uuid
        AND (sl.quantity IS NULL OR sl.quantity < ii.quantity)
        LIMIT 1
      )
      THEN RAISE(ABORT, 'Insufficient stock for one or more items in this issue')
    END;
END;

-- Trigger: After issue is marked as 'issued', update stock levels
CREATE TRIGGER IF NOT EXISTS trg_after_issue_approved
AFTER UPDATE OF status ON issues
WHEN NEW.status = 'issued' AND OLD.status != 'issued'
BEGIN
  -- Create stock adjustments for each issue item
  INSERT INTO stock_adjustments (
    uuid,
    product_uuid,
    location_uuid,
    adjustment_type,
    quantity_change,
    quantity_before,
    quantity_after,
    unit_id,
    conversion_factor,
    reference_type,
    reference_uuid,
    reason,
    created_by
  )
  SELECT
    'adj_' || hex(randomblob(16)),
    ii.product_uuid,
    NEW.from_location_uuid,
    'issue',
    -COALESCE(SUM(ii.quantity), 0),
    COALESCE((SELECT quantity FROM stock_levels WHERE product_uuid = ii.product_uuid AND location_uuid = NEW.from_location_uuid), 0),
    COALESCE((SELECT quantity FROM stock_levels WHERE product_uuid = ii.product_uuid AND location_uuid = NEW.from_location_uuid), 0) - COALESCE(SUM(ii.quantity), 0),
    ii.unit_id,
    1.0,
    'issue',
    NEW.uuid,
    'Stock issued: ' || NEW.issue_number,
    NEW.issued_by
  FROM issue_items ii
  WHERE ii.issue_uuid = NEW.uuid
  GROUP BY ii.product_uuid, ii.unit_id;

  -- Update stock_levels (decrease)
  UPDATE stock_levels
  SET
    quantity = quantity - (
      SELECT COALESCE(SUM(ii.quantity), 0)
      FROM issue_items ii
      WHERE ii.issue_uuid = NEW.uuid AND ii.product_uuid = stock_levels.product_uuid
    ),
    last_modified = datetime('now')
  WHERE location_uuid = NEW.from_location_uuid
  AND product_uuid IN (SELECT product_uuid FROM issue_items WHERE issue_uuid = NEW.uuid);
END;

-- ============================================================================
-- SECTION 3: TRANSFER TRIGGERS
-- ============================================================================

-- Trigger: Before transfer completion, check sufficient stock at source
CREATE TRIGGER IF NOT EXISTS trg_before_transfer_check_stock
BEFORE UPDATE OF status ON transfers
WHEN NEW.status = 'completed' AND OLD.status != 'completed'
BEGIN
  SELECT
    CASE
      WHEN EXISTS (
        SELECT 1
        FROM transfer_items ti
        LEFT JOIN stock_levels sl ON sl.product_uuid = ti.product_uuid AND sl.location_uuid = NEW.from_location_uuid
        WHERE ti.transfer_uuid = NEW.uuid
        AND (sl.quantity IS NULL OR sl.quantity < ti.quantity)
        LIMIT 1
      )
      THEN RAISE(ABORT, 'Insufficient stock at source location for transfer')
    END;
END;

-- Trigger: After transfer completion, update stock at both locations
CREATE TRIGGER IF NOT EXISTS trg_after_transfer_completed
AFTER UPDATE OF status ON transfers
WHEN NEW.status = 'completed' AND OLD.status != 'completed'
BEGIN
  -- Deduct from source location
  INSERT INTO stock_adjustments (
    uuid,
    product_uuid,
    location_uuid,
    adjustment_type,
    quantity_change,
    quantity_before,
    quantity_after,
    unit_id,
    conversion_factor,
    reference_type,
    reference_uuid,
    reason,
    created_by
  )
  SELECT
    'adj_' || hex(randomblob(16)),
    ti.product_uuid,
    NEW.from_location_uuid,
    'transfer_out',
    -COALESCE(SUM(ti.quantity), 0),
    COALESCE((SELECT quantity FROM stock_levels WHERE product_uuid = ti.product_uuid AND location_uuid = NEW.from_location_uuid), 0),
    COALESCE((SELECT quantity FROM stock_levels WHERE product_uuid = ti.product_uuid AND location_uuid = NEW.from_location_uuid), 0) - COALESCE(SUM(ti.quantity), 0),
    ti.unit_id,
    1.0,
    'transfer',
    NEW.uuid,
    'Transfer out: ' || NEW.transfer_number,
    NEW.completed_by
  FROM transfer_items ti
  WHERE ti.transfer_uuid = NEW.uuid
  GROUP BY ti.product_uuid, ti.unit_id;

  -- Add to destination location
  INSERT INTO stock_adjustments (
    uuid,
    product_uuid,
    location_uuid,
    adjustment_type,
    quantity_change,
    quantity_before,
    quantity_after,
    unit_id,
    conversion_factor,
    reference_type,
    reference_uuid,
    reason,
    created_by
  )
  SELECT
    'adj_' || hex(randomblob(16)),
    ti.product_uuid,
    NEW.to_location_uuid,
    'transfer_in',
    COALESCE(SUM(ti.quantity), 0),
    COALESCE((SELECT quantity FROM stock_levels WHERE product_uuid = ti.product_uuid AND location_uuid = NEW.to_location_uuid), 0),
    COALESCE((SELECT quantity FROM stock_levels WHERE product_uuid = ti.product_uuid AND location_uuid = NEW.to_location_uuid), 0) + COALESCE(SUM(ti.quantity), 0),
    ti.unit_id,
    1.0,
    'transfer',
    NEW.uuid,
    'Transfer in: ' || NEW.transfer_number,
    NEW.completed_by
  FROM transfer_items ti
  WHERE ti.transfer_uuid = NEW.uuid
  GROUP BY ti.product_uuid, ti.unit_id;

  -- Update stock_levels at source (decrease)
  UPDATE stock_levels
  SET
    quantity = quantity - (
      SELECT COALESCE(SUM(ti.quantity), 0)
      FROM transfer_items ti
      WHERE ti.transfer_uuid = NEW.uuid AND ti.product_uuid = stock_levels.product_uuid
    ),
    last_modified = datetime('now')
  WHERE location_uuid = NEW.from_location_uuid
  AND product_uuid IN (SELECT product_uuid FROM transfer_items WHERE transfer_uuid = NEW.uuid);

  -- Update stock_levels at destination (increase)
  INSERT INTO stock_levels (product_uuid, location_uuid, quantity, last_modified)
  SELECT
    ti.product_uuid,
    NEW.to_location_uuid,
    COALESCE(SUM(ti.quantity), 0),
    datetime('now')
  FROM transfer_items ti
  WHERE ti.transfer_uuid = NEW.uuid
  GROUP BY ti.product_uuid
  ON CONFLICT(product_uuid, location_uuid) DO UPDATE SET
    quantity = quantity + excluded.quantity,
    last_modified = excluded.last_modified;
END;

-- ============================================================================
-- SECTION 4: WASTAGE TRIGGERS
-- ============================================================================

-- Trigger: After wastage approval, deduct from stock
CREATE TRIGGER IF NOT EXISTS trg_after_wastage_approved
AFTER UPDATE OF status ON wastages
WHEN NEW.status = 'approved' AND OLD.status != 'approved'
BEGIN
  -- Create stock adjustments
  INSERT INTO stock_adjustments (
    uuid,
    product_uuid,
    location_uuid,
    adjustment_type,
    quantity_change,
    quantity_before,
    quantity_after,
    unit_id,
    conversion_factor,
    reference_type,
    reference_uuid,
    reason,
    created_by
  )
  SELECT
    'adj_' || hex(randomblob(16)),
    wi.product_uuid,
    NEW.location_uuid,
    'wastage',
    -COALESCE(SUM(wi.quantity), 0),
    COALESCE((SELECT quantity FROM stock_levels WHERE product_uuid = wi.product_uuid AND location_uuid = NEW.location_uuid), 0),
    COALESCE((SELECT quantity FROM stock_levels WHERE product_uuid = wi.product_uuid AND location_uuid = NEW.location_uuid), 0) - COALESCE(SUM(wi.quantity), 0),
    wi.unit_id,
    1.0,
    'wastage',
    NEW.uuid,
    'Wastage recorded: ' || NEW.wastage_number,
    NEW.approved_by
  FROM wastage_items wi
  WHERE wi.wastage_uuid = NEW.uuid
  GROUP BY wi.product_uuid, wi.unit_id;

  -- Update stock_levels (decrease)
  UPDATE stock_levels
  SET
    quantity = quantity - (
      SELECT COALESCE(SUM(wi.quantity), 0)
      FROM wastage_items wi
      WHERE wi.wastage_uuid = NEW.uuid AND wi.product_uuid = stock_levels.product_uuid
    ),
    last_modified = datetime('now')
  WHERE location_uuid = NEW.location_uuid
  AND product_uuid IN (SELECT product_uuid FROM wastage_items WHERE wastage_uuid = NEW.uuid);
END;

-- ============================================================================
-- SECTION 5: INVOICE TRIGGERS
-- ============================================================================

-- Trigger: Calculate invoice totals from items
CREATE TRIGGER IF NOT EXISTS trg_after_invoice_item_insert
AFTER INSERT ON invoice_items
BEGIN
  UPDATE invoices
  SET
    subtotal = (
      SELECT COALESCE(SUM(total_amount - gst_amount), 0)
      FROM invoice_items
      WHERE invoice_uuid = NEW.invoice_uuid
    ),
    gst_amount = (
      SELECT COALESCE(SUM(gst_amount), 0)
      FROM invoice_items
      WHERE invoice_uuid = NEW.invoice_uuid
    ),
    grand_total = (
      SELECT COALESCE(SUM(total_amount), 0)
      FROM invoice_items
      WHERE invoice_uuid = NEW.invoice_uuid
    ) - (SELECT COALESCE(discount_amount, 0) FROM invoices WHERE uuid = NEW.invoice_uuid),
    last_modified = datetime('now')
  WHERE uuid = NEW.invoice_uuid;
END;

CREATE TRIGGER IF NOT EXISTS trg_after_invoice_item_update
AFTER UPDATE ON invoice_items
BEGIN
  UPDATE invoices
  SET
    subtotal = (
      SELECT COALESCE(SUM(total_amount - gst_amount), 0)
      FROM invoice_items
      WHERE invoice_uuid = NEW.invoice_uuid
    ),
    gst_amount = (
      SELECT COALESCE(SUM(gst_amount), 0)
      FROM invoice_items
      WHERE invoice_uuid = NEW.invoice_uuid
    ),
    grand_total = (
      SELECT COALESCE(SUM(total_amount), 0)
      FROM invoice_items
      WHERE invoice_uuid = NEW.invoice_uuid
    ) - (SELECT COALESCE(discount_amount, 0) FROM invoices WHERE uuid = NEW.invoice_uuid),
    last_modified = datetime('now')
  WHERE uuid = NEW.invoice_uuid;
END;

CREATE TRIGGER IF NOT EXISTS trg_after_invoice_item_delete
AFTER DELETE ON invoice_items
BEGIN
  UPDATE invoices
  SET
    subtotal = (
      SELECT COALESCE(SUM(total_amount - gst_amount), 0)
      FROM invoice_items
      WHERE invoice_uuid = OLD.invoice_uuid
    ),
    gst_amount = (
      SELECT COALESCE(SUM(gst_amount), 0)
      FROM invoice_items
      WHERE invoice_uuid = OLD.invoice_uuid
    ),
    grand_total = (
      SELECT COALESCE(SUM(total_amount), 0)
      FROM invoice_items
      WHERE invoice_uuid = OLD.invoice_uuid
    ) - (SELECT COALESCE(discount_amount, 0) FROM invoices WHERE uuid = OLD.invoice_uuid),
    last_modified = datetime('now')
  WHERE uuid = OLD.invoice_uuid;
END;

-- ============================================================================
-- SECTION 6: PURCHASE TOTAL CALCULATION TRIGGERS
-- ============================================================================

CREATE TRIGGER IF NOT EXISTS trg_after_purchase_item_insert
AFTER INSERT ON purchase_items
BEGIN
  UPDATE purchases
  SET
    total_amount = (
      SELECT COALESCE(SUM(total_amount - gst_amount), 0)
      FROM purchase_items
      WHERE purchase_uuid = NEW.purchase_uuid
    ),
    gst_amount = (
      SELECT COALESCE(SUM(gst_amount), 0)
      FROM purchase_items
      WHERE purchase_uuid = NEW.purchase_uuid
    ),
    grand_total = (
      SELECT COALESCE(SUM(total_amount), 0)
      FROM purchase_items
      WHERE purchase_uuid = NEW.purchase_uuid
    ),
    last_modified = datetime('now')
  WHERE uuid = NEW.purchase_uuid;
END;

CREATE TRIGGER IF NOT EXISTS trg_after_purchase_item_update
AFTER UPDATE ON purchase_items
BEGIN
  UPDATE purchases
  SET
    total_amount = (
      SELECT COALESCE(SUM(total_amount - gst_amount), 0)
      FROM purchase_items
      WHERE purchase_uuid = NEW.purchase_uuid
    ),
    gst_amount = (
      SELECT COALESCE(SUM(gst_amount), 0)
      FROM purchase_items
      WHERE purchase_uuid = NEW.purchase_uuid
    ),
    grand_total = (
      SELECT COALESCE(SUM(total_amount), 0)
      FROM purchase_items
      WHERE purchase_uuid = NEW.purchase_uuid
    ),
    last_modified = datetime('now')
  WHERE uuid = NEW.purchase_uuid;
END;

CREATE TRIGGER IF NOT EXISTS trg_after_purchase_item_delete
AFTER DELETE ON purchase_items
BEGIN
  UPDATE purchases
  SET
    total_amount = (
      SELECT COALESCE(SUM(total_amount - gst_amount), 0)
      FROM purchase_items
      WHERE purchase_uuid = OLD.purchase_uuid
    ),
    gst_amount = (
      SELECT COALESCE(SUM(gst_amount), 0)
      FROM purchase_items
      WHERE purchase_uuid = OLD.purchase_uuid
    ),
    grand_total = (
      SELECT COALESCE(SUM(total_amount), 0)
      FROM purchase_items
      WHERE purchase_uuid = OLD.purchase_uuid
    ),
    last_modified = datetime('now')
  WHERE uuid = OLD.purchase_uuid;
END;

-- ============================================================================
-- SECTION 7: LOW STOCK ALERTS
-- ============================================================================

-- Trigger: Create alert when stock falls below reorder level
CREATE TRIGGER IF NOT EXISTS trg_after_stock_low_alert
AFTER UPDATE OF quantity ON stock_levels
WHEN NEW.quantity <= (SELECT COALESCE(reorder_level, 0) FROM products WHERE uuid = NEW.product_uuid)
AND NEW.quantity < OLD.quantity
BEGIN
  INSERT INTO alerts (
    uuid,
    alert_type,
    severity,
    title,
    message,
    reference_type,
    reference_uuid
  )
  SELECT
    'alert_' || hex(randomblob(16)),
    'low_stock',
    CASE
      WHEN NEW.quantity <= 0 THEN 'critical'
      WHEN NEW.quantity <= (p.min_stock_level * 0.5) THEN 'critical'
      ELSE 'warning'
    END,
    'Low Stock Alert',
    'Product "' || p.name || '" at location "' || l.name || '" has fallen to ' || NEW.quantity || ' ' || u.abbreviation || ' (reorder level: ' || p.reorder_level || ')',
    'product',
    NEW.product_uuid
  FROM products p
  LEFT JOIN locations l ON l.uuid = NEW.location_uuid
  LEFT JOIN units u ON u.id = p.default_unit_id
  WHERE p.uuid = NEW.product_uuid
  AND NOT EXISTS (
    SELECT 1 FROM alerts
    WHERE reference_uuid = NEW.product_uuid
    AND alert_type = 'low_stock'
    AND is_resolved = 0
    AND created_at > datetime('now', '-24 hours')
  );
END;

-- ============================================================================
-- END OF TRIGGERS
-- ============================================================================

-- Verification: Count triggers
-- SELECT COUNT(*) FROM sqlite_master WHERE type='trigger';
-- Expected: 14 triggers
