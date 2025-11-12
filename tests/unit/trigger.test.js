/**
 * Trigger Tests
 * Tests database triggers for stock automation and validation
 */

const Database = require('better-sqlite3');
const fs = require('fs');
const path = require('path');
const { v4: uuidv4 } = require('uuid');

describe('Database Triggers', () => {
  let db;
  const testDbPath = path.join(__dirname, 'test_triggers.db');

  beforeEach(() => {
    // Remove existing test database
    if (fs.existsSync(testDbPath)) {
      fs.unlinkSync(testDbPath);
    }

    // Create fresh database with schema and triggers
    db = new Database(testDbPath);
    db.pragma('foreign_keys = ON');

    // Apply schema
    const schema = fs.readFileSync(
      path.join(__dirname, '../../sql/v1_initial.sql'),
      'utf8'
    );
    db.exec(schema);

    // Apply triggers
    const triggers = fs.readFileSync(
      path.join(__dirname, '../../sql/v1_triggers.sql'),
      'utf8'
    );
    db.exec(triggers);

    // Create test data
    setupTestData();
  });

  afterEach(() => {
    if (db) {
      db.close();
    }
    if (fs.existsSync(testDbPath)) {
      fs.unlinkSync(testDbPath);
    }
  });

  function setupTestData() {
    // Create test product
    db.prepare(`
      INSERT INTO products (uuid, name, category_id, default_unit_id, base_unit_id, last_modified)
      VALUES ('prod_001', 'Test Product', NULL, 1, 1, datetime('now'))
    `).run();

    // Create test supplier
    db.prepare(`
      INSERT INTO suppliers (uuid, name, last_modified)
      VALUES ('sup_001', 'Test Supplier', datetime('now'))
    `).run();

    // Create test location
    db.prepare(`
      INSERT INTO locations (uuid, name, last_modified)
      VALUES ('loc_001', 'Test Location', datetime('now'))
    `).run();
  }

  describe('Purchase Triggers', () => {
    test('should update stock when purchase is received', () => {
      const purchaseUuid = uuidv4();

      // Create purchase
      db.prepare(`
        INSERT INTO purchases (
          uuid, purchase_number, supplier_uuid, location_uuid,
          purchase_date, status, created_by, last_modified
        ) VALUES (?, 'PUR001', 'sup_001', 'loc_001', date('now'), 'draft', 'user_admin', datetime('now'))
      `).run(purchaseUuid);

      // Add purchase items
      db.prepare(`
        INSERT INTO purchase_items (
          uuid, purchase_uuid, product_uuid, quantity, unit_id, last_modified
        ) VALUES ('item_001', ?, 'prod_001', 100, 1, datetime('now'))
      `).run(purchaseUuid);

      // Mark as received (trigger should fire)
      db.prepare(`
        UPDATE purchases
        SET status = 'received', approved_by = 'user_admin', last_modified = datetime('now')
        WHERE uuid = ?
      `).run(purchaseUuid);

      // Verify stock level updated
      const stockLevel = db.prepare(`
        SELECT quantity FROM stock_levels
        WHERE product_uuid = 'prod_001' AND location_uuid = 'loc_001'
      `).get();

      expect(stockLevel).toBeDefined();
      expect(stockLevel.quantity).toBe(100);

      // Verify stock adjustment created
      const adjustment = db.prepare(`
        SELECT * FROM stock_adjustments
        WHERE product_uuid = 'prod_001' AND adjustment_type = 'purchase'
      `).get();

      expect(adjustment).toBeDefined();
      expect(adjustment.quantity_change).toBe(100);
      expect(adjustment.quantity_before).toBe(0);
      expect(adjustment.quantity_after).toBe(100);
    });

    test('should handle multiple purchase items correctly with SUM aggregation', () => {
      const purchaseUuid = uuidv4();

      // Create purchase
      db.prepare(`
        INSERT INTO purchases (
          uuid, purchase_number, supplier_uuid, location_uuid,
          purchase_date, status, created_by, last_modified
        ) VALUES (?, 'PUR002', 'sup_001', 'loc_001', date('now'), 'draft', 'user_admin', datetime('now'))
      `).run(purchaseUuid);

      // Add multiple items of the same product
      db.prepare(`
        INSERT INTO purchase_items (uuid, purchase_uuid, product_uuid, quantity, unit_id, last_modified)
        VALUES
          ('item_001', ?, 'prod_001', 50, 1, datetime('now')),
          ('item_002', ?, 'prod_001', 30, 1, datetime('now')),
          ('item_003', ?, 'prod_001', 20, 1, datetime('now'))
      `).run(purchaseUuid, purchaseUuid, purchaseUuid);

      // Mark as received
      db.prepare(`
        UPDATE purchases
        SET status = 'received', approved_by = 'user_admin', last_modified = datetime('now')
        WHERE uuid = ?
      `).run(purchaseUuid);

      // Verify correct total (50 + 30 + 20 = 100)
      const stockLevel = db.prepare(`
        SELECT quantity FROM stock_levels
        WHERE product_uuid = 'prod_001' AND location_uuid = 'loc_001'
      `).get();

      expect(stockLevel.quantity).toBe(100);
    });
  });

  describe('Issue Triggers', () => {
    beforeEach(() => {
      // Add initial stock
      db.prepare(`
        INSERT INTO stock_levels (product_uuid, location_uuid, quantity, last_modified)
        VALUES ('prod_001', 'loc_001', 100, datetime('now'))
      `).run();
    });

    test('should prevent issue if insufficient stock', () => {
      const issueUuid = uuidv4();

      // Create issue
      db.prepare(`
        INSERT INTO issues (
          uuid, issue_number, from_location_uuid, issue_date,
          status, created_by, last_modified
        ) VALUES (?, 'ISS001', 'loc_001', date('now'), 'draft', 'user_admin', datetime('now'))
      `).run(issueUuid);

      // Add item requesting MORE than available
      db.prepare(`
        INSERT INTO issue_items (uuid, issue_uuid, product_uuid, quantity, unit_id, last_modified)
        VALUES ('item_001', ?, 'prod_001', 150, 1, datetime('now'))
      `).run(issueUuid);

      // Try to mark as issued - should fail
      expect(() => {
        db.prepare(`
          UPDATE issues
          SET status = 'issued', issued_by = 'user_admin', last_modified = datetime('now')
          WHERE uuid = ?
        `).run(issueUuid);
      }).toThrow(/Insufficient stock/);
    });

    test('should deduct stock when issue is approved', () => {
      const issueUuid = uuidv4();

      db.prepare(`
        INSERT INTO issues (
          uuid, issue_number, from_location_uuid, issue_date,
          status, created_by, last_modified
        ) VALUES (?, 'ISS002', 'loc_001', date('now'), 'draft', 'user_admin', datetime('now'))
      `).run(issueUuid);

      db.prepare(`
        INSERT INTO issue_items (uuid, issue_uuid, product_uuid, quantity, unit_id, last_modified)
        VALUES ('item_001', ?, 'prod_001', 30, 1, datetime('now'))
      `).run(issueUuid);

      // Mark as issued
      db.prepare(`
        UPDATE issues
        SET status = 'issued', issued_by = 'user_admin', last_modified = datetime('now')
        WHERE uuid = ?
      `).run(issueUuid);

      // Verify stock deducted
      const stockLevel = db.prepare(`
        SELECT quantity FROM stock_levels
        WHERE product_uuid = 'prod_001' AND location_uuid = 'loc_001'
      `).get();

      expect(stockLevel.quantity).toBe(70); // 100 - 30

      // Verify adjustment created
      const adjustment = db.prepare(`
        SELECT * FROM stock_adjustments
        WHERE product_uuid = 'prod_001' AND adjustment_type = 'issue'
      `).get();

      expect(adjustment).toBeDefined();
      expect(adjustment.quantity_change).toBe(-30);
      expect(adjustment.quantity_before).toBe(100);
      expect(adjustment.quantity_after).toBe(70);
    });
  });

  describe('Transfer Triggers', () => {
    beforeEach(() => {
      // Add second location
      db.prepare(`
        INSERT INTO locations (uuid, name, last_modified)
        VALUES ('loc_002', 'Test Location 2', datetime('now'))
      `).run();

      // Add stock to source location
      db.prepare(`
        INSERT INTO stock_levels (product_uuid, location_uuid, quantity, last_modified)
        VALUES ('prod_001', 'loc_001', 100, datetime('now'))
      `).run();
    });

    test('should prevent transfer if insufficient stock at source', () => {
      const transferUuid = uuidv4();

      db.prepare(`
        INSERT INTO transfers (
          uuid, transfer_number, from_location_uuid, to_location_uuid,
          transfer_date, status, created_by, last_modified
        ) VALUES (?, 'TRF001', 'loc_001', 'loc_002', date('now'), 'draft', 'user_admin', datetime('now'))
      `).run(transferUuid);

      db.prepare(`
        INSERT INTO transfer_items (uuid, transfer_uuid, product_uuid, quantity, unit_id, last_modified)
        VALUES ('item_001', ?, 'prod_001', 150, 1, datetime('now'))
      `).run(transferUuid);

      // Try to complete - should fail
      expect(() => {
        db.prepare(`
          UPDATE transfers
          SET status = 'completed', completed_by = 'user_admin', last_modified = datetime('now')
          WHERE uuid = ?
        `).run(transferUuid);
      }).toThrow(/Insufficient stock/);
    });

    test('should update stock at both locations on transfer completion', () => {
      const transferUuid = uuidv4();

      db.prepare(`
        INSERT INTO transfers (
          uuid, transfer_number, from_location_uuid, to_location_uuid,
          transfer_date, status, created_by, last_modified
        ) VALUES (?, 'TRF002', 'loc_001', 'loc_002', date('now'), 'draft', 'user_admin', datetime('now'))
      `).run(transferUuid);

      db.prepare(`
        INSERT INTO transfer_items (uuid, transfer_uuid, product_uuid, quantity, unit_id, last_modified)
        VALUES ('item_001', ?, 'prod_001', 40, 1, datetime('now'))
      `).run(transferUuid);

      // Complete transfer
      db.prepare(`
        UPDATE transfers
        SET status = 'completed', completed_by = 'user_admin', last_modified = datetime('now')
        WHERE uuid = ?
      `).run(transferUuid);

      // Verify source location deducted
      const sourceStock = db.prepare(`
        SELECT quantity FROM stock_levels
        WHERE product_uuid = 'prod_001' AND location_uuid = 'loc_001'
      `).get();
      expect(sourceStock.quantity).toBe(60); // 100 - 40

      // Verify destination location increased
      const destStock = db.prepare(`
        SELECT quantity FROM stock_levels
        WHERE product_uuid = 'prod_001' AND location_uuid = 'loc_002'
      `).get();
      expect(destStock.quantity).toBe(40);

      // Verify adjustments created
      const adjustments = db.prepare(`
        SELECT * FROM stock_adjustments
        WHERE product_uuid = 'prod_001' AND reference_type = 'transfer'
        ORDER BY adjustment_type
      `).all();

      expect(adjustments.length).toBe(2);
      expect(adjustments[0].adjustment_type).toBe('transfer_in');
      expect(adjustments[0].quantity_change).toBe(40);
      expect(adjustments[1].adjustment_type).toBe('transfer_out');
      expect(adjustments[1].quantity_change).toBe(-40);
    });
  });

  describe('Wastage Triggers', () => {
    beforeEach(() => {
      db.prepare(`
        INSERT INTO stock_levels (product_uuid, location_uuid, quantity, last_modified)
        VALUES ('prod_001', 'loc_001', 100, datetime('now'))
      `).run();
    });

    test('should deduct stock on wastage approval', () => {
      const wastageUuid = uuidv4();

      db.prepare(`
        INSERT INTO wastages (
          uuid, wastage_number, location_uuid, wastage_date,
          status, created_by, last_modified
        ) VALUES (?, 'WST001', 'loc_001', date('now'), 'draft', 'user_admin', datetime('now'))
      `).run(wastageUuid);

      db.prepare(`
        INSERT INTO wastage_items (uuid, wastage_uuid, product_uuid, quantity, unit_id, last_modified)
        VALUES ('item_001', ?, 'prod_001', 15, 1, datetime('now'))
      `).run(wastageUuid);

      // Approve wastage
      db.prepare(`
        UPDATE wastages
        SET status = 'approved', approved_by = 'user_admin', last_modified = datetime('now')
        WHERE uuid = ?
      `).run(wastageUuid);

      // Verify stock deducted
      const stockLevel = db.prepare(`
        SELECT quantity FROM stock_levels
        WHERE product_uuid = 'prod_001' AND location_uuid = 'loc_001'
      `).get();

      expect(stockLevel.quantity).toBe(85); // 100 - 15

      // Verify adjustment
      const adjustment = db.prepare(`
        SELECT * FROM stock_adjustments
        WHERE product_uuid = 'prod_001' AND adjustment_type = 'wastage'
      `).get();

      expect(adjustment).toBeDefined();
      expect(adjustment.quantity_change).toBe(-15);
    });
  });

  describe('Low Stock Alert Triggers', () => {
    test('should create alert when stock falls below reorder level', () => {
      // Set reorder level
      db.prepare(`
        UPDATE products
        SET reorder_level = 50, last_modified = datetime('now')
        WHERE uuid = 'prod_001'
      `).run();

      // Create initial stock
      db.prepare(`
        INSERT INTO stock_levels (product_uuid, location_uuid, quantity, last_modified)
        VALUES ('prod_001', 'loc_001', 100, datetime('now'))
      `).run();

      // Reduce stock below reorder level
      db.prepare(`
        UPDATE stock_levels
        SET quantity = 40, last_modified = datetime('now')
        WHERE product_uuid = 'prod_001' AND location_uuid = 'loc_001'
      `).run();

      // Check alert created
      const alert = db.prepare(`
        SELECT * FROM alerts
        WHERE alert_type = 'low_stock' AND reference_uuid = 'prod_001'
      `).get();

      expect(alert).toBeDefined();
      expect(alert.severity).toBe('warning');
    });
  });

  describe('Invoice Total Calculation Triggers', () => {
    test('should auto-calculate invoice totals from items', () => {
      const invoiceUuid = uuidv4();

      // Create invoice
      db.prepare(`
        INSERT INTO invoices (
          uuid, invoice_number, invoice_date, status,
          created_by, last_modified
        ) VALUES (?, 'INV001', date('now'), 'draft', 'user_admin', datetime('now'))
      `).run(invoiceUuid);

      // Add items
      db.prepare(`
        INSERT INTO invoice_items (
          uuid, invoice_uuid, product_uuid, quantity, unit_id,
          unit_price, gst_rate, gst_amount, total_amount, last_modified
        ) VALUES
          ('item_001', ?, 'prod_001', 2, 1, 100, 18, 36, 236, datetime('now')),
          ('item_002', ?, 'prod_001', 3, 1, 100, 18, 54, 354, datetime('now'))
      `).run(invoiceUuid, invoiceUuid);

      // Check invoice totals auto-calculated
      const invoice = db.prepare(`
        SELECT subtotal, gst_amount, grand_total FROM invoices WHERE uuid = ?
      `).get(invoiceUuid);

      expect(invoice.subtotal).toBe(500); // (236-36) + (354-54)
      expect(invoice.gst_amount).toBe(90); // 36 + 54
      expect(invoice.grand_total).toBe(590); // 236 + 354
    });
  });
});
