/**
 * Products Controller
 * Handles product CRUD operations, categories, and units
 */

const { getDatabase, transaction } = require('../config/database');
const logger = require('../config/logger');
const { v4: uuidv4 } = require('uuid');

/**
 * List all products
 * GET /api/products
 */
function listProducts(req, res) {
  try {
    const db = getDatabase();
    const { category_id, active_only, search } = req.query;

    let query = `
      SELECT
        p.*,
        c.name as category_name,
        u1.abbreviation as default_unit,
        u2.abbreviation as base_unit
      FROM products p
      LEFT JOIN categories c ON c.id = p.category_id
      LEFT JOIN units u1 ON u1.id = p.default_unit_id
      LEFT JOIN units u2 ON u2.id = p.base_unit_id
      WHERE 1=1
    `;

    const params = [];

    if (active_only === 'true') {
      query += ' AND p.is_active = 1 AND p.deleted_at IS NULL';
    }

    if (category_id) {
      query += ' AND p.category_id = ?';
      params.push(parseInt(category_id));
    }

    if (search) {
      query += ' AND (p.name LIKE ? OR p.sku LIKE ?)';
      params.push(`%${search}%`, `%${search}%`);
    }

    query += ' ORDER BY p.name ASC';

    const products = db.prepare(query).all(...params);

    res.json({
      success: true,
      products,
      count: products.length
    });
  } catch (error) {
    logger.error('List products error', { error: error.message });
    res.status(500).json({
      success: false,
      error: 'Failed to list products'
    });
  }
}

/**
 * Get single product with stock levels
 * GET /api/products/:uuid
 */
function getProduct(req, res) {
  try {
    const { uuid } = req.params;
    const db = getDatabase();

    const product = db.prepare(`
      SELECT
        p.*,
        c.name as category_name,
        u1.name as default_unit_name,
        u1.abbreviation as default_unit,
        u2.name as base_unit_name,
        u2.abbreviation as base_unit
      FROM products p
      LEFT JOIN categories c ON c.id = p.category_id
      LEFT JOIN units u1 ON u1.id = p.default_unit_id
      LEFT JOIN units u2 ON u2.id = p.base_unit_id
      WHERE p.uuid = ?
    `).get(uuid);

    if (!product) {
      return res.status(404).json({
        success: false,
        error: 'Product not found'
      });
    }

    // Get stock levels across all locations
    const stockLevels = db.prepare(`
      SELECT
        sl.*,
        l.name as location_name
      FROM stock_levels sl
      LEFT JOIN locations l ON l.uuid = sl.location_uuid
      WHERE sl.product_uuid = ?
    `).all(uuid);

    // Get recent stock adjustments
    const recentAdjustments = db.prepare(`
      SELECT
        sa.*,
        l.name as location_name,
        u.full_name as created_by_name
      FROM stock_adjustments sa
      LEFT JOIN locations l ON l.uuid = sa.location_uuid
      LEFT JOIN users u ON u.uuid = sa.created_by
      WHERE sa.product_uuid = ?
      ORDER BY sa.created_at DESC
      LIMIT 10
    `).all(uuid);

    res.json({
      success: true,
      product,
      stock_levels: stockLevels,
      recent_adjustments: recentAdjustments
    });
  } catch (error) {
    logger.error('Get product error', { error: error.message });
    res.status(500).json({
      success: false,
      error: 'Failed to get product'
    });
  }
}

/**
 * Create new product
 * POST /api/products
 */
function createProduct(req, res) {
  try {
    const {
      name,
      sku,
      category_id,
      default_unit_id,
      base_unit_id,
      description,
      reorder_level,
      min_stock_level,
      max_stock_level,
      cost_price,
      selling_price,
      gst_rate
    } = req.body;

    // Validation
    if (!name || !default_unit_id || !base_unit_id) {
      return res.status(400).json({
        success: false,
        error: 'Name, default_unit_id, and base_unit_id are required'
      });
    }

    const db = getDatabase();

    // Check if SKU already exists (if provided)
    if (sku) {
      const existing = db.prepare(
        'SELECT uuid FROM products WHERE sku = ? AND deleted_at IS NULL'
      ).get(sku);

      if (existing) {
        return res.status(409).json({
          success: false,
          error: 'SKU already exists'
        });
      }
    }

    const productUuid = uuidv4();
    const now = new Date().toISOString();

    const result = transaction(() => {
      db.prepare(`
        INSERT INTO products (
          uuid, name, sku, category_id, default_unit_id, base_unit_id,
          description, reorder_level, min_stock_level, max_stock_level,
          cost_price, selling_price, gst_rate, is_active,
          created_at, last_modified, created_by
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 1, ?, ?, ?)
      `).run(
        productUuid,
        name,
        sku || null,
        category_id || null,
        default_unit_id,
        base_unit_id,
        description || null,
        reorder_level || 0,
        min_stock_level || 0,
        max_stock_level || null,
        cost_price || 0,
        selling_price || 0,
        gst_rate || 0,
        now,
        now,
        req.user.uuid
      );

      // Add to sync queue
      db.prepare(`
        INSERT INTO sync_queue (table_name, operation, record_uuid, payload, created_at)
        VALUES ('products', 'insert', ?, ?, datetime('now'))
      `).run(productUuid, JSON.stringify({
        uuid: productUuid,
        name,
        sku,
        category_id,
        default_unit_id,
        base_unit_id,
        description,
        reorder_level: reorder_level || 0,
        min_stock_level: min_stock_level || 0,
        max_stock_level,
        cost_price: cost_price || 0,
        selling_price: selling_price || 0,
        gst_rate: gst_rate || 0,
        is_active: 1,
        created_at: now,
        last_modified: now,
        created_by: req.user.uuid
      }));

      // Log audit
      db.prepare(`
        INSERT INTO audit_logs (table_name, record_uuid, operation, user_uuid, new_values)
        VALUES ('products', ?, 'insert', ?, ?)
      `).run(productUuid, req.user.uuid, JSON.stringify(req.body));

      return { success: true };
    });

    logger.info('Product created', { product_uuid: productUuid, name, by_user: req.user.username });

    res.status(201).json({
      success: true,
      message: 'Product created successfully',
      product: {
        uuid: productUuid,
        name,
        sku
      }
    });
  } catch (error) {
    logger.error('Create product error', { error: error.message });
    res.status(500).json({
      success: false,
      error: 'Failed to create product'
    });
  }
}

/**
 * Update product
 * PUT /api/products/:uuid
 */
function updateProduct(req, res) {
  try {
    const { uuid } = req.params;
    const db = getDatabase();

    // Check product exists
    const product = db.prepare('SELECT * FROM products WHERE uuid = ?').get(uuid);

    if (!product) {
      return res.status(404).json({
        success: false,
        error: 'Product not found'
      });
    }

    // Build update query
    const allowedFields = [
      'name', 'sku', 'category_id', 'default_unit_id', 'base_unit_id',
      'description', 'reorder_level', 'min_stock_level', 'max_stock_level',
      'cost_price', 'selling_price', 'gst_rate', 'is_active'
    ];

    const updates = [];
    const values = [];

    allowedFields.forEach(field => {
      if (req.body[field] !== undefined) {
        updates.push(`${field} = ?`);
        values.push(req.body[field]);
      }
    });

    if (updates.length === 0) {
      return res.status(400).json({
        success: false,
        error: 'No fields to update'
      });
    }

    const now = new Date().toISOString();
    updates.push('last_modified = ?');
    values.push(now);
    values.push(uuid);

    const result = transaction(() => {
      db.prepare(`
        UPDATE products SET ${updates.join(', ')} WHERE uuid = ?
      `).run(...values);

      // Add to sync queue
      const updatedProduct = db.prepare('SELECT * FROM products WHERE uuid = ?').get(uuid);
      db.prepare(`
        INSERT INTO sync_queue (table_name, operation, record_uuid, payload, created_at)
        VALUES ('products', 'update', ?, ?, datetime('now'))
      `).run(uuid, JSON.stringify(updatedProduct));

      // Log audit
      db.prepare(`
        INSERT INTO audit_logs (table_name, record_uuid, operation, user_uuid, old_values, new_values)
        VALUES ('products', ?, 'update', ?, ?, ?)
      `).run(uuid, req.user.uuid, JSON.stringify(product), JSON.stringify(req.body));

      return { success: true };
    });

    logger.info('Product updated', { product_uuid: uuid, by_user: req.user.username });

    res.json({
      success: true,
      message: 'Product updated successfully'
    });
  } catch (error) {
    logger.error('Update product error', { error: error.message });
    res.status(500).json({
      success: false,
      error: 'Failed to update product'
    });
  }
}

/**
 * Delete product (soft delete)
 * DELETE /api/products/:uuid
 */
function deleteProduct(req, res) {
  try {
    const { uuid } = req.params;
    const db = getDatabase();

    // Check product exists
    const product = db.prepare('SELECT * FROM products WHERE uuid = ?').get(uuid);

    if (!product) {
      return res.status(404).json({
        success: false,
        error: 'Product not found'
      });
    }

    const now = new Date().toISOString();

    const result = transaction(() => {
      db.prepare(`
        UPDATE products
        SET is_active = 0, deleted_at = ?, deleted_by = ?, last_modified = ?
        WHERE uuid = ?
      `).run(now, req.user.uuid, now, uuid);

      // Add to sync queue
      db.prepare(`
        INSERT INTO sync_queue (table_name, operation, record_uuid, payload, created_at)
        VALUES ('products', 'delete', ?, ?, datetime('now'))
      `).run(uuid, JSON.stringify({ uuid, deleted_at: now, deleted_by: req.user.uuid }));

      // Log audit
      db.prepare(`
        INSERT INTO audit_logs (table_name, record_uuid, operation, user_uuid, old_values)
        VALUES ('products', ?, 'delete', ?, ?)
      `).run(uuid, req.user.uuid, JSON.stringify(product));

      return { success: true };
    });

    logger.info('Product deleted', { product_uuid: uuid, by_user: req.user.username });

    res.json({
      success: true,
      message: 'Product deleted successfully'
    });
  } catch (error) {
    logger.error('Delete product error', { error: error.message });
    res.status(500).json({
      success: false,
      error: 'Failed to delete product'
    });
  }
}

/**
 * Get product stock summary
 * GET /api/products/:uuid/stock
 */
function getProductStock(req, res) {
  try {
    const { uuid } = req.params;
    const db = getDatabase();

    const stockSummary = db.prepare(`
      SELECT
        p.uuid,
        p.name,
        p.sku,
        p.reorder_level,
        u.abbreviation as unit,
        COALESCE(SUM(sl.quantity), 0) as total_quantity,
        COUNT(DISTINCT sl.location_uuid) as locations_count
      FROM products p
      LEFT JOIN stock_levels sl ON sl.product_uuid = p.uuid
      LEFT JOIN units u ON u.id = p.default_unit_id
      WHERE p.uuid = ?
      GROUP BY p.uuid
    `).get(uuid);

    if (!stockSummary) {
      return res.status(404).json({
        success: false,
        error: 'Product not found'
      });
    }

    // Get stock by location
    const stockByLocation = db.prepare(`
      SELECT
        l.name as location_name,
        sl.quantity,
        sl.last_modified
      FROM stock_levels sl
      JOIN locations l ON l.uuid = sl.location_uuid
      WHERE sl.product_uuid = ?
    `).all(uuid);

    res.json({
      success: true,
      summary: stockSummary,
      by_location: stockByLocation
    });
  } catch (error) {
    logger.error('Get product stock error', { error: error.message });
    res.status(500).json({
      success: false,
      error: 'Failed to get product stock'
    });
  }
}

// ============================================================================
// CATEGORIES
// ============================================================================

/**
 * List all categories
 * GET /api/categories
 */
function listCategories(req, res) {
  try {
    const db = getDatabase();

    const categories = db.prepare(`
      SELECT
        c.*,
        pc.name as parent_category_name,
        COUNT(DISTINCT p.uuid) as product_count
      FROM categories c
      LEFT JOIN categories pc ON pc.id = c.parent_category_id
      LEFT JOIN products p ON p.category_id = c.id AND p.is_active = 1
      GROUP BY c.id
      ORDER BY c.name ASC
    `).all();

    res.json({
      success: true,
      categories,
      count: categories.length
    });
  } catch (error) {
    logger.error('List categories error', { error: error.message });
    res.status(500).json({
      success: false,
      error: 'Failed to list categories'
    });
  }
}

/**
 * Create category
 * POST /api/categories
 */
function createCategory(req, res) {
  try {
    const { name, description, parent_category_id } = req.body;

    if (!name) {
      return res.status(400).json({
        success: false,
        error: 'Name is required'
      });
    }

    const db = getDatabase();
    const categoryUuid = uuidv4();
    const now = new Date().toISOString();

    const result = transaction(() => {
      const info = db.prepare(`
        INSERT INTO categories (uuid, name, description, parent_category_id, created_at, last_modified)
        VALUES (?, ?, ?, ?, ?, ?)
      `).run(categoryUuid, name, description || null, parent_category_id || null, now, now);

      // Add to sync queue
      db.prepare(`
        INSERT INTO sync_queue (table_name, operation, record_uuid, payload, created_at)
        VALUES ('categories', 'insert', ?, ?, datetime('now'))
      `).run(categoryUuid, JSON.stringify({
        uuid: categoryUuid,
        name,
        description,
        parent_category_id,
        created_at: now,
        last_modified: now
      }));

      return { success: true, id: info.lastInsertRowid };
    });

    logger.info('Category created', { category_uuid: categoryUuid, name });

    res.status(201).json({
      success: true,
      message: 'Category created successfully',
      category: {
        uuid: categoryUuid,
        name
      }
    });
  } catch (error) {
    logger.error('Create category error', { error: error.message });
    res.status(500).json({
      success: false,
      error: 'Failed to create category'
    });
  }
}

// ============================================================================
// UNITS
// ============================================================================

/**
 * List all units
 * GET /api/units
 */
function listUnits(req, res) {
  try {
    const db = getDatabase();

    const units = db.prepare(`
      SELECT * FROM units ORDER BY unit_type, name ASC
    `).all();

    res.json({
      success: true,
      units,
      count: units.length
    });
  } catch (error) {
    logger.error('List units error', { error: error.message });
    res.status(500).json({
      success: false,
      error: 'Failed to list units'
    });
  }
}

/**
 * Get unit conversions
 * GET /api/units/conversions
 */
function getUnitConversions(req, res) {
  try {
    const db = getDatabase();

    const conversions = db.prepare(`
      SELECT
        uc.*,
        u1.name as from_unit_name,
        u1.abbreviation as from_unit,
        u2.name as to_unit_name,
        u2.abbreviation as to_unit
      FROM unit_conversions uc
      JOIN units u1 ON u1.id = uc.from_unit_id
      JOIN units u2 ON u2.id = uc.to_unit_id
      ORDER BY u1.name, u2.name
    `).all();

    res.json({
      success: true,
      conversions,
      count: conversions.length
    });
  } catch (error) {
    logger.error('Get unit conversions error', { error: error.message });
    res.status(500).json({
      success: false,
      error: 'Failed to get unit conversions'
    });
  }
}

module.exports = {
  listProducts,
  getProduct,
  createProduct,
  updateProduct,
  deleteProduct,
  getProductStock,
  listCategories,
  createCategory,
  listUnits,
  getUnitConversions
};
