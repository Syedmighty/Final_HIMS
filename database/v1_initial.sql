-- ============================================================================
-- HOTEL INVENTORY MANAGEMENT SYSTEM (HIMS) - DATABASE SCHEMA v1.0
-- ============================================================================
-- Description: Complete SQLite schema for offline-first hotel inventory
-- Features: Stock tracking, recipes, sync, audit trails, batch management
-- Created: 2025-11-11
-- Compatible with: SQLite 3.35+
-- ============================================================================

PRAGMA foreign_keys = ON;
PRAGMA journal_mode = WAL; -- Write-Ahead Logging for better concurrency
PRAGMA synchronous = NORMAL;
PRAGMA temp_store = MEMORY;
PRAGMA mmap_size = 30000000000;

-- ============================================================================
-- SECTION 1: SCHEMA METADATA & VERSIONING
-- ============================================================================

CREATE TABLE schema_migrations (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  version TEXT NOT NULL UNIQUE,
  description TEXT NOT NULL,
  applied_at TEXT NOT NULL DEFAULT (datetime('now')),
  checksum TEXT
);

-- Initial schema version
INSERT INTO schema_migrations (version, description, checksum)
VALUES ('1.0.0', 'Initial schema with all core tables', 'SHA256_PLACEHOLDER');

-- ============================================================================
-- SECTION 2: MASTER DATA TABLES (Foundation)
-- ============================================================================

-- --------------------
-- 2.1 UNITS TABLE
-- --------------------
-- Defines measurement units (kg, litre, pieces, dozen, etc.)
CREATE TABLE units (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  uuid TEXT NOT NULL UNIQUE DEFAULT (hex(randomblob(16))),
  name TEXT NOT NULL UNIQUE,
  abbreviation TEXT NOT NULL UNIQUE,
  unit_type TEXT CHECK (unit_type IN ('weight', 'volume', 'count', 'length')) NOT NULL,
  is_active INTEGER DEFAULT 1 CHECK (is_active IN (0, 1)),
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  last_modified TEXT NOT NULL DEFAULT (datetime('now')),
  created_by TEXT,
  modified_by TEXT,
  deleted_at TEXT,
  deleted_by TEXT
);

CREATE INDEX idx_units_uuid ON units(uuid);
CREATE INDEX idx_units_active ON units(is_active) WHERE is_active = 1;

-- --------------------
-- 2.2 CATEGORIES TABLE
-- --------------------
-- Product groupings (Meat, Vegetables, Spices, Beverages, etc.)
CREATE TABLE categories (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  uuid TEXT NOT NULL UNIQUE DEFAULT (hex(randomblob(16))),
  name TEXT NOT NULL UNIQUE,
  description TEXT,
  parent_category_id INTEGER,
  is_active INTEGER DEFAULT 1 CHECK (is_active IN (0, 1)),
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  last_modified TEXT NOT NULL DEFAULT (datetime('now')),
  created_by TEXT,
  modified_by TEXT,
  deleted_at TEXT,
  deleted_by TEXT,
  FOREIGN KEY (parent_category_id) REFERENCES categories(id) ON DELETE SET NULL
);

CREATE INDEX idx_categories_uuid ON categories(uuid);
CREATE INDEX idx_categories_parent ON categories(parent_category_id);
CREATE INDEX idx_categories_active ON categories(is_active) WHERE is_active = 1;

-- --------------------
-- 2.3 SUPPLIERS TABLE
-- --------------------
-- Vendor information
CREATE TABLE suppliers (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  uuid TEXT NOT NULL UNIQUE DEFAULT (hex(randomblob(16))),
  name TEXT NOT NULL,
  contact_person TEXT,
  phone TEXT,
  email TEXT,
  address TEXT,
  gstin TEXT, -- GST Identification Number
  credit_limit REAL DEFAULT 0 CHECK (credit_limit >= 0),
  credit_days INTEGER DEFAULT 0 CHECK (credit_days >= 0),
  is_active INTEGER DEFAULT 1 CHECK (is_active IN (0, 1)),
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  last_modified TEXT NOT NULL DEFAULT (datetime('now')),
  created_by TEXT,
  modified_by TEXT,
  deleted_at TEXT,
  deleted_by TEXT
);

CREATE INDEX idx_suppliers_uuid ON suppliers(uuid);
CREATE INDEX idx_suppliers_name ON suppliers(name);
CREATE INDEX idx_suppliers_active ON suppliers(is_active) WHERE is_active = 1;

-- --------------------
-- 2.4 LOCATIONS TABLE
-- --------------------
-- Storage areas and kitchens (Main Store, Chinese Kitchen, Tandoor Section, etc.)
CREATE TABLE locations (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  uuid TEXT NOT NULL UNIQUE DEFAULT (hex(randomblob(16))),
  name TEXT NOT NULL UNIQUE,
  location_type TEXT CHECK (location_type IN ('store', 'kitchen', 'bar', 'other')) NOT NULL,
  description TEXT,
  is_active INTEGER DEFAULT 1 CHECK (is_active IN (0, 1)),
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  last_modified TEXT NOT NULL DEFAULT (datetime('now')),
  created_by TEXT,
  modified_by TEXT,
  deleted_at TEXT,
  deleted_by TEXT
);

CREATE INDEX idx_locations_uuid ON locations(uuid);
CREATE INDEX idx_locations_type ON locations(location_type);
CREATE INDEX idx_locations_active ON locations(is_active) WHERE is_active = 1;

-- --------------------
-- 2.5 ROLES TABLE (RBAC)
-- --------------------
-- User roles and permissions
CREATE TABLE roles (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  uuid TEXT NOT NULL UNIQUE DEFAULT (hex(randomblob(16))),
  name TEXT NOT NULL UNIQUE,
  description TEXT,
  permissions_json TEXT NOT NULL DEFAULT '{}', -- JSON array of permissions
  is_active INTEGER DEFAULT 1 CHECK (is_active IN (0, 1)),
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  last_modified TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX idx_roles_uuid ON roles(uuid);
CREATE INDEX idx_roles_active ON roles(is_active) WHERE is_active = 1;

-- Seed default roles
INSERT INTO roles (name, description, permissions_json) VALUES
  ('Admin', 'Full system access', '["all"]'),
  ('Store Manager', 'Manage purchases and stock', '["purchases.create", "purchases.view", "stock.view", "stock.adjust"]'),
  ('Chef', 'View recipes and request items', '["issues.request", "recipes.view", "stock.view"]'),
  ('Accountant', 'View reports and audit logs', '["reports.view", "audit.view"]');

-- --------------------
-- 2.6 USERS TABLE
-- --------------------
-- Staff members with login credentials
CREATE TABLE users (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  uuid TEXT NOT NULL UNIQUE DEFAULT (hex(randomblob(16))),
  username TEXT NOT NULL UNIQUE,
  password_hash TEXT NOT NULL, -- Bcrypt/Argon2 hash
  full_name TEXT NOT NULL,
  email TEXT,
  phone TEXT,
  is_active INTEGER DEFAULT 1 CHECK (is_active IN (0, 1)),
  last_login TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  last_modified TEXT NOT NULL DEFAULT (datetime('now')),
  created_by TEXT,
  modified_by TEXT,
  deleted_at TEXT,
  deleted_by TEXT
);

CREATE INDEX idx_users_uuid ON users(uuid);
CREATE INDEX idx_users_username ON users(username);
CREATE INDEX idx_users_active ON users(is_active) WHERE is_active = 1;

-- --------------------
-- 2.7 USER_ROLES TABLE (Junction)
-- --------------------
-- Many-to-many relationship between users and roles
CREATE TABLE user_roles (
  user_uuid TEXT NOT NULL,
  role_id INTEGER NOT NULL,
  assigned_at TEXT NOT NULL DEFAULT (datetime('now')),
  assigned_by TEXT,
  PRIMARY KEY (user_uuid, role_id),
  FOREIGN KEY (user_uuid) REFERENCES users(uuid) ON DELETE CASCADE,
  FOREIGN KEY (role_id) REFERENCES roles(id) ON DELETE CASCADE
);

CREATE INDEX idx_user_roles_user ON user_roles(user_uuid);
CREATE INDEX idx_user_roles_role ON user_roles(role_id);

-- --------------------
-- 2.8 PRODUCTS TABLE
-- --------------------
-- Items purchased and used (Chicken, Oil, Rice, etc.)
CREATE TABLE products (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  uuid TEXT NOT NULL UNIQUE DEFAULT (hex(randomblob(16))),
  name TEXT NOT NULL,
  sku TEXT UNIQUE, -- Stock Keeping Unit
  category_id INTEGER,
  default_unit_id INTEGER NOT NULL,
  base_unit_id INTEGER NOT NULL, -- Base unit for all calculations
  description TEXT,
  reorder_level REAL DEFAULT 0 CHECK (reorder_level >= 0),
  reorder_quantity REAL DEFAULT 0 CHECK (reorder_quantity >= 0),
  hsn_code TEXT, -- Harmonized System Nomenclature (for GST)
  tax_rate REAL DEFAULT 0 CHECK (tax_rate >= 0 AND tax_rate <= 100),
  is_active INTEGER DEFAULT 1 CHECK (is_active IN (0, 1)),
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  last_modified TEXT NOT NULL DEFAULT (datetime('now')),
  created_by TEXT,
  modified_by TEXT,
  deleted_at TEXT,
  deleted_by TEXT,
  FOREIGN KEY (category_id) REFERENCES categories(id) ON DELETE SET NULL,
  FOREIGN KEY (default_unit_id) REFERENCES units(id) ON DELETE RESTRICT,
  FOREIGN KEY (base_unit_id) REFERENCES units(id) ON DELETE RESTRICT
);

CREATE INDEX idx_products_uuid ON products(uuid);
CREATE INDEX idx_products_name ON products(name);
CREATE INDEX idx_products_sku ON products(sku);
CREATE INDEX idx_products_category ON products(category_id);
CREATE INDEX idx_products_active ON products(is_active) WHERE is_active = 1;

-- --------------------
-- 2.9 UNIT CONVERSIONS TABLE
-- --------------------
-- Product-specific unit conversions (e.g., "1 kg chicken = 4 pieces")
CREATE TABLE unit_conversions (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  uuid TEXT NOT NULL UNIQUE DEFAULT (hex(randomblob(16))),
  product_uuid TEXT NOT NULL,
  from_unit_id INTEGER NOT NULL,
  to_unit_id INTEGER NOT NULL,
  conversion_factor REAL NOT NULL CHECK (conversion_factor > 0),
  is_active INTEGER DEFAULT 1 CHECK (is_active IN (0, 1)),
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  last_modified TEXT NOT NULL DEFAULT (datetime('now')),
  created_by TEXT,
  modified_by TEXT,
  FOREIGN KEY (product_uuid) REFERENCES products(uuid) ON DELETE CASCADE,
  FOREIGN KEY (from_unit_id) REFERENCES units(id) ON DELETE RESTRICT,
  FOREIGN KEY (to_unit_id) REFERENCES units(id) ON DELETE RESTRICT,
  UNIQUE (product_uuid, from_unit_id, to_unit_id)
);

CREATE INDEX idx_unit_conversions_product ON unit_conversions(product_uuid);
CREATE INDEX idx_unit_conversions_from_unit ON unit_conversions(from_unit_id);
CREATE INDEX idx_unit_conversions_to_unit ON unit_conversions(to_unit_id);

-- --------------------
-- 2.10 PRODUCT BATCHES TABLE
-- --------------------
-- Batch/lot tracking for expiry management
CREATE TABLE product_batches (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  uuid TEXT NOT NULL UNIQUE DEFAULT (hex(randomblob(16))),
  product_uuid TEXT NOT NULL,
  batch_number TEXT NOT NULL,
  location_id INTEGER NOT NULL,
  quantity REAL NOT NULL DEFAULT 0 CHECK (quantity >= 0),
  unit_id INTEGER NOT NULL,
  received_date TEXT NOT NULL DEFAULT (date('now')),
  expiry_date TEXT,
  manufacturing_date TEXT,
  mrp REAL CHECK (mrp >= 0),
  cost_per_unit REAL CHECK (cost_per_unit >= 0),
  supplier_id INTEGER,
  is_active INTEGER DEFAULT 1 CHECK (is_active IN (0, 1)),
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  last_modified TEXT NOT NULL DEFAULT (datetime('now')),
  created_by TEXT,
  modified_by TEXT,
  FOREIGN KEY (product_uuid) REFERENCES products(uuid) ON DELETE CASCADE,
  FOREIGN KEY (location_id) REFERENCES locations(id) ON DELETE RESTRICT,
  FOREIGN KEY (unit_id) REFERENCES units(id) ON DELETE RESTRICT,
  FOREIGN KEY (supplier_id) REFERENCES suppliers(id) ON DELETE SET NULL,
  UNIQUE (product_uuid, batch_number, location_id)
);

CREATE INDEX idx_product_batches_product ON product_batches(product_uuid);
CREATE INDEX idx_product_batches_location ON product_batches(location_id);
CREATE INDEX idx_product_batches_expiry ON product_batches(expiry_date);
CREATE INDEX idx_product_batches_received ON product_batches(received_date);

-- ============================================================================
-- SECTION 3: TRANSACTION TABLES (Daily Operations)
-- ============================================================================

-- --------------------
-- 3.1 PURCHASES TABLE
-- --------------------
-- Purchase orders/invoices
CREATE TABLE purchases (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  uuid TEXT NOT NULL UNIQUE DEFAULT (hex(randomblob(16))),
  purchase_number TEXT NOT NULL UNIQUE,
  supplier_id INTEGER NOT NULL,
  location_id INTEGER NOT NULL, -- Receiving location
  purchase_date TEXT NOT NULL DEFAULT (date('now')),
  invoice_number TEXT,
  invoice_date TEXT,
  total_amount REAL NOT NULL DEFAULT 0 CHECK (total_amount >= 0),
  tax_amount REAL DEFAULT 0 CHECK (tax_amount >= 0),
  discount_amount REAL DEFAULT 0 CHECK (discount_amount >= 0),
  net_amount REAL NOT NULL DEFAULT 0 CHECK (net_amount >= 0),
  payment_status TEXT CHECK (payment_status IN ('pending', 'partial', 'paid')) DEFAULT 'pending',
  payment_due_date TEXT,
  notes TEXT,
  status TEXT CHECK (status IN ('draft', 'approved', 'received', 'cancelled')) DEFAULT 'draft',
  approved_by TEXT,
  approved_at TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  last_modified TEXT NOT NULL DEFAULT (datetime('now')),
  created_by TEXT NOT NULL,
  modified_by TEXT,
  deleted_at TEXT,
  deleted_by TEXT,
  FOREIGN KEY (supplier_id) REFERENCES suppliers(id) ON DELETE RESTRICT,
  FOREIGN KEY (location_id) REFERENCES locations(id) ON DELETE RESTRICT,
  FOREIGN KEY (created_by) REFERENCES users(uuid) ON DELETE RESTRICT,
  FOREIGN KEY (approved_by) REFERENCES users(uuid) ON DELETE RESTRICT
);

CREATE INDEX idx_purchases_uuid ON purchases(uuid);
CREATE INDEX idx_purchases_number ON purchases(purchase_number);
CREATE INDEX idx_purchases_supplier ON purchases(supplier_id);
CREATE INDEX idx_purchases_location ON purchases(location_id);
CREATE INDEX idx_purchases_date ON purchases(purchase_date);
CREATE INDEX idx_purchases_status ON purchases(status);
CREATE INDEX idx_purchases_created_by ON purchases(created_by);

-- --------------------
-- 3.2 PURCHASE LINE ITEMS TABLE
-- --------------------
-- Individual items in a purchase
CREATE TABLE purchase_line_items (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  uuid TEXT NOT NULL UNIQUE DEFAULT (hex(randomblob(16))),
  purchase_id INTEGER NOT NULL,
  product_uuid TEXT NOT NULL,
  batch_uuid TEXT, -- Link to product_batches
  quantity REAL NOT NULL CHECK (quantity > 0),
  unit_id INTEGER NOT NULL,
  unit_price REAL NOT NULL CHECK (unit_price >= 0),
  tax_rate REAL DEFAULT 0 CHECK (tax_rate >= 0 AND tax_rate <= 100),
  tax_amount REAL DEFAULT 0 CHECK (tax_amount >= 0),
  discount_amount REAL DEFAULT 0 CHECK (discount_amount >= 0),
  line_total REAL NOT NULL CHECK (line_total >= 0),
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  last_modified TEXT NOT NULL DEFAULT (datetime('now')),
  FOREIGN KEY (purchase_id) REFERENCES purchases(id) ON DELETE CASCADE,
  FOREIGN KEY (product_uuid) REFERENCES products(uuid) ON DELETE RESTRICT,
  FOREIGN KEY (batch_uuid) REFERENCES product_batches(uuid) ON DELETE SET NULL,
  FOREIGN KEY (unit_id) REFERENCES units(id) ON DELETE RESTRICT
);

CREATE INDEX idx_purchase_line_items_uuid ON purchase_line_items(uuid);
CREATE INDEX idx_purchase_line_items_purchase ON purchase_line_items(purchase_id);
CREATE INDEX idx_purchase_line_items_product ON purchase_line_items(product_uuid);
CREATE INDEX idx_purchase_line_items_batch ON purchase_line_items(batch_uuid);

-- --------------------
-- 3.3 ISSUES TABLE
-- --------------------
-- Stock issued to kitchens/departments
CREATE TABLE issues (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  uuid TEXT NOT NULL UNIQUE DEFAULT (hex(randomblob(16))),
  issue_number TEXT NOT NULL UNIQUE,
  from_location_id INTEGER NOT NULL,
  to_location_id INTEGER NOT NULL,
  issue_date TEXT NOT NULL DEFAULT (date('now')),
  requested_by TEXT,
  issued_by TEXT NOT NULL,
  notes TEXT,
  status TEXT CHECK (status IN ('pending', 'approved', 'issued', 'cancelled')) DEFAULT 'pending',
  approved_by TEXT,
  approved_at TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  last_modified TEXT NOT NULL DEFAULT (datetime('now')),
  created_by TEXT NOT NULL,
  modified_by TEXT,
  deleted_at TEXT,
  deleted_by TEXT,
  FOREIGN KEY (from_location_id) REFERENCES locations(id) ON DELETE RESTRICT,
  FOREIGN KEY (to_location_id) REFERENCES locations(id) ON DELETE RESTRICT,
  FOREIGN KEY (requested_by) REFERENCES users(uuid) ON DELETE RESTRICT,
  FOREIGN KEY (issued_by) REFERENCES users(uuid) ON DELETE RESTRICT,
  FOREIGN KEY (approved_by) REFERENCES users(uuid) ON DELETE RESTRICT,
  FOREIGN KEY (created_by) REFERENCES users(uuid) ON DELETE RESTRICT,
  CHECK (from_location_id != to_location_id)
);

CREATE INDEX idx_issues_uuid ON issues(uuid);
CREATE INDEX idx_issues_number ON issues(issue_number);
CREATE INDEX idx_issues_from_location ON issues(from_location_id);
CREATE INDEX idx_issues_to_location ON issues(to_location_id);
CREATE INDEX idx_issues_date ON issues(issue_date);
CREATE INDEX idx_issues_status ON issues(status);
CREATE INDEX idx_issues_created_by ON issues(created_by);

-- --------------------
-- 3.4 ISSUE LINE ITEMS TABLE
-- --------------------
-- Individual items in an issue
CREATE TABLE issue_line_items (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  uuid TEXT NOT NULL UNIQUE DEFAULT (hex(randomblob(16))),
  issue_id INTEGER NOT NULL,
  product_uuid TEXT NOT NULL,
  batch_uuid TEXT,
  quantity REAL NOT NULL CHECK (quantity > 0),
  unit_id INTEGER NOT NULL,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  last_modified TEXT NOT NULL DEFAULT (datetime('now')),
  FOREIGN KEY (issue_id) REFERENCES issues(id) ON DELETE CASCADE,
  FOREIGN KEY (product_uuid) REFERENCES products(uuid) ON DELETE RESTRICT,
  FOREIGN KEY (batch_uuid) REFERENCES product_batches(uuid) ON DELETE SET NULL,
  FOREIGN KEY (unit_id) REFERENCES units(id) ON DELETE RESTRICT
);

CREATE INDEX idx_issue_line_items_uuid ON issue_line_items(uuid);
CREATE INDEX idx_issue_line_items_issue ON issue_line_items(issue_id);
CREATE INDEX idx_issue_line_items_product ON issue_line_items(product_uuid);
CREATE INDEX idx_issue_line_items_batch ON issue_line_items(batch_uuid);

-- --------------------
-- 3.5 WASTAGE/RETURNS TABLE
-- --------------------
-- Track spoilage, damage, and returns
CREATE TABLE wastage_returns (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  uuid TEXT NOT NULL UNIQUE DEFAULT (hex(randomblob(16))),
  transaction_number TEXT NOT NULL UNIQUE,
  transaction_type TEXT CHECK (transaction_type IN ('wastage', 'return_to_supplier', 'return_from_kitchen')) NOT NULL,
  product_uuid TEXT NOT NULL,
  batch_uuid TEXT,
  location_id INTEGER NOT NULL,
  quantity REAL NOT NULL CHECK (quantity > 0),
  unit_id INTEGER NOT NULL,
  reason TEXT NOT NULL,
  transaction_date TEXT NOT NULL DEFAULT (date('now')),
  reported_by TEXT NOT NULL,
  approved_by TEXT,
  approved_at TEXT,
  notes TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  last_modified TEXT NOT NULL DEFAULT (datetime('now')),
  created_by TEXT NOT NULL,
  modified_by TEXT,
  deleted_at TEXT,
  deleted_by TEXT,
  FOREIGN KEY (product_uuid) REFERENCES products(uuid) ON DELETE RESTRICT,
  FOREIGN KEY (batch_uuid) REFERENCES product_batches(uuid) ON DELETE SET NULL,
  FOREIGN KEY (location_id) REFERENCES locations(id) ON DELETE RESTRICT,
  FOREIGN KEY (unit_id) REFERENCES units(id) ON DELETE RESTRICT,
  FOREIGN KEY (reported_by) REFERENCES users(uuid) ON DELETE RESTRICT,
  FOREIGN KEY (approved_by) REFERENCES users(uuid) ON DELETE RESTRICT,
  FOREIGN KEY (created_by) REFERENCES users(uuid) ON DELETE RESTRICT
);

CREATE INDEX idx_wastage_returns_uuid ON wastage_returns(uuid);
CREATE INDEX idx_wastage_returns_number ON wastage_returns(transaction_number);
CREATE INDEX idx_wastage_returns_type ON wastage_returns(transaction_type);
CREATE INDEX idx_wastage_returns_product ON wastage_returns(product_uuid);
CREATE INDEX idx_wastage_returns_location ON wastage_returns(location_id);
CREATE INDEX idx_wastage_returns_date ON wastage_returns(transaction_date);

-- --------------------
-- 3.6 STOCK TRANSFERS TABLE
-- --------------------
-- Move stock between locations
CREATE TABLE stock_transfers (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  uuid TEXT NOT NULL UNIQUE DEFAULT (hex(randomblob(16))),
  transfer_number TEXT NOT NULL UNIQUE,
  from_location_id INTEGER NOT NULL,
  to_location_id INTEGER NOT NULL,
  transfer_date TEXT NOT NULL DEFAULT (date('now')),
  initiated_by TEXT NOT NULL,
  approved_by TEXT,
  approved_at TEXT,
  notes TEXT,
  status TEXT CHECK (status IN ('pending', 'in_transit', 'completed', 'cancelled')) DEFAULT 'pending',
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  last_modified TEXT NOT NULL DEFAULT (datetime('now')),
  created_by TEXT NOT NULL,
  modified_by TEXT,
  deleted_at TEXT,
  deleted_by TEXT,
  FOREIGN KEY (from_location_id) REFERENCES locations(id) ON DELETE RESTRICT,
  FOREIGN KEY (to_location_id) REFERENCES locations(id) ON DELETE RESTRICT,
  FOREIGN KEY (initiated_by) REFERENCES users(uuid) ON DELETE RESTRICT,
  FOREIGN KEY (approved_by) REFERENCES users(uuid) ON DELETE RESTRICT,
  FOREIGN KEY (created_by) REFERENCES users(uuid) ON DELETE RESTRICT,
  CHECK (from_location_id != to_location_id)
);

CREATE INDEX idx_stock_transfers_uuid ON stock_transfers(uuid);
CREATE INDEX idx_stock_transfers_number ON stock_transfers(transfer_number);
CREATE INDEX idx_stock_transfers_from_location ON stock_transfers(from_location_id);
CREATE INDEX idx_stock_transfers_to_location ON stock_transfers(to_location_id);
CREATE INDEX idx_stock_transfers_date ON stock_transfers(transfer_date);
CREATE INDEX idx_stock_transfers_status ON stock_transfers(status);

-- --------------------
-- 3.7 STOCK TRANSFER ITEMS TABLE
-- --------------------
-- Line items for stock transfers
CREATE TABLE stock_transfer_items (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  uuid TEXT NOT NULL UNIQUE DEFAULT (hex(randomblob(16))),
  transfer_id INTEGER NOT NULL,
  product_uuid TEXT NOT NULL,
  batch_uuid TEXT,
  quantity REAL NOT NULL CHECK (quantity > 0),
  unit_id INTEGER NOT NULL,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  last_modified TEXT NOT NULL DEFAULT (datetime('now')),
  FOREIGN KEY (transfer_id) REFERENCES stock_transfers(id) ON DELETE CASCADE,
  FOREIGN KEY (product_uuid) REFERENCES products(uuid) ON DELETE RESTRICT,
  FOREIGN KEY (batch_uuid) REFERENCES product_batches(uuid) ON DELETE SET NULL,
  FOREIGN KEY (unit_id) REFERENCES units(id) ON DELETE RESTRICT
);

CREATE INDEX idx_stock_transfer_items_uuid ON stock_transfer_items(uuid);
CREATE INDEX idx_stock_transfer_items_transfer ON stock_transfer_items(transfer_id);
CREATE INDEX idx_stock_transfer_items_product ON stock_transfer_items(product_uuid);

-- ============================================================================
-- SECTION 4: ANALYTICS & REPORTING TABLES
-- ============================================================================

-- --------------------
-- 4.1 STOCK LEVELS TABLE
-- --------------------
-- Current stock quantity per product per location
CREATE TABLE stock_levels (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  product_uuid TEXT NOT NULL,
  location_id INTEGER NOT NULL,
  quantity REAL NOT NULL DEFAULT 0 CHECK (quantity >= 0),
  unit_id INTEGER NOT NULL,
  last_updated TEXT NOT NULL DEFAULT (datetime('now')),
  updated_by TEXT,
  FOREIGN KEY (product_uuid) REFERENCES products(uuid) ON DELETE CASCADE,
  FOREIGN KEY (location_id) REFERENCES locations(id) ON DELETE CASCADE,
  FOREIGN KEY (unit_id) REFERENCES units(id) ON DELETE RESTRICT,
  UNIQUE (product_uuid, location_id)
);

CREATE INDEX idx_stock_levels_product ON stock_levels(product_uuid);
CREATE INDEX idx_stock_levels_location ON stock_levels(location_id);
CREATE INDEX idx_stock_levels_updated ON stock_levels(last_updated);

-- --------------------
-- 4.2 STOCK ADJUSTMENTS TABLE
-- --------------------
-- Audit log of all stock movements
CREATE TABLE stock_adjustments (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  uuid TEXT NOT NULL UNIQUE DEFAULT (hex(randomblob(16))),
  product_uuid TEXT NOT NULL,
  location_id INTEGER NOT NULL,
  adjustment_type TEXT CHECK (adjustment_type IN ('purchase', 'issue', 'wastage', 'return', 'transfer_in', 'transfer_out', 'manual')) NOT NULL,
  quantity_change REAL NOT NULL, -- Can be positive or negative
  quantity_before REAL NOT NULL,
  quantity_after REAL NOT NULL,
  unit_id INTEGER NOT NULL,
  reference_type TEXT, -- 'purchase', 'issue', 'transfer', etc.
  reference_id INTEGER, -- ID of related transaction
  reason TEXT,
  adjustment_date TEXT NOT NULL DEFAULT (datetime('now')),
  adjusted_by TEXT NOT NULL,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  FOREIGN KEY (product_uuid) REFERENCES products(uuid) ON DELETE RESTRICT,
  FOREIGN KEY (location_id) REFERENCES locations(id) ON DELETE RESTRICT,
  FOREIGN KEY (unit_id) REFERENCES units(id) ON DELETE RESTRICT,
  FOREIGN KEY (adjusted_by) REFERENCES users(uuid) ON DELETE RESTRICT
);

CREATE INDEX idx_stock_adjustments_uuid ON stock_adjustments(uuid);
CREATE INDEX idx_stock_adjustments_product ON stock_adjustments(product_uuid);
CREATE INDEX idx_stock_adjustments_location ON stock_adjustments(location_id);
CREATE INDEX idx_stock_adjustments_type ON stock_adjustments(adjustment_type);
CREATE INDEX idx_stock_adjustments_date ON stock_adjustments(adjustment_date);
CREATE INDEX idx_stock_adjustments_reference ON stock_adjustments(reference_type, reference_id);

-- --------------------
-- 4.3 STOCK ALERTS TABLE
-- --------------------
-- Automated alerts for low stock and expiring items
CREATE TABLE stock_alerts (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  uuid TEXT NOT NULL UNIQUE DEFAULT (hex(randomblob(16))),
  alert_type TEXT CHECK (alert_type IN ('reorder', 'expiry', 'overstock')) NOT NULL,
  product_uuid TEXT NOT NULL,
  location_id INTEGER,
  batch_uuid TEXT,
  threshold_value REAL,
  current_value REAL NOT NULL,
  severity TEXT CHECK (severity IN ('low', 'medium', 'high', 'critical')) DEFAULT 'medium',
  message TEXT NOT NULL,
  triggered_at TEXT NOT NULL DEFAULT (datetime('now')),
  resolved INTEGER DEFAULT 0 CHECK (resolved IN (0, 1)),
  resolved_at TEXT,
  resolved_by TEXT,
  notes TEXT,
  FOREIGN KEY (product_uuid) REFERENCES products(uuid) ON DELETE CASCADE,
  FOREIGN KEY (location_id) REFERENCES locations(id) ON DELETE CASCADE,
  FOREIGN KEY (batch_uuid) REFERENCES product_batches(uuid) ON DELETE CASCADE,
  FOREIGN KEY (resolved_by) REFERENCES users(uuid) ON DELETE SET NULL
);

CREATE INDEX idx_stock_alerts_uuid ON stock_alerts(uuid);
CREATE INDEX idx_stock_alerts_type ON stock_alerts(alert_type);
CREATE INDEX idx_stock_alerts_product ON stock_alerts(product_uuid);
CREATE INDEX idx_stock_alerts_resolved ON stock_alerts(resolved);
CREATE INDEX idx_stock_alerts_triggered ON stock_alerts(triggered_at);
CREATE INDEX idx_stock_alerts_severity ON stock_alerts(severity);

-- --------------------
-- 4.4 RECIPES TABLE
-- --------------------
-- Dish recipes with ingredients
CREATE TABLE recipes (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  uuid TEXT NOT NULL UNIQUE DEFAULT (hex(randomblob(16))),
  name TEXT NOT NULL UNIQUE,
  description TEXT,
  category TEXT, -- Appetizer, Main Course, Dessert, etc.
  serving_size TEXT,
  preparation_time INTEGER, -- in minutes
  cooking_time INTEGER, -- in minutes
  cost_per_serving REAL DEFAULT 0 CHECK (cost_per_serving >= 0),
  selling_price REAL CHECK (selling_price >= 0),
  profit_margin REAL GENERATED ALWAYS AS (
    CASE
      WHEN selling_price > 0 THEN ((selling_price - cost_per_serving) / selling_price * 100)
      ELSE 0
    END
  ) VIRTUAL,
  is_active INTEGER DEFAULT 1 CHECK (is_active IN (0, 1)),
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  last_modified TEXT NOT NULL DEFAULT (datetime('now')),
  created_by TEXT,
  modified_by TEXT,
  deleted_at TEXT,
  deleted_by TEXT
);

CREATE INDEX idx_recipes_uuid ON recipes(uuid);
CREATE INDEX idx_recipes_name ON recipes(name);
CREATE INDEX idx_recipes_category ON recipes(category);
CREATE INDEX idx_recipes_active ON recipes(is_active) WHERE is_active = 1;

-- --------------------
-- 4.5 RECIPE INGREDIENTS TABLE
-- --------------------
-- Ingredients required for each recipe
CREATE TABLE recipe_ingredients (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  uuid TEXT NOT NULL UNIQUE DEFAULT (hex(randomblob(16))),
  recipe_id INTEGER NOT NULL,
  product_uuid TEXT NOT NULL,
  quantity REAL NOT NULL CHECK (quantity > 0),
  unit_id INTEGER NOT NULL,
  notes TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  last_modified TEXT NOT NULL DEFAULT (datetime('now')),
  FOREIGN KEY (recipe_id) REFERENCES recipes(id) ON DELETE CASCADE,
  FOREIGN KEY (product_uuid) REFERENCES products(uuid) ON DELETE RESTRICT,
  FOREIGN KEY (unit_id) REFERENCES units(id) ON DELETE RESTRICT
);

CREATE INDEX idx_recipe_ingredients_uuid ON recipe_ingredients(uuid);
CREATE INDEX idx_recipe_ingredients_recipe ON recipe_ingredients(recipe_id);
CREATE INDEX idx_recipe_ingredients_product ON recipe_ingredients(product_uuid);

-- ============================================================================
-- SECTION 5: SYNC & AUDIT TABLES
-- ============================================================================

-- --------------------
-- 5.1 SYNC QUEUE TABLE
-- --------------------
-- Tracks pending sync operations for LAN sync
CREATE TABLE sync_queue (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  table_name TEXT NOT NULL,
  record_uuid TEXT NOT NULL,
  operation TEXT CHECK (operation IN ('insert', 'update', 'delete')) NOT NULL,
  payload TEXT NOT NULL, -- JSON of the record
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  synced INTEGER DEFAULT 0 CHECK (synced IN (0, 1)),
  synced_at TEXT,
  sync_attempts INTEGER DEFAULT 0,
  last_error TEXT
);

CREATE INDEX idx_sync_queue_synced ON sync_queue(synced) WHERE synced = 0;
CREATE INDEX idx_sync_queue_table ON sync_queue(table_name);
CREATE INDEX idx_sync_queue_created ON sync_queue(created_at);

-- --------------------
-- 5.2 CONFLICT LOGS TABLE
-- --------------------
-- Records sync conflicts for manual resolution
CREATE TABLE conflict_logs (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  uuid TEXT NOT NULL UNIQUE DEFAULT (hex(randomblob(16))),
  table_name TEXT NOT NULL,
  record_uuid TEXT NOT NULL,
  conflict_type TEXT CHECK (conflict_type IN ('update_conflict', 'delete_conflict')) NOT NULL,
  local_data TEXT NOT NULL, -- JSON
  remote_data TEXT NOT NULL, -- JSON
  local_timestamp TEXT NOT NULL,
  remote_timestamp TEXT NOT NULL,
  detected_at TEXT NOT NULL DEFAULT (datetime('now')),
  resolved INTEGER DEFAULT 0 CHECK (resolved IN (0, 1)),
  resolved_at TEXT,
  resolved_by TEXT,
  resolution_strategy TEXT, -- 'local_wins', 'remote_wins', 'manual'
  notes TEXT,
  FOREIGN KEY (resolved_by) REFERENCES users(uuid) ON DELETE SET NULL
);

CREATE INDEX idx_conflict_logs_uuid ON conflict_logs(uuid);
CREATE INDEX idx_conflict_logs_table ON conflict_logs(table_name);
CREATE INDEX idx_conflict_logs_resolved ON conflict_logs(resolved);
CREATE INDEX idx_conflict_logs_detected ON conflict_logs(detected_at);

-- --------------------
-- 5.3 AUDIT LOGS TABLE
-- --------------------
-- Comprehensive audit trail of all user actions
CREATE TABLE audit_logs (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  uuid TEXT NOT NULL UNIQUE DEFAULT (hex(randomblob(16))),
  user_uuid TEXT NOT NULL,
  action TEXT NOT NULL, -- 'create', 'read', 'update', 'delete'
  table_name TEXT NOT NULL,
  record_id INTEGER,
  record_uuid TEXT,
  old_values TEXT, -- JSON
  new_values TEXT, -- JSON
  ip_address TEXT,
  user_agent TEXT,
  timestamp TEXT NOT NULL DEFAULT (datetime('now')),
  FOREIGN KEY (user_uuid) REFERENCES users(uuid) ON DELETE RESTRICT
);

CREATE INDEX idx_audit_logs_uuid ON audit_logs(uuid);
CREATE INDEX idx_audit_logs_user ON audit_logs(user_uuid);
CREATE INDEX idx_audit_logs_action ON audit_logs(action);
CREATE INDEX idx_audit_logs_table ON audit_logs(table_name);
CREATE INDEX idx_audit_logs_timestamp ON audit_logs(timestamp);
CREATE INDEX idx_audit_logs_record ON audit_logs(table_name, record_uuid);

-- ============================================================================
-- SECTION 6: DATABASE TRIGGERS FOR AUTOMATION
-- ============================================================================

-- --------------------
-- 6.1 PURCHASE TRIGGERS
-- --------------------

-- Update purchase totals when line items change
CREATE TRIGGER trg_after_purchase_line_insert
AFTER INSERT ON purchase_line_items
BEGIN
  UPDATE purchases
  SET
    total_amount = (SELECT SUM(line_total) FROM purchase_line_items WHERE purchase_id = NEW.purchase_id),
    tax_amount = (SELECT SUM(tax_amount) FROM purchase_line_items WHERE purchase_id = NEW.purchase_id),
    net_amount = (SELECT SUM(line_total) FROM purchase_line_items WHERE purchase_id = NEW.purchase_id) -
                 (SELECT discount_amount FROM purchases WHERE id = NEW.purchase_id),
    last_modified = datetime('now')
  WHERE id = NEW.purchase_id;
END;

CREATE TRIGGER trg_after_purchase_line_update
AFTER UPDATE ON purchase_line_items
BEGIN
  UPDATE purchases
  SET
    total_amount = (SELECT SUM(line_total) FROM purchase_line_items WHERE purchase_id = NEW.purchase_id),
    tax_amount = (SELECT SUM(tax_amount) FROM purchase_line_items WHERE purchase_id = NEW.purchase_id),
    net_amount = (SELECT SUM(line_total) FROM purchase_line_items WHERE purchase_id = NEW.purchase_id) -
                 (SELECT discount_amount FROM purchases WHERE id = NEW.purchase_id),
    last_modified = datetime('now')
  WHERE id = NEW.purchase_id;
END;

CREATE TRIGGER trg_after_purchase_line_delete
AFTER DELETE ON purchase_line_items
BEGIN
  UPDATE purchases
  SET
    total_amount = COALESCE((SELECT SUM(line_total) FROM purchase_line_items WHERE purchase_id = OLD.purchase_id), 0),
    tax_amount = COALESCE((SELECT SUM(tax_amount) FROM purchase_line_items WHERE purchase_id = OLD.purchase_id), 0),
    net_amount = COALESCE((SELECT SUM(line_total) FROM purchase_line_items WHERE purchase_id = OLD.purchase_id), 0) -
                 (SELECT discount_amount FROM purchases WHERE id = OLD.purchase_id),
    last_modified = datetime('now')
  WHERE id = OLD.purchase_id;
END;

-- Increase stock when purchase is approved
CREATE TRIGGER trg_after_purchase_approved
AFTER UPDATE OF status ON purchases
WHEN NEW.status = 'received' AND OLD.status != 'received'
BEGIN
  -- Update stock levels for each purchase line item
  INSERT INTO stock_levels (product_uuid, location_id, quantity, unit_id, last_updated, updated_by)
  SELECT
    pli.product_uuid,
    NEW.location_id,
    pli.quantity,
    pli.unit_id,
    datetime('now'),
    NEW.modified_by
  FROM purchase_line_items pli
  WHERE pli.purchase_id = NEW.id
  ON CONFLICT(product_uuid, location_id) DO UPDATE SET
    quantity = stock_levels.quantity + excluded.quantity,
    last_updated = datetime('now'),
    updated_by = excluded.updated_by;

  -- Log stock adjustments
  INSERT INTO stock_adjustments (
    product_uuid, location_id, adjustment_type,
    quantity_change, quantity_before, quantity_after,
    unit_id, reference_type, reference_id,
    adjustment_date, adjusted_by
  )
  SELECT
    pli.product_uuid,
    NEW.location_id,
    'purchase',
    pli.quantity,
    COALESCE((SELECT quantity FROM stock_levels WHERE product_uuid = pli.product_uuid AND location_id = NEW.location_id), 0) - pli.quantity,
    COALESCE((SELECT quantity FROM stock_levels WHERE product_uuid = pli.product_uuid AND location_id = NEW.location_id), 0),
    pli.unit_id,
    'purchase',
    NEW.id,
    datetime('now'),
    NEW.modified_by
  FROM purchase_line_items pli
  WHERE pli.purchase_id = NEW.id;
END;

-- --------------------
-- 6.2 ISSUE TRIGGERS
-- --------------------

-- Check stock availability before issuing
CREATE TRIGGER trg_before_issue_check_stock
BEFORE UPDATE OF status ON issues
WHEN NEW.status = 'issued' AND OLD.status != 'issued'
BEGIN
  SELECT CASE
    WHEN EXISTS (
      SELECT 1
      FROM issue_line_items ili
      LEFT JOIN stock_levels sl ON
        ili.product_uuid = sl.product_uuid AND
        sl.location_id = NEW.from_location_id
      WHERE ili.issue_id = NEW.id
      AND (sl.quantity IS NULL OR sl.quantity < ili.quantity)
    )
    THEN RAISE(ABORT, 'Insufficient stock for one or more items')
  END;
END;

-- Decrease stock when issue is approved
CREATE TRIGGER trg_after_issue_approved
AFTER UPDATE OF status ON issues
WHEN NEW.status = 'issued' AND OLD.status != 'issued'
BEGIN
  -- Decrease stock from source location
  UPDATE stock_levels
  SET
    quantity = stock_levels.quantity - (
      SELECT ili.quantity
      FROM issue_line_items ili
      WHERE ili.issue_id = NEW.id AND ili.product_uuid = stock_levels.product_uuid
    ),
    last_updated = datetime('now'),
    updated_by = NEW.modified_by
  WHERE location_id = NEW.from_location_id
  AND product_uuid IN (SELECT product_uuid FROM issue_line_items WHERE issue_id = NEW.id);

  -- Increase stock at destination location
  INSERT INTO stock_levels (product_uuid, location_id, quantity, unit_id, last_updated, updated_by)
  SELECT
    ili.product_uuid,
    NEW.to_location_id,
    ili.quantity,
    ili.unit_id,
    datetime('now'),
    NEW.modified_by
  FROM issue_line_items ili
  WHERE ili.issue_id = NEW.id
  ON CONFLICT(product_uuid, location_id) DO UPDATE SET
    quantity = stock_levels.quantity + excluded.quantity,
    last_updated = datetime('now'),
    updated_by = excluded.updated_by;

  -- Log stock adjustments for source location
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
    -ili.quantity,
    (SELECT quantity FROM stock_levels WHERE product_uuid = ili.product_uuid AND location_id = NEW.from_location_id) + ili.quantity,
    (SELECT quantity FROM stock_levels WHERE product_uuid = ili.product_uuid AND location_id = NEW.from_location_id),
    ili.unit_id,
    'issue',
    NEW.id,
    datetime('now'),
    NEW.modified_by
  FROM issue_line_items ili
  WHERE ili.issue_id = NEW.id;

  -- Log stock adjustments for destination location
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
    ili.quantity,
    COALESCE((SELECT quantity FROM stock_levels WHERE product_uuid = ili.product_uuid AND location_id = NEW.to_location_id), 0) - ili.quantity,
    COALESCE((SELECT quantity FROM stock_levels WHERE product_uuid = ili.product_uuid AND location_id = NEW.to_location_id), 0),
    ili.unit_id,
    'issue',
    NEW.id,
    datetime('now'),
    NEW.modified_by
  FROM issue_line_items ili
  WHERE ili.issue_id = NEW.id;
END;

-- --------------------
-- 6.3 WASTAGE TRIGGERS
-- --------------------

-- Decrease stock when wastage is recorded
CREATE TRIGGER trg_after_wastage_insert
AFTER INSERT ON wastage_returns
WHEN NEW.transaction_type = 'wastage'
BEGIN
  -- Decrease stock
  UPDATE stock_levels
  SET
    quantity = quantity - NEW.quantity,
    last_updated = datetime('now'),
    updated_by = NEW.created_by
  WHERE product_uuid = NEW.product_uuid
  AND location_id = NEW.location_id;

  -- Log adjustment
  INSERT INTO stock_adjustments (
    product_uuid, location_id, adjustment_type,
    quantity_change, quantity_before, quantity_after,
    unit_id, reference_type, reference_id, reason,
    adjustment_date, adjusted_by
  )
  VALUES (
    NEW.product_uuid,
    NEW.location_id,
    'wastage',
    -NEW.quantity,
    (SELECT quantity FROM stock_levels WHERE product_uuid = NEW.product_uuid AND location_id = NEW.location_id) + NEW.quantity,
    (SELECT quantity FROM stock_levels WHERE product_uuid = NEW.product_uuid AND location_id = NEW.location_id),
    NEW.unit_id,
    'wastage',
    NEW.id,
    NEW.reason,
    datetime('now'),
    NEW.created_by
  );
END;

-- --------------------
-- 6.4 STOCK TRANSFER TRIGGERS
-- --------------------

-- Process stock transfer when completed
CREATE TRIGGER trg_after_transfer_completed
AFTER UPDATE OF status ON stock_transfers
WHEN NEW.status = 'completed' AND OLD.status != 'completed'
BEGIN
  -- Decrease stock from source
  UPDATE stock_levels
  SET
    quantity = stock_levels.quantity - (
      SELECT sti.quantity
      FROM stock_transfer_items sti
      WHERE sti.transfer_id = NEW.id AND sti.product_uuid = stock_levels.product_uuid
    ),
    last_updated = datetime('now'),
    updated_by = NEW.modified_by
  WHERE location_id = NEW.from_location_id
  AND product_uuid IN (SELECT product_uuid FROM stock_transfer_items WHERE transfer_id = NEW.id);

  -- Increase stock at destination
  INSERT INTO stock_levels (product_uuid, location_id, quantity, unit_id, last_updated, updated_by)
  SELECT
    sti.product_uuid,
    NEW.to_location_id,
    sti.quantity,
    sti.unit_id,
    datetime('now'),
    NEW.modified_by
  FROM stock_transfer_items sti
  WHERE sti.transfer_id = NEW.id
  ON CONFLICT(product_uuid, location_id) DO UPDATE SET
    quantity = stock_levels.quantity + excluded.quantity,
    last_updated = datetime('now'),
    updated_by = excluded.updated_by;

  -- Log adjustments for both locations
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
    -sti.quantity,
    (SELECT quantity FROM stock_levels WHERE product_uuid = sti.product_uuid AND location_id = NEW.from_location_id) + sti.quantity,
    (SELECT quantity FROM stock_levels WHERE product_uuid = sti.product_uuid AND location_id = NEW.from_location_id),
    sti.unit_id,
    'transfer',
    NEW.id,
    datetime('now'),
    NEW.modified_by
  FROM stock_transfer_items sti
  WHERE sti.transfer_id = NEW.id;

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
    sti.quantity,
    COALESCE((SELECT quantity FROM stock_levels WHERE product_uuid = sti.product_uuid AND location_id = NEW.to_location_id), 0) - sti.quantity,
    COALESCE((SELECT quantity FROM stock_levels WHERE product_uuid = sti.product_uuid AND location_id = NEW.to_location_id), 0),
    sti.unit_id,
    'transfer',
    NEW.id,
    datetime('now'),
    NEW.modified_by
  FROM stock_transfer_items sti
  WHERE sti.transfer_id = NEW.id;
END;

-- --------------------
-- 6.5 STOCK ALERT TRIGGERS
-- --------------------

-- Generate reorder alerts when stock falls below threshold
CREATE TRIGGER trg_after_stock_update_check_reorder
AFTER UPDATE OF quantity ON stock_levels
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

-- Generate expiry alerts for batches nearing expiry
CREATE TRIGGER trg_check_batch_expiry
AFTER INSERT ON product_batches
WHEN NEW.expiry_date IS NOT NULL
BEGIN
  INSERT INTO stock_alerts (
    alert_type, product_uuid, location_id, batch_uuid,
    threshold_value, current_value, severity, message
  )
  SELECT
    'expiry',
    NEW.product_uuid,
    NEW.location_id,
    NEW.uuid,
    30, -- days threshold
    CAST((julianday(NEW.expiry_date) - julianday('now')) AS INTEGER),
    CASE
      WHEN julianday(NEW.expiry_date) - julianday('now') <= 7 THEN 'critical'
      WHEN julianday(NEW.expiry_date) - julianday('now') <= 15 THEN 'high'
      WHEN julianday(NEW.expiry_date) - julianday('now') <= 30 THEN 'medium'
      ELSE 'low'
    END,
    'Batch ' || NEW.batch_number || ' of ' || p.name || ' expires on ' || NEW.expiry_date
  FROM products p
  WHERE p.uuid = NEW.product_uuid
  AND julianday(NEW.expiry_date) - julianday('now') <= 30;
END;

-- --------------------
-- 6.6 SYNC QUEUE TRIGGERS
-- --------------------

-- Add to sync queue on master data changes
CREATE TRIGGER trg_sync_products_insert AFTER INSERT ON products
BEGIN
  INSERT INTO sync_queue (table_name, record_uuid, operation, payload)
  VALUES ('products', NEW.uuid, 'insert', json_object(
    'uuid', NEW.uuid, 'name', NEW.name, 'sku', NEW.sku,
    'category_id', NEW.category_id, 'default_unit_id', NEW.default_unit_id,
    'base_unit_id', NEW.base_unit_id, 'description', NEW.description,
    'reorder_level', NEW.reorder_level, 'reorder_quantity', NEW.reorder_quantity,
    'hsn_code', NEW.hsn_code, 'tax_rate', NEW.tax_rate,
    'is_active', NEW.is_active, 'last_modified', NEW.last_modified
  ));
END;

CREATE TRIGGER trg_sync_products_update AFTER UPDATE ON products
BEGIN
  INSERT INTO sync_queue (table_name, record_uuid, operation, payload)
  VALUES ('products', NEW.uuid, 'update', json_object(
    'uuid', NEW.uuid, 'name', NEW.name, 'sku', NEW.sku,
    'category_id', NEW.category_id, 'default_unit_id', NEW.default_unit_id,
    'base_unit_id', NEW.base_unit_id, 'description', NEW.description,
    'reorder_level', NEW.reorder_level, 'reorder_quantity', NEW.reorder_quantity,
    'hsn_code', NEW.hsn_code, 'tax_rate', NEW.tax_rate,
    'is_active', NEW.is_active, 'last_modified', NEW.last_modified
  ));
END;

-- Similar sync triggers can be added for other tables as needed

-- --------------------
-- 6.7 AUTO-UPDATE TIMESTAMPS
-- --------------------

-- Auto-update last_modified on all tables with that column
CREATE TRIGGER trg_products_update_timestamp AFTER UPDATE ON products
BEGIN
  UPDATE products SET last_modified = datetime('now') WHERE id = NEW.id;
END;

CREATE TRIGGER trg_purchases_update_timestamp AFTER UPDATE ON purchases
BEGIN
  UPDATE purchases SET last_modified = datetime('now') WHERE id = NEW.id;
END;

CREATE TRIGGER trg_issues_update_timestamp AFTER UPDATE ON issues
BEGIN
  UPDATE issues SET last_modified = datetime('now') WHERE id = NEW.id;
END;

-- Add similar triggers for other transactional tables

-- ============================================================================
-- SECTION 7: VIEWS FOR REPORTING
-- ============================================================================

-- --------------------
-- 7.1 CURRENT STOCK VIEW
-- --------------------
-- Consolidated view of current stock with product details
CREATE VIEW vw_current_stock AS
SELECT
  sl.id,
  p.uuid AS product_uuid,
  p.name AS product_name,
  p.sku,
  c.name AS category_name,
  l.name AS location_name,
  l.location_type,
  sl.quantity,
  u.name AS unit_name,
  u.abbreviation AS unit_abbr,
  p.reorder_level,
  CASE
    WHEN sl.quantity <= p.reorder_level THEN 1
    ELSE 0
  END AS is_below_reorder,
  sl.last_updated,
  (SELECT SUM(pb.quantity * pb.cost_per_unit)
   FROM product_batches pb
   WHERE pb.product_uuid = p.uuid AND pb.location_id = l.id) AS total_value
FROM stock_levels sl
JOIN products p ON sl.product_uuid = p.uuid
JOIN locations l ON sl.location_id = l.id
JOIN units u ON sl.unit_id = u.id
LEFT JOIN categories c ON p.category_id = c.id
WHERE p.is_active = 1;

-- --------------------
-- 7.2 LOW STOCK VIEW
-- --------------------
CREATE VIEW vw_low_stock AS
SELECT * FROM vw_current_stock
WHERE is_below_reorder = 1
ORDER BY quantity ASC;

-- --------------------
-- 7.3 EXPIRING BATCHES VIEW
-- --------------------
CREATE VIEW vw_expiring_batches AS
SELECT
  pb.uuid,
  pb.batch_number,
  p.name AS product_name,
  p.sku,
  l.name AS location_name,
  pb.quantity,
  u.abbreviation AS unit,
  pb.expiry_date,
  CAST((julianday(pb.expiry_date) - julianday('now')) AS INTEGER) AS days_to_expiry,
  CASE
    WHEN julianday(pb.expiry_date) - julianday('now') <= 7 THEN 'critical'
    WHEN julianday(pb.expiry_date) - julianday('now') <= 15 THEN 'high'
    WHEN julianday(pb.expiry_date) - julianday('now') <= 30 THEN 'medium'
    ELSE 'low'
  END AS urgency
FROM product_batches pb
JOIN products p ON pb.product_uuid = p.uuid
JOIN locations l ON pb.location_id = l.id
JOIN units u ON pb.unit_id = u.id
WHERE pb.expiry_date IS NOT NULL
AND pb.is_active = 1
AND julianday(pb.expiry_date) - julianday('now') <= 30
ORDER BY pb.expiry_date ASC;

-- --------------------
-- 7.4 DAILY PURCHASE SUMMARY VIEW
-- --------------------
CREATE VIEW vw_daily_purchase_summary AS
SELECT
  p.purchase_date,
  s.name AS supplier_name,
  COUNT(DISTINCT p.id) AS total_purchases,
  SUM(p.net_amount) AS total_amount,
  SUM(p.tax_amount) AS total_tax,
  SUM(p.discount_amount) AS total_discount
FROM purchases p
JOIN suppliers s ON p.supplier_id = s.id
WHERE p.status = 'received'
GROUP BY p.purchase_date, s.id
ORDER BY p.purchase_date DESC;

-- --------------------
-- 7.5 DAILY ISSUE SUMMARY VIEW
-- --------------------
CREATE VIEW vw_daily_issue_summary AS
SELECT
  i.issue_date,
  l_from.name AS from_location,
  l_to.name AS to_location,
  COUNT(DISTINCT i.id) AS total_issues,
  COUNT(ili.id) AS total_items
FROM issues i
JOIN locations l_from ON i.from_location_id = l_from.id
JOIN locations l_to ON i.to_location_id = l_to.id
LEFT JOIN issue_line_items ili ON i.id = ili.issue_id
WHERE i.status = 'issued'
GROUP BY i.issue_date, l_from.id, l_to.id
ORDER BY i.issue_date DESC;

-- --------------------
-- 7.6 RECIPE COSTING VIEW
-- --------------------
CREATE VIEW vw_recipe_costing AS
SELECT
  r.uuid,
  r.name AS recipe_name,
  r.category,
  r.serving_size,
  COUNT(ri.id) AS ingredient_count,
  SUM(
    ri.quantity * COALESCE(
      (SELECT AVG(pli.unit_price)
       FROM purchase_line_items pli
       WHERE pli.product_uuid = ri.product_uuid
       AND pli.created_at >= date('now', '-30 days')
      ), 0)
  ) AS estimated_cost,
  r.selling_price,
  r.profit_margin,
  r.is_active
FROM recipes r
LEFT JOIN recipe_ingredients ri ON r.id = ri.recipe_id
GROUP BY r.id;

-- --------------------
-- 7.7 SUPPLIER PERFORMANCE VIEW
-- --------------------
CREATE VIEW vw_supplier_performance AS
SELECT
  s.uuid,
  s.name AS supplier_name,
  COUNT(DISTINCT p.id) AS total_purchases,
  SUM(p.net_amount) AS total_amount_paid,
  AVG(julianday(p.purchase_date) - julianday(p.created_at)) AS avg_delivery_time_days,
  COUNT(CASE WHEN p.payment_status = 'pending' THEN 1 END) AS pending_payments,
  SUM(CASE WHEN p.payment_status = 'pending' THEN p.net_amount ELSE 0 END) AS outstanding_amount
FROM suppliers s
LEFT JOIN purchases p ON s.id = p.supplier_id AND p.status = 'received'
GROUP BY s.id;

-- --------------------
-- 7.8 ACTIVE ALERTS VIEW
-- --------------------
CREATE VIEW vw_active_alerts AS
SELECT
  sa.uuid,
  sa.alert_type,
  p.name AS product_name,
  l.name AS location_name,
  sa.severity,
  sa.message,
  sa.triggered_at,
  CAST((julianday('now') - julianday(sa.triggered_at)) AS INTEGER) AS days_open
FROM stock_alerts sa
JOIN products p ON sa.product_uuid = p.uuid
LEFT JOIN locations l ON sa.location_id = l.id
WHERE sa.resolved = 0
ORDER BY
  CASE sa.severity
    WHEN 'critical' THEN 1
    WHEN 'high' THEN 2
    WHEN 'medium' THEN 3
    ELSE 4
  END,
  sa.triggered_at ASC;

-- ============================================================================
-- SECTION 8: UTILITY FUNCTIONS & PROCEDURES
-- ============================================================================

-- Note: SQLite doesn't support stored procedures, but we can document
-- common query patterns here for implementation in application code

-- Example: Get stock value by location
-- SELECT
--   l.name AS location,
--   SUM(sl.quantity * COALESCE(pb.cost_per_unit, 0)) AS total_value
-- FROM stock_levels sl
-- JOIN locations l ON sl.location_id = l.id
-- LEFT JOIN product_batches pb ON sl.product_uuid = pb.product_uuid AND sl.location_id = pb.location_id
-- GROUP BY l.id;

-- Example: Get stock movements for a product
-- SELECT * FROM stock_adjustments
-- WHERE product_uuid = ?
-- ORDER BY adjustment_date DESC
-- LIMIT 100;

-- ============================================================================
-- SECTION 9: INITIAL SEED DATA
-- ============================================================================

-- --------------------
-- 9.1 DEFAULT UNITS
-- --------------------
INSERT INTO units (name, abbreviation, unit_type, created_by) VALUES
  ('Kilogram', 'kg', 'weight', 'system'),
  ('Gram', 'g', 'weight', 'system'),
  ('Litre', 'L', 'volume', 'system'),
  ('Millilitre', 'ml', 'volume', 'system'),
  ('Piece', 'pc', 'count', 'system'),
  ('Dozen', 'doz', 'count', 'system'),
  ('Packet', 'pkt', 'count', 'system'),
  ('Box', 'box', 'count', 'system'),
  ('Bottle', 'btl', 'count', 'system'),
  ('Can', 'can', 'count', 'system');

-- --------------------
-- 9.2 DEFAULT CATEGORIES
-- --------------------
INSERT INTO categories (name, description, created_by) VALUES
  ('Vegetables', 'Fresh and frozen vegetables', 'system'),
  ('Meat & Poultry', 'Chicken, mutton, fish, etc.', 'system'),
  ('Dairy', 'Milk, cheese, butter, cream', 'system'),
  ('Spices', 'Whole and ground spices', 'system'),
  ('Oils & Fats', 'Cooking oils, ghee, butter', 'system'),
  ('Beverages', 'Soft drinks, juices, water', 'system'),
  ('Bakery', 'Bread, buns, pastries', 'system'),
  ('Dry Goods', 'Rice, flour, pulses, pasta', 'system'),
  ('Condiments', 'Sauces, vinegar, salt, sugar', 'system'),
  ('Cleaning Supplies', 'Detergents, sanitizers', 'system');

-- --------------------
-- 9.3 DEFAULT LOCATIONS
-- --------------------
INSERT INTO locations (name, location_type, description, created_by) VALUES
  ('Main Store', 'store', 'Central storage facility', 'system'),
  ('Indian Kitchen', 'kitchen', 'Indian cuisine preparation area', 'system'),
  ('Chinese Kitchen', 'kitchen', 'Chinese cuisine preparation area', 'system'),
  ('Bar', 'bar', 'Beverage service area', 'system'),
  ('Cold Storage', 'store', 'Refrigerated storage', 'system');

-- ============================================================================
-- SECTION 10: DATABASE INTEGRITY CHECKS
-- ============================================================================

-- Enable foreign key enforcement
PRAGMA foreign_keys = ON;

-- Verify schema integrity
PRAGMA integrity_check;

-- ============================================================================
-- END OF SCHEMA
-- ============================================================================

-- Database version info
SELECT 'HIMS Database Schema v1.0 initialized successfully' AS status;
SELECT COUNT(*) AS table_count FROM sqlite_master WHERE type='table';
SELECT COUNT(*) AS view_count FROM sqlite_master WHERE type='view';
SELECT COUNT(*) AS trigger_count FROM sqlite_master WHERE type='trigger';
SELECT COUNT(*) AS index_count FROM sqlite_master WHERE type='index';
