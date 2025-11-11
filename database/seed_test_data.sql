-- ============================================================================
-- HIMS - SEED TEST DATA
-- ============================================================================
-- Description: Sample data for testing the hotel inventory management system
-- Usage: Run this after v1_initial.sql to populate with realistic test data
-- ============================================================================

-- ============================================================================
-- 1. TEST USERS
-- ============================================================================

-- Password for all test users: "password123" (hashed with bcrypt)
-- In production, use proper password hashing
INSERT INTO users (uuid, username, password_hash, full_name, email, phone, created_by) VALUES
  ('user-admin-001', 'admin', '$2a$10$YourHashedPasswordHere', 'System Administrator', 'admin@hotel.com', '+91-9876543210', 'system'),
  ('user-manager-001', 'store_manager', '$2a$10$YourHashedPasswordHere', 'Rajesh Kumar', 'rajesh@hotel.com', '+91-9876543211', 'user-admin-001'),
  ('user-chef-001', 'chef_indian', '$2a$10$YourHashedPasswordHere', 'Ramesh Singh', 'ramesh@hotel.com', '+91-9876543212', 'user-admin-001'),
  ('user-chef-002', 'chef_chinese', '$2a$10$YourHashedPasswordHere', 'Wei Zhang', 'wei@hotel.com', '+91-9876543213', 'user-admin-001'),
  ('user-accountant-001', 'accountant', '$2a$10$YourHashedPasswordHere', 'Priya Sharma', 'priya@hotel.com', '+91-9876543214', 'user-admin-001');

-- Assign roles to users
INSERT INTO user_roles (user_uuid, role_id, assigned_by) VALUES
  ('user-admin-001', 1, 'system'),          -- Admin
  ('user-manager-001', 2, 'user-admin-001'), -- Store Manager
  ('user-chef-001', 3, 'user-admin-001'),    -- Chef
  ('user-chef-002', 3, 'user-admin-001'),    -- Chef
  ('user-accountant-001', 4, 'user-admin-001'); -- Accountant

-- ============================================================================
-- 2. TEST SUPPLIERS
-- ============================================================================

INSERT INTO suppliers (uuid, name, contact_person, phone, email, address, gstin, credit_limit, credit_days, created_by) VALUES
  ('supplier-001', 'Fresh Vegetables Mart', 'Suresh Patel', '+91-9123456701', 'suresh@freshveggies.com', '123 Market Road, Mumbai', '27AABCU9603R1ZM', 50000, 30, 'user-manager-001'),
  ('supplier-002', 'Premium Meats & Poultry', 'Mohammed Ali', '+91-9123456702', 'ali@premiummeats.com', '456 Butcher Street, Mumbai', '27AABCU9603R1ZN', 100000, 15, 'user-manager-001'),
  ('supplier-003', 'Spice Traders Co.', 'Lakshmi Iyer', '+91-9123456703', 'lakshmi@spicetraders.com', '789 Spice Bazaar, Mumbai', '27AABCU9603R1ZO', 30000, 45, 'user-manager-001'),
  ('supplier-004', 'Dairy Fresh Products', 'Ramesh Yadav', '+91-9123456704', 'ramesh@dairyfresh.com', '321 Dairy Lane, Mumbai', '27AABCU9603R1ZP', 40000, 7, 'user-manager-001'),
  ('supplier-005', 'Beverage Distributors Ltd', 'Anil Kumar', '+91-9123456705', 'anil@beveragedist.com', '654 Drink Avenue, Mumbai', '27AABCU9603R1ZQ', 75000, 30, 'user-manager-001');

-- ============================================================================
-- 3. TEST PRODUCTS
-- ============================================================================

-- Vegetables
INSERT INTO products (uuid, name, sku, category_id, default_unit_id, base_unit_id, description, reorder_level, reorder_quantity, hsn_code, tax_rate, created_by) VALUES
  ('prod-veg-001', 'Onion', 'VEG-001', 1, 1, 1, 'Red onions', 50, 100, '07031000', 5, 'user-manager-001'),
  ('prod-veg-002', 'Tomato', 'VEG-002', 1, 1, 1, 'Fresh tomatoes', 30, 50, '07020000', 5, 'user-manager-001'),
  ('prod-veg-003', 'Potato', 'VEG-003', 1, 1, 1, 'Washed potatoes', 100, 200, '07010000', 5, 'user-manager-001'),
  ('prod-veg-004', 'Green Chilli', 'VEG-004', 1, 1, 2, 'Fresh green chilli', 5, 10, '07096000', 5, 'user-manager-001');

-- Meat & Poultry
INSERT INTO products (uuid, name, sku, category_id, default_unit_id, base_unit_id, description, reorder_level, reorder_quantity, hsn_code, tax_rate, created_by) VALUES
  ('prod-meat-001', 'Chicken Breast', 'MEAT-001', 2, 1, 1, 'Boneless chicken breast', 20, 50, '02071200', 0, 'user-manager-001'),
  ('prod-meat-002', 'Chicken Whole', 'MEAT-002', 2, 5, 5, 'Whole chicken (approx 1.5kg each)', 10, 20, '02071100', 0, 'user-manager-001'),
  ('prod-meat-003', 'Mutton', 'MEAT-003', 2, 1, 1, 'Fresh mutton', 15, 30, '02041000', 0, 'user-manager-001'),
  ('prod-meat-004', 'Fish (Pomfret)', 'MEAT-004', 2, 1, 1, 'Fresh pomfret fish', 10, 20, '03038900', 5, 'user-manager-001'),
  ('prod-meat-005', 'Prawns', 'MEAT-005', 2, 1, 1, 'Large prawns', 5, 10, '03061700', 5, 'user-manager-001');

-- Dairy
INSERT INTO products (uuid, name, sku, category_id, default_unit_id, base_unit_id, description, reorder_level, reorder_quantity, hsn_code, tax_rate, created_by) VALUES
  ('prod-dairy-001', 'Full Cream Milk', 'DAIRY-001', 3, 3, 3, 'Full fat fresh milk', 50, 100, '04011000', 0, 'user-manager-001'),
  ('prod-dairy-002', 'Butter', 'DAIRY-002', 3, 1, 2, 'Salted butter', 10, 20, '04050010', 12, 'user-manager-001'),
  ('prod-dairy-003', 'Cheese (Cheddar)', 'DAIRY-003', 3, 1, 2, 'Cheddar cheese block', 5, 10, '04061020', 12, 'user-manager-001'),
  ('prod-dairy-004', 'Fresh Cream', 'DAIRY-004', 3, 3, 4, 'Cooking cream', 10, 20, '04012010', 12, 'user-manager-001'),
  ('prod-dairy-005', 'Paneer', 'DAIRY-005', 3, 1, 2, 'Fresh cottage cheese', 8, 15, '04061030', 5, 'user-manager-001');

-- Spices
INSERT INTO products (uuid, name, sku, category_id, default_unit_id, base_unit_id, description, reorder_level, reorder_quantity, hsn_code, tax_rate, created_by) VALUES
  ('prod-spice-001', 'Turmeric Powder', 'SPICE-001', 4, 1, 2, 'Pure turmeric powder', 5, 10, '09103000', 5, 'user-manager-001'),
  ('prod-spice-002', 'Red Chilli Powder', 'SPICE-002', 4, 1, 2, 'Kashmiri chilli powder', 5, 10, '09042200', 5, 'user-manager-001'),
  ('prod-spice-003', 'Cumin Seeds', 'SPICE-003', 4, 1, 2, 'Whole cumin seeds', 3, 5, '09093100', 5, 'user-manager-001'),
  ('prod-spice-004', 'Garam Masala', 'SPICE-004', 4, 1, 2, 'Mixed spice blend', 2, 5, '09109900', 5, 'user-manager-001'),
  ('prod-spice-005', 'Bay Leaves', 'SPICE-005', 4, 2, 2, 'Dried bay leaves', 0.5, 1, '09109910', 5, 'user-manager-001');

-- Oils & Fats
INSERT INTO products (uuid, name, sku, category_id, default_unit_id, base_unit_id, description, reorder_level, reorder_quantity, hsn_code, tax_rate, created_by) VALUES
  ('prod-oil-001', 'Sunflower Oil', 'OIL-001', 5, 3, 3, 'Refined sunflower oil', 20, 50, '15121900', 5, 'user-manager-001'),
  ('prod-oil-002', 'Olive Oil', 'OIL-002', 5, 3, 4, 'Extra virgin olive oil', 5, 10, '15099000', 12, 'user-manager-001'),
  ('prod-oil-003', 'Ghee', 'OIL-003', 5, 1, 2, 'Pure cow ghee', 10, 20, '04050020', 12, 'user-manager-001');

-- Beverages
INSERT INTO products (uuid, name, sku, category_id, default_unit_id, base_unit_id, description, reorder_level, reorder_quantity, hsn_code, tax_rate, created_by) VALUES
  ('prod-bev-001', 'Mineral Water (1L)', 'BEV-001', 6, 9, 9, 'Packaged drinking water', 100, 200, '22021000', 18, 'user-manager-001'),
  ('prod-bev-002', 'Coca Cola (330ml)', 'BEV-002', 6, 10, 10, 'Coca Cola cans', 50, 100, '22021010', 28, 'user-manager-001'),
  ('prod-bev-003', 'Orange Juice (1L)', 'BEV-003', 6, 9, 9, 'Fresh orange juice', 20, 40, '20099000', 12, 'user-manager-001');

-- Dry Goods
INSERT INTO products (uuid, name, sku, category_id, default_unit_id, base_unit_id, description, reorder_level, reorder_quantity, hsn_code, tax_rate, created_by) VALUES
  ('prod-dry-001', 'Basmati Rice', 'DRY-001', 8, 1, 1, 'Premium basmati rice', 100, 200, '10063000', 5, 'user-manager-001'),
  ('prod-dry-002', 'Wheat Flour (Maida)', 'DRY-002', 8, 1, 1, 'Refined wheat flour', 50, 100, '11010010', 5, 'user-manager-001'),
  ('prod-dry-003', 'Pasta (Penne)', 'DRY-003', 8, 1, 2, 'Penne pasta', 10, 20, '19021100', 18, 'user-manager-001');

-- Condiments
INSERT INTO products (uuid, name, sku, category_id, default_unit_id, base_unit_id, description, reorder_level, reorder_quantity, hsn_code, tax_rate, created_by) VALUES
  ('prod-cond-001', 'Salt', 'COND-001', 9, 1, 1, 'Iodized table salt', 20, 50, '25010000', 5, 'user-manager-001'),
  ('prod-cond-002', 'Sugar', 'COND-002', 9, 1, 1, 'White refined sugar', 50, 100, '17019900', 5, 'user-manager-001'),
  ('prod-cond-003', 'Soy Sauce (1L)', 'COND-003', 9, 9, 4, 'Dark soy sauce', 5, 10, '21039000', 18, 'user-manager-001'),
  ('prod-cond-004', 'Vinegar (500ml)', 'COND-004', 9, 9, 4, 'White vinegar', 5, 10, '22090000', 12, 'user-manager-001'),
  ('prod-cond-005', 'Tomato Ketchup', 'COND-005', 9, 9, 2, 'Tomato ketchup bottle', 10, 20, '21032000', 12, 'user-manager-001');

-- ============================================================================
-- 4. UNIT CONVERSIONS
-- ============================================================================

-- Chicken conversions: whole chicken pieces to kg
INSERT INTO unit_conversions (product_uuid, from_unit_id, to_unit_id, conversion_factor, created_by) VALUES
  ('prod-meat-002', 5, 1, 1.5, 'user-manager-001'); -- 1 piece = 1.5 kg

-- Bottle/Can conversions
INSERT INTO unit_conversions (product_uuid, from_unit_id, to_unit_id, conversion_factor, created_by) VALUES
  ('prod-bev-001', 9, 3, 1, 'user-manager-001'),    -- 1 bottle = 1 litre
  ('prod-bev-002', 10, 4, 330, 'user-manager-001'), -- 1 can = 330 ml
  ('prod-bev-003', 9, 3, 1, 'user-manager-001');    -- 1 bottle = 1 litre

-- ============================================================================
-- 5. SAMPLE PURCHASE ORDERS
-- ============================================================================

-- Purchase 1: Vegetables from Fresh Vegetables Mart
INSERT INTO purchases (
  uuid, purchase_number, supplier_id, location_id, purchase_date,
  invoice_number, invoice_date, status, created_by, approved_by
) VALUES (
  'purchase-001', 'PO-2025-001', 1, 1, '2025-11-01',
  'INV-VEG-2025-001', '2025-11-01', 'received', 'user-manager-001', 'user-admin-001'
);

INSERT INTO purchase_line_items (purchase_id, product_uuid, quantity, unit_id, unit_price, tax_rate, tax_amount, line_total) VALUES
  (1, 'prod-veg-001', 100, 1, 40, 5, 200, 4200),   -- Onion 100kg @ 40/kg
  (1, 'prod-veg-002', 50, 1, 30, 5, 75, 1575),     -- Tomato 50kg @ 30/kg
  (1, 'prod-veg-003', 150, 1, 25, 5, 187.5, 3937.5), -- Potato 150kg @ 25/kg
  (1, 'prod-veg-004', 10, 1, 80, 5, 40, 840);      -- Green Chilli 10kg @ 80/kg

-- Purchase 2: Meat & Poultry from Premium Meats
INSERT INTO purchases (
  uuid, purchase_number, supplier_id, location_id, purchase_date,
  invoice_number, invoice_date, status, created_by, approved_by
) VALUES (
  'purchase-002', 'PO-2025-002', 2, 1, '2025-11-02',
  'INV-MEAT-2025-001', '2025-11-02', 'received', 'user-manager-001', 'user-admin-001'
);

INSERT INTO purchase_line_items (purchase_id, product_uuid, quantity, unit_id, unit_price, tax_rate, tax_amount, line_total) VALUES
  (2, 'prod-meat-001', 50, 1, 180, 0, 0, 9000),    -- Chicken Breast 50kg @ 180/kg
  (2, 'prod-meat-002', 20, 5, 250, 0, 0, 5000),    -- Chicken Whole 20pcs @ 250/pc
  (2, 'prod-meat-003', 30, 1, 450, 0, 0, 13500),   -- Mutton 30kg @ 450/kg
  (2, 'prod-meat-004', 15, 1, 300, 5, 225, 4725),  -- Fish 15kg @ 300/kg
  (2, 'prod-meat-005', 10, 1, 600, 5, 300, 6300);  -- Prawns 10kg @ 600/kg

-- Purchase 3: Dairy products
INSERT INTO purchases (
  uuid, purchase_number, supplier_id, location_id, purchase_date,
  invoice_number, invoice_date, status, created_by, approved_by
) VALUES (
  'purchase-003', 'PO-2025-003', 4, 5, '2025-11-03',
  'INV-DAIRY-2025-001', '2025-11-03', 'received', 'user-manager-001', 'user-admin-001'
);

INSERT INTO purchase_line_items (purchase_id, product_uuid, quantity, unit_id, unit_price, tax_rate, tax_amount, line_total) VALUES
  (3, 'prod-dairy-001', 100, 3, 60, 0, 0, 6000),    -- Milk 100L @ 60/L
  (3, 'prod-dairy-002', 20, 1, 450, 12, 1080, 10080), -- Butter 20kg @ 450/kg
  (3, 'prod-dairy-003', 10, 1, 500, 12, 600, 5600),  -- Cheese 10kg @ 500/kg
  (3, 'prod-dairy-004', 25, 3, 150, 12, 450, 4200),  -- Cream 25L @ 150/L
  (3, 'prod-dairy-005', 15, 1, 280, 5, 210, 4410);   -- Paneer 15kg @ 280/kg

-- ============================================================================
-- 6. PRODUCT BATCHES (For expiry tracking)
-- ============================================================================

-- Batches for dairy products (with expiry dates)
INSERT INTO product_batches (
  product_uuid, batch_number, location_id, quantity, unit_id,
  received_date, expiry_date, cost_per_unit, supplier_id, created_by
) VALUES
  ('prod-dairy-001', 'MILK-NOV-01', 5, 100, 3, '2025-11-03', '2025-11-06', 60, 4, 'user-manager-001'),
  ('prod-dairy-002', 'BUTTER-NOV-01', 5, 20, 1, '2025-11-03', '2025-12-03', 450, 4, 'user-manager-001'),
  ('prod-dairy-003', 'CHEESE-NOV-01', 5, 10, 1, '2025-11-03', '2025-12-15', 500, 4, 'user-manager-001'),
  ('prod-dairy-004', 'CREAM-NOV-01', 5, 25, 3, '2025-11-03', '2025-11-10', 150, 4, 'user-manager-001'),
  ('prod-dairy-005', 'PANEER-NOV-01', 5, 15, 1, '2025-11-03', '2025-11-08', 280, 4, 'user-manager-001');

-- Batches for meat (shorter expiry)
INSERT INTO product_batches (
  product_uuid, batch_number, location_id, quantity, unit_id,
  received_date, expiry_date, cost_per_unit, supplier_id, created_by
) VALUES
  ('prod-meat-001', 'CHICKEN-NOV-02', 5, 50, 1, '2025-11-02', '2025-11-05', 180, 2, 'user-manager-001'),
  ('prod-meat-004', 'FISH-NOV-02', 5, 15, 1, '2025-11-02', '2025-11-04', 300, 2, 'user-manager-001'),
  ('prod-meat-005', 'PRAWNS-NOV-02', 5, 10, 1, '2025-11-02', '2025-11-04', 600, 2, 'user-manager-001');

-- ============================================================================
-- 7. SAMPLE ISSUES TO KITCHENS
-- ============================================================================

-- Issue 1: Items to Indian Kitchen
INSERT INTO issues (
  uuid, issue_number, from_location_id, to_location_id, issue_date,
  requested_by, issued_by, status, created_by, approved_by
) VALUES (
  'issue-001', 'ISS-2025-001', 1, 2, '2025-11-05',
  'user-chef-001', 'user-manager-001', 'issued', 'user-chef-001', 'user-manager-001'
);

INSERT INTO issue_line_items (issue_id, product_uuid, quantity, unit_id) VALUES
  (1, 'prod-veg-001', 20, 1),  -- Onion 20kg
  (1, 'prod-veg-002', 15, 1),  -- Tomato 15kg
  (1, 'prod-meat-001', 10, 1), -- Chicken 10kg
  (1, 'prod-spice-001', 2, 1), -- Turmeric 2kg
  (1, 'prod-oil-001', 5, 3);   -- Oil 5L

-- Issue 2: Items to Chinese Kitchen
INSERT INTO issues (
  uuid, issue_number, from_location_id, to_location_id, issue_date,
  requested_by, issued_by, status, created_by, approved_by
) VALUES (
  'issue-002', 'ISS-2025-002', 1, 3, '2025-11-05',
  'user-chef-002', 'user-manager-001', 'issued', 'user-chef-002', 'user-manager-001'
);

INSERT INTO issue_line_items (issue_id, product_uuid, quantity, unit_id) VALUES
  (2, 'prod-veg-001', 10, 1),   -- Onion 10kg
  (2, 'prod-meat-001', 8, 1),   -- Chicken 8kg
  (2, 'prod-cond-003', 2, 9),   -- Soy Sauce 2L
  (2, 'prod-cond-004', 1, 9),   -- Vinegar 1L
  (2, 'prod-oil-001', 3, 3);    -- Oil 3L

-- ============================================================================
-- 8. SAMPLE WASTAGE RECORDS
-- ============================================================================

INSERT INTO wastage_returns (
  uuid, transaction_number, transaction_type, product_uuid, location_id,
  quantity, unit_id, reason, transaction_date, reported_by, created_by, approved_by
) VALUES
  ('waste-001', 'WASTE-2025-001', 'wastage', 'prod-veg-002', 2, 2, 1, 'Spoiled/Overripe', '2025-11-06', 'user-chef-001', 'user-chef-001', 'user-manager-001'),
  ('waste-002', 'WASTE-2025-002', 'wastage', 'prod-dairy-001', 5, 5, 3, 'Expired', '2025-11-07', 'user-manager-001', 'user-manager-001', 'user-admin-001');

-- ============================================================================
-- 9. SAMPLE RECIPES
-- ============================================================================

-- Recipe 1: Butter Chicken
INSERT INTO recipes (
  uuid, name, description, category, serving_size, preparation_time,
  cooking_time, selling_price, created_by
) VALUES (
  'recipe-001', 'Butter Chicken', 'Classic North Indian curry',
  'Main Course', '4 servings', 30, 45, 450, 'user-chef-001'
);

INSERT INTO recipe_ingredients (recipe_id, product_uuid, quantity, unit_id) VALUES
  (1, 'prod-meat-001', 1, 1),        -- Chicken 1kg
  (1, 'prod-veg-001', 0.2, 1),       -- Onion 200g
  (1, 'prod-veg-002', 0.3, 1),       -- Tomato 300g
  (1, 'prod-dairy-002', 0.1, 1),     -- Butter 100g
  (1, 'prod-dairy-004', 0.2, 3),     -- Cream 200ml
  (1, 'prod-spice-001', 0.01, 1),    -- Turmeric 10g
  (1, 'prod-spice-002', 0.015, 1),   -- Chilli powder 15g
  (1, 'prod-spice-004', 0.01, 1);    -- Garam Masala 10g

-- Recipe 2: Chicken Fried Rice
INSERT INTO recipes (
  uuid, name, description, category, serving_size, preparation_time,
  cooking_time, selling_price, created_by
) VALUES (
  'recipe-002', 'Chicken Fried Rice', 'Chinese style fried rice',
  'Main Course', '2 servings', 15, 20, 280, 'user-chef-002'
);

INSERT INTO recipe_ingredients (recipe_id, product_uuid, quantity, unit_id) VALUES
  (2, 'prod-meat-001', 0.3, 1),      -- Chicken 300g
  (2, 'prod-dry-001', 0.4, 1),       -- Rice 400g (cooked weight)
  (2, 'prod-veg-001', 0.1, 1),       -- Onion 100g
  (2, 'prod-cond-003', 0.03, 3),     -- Soy Sauce 30ml
  (2, 'prod-oil-001', 0.05, 3);      -- Oil 50ml

-- Recipe 3: Paneer Tikka
INSERT INTO recipes (
  uuid, name, description, category, serving_size, preparation_time,
  cooking_time, selling_price, created_by
) VALUES (
  'recipe-003', 'Paneer Tikka', 'Grilled cottage cheese appetizer',
  'Appetizer', '4 servings', 20, 15, 320, 'user-chef-001'
);

INSERT INTO recipe_ingredients (recipe_id, product_uuid, quantity, unit_id) VALUES
  (3, 'prod-dairy-005', 0.5, 1),     -- Paneer 500g
  (3, 'prod-veg-001', 0.1, 1),       -- Onion 100g
  (3, 'prod-spice-001', 0.01, 1),    -- Turmeric 10g
  (3, 'prod-spice-002', 0.01, 1),    -- Chilli powder 10g
  (3, 'prod-oil-001', 0.03, 3);      -- Oil 30ml

-- ============================================================================
-- 10. SAMPLE STOCK TRANSFER
-- ============================================================================

INSERT INTO stock_transfers (
  uuid, transfer_number, from_location_id, to_location_id, transfer_date,
  initiated_by, status, created_by, approved_by
) VALUES (
  'transfer-001', 'TRF-2025-001', 5, 1, '2025-11-04',
  'user-manager-001', 'completed', 'user-manager-001', 'user-admin-001'
);

INSERT INTO stock_transfer_items (transfer_id, product_uuid, quantity, unit_id) VALUES
  (1, 'prod-dairy-002', 5, 1),  -- Butter 5kg from cold storage to main store
  (1, 'prod-dairy-003', 3, 1);  -- Cheese 3kg from cold storage to main store

-- ============================================================================
-- VERIFICATION QUERIES
-- ============================================================================

-- Count records in each table
SELECT 'Users' AS table_name, COUNT(*) AS count FROM users
UNION ALL
SELECT 'Suppliers', COUNT(*) FROM suppliers
UNION ALL
SELECT 'Products', COUNT(*) FROM products
UNION ALL
SELECT 'Purchases', COUNT(*) FROM purchases
UNION ALL
SELECT 'Issues', COUNT(*) FROM issues
UNION ALL
SELECT 'Recipes', COUNT(*) FROM recipes
UNION ALL
SELECT 'Product Batches', COUNT(*) FROM product_batches
UNION ALL
SELECT 'Unit Conversions', COUNT(*) FROM unit_conversions;

-- Show current stock levels (should be populated by triggers)
SELECT
  p.name AS product,
  l.name AS location,
  sl.quantity,
  u.abbreviation AS unit
FROM stock_levels sl
JOIN products p ON sl.product_uuid = p.uuid
JOIN locations l ON sl.location_id = l.id
JOIN units u ON sl.unit_id = u.id
ORDER BY l.name, p.name;

-- Show active alerts (expiry, reorder)
SELECT
  alert_type,
  severity,
  message,
  triggered_at
FROM stock_alerts
WHERE resolved = 0
ORDER BY
  CASE severity
    WHEN 'critical' THEN 1
    WHEN 'high' THEN 2
    WHEN 'medium' THEN 3
    ELSE 4
  END,
  triggered_at;

-- Show stock adjustments log
SELECT
  adjustment_type,
  COUNT(*) AS count,
  SUM(ABS(quantity_change)) AS total_quantity
FROM stock_adjustments
GROUP BY adjustment_type;

SELECT 'Test data seeded successfully!' AS status;
