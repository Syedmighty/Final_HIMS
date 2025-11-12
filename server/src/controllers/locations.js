/**
 * Locations Controller
 * Handles warehouses, kitchens, stores, and other storage locations
 */

const { getDatabase, transaction } = require('../config/database');
const logger = require('../config/logger');
const { v4: uuidv4 } = require('uuid');

/**
 * List all locations
 * GET /api/locations
 */
function listLocations(req, res) {
  try {
    const db = getDatabase();
    const { active_only, location_type } = req.query;

    let query = 'SELECT * FROM locations WHERE 1=1';
    const params = [];

    if (active_only === 'true') {
      query += ' AND is_active = 1';
    }

    if (location_type) {
      query += ' AND location_type = ?';
      params.push(location_type);
    }

    query += ' ORDER BY name ASC';

    const locations = db.prepare(query).all(...params);

    // Get stock summary for each location
    const locationsWithStock = locations.map(location => {
      const stockSummary = db.prepare(`
        SELECT
          COUNT(DISTINCT product_uuid) as products_count,
          COALESCE(SUM(quantity), 0) as total_quantity
        FROM stock_levels
        WHERE location_uuid = ? AND quantity > 0
      `).get(location.uuid);

      return {
        ...location,
        stock_summary: stockSummary
      };
    });

    res.json({
      success: true,
      locations: locationsWithStock,
      count: locationsWithStock.length
    });
  } catch (error) {
    logger.error('List locations error', { error: error.message });
    res.status(500).json({
      success: false,
      error: 'Failed to list locations'
    });
  }
}

/**
 * Get single location with detailed stock information
 * GET /api/locations/:uuid
 */
function getLocation(req, res) {
  try {
    const { uuid } = req.params;
    const db = getDatabase();

    const location = db.prepare('SELECT * FROM locations WHERE uuid = ?').get(uuid);

    if (!location) {
      return res.status(404).json({
        success: false,
        error: 'Location not found'
      });
    }

    // Get stock summary
    const stockSummary = db.prepare(`
      SELECT
        COUNT(DISTINCT product_uuid) as products_count,
        COALESCE(SUM(quantity), 0) as total_quantity,
        COALESCE(SUM(CASE WHEN quantity <= (
          SELECT reorder_level FROM products WHERE uuid = stock_levels.product_uuid
        ) THEN 1 ELSE 0 END), 0) as low_stock_count
      FROM stock_levels
      WHERE location_uuid = ? AND quantity > 0
    `).get(uuid);

    // Get stock items at this location
    const stockItems = db.prepare(`
      SELECT
        sl.*,
        p.name as product_name,
        p.sku,
        p.reorder_level,
        u.abbreviation as unit
      FROM stock_levels sl
      JOIN products p ON p.uuid = sl.product_uuid
      LEFT JOIN units u ON u.id = p.default_unit_id
      WHERE sl.location_uuid = ? AND sl.quantity > 0
      ORDER BY p.name ASC
    `).all(uuid);

    res.json({
      success: true,
      location,
      stock_summary: stockSummary,
      stock_items: stockItems
    });
  } catch (error) {
    logger.error('Get location error', { error: error.message });
    res.status(500).json({
      success: false,
      error: 'Failed to get location'
    });
  }
}

/**
 * Create new location
 * POST /api/locations
 */
function createLocation(req, res) {
  try {
    const { name, location_type, description } = req.body;

    // Validation
    if (!name) {
      return res.status(400).json({
        success: false,
        error: 'Name is required'
      });
    }

    if (location_type && !['warehouse', 'kitchen', 'bar', 'restaurant', 'store'].includes(location_type)) {
      return res.status(400).json({
        success: false,
        error: 'location_type must be: warehouse, kitchen, bar, restaurant, or store'
      });
    }

    const db = getDatabase();
    const locationUuid = uuidv4();
    const now = new Date().toISOString();

    // Check for duplicate name
    const existingLocation = db.prepare('SELECT uuid FROM locations WHERE name = ?').get(name);
    if (existingLocation) {
      return res.status(409).json({
        success: false,
        error: 'Location with this name already exists'
      });
    }

    const result = transaction(() => {
      db.prepare(`
        INSERT INTO locations (
          uuid, name, location_type, description, is_active,
          created_at, last_modified
        ) VALUES (?, ?, ?, ?, 1, ?, ?)
      `).run(
        locationUuid,
        name,
        location_type || null,
        description || null,
        now,
        now
      );

      // Add to sync queue
      const locationData = db.prepare('SELECT * FROM locations WHERE uuid = ?').get(locationUuid);
      db.prepare(`
        INSERT INTO sync_queue (table_name, operation, record_uuid, payload, created_at)
        VALUES ('locations', 'insert', ?, ?, datetime('now'))
      `).run(locationUuid, JSON.stringify(locationData));

      // Log audit
      db.prepare(`
        INSERT INTO audit_logs (table_name, record_uuid, operation, user_uuid, new_values)
        VALUES ('locations', ?, 'insert', ?, ?)
      `).run(locationUuid, req.user.uuid, JSON.stringify({ name, location_type, description }));

      return { success: true };
    });

    logger.info('Location created', {
      location_uuid: locationUuid,
      name,
      by_user: req.user.username
    });

    res.status(201).json({
      success: true,
      message: 'Location created successfully',
      location: {
        uuid: locationUuid,
        name
      }
    });
  } catch (error) {
    logger.error('Create location error', { error: error.message, stack: error.stack });
    res.status(500).json({
      success: false,
      error: 'Failed to create location'
    });
  }
}

/**
 * Update location
 * PUT /api/locations/:uuid
 */
function updateLocation(req, res) {
  try {
    const { uuid } = req.params;
    const { name, location_type, description, is_active } = req.body;

    const db = getDatabase();

    const location = db.prepare('SELECT * FROM locations WHERE uuid = ?').get(uuid);

    if (!location) {
      return res.status(404).json({
        success: false,
        error: 'Location not found'
      });
    }

    // Check for duplicate name (excluding current location)
    if (name && name !== location.name) {
      const existingLocation = db.prepare(
        'SELECT uuid FROM locations WHERE name = ? AND uuid != ?'
      ).get(name, uuid);

      if (existingLocation) {
        return res.status(409).json({
          success: false,
          error: 'Location with this name already exists'
        });
      }
    }

    if (location_type && !['warehouse', 'kitchen', 'bar', 'restaurant', 'store'].includes(location_type)) {
      return res.status(400).json({
        success: false,
        error: 'location_type must be: warehouse, kitchen, bar, restaurant, or store'
      });
    }

    const now = new Date().toISOString();

    const result = transaction(() => {
      const updates = {};
      if (name !== undefined) updates.name = name;
      if (location_type !== undefined) updates.location_type = location_type;
      if (description !== undefined) updates.description = description;
      if (is_active !== undefined) updates.is_active = is_active ? 1 : 0;
      updates.last_modified = now;

      const updateFields = Object.keys(updates).map(k => `${k} = ?`).join(', ');
      const updateValues = [...Object.values(updates), uuid];

      db.prepare(`
        UPDATE locations SET ${updateFields} WHERE uuid = ?
      `).run(...updateValues);

      // Add to sync queue
      const updatedLocation = db.prepare('SELECT * FROM locations WHERE uuid = ?').get(uuid);
      db.prepare(`
        INSERT INTO sync_queue (table_name, operation, record_uuid, payload, created_at)
        VALUES ('locations', 'update', ?, ?, datetime('now'))
      `).run(uuid, JSON.stringify(updatedLocation));

      // Log audit
      db.prepare(`
        INSERT INTO audit_logs (table_name, record_uuid, operation, user_uuid, old_values, new_values)
        VALUES ('locations', ?, 'update', ?, ?, ?)
      `).run(uuid, req.user.uuid, JSON.stringify(location), JSON.stringify(updates));

      return { success: true };
    });

    logger.info('Location updated', { location_uuid: uuid, by_user: req.user.username });

    res.json({
      success: true,
      message: 'Location updated successfully'
    });
  } catch (error) {
    logger.error('Update location error', { error: error.message });
    res.status(500).json({
      success: false,
      error: 'Failed to update location'
    });
  }
}

/**
 * Delete location (soft delete by deactivating)
 * DELETE /api/locations/:uuid
 */
function deleteLocation(req, res) {
  try {
    const { uuid } = req.params;
    const db = getDatabase();

    const location = db.prepare('SELECT * FROM locations WHERE uuid = ?').get(uuid);

    if (!location) {
      return res.status(404).json({
        success: false,
        error: 'Location not found'
      });
    }

    // Check if location has stock
    const stockCount = db.prepare(`
      SELECT COUNT(*) as count
      FROM stock_levels
      WHERE location_uuid = ? AND quantity > 0
    `).get(uuid);

    if (stockCount.count > 0) {
      return res.status(400).json({
        success: false,
        error: `Cannot delete location with existing stock (${stockCount.count} products). Please transfer or remove stock first.`
      });
    }

    // Check if location is referenced in any pending transactions
    const hasPendingTransactions = db.prepare(`
      SELECT
        (SELECT COUNT(*) FROM purchases WHERE location_uuid = ? AND status != 'received') +
        (SELECT COUNT(*) FROM issues WHERE (from_location_uuid = ? OR to_location_uuid = ?) AND status != 'issued') +
        (SELECT COUNT(*) FROM transfers WHERE (from_location_uuid = ? OR to_location_uuid = ?) AND status != 'completed') +
        (SELECT COUNT(*) FROM wastages WHERE location_uuid = ? AND status != 'approved') as count
    `).get(uuid, uuid, uuid, uuid, uuid, uuid);

    if (hasPendingTransactions.count > 0) {
      return res.status(400).json({
        success: false,
        error: 'Cannot delete location with pending transactions. Please complete or cancel them first.'
      });
    }

    const now = new Date().toISOString();

    const result = transaction(() => {
      // Soft delete by deactivating
      db.prepare(`
        UPDATE locations
        SET is_active = 0, last_modified = ?
        WHERE uuid = ?
      `).run(now, uuid);

      // Log audit
      db.prepare(`
        INSERT INTO audit_logs (table_name, record_uuid, operation, user_uuid, old_values)
        VALUES ('locations', ?, 'delete', ?, ?)
      `).run(uuid, req.user.uuid, JSON.stringify(location));

      return { success: true };
    });

    logger.info('Location deleted (deactivated)', { location_uuid: uuid, by_user: req.user.username });

    res.json({
      success: true,
      message: 'Location deleted successfully'
    });
  } catch (error) {
    logger.error('Delete location error', { error: error.message });
    res.status(500).json({
      success: false,
      error: 'Failed to delete location'
    });
  }
}

/**
 * Get location stock summary with low stock alerts
 * GET /api/locations/:uuid/stock-summary
 */
function getLocationStockSummary(req, res) {
  try {
    const { uuid } = req.params;
    const db = getDatabase();

    const location = db.prepare('SELECT * FROM locations WHERE uuid = ?').get(uuid);

    if (!location) {
      return res.status(404).json({
        success: false,
        error: 'Location not found'
      });
    }

    // Get products below reorder level
    const lowStockItems = db.prepare(`
      SELECT
        p.uuid as product_uuid,
        p.name as product_name,
        p.sku,
        sl.quantity as current_stock,
        p.reorder_level,
        p.min_stock_level,
        u.abbreviation as unit
      FROM stock_levels sl
      JOIN products p ON p.uuid = sl.product_uuid
      LEFT JOIN units u ON u.id = p.default_unit_id
      WHERE sl.location_uuid = ?
        AND sl.quantity <= p.reorder_level
        AND sl.quantity > 0
      ORDER BY (sl.quantity - p.reorder_level) ASC
    `).all(uuid);

    // Get out of stock items that had stock before
    const outOfStockItems = db.prepare(`
      SELECT
        p.uuid as product_uuid,
        p.name as product_name,
        p.sku,
        p.reorder_level,
        u.abbreviation as unit
      FROM products p
      LEFT JOIN units u ON u.id = p.default_unit_id
      WHERE p.uuid IN (
        SELECT DISTINCT product_uuid
        FROM stock_adjustments
        WHERE location_uuid = ?
      )
      AND p.uuid NOT IN (
        SELECT product_uuid
        FROM stock_levels
        WHERE location_uuid = ? AND quantity > 0
      )
      AND p.is_active = 1
      ORDER BY p.name ASC
    `).all(uuid, uuid);

    // Overall summary
    const summary = db.prepare(`
      SELECT
        COUNT(DISTINCT sl.product_uuid) as total_products,
        COALESCE(SUM(sl.quantity), 0) as total_quantity,
        COUNT(CASE WHEN sl.quantity <= p.reorder_level THEN 1 END) as low_stock_count,
        COUNT(CASE WHEN sl.quantity <= p.min_stock_level THEN 1 END) as critical_stock_count
      FROM stock_levels sl
      JOIN products p ON p.uuid = sl.product_uuid
      WHERE sl.location_uuid = ? AND sl.quantity > 0
    `).get(uuid);

    res.json({
      success: true,
      location: {
        uuid: location.uuid,
        name: location.name,
        location_type: location.location_type
      },
      summary,
      low_stock_items: lowStockItems,
      out_of_stock_items: outOfStockItems,
      alerts: {
        low_stock: lowStockItems.length,
        out_of_stock: outOfStockItems.length,
        total_alerts: lowStockItems.length + outOfStockItems.length
      }
    });
  } catch (error) {
    logger.error('Get location stock summary error', { error: error.message });
    res.status(500).json({
      success: false,
      error: 'Failed to get location stock summary'
    });
  }
}

module.exports = {
  listLocations,
  getLocation,
  createLocation,
  updateLocation,
  deleteLocation,
  getLocationStockSummary
};
