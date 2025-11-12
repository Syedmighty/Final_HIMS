-- ============================================================================
-- HIMS DATABASE SCHEMA v1.0.0 - Initial Core Schema
-- ============================================================================
-- Description: Hotel Inventory Management System - Complete Initial Schema
-- Purpose: Core tables for inventory, purchases, issues, transfers, invoices
-- Version: 1.0.0
-- Target Release: Q1 2026
-- ============================================================================

PRAGMA foreign_keys = ON;
PRAGMA journal_mode = WAL;
PRAGMA synchronous = NORMAL;
PRAGMA temp_store = MEMORY;
PRAGMA cache_size = -64000; -- 64MB cache

-- ============================================================================
-- SECTION 1: SCHEMA METADATA
-- ============================================================================

CREATE TABLE IF NOT EXISTS schema_migrations (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  version TEXT NOT NULL UNIQUE,
  description TEXT,
  checksum TEXT,
  applied_at TEXT NOT NULL DEFAULT (datetime('now')),
  applied_by TEXT
);

INSERT OR IGNORE INTO schema_migrations (version, description, checksum)
VALUES ('1.0.0', 'Initial core schema', 'INITIAL');

-- ============================================================================
-- SECTION 2: USER MANAGEMENT & AUTHENTICATION
-- ============================================================================

CREATE TABLE IF NOT EXISTS users (
  uuid TEXT PRIMARY KEY,
  username TEXT NOT NULL UNIQUE,
  password_hash TEXT NOT NULL, -- bcrypt hashed
  full_name TEXT NOT NULL,
  role TEXT NOT NULL CHECK (role IN ('admin', 'manager', 'staff', 'viewer')),
  email TEXT,
  phone TEXT,
  is_active INTEGER NOT NULL DEFAULT 1 CHECK (is_active IN (0, 1)),
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  last_modified TEXT NOT NULL DEFAULT (datetime('now')),
  created_by TEXT,
  deleted_at TEXT,
  deleted_by TEXT
);

CREATE INDEX idx_users_username ON users(username);
CREATE INDEX idx_users_role ON users(role);
CREATE INDEX idx_users_active ON users(is_active) WHERE is_active = 1;

-- ============================================================================
-- SECTION 3: UNITS & CONVERSIONS
-- ============================================================================

CREATE TABLE IF NOT EXISTS units (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  uuid TEXT NOT NULL UNIQUE,
  name TEXT NOT NULL UNIQUE,
  abbreviation TEXT NOT NULL UNIQUE,
  unit_type TEXT CHECK (unit_type IN ('weight', 'volume', 'count', 'length')),
  is_base_unit INTEGER NOT NULL DEFAULT 0 CHECK (is_base_unit IN (0, 1)),
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  last_modified TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX idx_units_uuid ON units(uuid);
CREATE INDEX idx_units_type ON units(unit_type);

-- Unit conversions: bidirectional conversion factors
CREATE TABLE IF NOT EXISTS unit_conversions (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  from_unit_id INTEGER NOT NULL,
  to_unit_id INTEGER NOT NULL,
  conversion_factor REAL NOT NULL CHECK (conversion_factor > 0),
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  last_modified TEXT NOT NULL DEFAULT (datetime('now')),
  FOREIGN KEY (from_unit_id) REFERENCES units(id) ON DELETE CASCADE,
  FOREIGN KEY (to_unit_id) REFERENCES units(id) ON DELETE CASCADE,
  UNIQUE (from_unit_id, to_unit_id)
);

CREATE INDEX idx_unit_conversions_from ON unit_conversions(from_unit_id);
CREATE INDEX idx_unit_conversions_to ON unit_conversions(to_unit_id);

-- ============================================================================
-- SECTION 4: CATEGORIES & PRODUCTS
-- ============================================================================

CREATE TABLE IF NOT EXISTS categories (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  uuid TEXT NOT NULL UNIQUE,
  name TEXT NOT NULL UNIQUE,
  description TEXT,
  parent_category_id INTEGER,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  last_modified TEXT NOT NULL DEFAULT (datetime('now')),
  FOREIGN KEY (parent_category_id) REFERENCES categories(id) ON DELETE SET NULL
);

CREATE INDEX idx_categories_uuid ON categories(uuid);
CREATE INDEX idx_categories_parent ON categories(parent_category_id);

CREATE TABLE IF NOT EXISTS products (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  uuid TEXT NOT NULL UNIQUE,
  name TEXT NOT NULL,
  sku TEXT UNIQUE,
  category_id INTEGER,
  default_unit_id INTEGER NOT NULL,
  base_unit_id INTEGER NOT NULL,
  description TEXT,
  reorder_level REAL DEFAULT 0,
  min_stock_level REAL DEFAULT 0,
  max_stock_level REAL,
  cost_price REAL DEFAULT 0,
  selling_price REAL DEFAULT 0,
  gst_rate REAL DEFAULT 0 CHECK (gst_rate >= 0 AND gst_rate <= 100),
  is_active INTEGER NOT NULL DEFAULT 1 CHECK (is_active IN (0, 1)),
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  last_modified TEXT NOT NULL DEFAULT (datetime('now')),
  created_by TEXT,
  deleted_at TEXT,
  deleted_by TEXT,
  FOREIGN KEY (category_id) REFERENCES categories(id) ON DELETE SET NULL,
  FOREIGN KEY (default_unit_id) REFERENCES units(id) ON DELETE RESTRICT,
  FOREIGN KEY (base_unit_id) REFERENCES units(id) ON DELETE RESTRICT,
  FOREIGN KEY (created_by) REFERENCES users(uuid) ON DELETE SET NULL,
  FOREIGN KEY (deleted_by) REFERENCES users(uuid) ON DELETE SET NULL
);

CREATE INDEX idx_products_uuid ON products(uuid);
CREATE INDEX idx_products_sku ON products(sku);
CREATE INDEX idx_products_category ON products(category_id);
CREATE INDEX idx_products_active ON products(is_active) WHERE is_active = 1;

-- ============================================================================
-- SECTION 5: SUPPLIERS
-- ============================================================================

CREATE TABLE IF NOT EXISTS suppliers (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  uuid TEXT NOT NULL UNIQUE,
  name TEXT NOT NULL,
  contact_person TEXT,
  phone TEXT,
  email TEXT,
  address TEXT,
  gst_number TEXT,
  credit_days INTEGER DEFAULT 0,
  is_active INTEGER NOT NULL DEFAULT 1 CHECK (is_active IN (0, 1)),
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  last_modified TEXT NOT NULL DEFAULT (datetime('now')),
  created_by TEXT,
  deleted_at TEXT,
  deleted_by TEXT,
  FOREIGN KEY (created_by) REFERENCES users(uuid) ON DELETE SET NULL,
  FOREIGN KEY (deleted_by) REFERENCES users(uuid) ON DELETE SET NULL
);

CREATE INDEX idx_suppliers_uuid ON suppliers(uuid);
CREATE INDEX idx_suppliers_active ON suppliers(is_active) WHERE is_active = 1;

-- ============================================================================
-- SECTION 6: LOCATIONS
-- ============================================================================

CREATE TABLE IF NOT EXISTS locations (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  uuid TEXT NOT NULL UNIQUE,
  name TEXT NOT NULL UNIQUE,
  location_type TEXT CHECK (location_type IN ('warehouse', 'kitchen', 'bar', 'restaurant', 'store')),
  description TEXT,
  is_active INTEGER NOT NULL DEFAULT 1 CHECK (is_active IN (0, 1)),
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  last_modified TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX idx_locations_uuid ON locations(uuid);
CREATE INDEX idx_locations_active ON locations(is_active) WHERE is_active = 1;

-- ============================================================================
-- SECTION 7: STOCK LEVELS (SOURCE OF TRUTH)
-- ============================================================================

CREATE TABLE IF NOT EXISTS stock_levels (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  product_uuid TEXT NOT NULL,
  location_uuid TEXT NOT NULL,
  quantity REAL NOT NULL DEFAULT 0 CHECK (quantity >= 0),
  last_modified TEXT NOT NULL DEFAULT (datetime('now')),
  FOREIGN KEY (product_uuid) REFERENCES products(uuid) ON DELETE CASCADE,
  FOREIGN KEY (location_uuid) REFERENCES locations(uuid) ON DELETE CASCADE,
  UNIQUE (product_uuid, location_uuid)
);

CREATE INDEX idx_stock_levels_product ON stock_levels(product_uuid);
CREATE INDEX idx_stock_levels_location ON stock_levels(location_uuid);
CREATE INDEX idx_stock_levels_low ON stock_levels(quantity) WHERE quantity <= 0;

-- ============================================================================
-- SECTION 8: STOCK ADJUSTMENTS (AUDIT TRAIL - SOURCE OF TRUTH FOR STOCK)
-- ============================================================================

CREATE TABLE IF NOT EXISTS stock_adjustments (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  uuid TEXT NOT NULL UNIQUE,
  product_uuid TEXT NOT NULL,
  location_uuid TEXT NOT NULL,
  adjustment_type TEXT NOT NULL CHECK (adjustment_type IN ('purchase', 'issue', 'transfer_in', 'transfer_out', 'wastage', 'return', 'adjustment', 'recipe_consumption')),
  quantity_change REAL NOT NULL, -- positive for IN, negative for OUT
  quantity_before REAL NOT NULL,
  quantity_after REAL NOT NULL,
  unit_id INTEGER NOT NULL,
  conversion_factor REAL DEFAULT 1.0,
  reference_type TEXT, -- 'purchase', 'issue', 'transfer', etc.
  reference_uuid TEXT, -- uuid of related transaction
  reason TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  created_by TEXT NOT NULL,
  notes TEXT,
  FOREIGN KEY (product_uuid) REFERENCES products(uuid) ON DELETE CASCADE,
  FOREIGN KEY (location_uuid) REFERENCES locations(uuid) ON DELETE CASCADE,
  FOREIGN KEY (unit_id) REFERENCES units(id) ON DELETE RESTRICT,
  FOREIGN KEY (created_by) REFERENCES users(uuid) ON DELETE RESTRICT
);

CREATE INDEX idx_stock_adjustments_uuid ON stock_adjustments(uuid);
CREATE INDEX idx_stock_adjustments_product ON stock_adjustments(product_uuid);
CREATE INDEX idx_stock_adjustments_location ON stock_adjustments(location_uuid);
CREATE INDEX idx_stock_adjustments_type ON stock_adjustments(adjustment_type);
CREATE INDEX idx_stock_adjustments_reference ON stock_adjustments(reference_type, reference_uuid);
CREATE INDEX idx_stock_adjustments_created ON stock_adjustments(created_at);

-- ============================================================================
-- SECTION 9: PURCHASES
-- ============================================================================

CREATE TABLE IF NOT EXISTS purchases (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  uuid TEXT NOT NULL UNIQUE,
  purchase_number TEXT NOT NULL UNIQUE,
  supplier_uuid TEXT NOT NULL,
  location_uuid TEXT NOT NULL,
  purchase_date TEXT NOT NULL,
  invoice_number TEXT,
  invoice_date TEXT,
  total_amount REAL NOT NULL DEFAULT 0,
  gst_amount REAL DEFAULT 0,
  grand_total REAL NOT NULL DEFAULT 0,
  status TEXT NOT NULL DEFAULT 'draft' CHECK (status IN ('draft', 'ordered', 'received', 'cancelled')),
  payment_status TEXT DEFAULT 'pending' CHECK (payment_status IN ('pending', 'partial', 'paid')),
  notes TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  last_modified TEXT NOT NULL DEFAULT (datetime('now')),
  created_by TEXT NOT NULL,
  approved_at TEXT,
  approved_by TEXT,
  FOREIGN KEY (supplier_uuid) REFERENCES suppliers(uuid) ON DELETE RESTRICT,
  FOREIGN KEY (location_uuid) REFERENCES locations(uuid) ON DELETE RESTRICT,
  FOREIGN KEY (created_by) REFERENCES users(uuid) ON DELETE RESTRICT,
  FOREIGN KEY (approved_by) REFERENCES users(uuid) ON DELETE SET NULL
);

CREATE INDEX idx_purchases_uuid ON purchases(uuid);
CREATE INDEX idx_purchases_number ON purchases(purchase_number);
CREATE INDEX idx_purchases_supplier ON purchases(supplier_uuid);
CREATE INDEX idx_purchases_status ON purchases(status);
CREATE INDEX idx_purchases_date ON purchases(purchase_date);

CREATE TABLE IF NOT EXISTS purchase_items (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  uuid TEXT NOT NULL UNIQUE,
  purchase_uuid TEXT NOT NULL,
  product_uuid TEXT NOT NULL,
  quantity REAL NOT NULL CHECK (quantity > 0),
  unit_id INTEGER NOT NULL,
  unit_price REAL NOT NULL DEFAULT 0,
  gst_rate REAL DEFAULT 0,
  gst_amount REAL DEFAULT 0,
  total_amount REAL NOT NULL DEFAULT 0,
  notes TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  last_modified TEXT NOT NULL DEFAULT (datetime('now')),
  FOREIGN KEY (purchase_uuid) REFERENCES purchases(uuid) ON DELETE CASCADE,
  FOREIGN KEY (product_uuid) REFERENCES products(uuid) ON DELETE RESTRICT,
  FOREIGN KEY (unit_id) REFERENCES units(id) ON DELETE RESTRICT
);

CREATE INDEX idx_purchase_items_uuid ON purchase_items(uuid);
CREATE INDEX idx_purchase_items_purchase ON purchase_items(purchase_uuid);
CREATE INDEX idx_purchase_items_product ON purchase_items(product_uuid);

-- ============================================================================
-- SECTION 10: ISSUES (STOCK OUT)
-- ============================================================================

CREATE TABLE IF NOT EXISTS issues (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  uuid TEXT NOT NULL UNIQUE,
  issue_number TEXT NOT NULL UNIQUE,
  from_location_uuid TEXT NOT NULL,
  to_location_uuid TEXT,
  issue_date TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'draft' CHECK (status IN ('draft', 'issued', 'cancelled')),
  reason TEXT,
  notes TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  last_modified TEXT NOT NULL DEFAULT (datetime('now')),
  created_by TEXT NOT NULL,
  issued_at TEXT,
  issued_by TEXT,
  FOREIGN KEY (from_location_uuid) REFERENCES locations(uuid) ON DELETE RESTRICT,
  FOREIGN KEY (to_location_uuid) REFERENCES locations(uuid) ON DELETE SET NULL,
  FOREIGN KEY (created_by) REFERENCES users(uuid) ON DELETE RESTRICT,
  FOREIGN KEY (issued_by) REFERENCES users(uuid) ON DELETE SET NULL
);

CREATE INDEX idx_issues_uuid ON issues(uuid);
CREATE INDEX idx_issues_number ON issues(issue_number);
CREATE INDEX idx_issues_from_location ON issues(from_location_uuid);
CREATE INDEX idx_issues_status ON issues(status);
CREATE INDEX idx_issues_date ON issues(issue_date);

CREATE TABLE IF NOT EXISTS issue_items (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  uuid TEXT NOT NULL UNIQUE,
  issue_uuid TEXT NOT NULL,
  product_uuid TEXT NOT NULL,
  quantity REAL NOT NULL CHECK (quantity > 0),
  unit_id INTEGER NOT NULL,
  notes TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  last_modified TEXT NOT NULL DEFAULT (datetime('now')),
  FOREIGN KEY (issue_uuid) REFERENCES issues(uuid) ON DELETE CASCADE,
  FOREIGN KEY (product_uuid) REFERENCES products(uuid) ON DELETE RESTRICT,
  FOREIGN KEY (unit_id) REFERENCES units(id) ON DELETE RESTRICT
);

CREATE INDEX idx_issue_items_uuid ON issue_items(uuid);
CREATE INDEX idx_issue_items_issue ON issue_items(issue_uuid);
CREATE INDEX idx_issue_items_product ON issue_items(product_uuid);

-- ============================================================================
-- SECTION 11: TRANSFERS (INTER-LOCATION)
-- ============================================================================

CREATE TABLE IF NOT EXISTS transfers (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  uuid TEXT NOT NULL UNIQUE,
  transfer_number TEXT NOT NULL UNIQUE,
  from_location_uuid TEXT NOT NULL,
  to_location_uuid TEXT NOT NULL,
  transfer_date TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'draft' CHECK (status IN ('draft', 'in_transit', 'completed', 'cancelled')),
  notes TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  last_modified TEXT NOT NULL DEFAULT (datetime('now')),
  created_by TEXT NOT NULL,
  completed_at TEXT,
  completed_by TEXT,
  FOREIGN KEY (from_location_uuid) REFERENCES locations(uuid) ON DELETE RESTRICT,
  FOREIGN KEY (to_location_uuid) REFERENCES locations(uuid) ON DELETE RESTRICT,
  FOREIGN KEY (created_by) REFERENCES users(uuid) ON DELETE RESTRICT,
  FOREIGN KEY (completed_by) REFERENCES users(uuid) ON DELETE SET NULL,
  CHECK (from_location_uuid != to_location_uuid)
);

CREATE INDEX idx_transfers_uuid ON transfers(uuid);
CREATE INDEX idx_transfers_number ON transfers(transfer_number);
CREATE INDEX idx_transfers_from ON transfers(from_location_uuid);
CREATE INDEX idx_transfers_to ON transfers(to_location_uuid);
CREATE INDEX idx_transfers_status ON transfers(status);

CREATE TABLE IF NOT EXISTS transfer_items (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  uuid TEXT NOT NULL UNIQUE,
  transfer_uuid TEXT NOT NULL,
  product_uuid TEXT NOT NULL,
  quantity REAL NOT NULL CHECK (quantity > 0),
  unit_id INTEGER NOT NULL,
  notes TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  last_modified TEXT NOT NULL DEFAULT (datetime('now')),
  FOREIGN KEY (transfer_uuid) REFERENCES transfers(uuid) ON DELETE CASCADE,
  FOREIGN KEY (product_uuid) REFERENCES products(uuid) ON DELETE RESTRICT,
  FOREIGN KEY (unit_id) REFERENCES units(id) ON DELETE RESTRICT
);

CREATE INDEX idx_transfer_items_uuid ON transfer_items(uuid);
CREATE INDEX idx_transfer_items_transfer ON transfer_items(transfer_uuid);
CREATE INDEX idx_transfer_items_product ON transfer_items(product_uuid);

-- ============================================================================
-- SECTION 12: WASTAGE & RETURNS
-- ============================================================================

CREATE TABLE IF NOT EXISTS wastages (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  uuid TEXT NOT NULL UNIQUE,
  wastage_number TEXT NOT NULL UNIQUE,
  location_uuid TEXT NOT NULL,
  wastage_date TEXT NOT NULL,
  wastage_type TEXT CHECK (wastage_type IN ('damage', 'expiry', 'spoilage', 'other')),
  status TEXT NOT NULL DEFAULT 'draft' CHECK (status IN ('draft', 'approved', 'cancelled')),
  notes TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  last_modified TEXT NOT NULL DEFAULT (datetime('now')),
  created_by TEXT NOT NULL,
  approved_at TEXT,
  approved_by TEXT,
  FOREIGN KEY (location_uuid) REFERENCES locations(uuid) ON DELETE RESTRICT,
  FOREIGN KEY (created_by) REFERENCES users(uuid) ON DELETE RESTRICT,
  FOREIGN KEY (approved_by) REFERENCES users(uuid) ON DELETE SET NULL
);

CREATE INDEX idx_wastages_uuid ON wastages(uuid);
CREATE INDEX idx_wastages_location ON wastages(location_uuid);
CREATE INDEX idx_wastages_status ON wastages(status);

CREATE TABLE IF NOT EXISTS wastage_items (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  uuid TEXT NOT NULL UNIQUE,
  wastage_uuid TEXT NOT NULL,
  product_uuid TEXT NOT NULL,
  quantity REAL NOT NULL CHECK (quantity > 0),
  unit_id INTEGER NOT NULL,
  reason TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  last_modified TEXT NOT NULL DEFAULT (datetime('now')),
  FOREIGN KEY (wastage_uuid) REFERENCES wastages(uuid) ON DELETE CASCADE,
  FOREIGN KEY (product_uuid) REFERENCES products(uuid) ON DELETE RESTRICT,
  FOREIGN KEY (unit_id) REFERENCES units(id) ON DELETE RESTRICT
);

CREATE INDEX idx_wastage_items_uuid ON wastage_items(uuid);
CREATE INDEX idx_wastage_items_wastage ON wastage_items(wastage_uuid);
CREATE INDEX idx_wastage_items_product ON wastage_items(product_uuid);

-- ============================================================================
-- SECTION 13: RECIPES
-- ============================================================================

CREATE TABLE IF NOT EXISTS recipes (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  uuid TEXT NOT NULL UNIQUE,
  name TEXT NOT NULL,
  description TEXT,
  yield_quantity REAL DEFAULT 1,
  yield_unit_id INTEGER,
  preparation_time INTEGER, -- minutes
  cost_price REAL DEFAULT 0,
  selling_price REAL DEFAULT 0,
  is_active INTEGER NOT NULL DEFAULT 1 CHECK (is_active IN (0, 1)),
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  last_modified TEXT NOT NULL DEFAULT (datetime('now')),
  created_by TEXT,
  FOREIGN KEY (yield_unit_id) REFERENCES units(id) ON DELETE SET NULL,
  FOREIGN KEY (created_by) REFERENCES users(uuid) ON DELETE SET NULL
);

CREATE INDEX idx_recipes_uuid ON recipes(uuid);
CREATE INDEX idx_recipes_active ON recipes(is_active) WHERE is_active = 1;

CREATE TABLE IF NOT EXISTS recipe_ingredients (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  uuid TEXT NOT NULL UNIQUE,
  recipe_uuid TEXT NOT NULL,
  product_uuid TEXT NOT NULL,
  quantity REAL NOT NULL CHECK (quantity > 0),
  unit_id INTEGER NOT NULL,
  notes TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  last_modified TEXT NOT NULL DEFAULT (datetime('now')),
  FOREIGN KEY (recipe_uuid) REFERENCES recipes(uuid) ON DELETE CASCADE,
  FOREIGN KEY (product_uuid) REFERENCES products(uuid) ON DELETE RESTRICT,
  FOREIGN KEY (unit_id) REFERENCES units(id) ON DELETE RESTRICT
);

CREATE INDEX idx_recipe_ingredients_uuid ON recipe_ingredients(uuid);
CREATE INDEX idx_recipe_ingredients_recipe ON recipe_ingredients(recipe_uuid);
CREATE INDEX idx_recipe_ingredients_product ON recipe_ingredients(product_uuid);

-- ============================================================================
-- SECTION 14: INVOICES
-- ============================================================================

CREATE TABLE IF NOT EXISTS invoices (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  uuid TEXT NOT NULL UNIQUE,
  invoice_number TEXT NOT NULL UNIQUE,
  invoice_date TEXT NOT NULL,
  customer_name TEXT,
  customer_phone TEXT,
  customer_address TEXT,
  customer_gst TEXT,
  invoice_type TEXT NOT NULL DEFAULT 'cash' CHECK (invoice_type IN ('cash', 'credit')),
  payment_status TEXT NOT NULL DEFAULT 'pending' CHECK (payment_status IN ('pending', 'partial', 'paid')),
  subtotal REAL NOT NULL DEFAULT 0,
  discount_amount REAL DEFAULT 0,
  gst_amount REAL DEFAULT 0,
  grand_total REAL NOT NULL DEFAULT 0,
  notes TEXT,
  status TEXT NOT NULL DEFAULT 'draft' CHECK (status IN ('draft', 'finalized', 'cancelled')),
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  last_modified TEXT NOT NULL DEFAULT (datetime('now')),
  created_by TEXT NOT NULL,
  finalized_at TEXT,
  finalized_by TEXT,
  FOREIGN KEY (created_by) REFERENCES users(uuid) ON DELETE RESTRICT,
  FOREIGN KEY (finalized_by) REFERENCES users(uuid) ON DELETE SET NULL
);

CREATE INDEX idx_invoices_uuid ON invoices(uuid);
CREATE INDEX idx_invoices_number ON invoices(invoice_number);
CREATE INDEX idx_invoices_date ON invoices(invoice_date);
CREATE INDEX idx_invoices_status ON invoices(status);
CREATE INDEX idx_invoices_type ON invoices(invoice_type);

CREATE TABLE IF NOT EXISTS invoice_items (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  uuid TEXT NOT NULL UNIQUE,
  invoice_uuid TEXT NOT NULL,
  product_uuid TEXT NOT NULL,
  quantity REAL NOT NULL CHECK (quantity > 0),
  unit_id INTEGER NOT NULL,
  unit_price REAL NOT NULL DEFAULT 0,
  discount_percent REAL DEFAULT 0 CHECK (discount_percent >= 0 AND discount_percent <= 100),
  discount_amount REAL DEFAULT 0,
  gst_rate REAL DEFAULT 0,
  gst_amount REAL DEFAULT 0,
  total_amount REAL NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  last_modified TEXT NOT NULL DEFAULT (datetime('now')),
  FOREIGN KEY (invoice_uuid) REFERENCES invoices(uuid) ON DELETE CASCADE,
  FOREIGN KEY (product_uuid) REFERENCES products(uuid) ON DELETE RESTRICT,
  FOREIGN KEY (unit_id) REFERENCES units(id) ON DELETE RESTRICT
);

CREATE INDEX idx_invoice_items_uuid ON invoice_items(uuid);
CREATE INDEX idx_invoice_items_invoice ON invoice_items(invoice_uuid);
CREATE INDEX idx_invoice_items_product ON invoice_items(product_uuid);

-- ============================================================================
-- SECTION 15: SYNC INFRASTRUCTURE
-- ============================================================================

CREATE TABLE IF NOT EXISTS sync_queue (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  table_name TEXT NOT NULL,
  operation TEXT NOT NULL CHECK (operation IN ('insert', 'update', 'delete')),
  record_uuid TEXT NOT NULL,
  payload TEXT NOT NULL, -- JSON
  synced INTEGER NOT NULL DEFAULT 0 CHECK (synced IN (0, 1)),
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  synced_at TEXT,
  retry_count INTEGER DEFAULT 0,
  last_error TEXT
);

CREATE INDEX idx_sync_queue_synced ON sync_queue(synced) WHERE synced = 0;
CREATE INDEX idx_sync_queue_table ON sync_queue(table_name);
CREATE INDEX idx_sync_queue_created ON sync_queue(created_at);

CREATE TABLE IF NOT EXISTS conflict_logs (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  table_name TEXT NOT NULL,
  record_uuid TEXT NOT NULL,
  local_payload TEXT NOT NULL, -- JSON
  remote_payload TEXT NOT NULL, -- JSON
  local_last_modified TEXT,
  remote_last_modified TEXT,
  resolution_strategy TEXT, -- 'local_wins', 'remote_wins', 'manual'
  resolved INTEGER NOT NULL DEFAULT 0 CHECK (resolved IN (0, 1)),
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  resolved_at TEXT,
  resolved_by TEXT,
  notes TEXT,
  FOREIGN KEY (resolved_by) REFERENCES users(uuid) ON DELETE SET NULL
);

CREATE INDEX idx_conflict_logs_resolved ON conflict_logs(resolved) WHERE resolved = 0;
CREATE INDEX idx_conflict_logs_table ON conflict_logs(table_name);
CREATE INDEX idx_conflict_logs_created ON conflict_logs(created_at);

-- ============================================================================
-- SECTION 16: AUDIT LOGS
-- ============================================================================

CREATE TABLE IF NOT EXISTS audit_logs (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  table_name TEXT NOT NULL,
  record_uuid TEXT,
  operation TEXT NOT NULL CHECK (operation IN ('insert', 'update', 'delete', 'sync')),
  old_values TEXT, -- JSON
  new_values TEXT, -- JSON
  user_uuid TEXT,
  device_uuid TEXT,
  ip_address TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX idx_audit_logs_table ON audit_logs(table_name);
CREATE INDEX idx_audit_logs_user ON audit_logs(user_uuid);
CREATE INDEX idx_audit_logs_created ON audit_logs(created_at);

-- ============================================================================
-- SECTION 17: ALERTS & NOTIFICATIONS
-- ============================================================================

CREATE TABLE IF NOT EXISTS alerts (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  uuid TEXT NOT NULL UNIQUE,
  alert_type TEXT NOT NULL CHECK (alert_type IN ('low_stock', 'reorder', 'expiry', 'sync_conflict', 'system')),
  severity TEXT NOT NULL CHECK (severity IN ('info', 'warning', 'critical')),
  title TEXT NOT NULL,
  message TEXT NOT NULL,
  reference_type TEXT,
  reference_uuid TEXT,
  is_read INTEGER NOT NULL DEFAULT 0 CHECK (is_read IN (0, 1)),
  is_resolved INTEGER NOT NULL DEFAULT 0 CHECK (is_resolved IN (0, 1)),
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  read_at TEXT,
  resolved_at TEXT,
  resolved_by TEXT,
  FOREIGN KEY (resolved_by) REFERENCES users(uuid) ON DELETE SET NULL
);

CREATE INDEX idx_alerts_uuid ON alerts(uuid);
CREATE INDEX idx_alerts_type ON alerts(alert_type);
CREATE INDEX idx_alerts_unread ON alerts(is_read) WHERE is_read = 0;
CREATE INDEX idx_alerts_unresolved ON alerts(is_resolved) WHERE is_resolved = 0;

-- ============================================================================
-- SECTION 18: COMPANY SETTINGS
-- ============================================================================

CREATE TABLE IF NOT EXISTS company_settings (
  id INTEGER PRIMARY KEY CHECK (id = 1), -- Single row table
  company_name TEXT NOT NULL,
  address TEXT,
  phone TEXT,
  email TEXT,
  gst_number TEXT,
  logo_path TEXT,
  currency TEXT DEFAULT 'INR',
  decimal_places INTEGER DEFAULT 2,
  date_format TEXT DEFAULT 'yyyy-MM-dd',
  time_zone TEXT DEFAULT 'Asia/Kolkata',
  financial_year_start TEXT DEFAULT '04-01', -- MM-DD format
  last_modified TEXT NOT NULL DEFAULT (datetime('now'))
);

-- Insert default settings
INSERT OR IGNORE INTO company_settings (id, company_name) VALUES (1, 'My Hotel');

-- ============================================================================
-- SECTION 19: SEED DATA - BASE UNITS
-- ============================================================================

INSERT OR IGNORE INTO units (uuid, name, abbreviation, unit_type, is_base_unit) VALUES
('unit_kg', 'Kilogram', 'kg', 'weight', 1),
('unit_ltr', 'Liter', 'L', 'volume', 1),
('unit_pcs', 'Pieces', 'pcs', 'count', 1);

INSERT OR IGNORE INTO units (uuid, name, abbreviation, unit_type, is_base_unit) VALUES
('unit_gm', 'Gram', 'g', 'weight', 0),
('unit_ml', 'Milliliter', 'ml', 'volume', 0),
('unit_dz', 'Dozen', 'dz', 'count', 0);

-- Conversion factors
INSERT OR IGNORE INTO unit_conversions (from_unit_id, to_unit_id, conversion_factor) VALUES
((SELECT id FROM units WHERE uuid='unit_gm'), (SELECT id FROM units WHERE uuid='unit_kg'), 0.001),
((SELECT id FROM units WHERE uuid='unit_kg'), (SELECT id FROM units WHERE uuid='unit_gm'), 1000),
((SELECT id FROM units WHERE uuid='unit_ml'), (SELECT id FROM units WHERE uuid='unit_ltr'), 0.001),
((SELECT id FROM units WHERE uuid='unit_ltr'), (SELECT id FROM units WHERE uuid='unit_ml'), 1000),
((SELECT id FROM units WHERE uuid='unit_dz'), (SELECT id FROM units WHERE uuid='unit_pcs'), 12),
((SELECT id FROM units WHERE uuid='unit_pcs'), (SELECT id FROM units WHERE uuid='unit_dz'), 0.083333);

-- ============================================================================
-- SECTION 20: SEED DATA - DEFAULT USER
-- ============================================================================

-- Default admin user (password: admin123 - MUST BE CHANGED IN PRODUCTION)
-- bcrypt hash for 'admin123': $2b$10$rKvEJQZxJZh0e7nD5W3j0.Kq6yh7nPYxIqXJ0xQHzxqFzJKQfQZYG
INSERT OR IGNORE INTO users (uuid, username, password_hash, full_name, role, is_active) VALUES
('user_admin', 'admin', '$2b$10$rKvEJQZxJZh0e7nD5W3j0.Kq6yh7nPYxIqXJ0xQHzxqFzJKQfQZYG', 'System Administrator', 'admin', 1);

-- ============================================================================
-- SECTION 21: SEED DATA - DEFAULT LOCATION
-- ============================================================================

INSERT OR IGNORE INTO locations (uuid, name, location_type) VALUES
('loc_main', 'Main Warehouse', 'warehouse');

-- ============================================================================
-- END OF INITIAL SCHEMA
-- ============================================================================

-- Verification queries
-- Run these after applying schema:
-- SELECT COUNT(*) FROM sqlite_master WHERE type='table';
-- SELECT COUNT(*) FROM sqlite_master WHERE type='index';
-- PRAGMA foreign_key_check;
-- PRAGMA integrity_check;
