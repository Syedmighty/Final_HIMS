/**
 * Wastage Controller
 * Handles damaged, expired, spoiled, and other wastage tracking
 */

const { getDatabase, transaction } = require('../config/database');
const logger = require('../config/logger');
const { v4: uuidv4 } = require('uuid');

/**
 * List all wastage records
 * GET /api/wastage
 */
function listWastage(req, res) {
  try {
    const db = getDatabase();
    const { status, wastage_type, location_uuid, from_date, to_date } = req.query;

    let query = `
      SELECT
        w.*,
        l.name as location_name,
        u1.full_name as created_by_name,
        u2.full_name as approved_by_name,
        COUNT(wi.id) as items_count
      FROM wastages w
      LEFT JOIN locations l ON l.uuid = w.location_uuid
      LEFT JOIN users u1 ON u1.uuid = w.created_by
      LEFT JOIN users u2 ON u2.uuid = w.approved_by
      LEFT JOIN wastage_items wi ON wi.wastage_uuid = w.uuid
      WHERE 1=1
    `;

    const params = [];

    if (status) {
      query += ' AND w.status = ?';
      params.push(status);
    }

    if (wastage_type) {
      query += ' AND w.wastage_type = ?';
      params.push(wastage_type);
    }

    if (location_uuid) {
      query += ' AND w.location_uuid = ?';
      params.push(location_uuid);
    }

    if (from_date) {
      query += ' AND w.wastage_date >= ?';
      params.push(from_date);
    }

    if (to_date) {
      query += ' AND w.wastage_date <= ?';
      params.push(to_date);
    }

    query += ' GROUP BY w.id ORDER BY w.wastage_date DESC, w.created_at DESC';

    const wastages = db.prepare(query).all(...params);

    res.json({
      success: true,
      wastages,
      count: wastages.length
    });
  } catch (error) {
    logger.error('List wastage error', { error: error.message });
    res.status(500).json({
      success: false,
      error: 'Failed to list wastage records'
    });
  }
}

/**
 * Get single wastage record with items
 * GET /api/wastage/:uuid
 */
function getWastage(req, res) {
  try {
    const { uuid } = req.params;
    const db = getDatabase();

    const wastage = db.prepare(`
      SELECT
        w.*,
        l.name as location_name,
        u1.full_name as created_by_name,
        u2.full_name as approved_by_name
      FROM wastages w
      LEFT JOIN locations l ON l.uuid = w.location_uuid
      LEFT JOIN users u1 ON u1.uuid = w.created_by
      LEFT JOIN users u2 ON u2.uuid = w.approved_by
      WHERE w.uuid = ?
    `).get(uuid);

    if (!wastage) {
      return res.status(404).json({
        success: false,
        error: 'Wastage record not found'
      });
    }

    // Get wastage items
    const items = db.prepare(`
      SELECT
        wi.*,
        p.name as product_name,
        p.sku,
        u.abbreviation as unit
      FROM wastage_items wi
      LEFT JOIN products p ON p.uuid = wi.product_uuid
      LEFT JOIN units u ON u.id = wi.unit_id
      WHERE wi.wastage_uuid = ?
      ORDER BY wi.created_at
    `).all(uuid);

    res.json({
      success: true,
      wastage,
      items
    });
  } catch (error) {
    logger.error('Get wastage error', { error: error.message });
    res.status(500).json({
      success: false,
      error: 'Failed to get wastage record'
    });
  }
}

/**
 * Create new wastage record
 * POST /api/wastage
 */
function createWastage(req, res) {
  try {
    const {
      location_uuid,
      wastage_date,
      wastage_type,
      notes,
      items
    } = req.body;

    // Validation
    if (!location_uuid || !wastage_date || !wastage_type) {
      return res.status(400).json({
        success: false,
        error: 'location_uuid, wastage_date, and wastage_type are required'
      });
    }

    if (!['damage', 'expiry', 'spoilage', 'other'].includes(wastage_type)) {
      return res.status(400).json({
        success: false,
        error: 'wastage_type must be: damage, expiry, spoilage, or other'
      });
    }

    if (!items || !Array.isArray(items) || items.length === 0) {
      return res.status(400).json({
        success: false,
        error: 'At least one item is required'
      });
    }

    const db = getDatabase();
    const wastageUuid = uuidv4();
    const now = new Date().toISOString();

    // Generate wastage number
    const lastWastage = db.prepare(
      "SELECT wastage_number FROM wastages ORDER BY id DESC LIMIT 1"
    ).get();

    let wastageNumber = 'WST0001';
    if (lastWastage) {
      const lastNum = parseInt(lastWastage.wastage_number.substring(3));
      wastageNumber = `WST${String(lastNum + 1).padStart(4, '0')}`;
    }

    const result = transaction(() => {
      // Check stock availability (optional warning, but don't block)
      const insufficientItems = [];

      for (const item of items) {
        const stockLevel = db.prepare(`
          SELECT quantity FROM stock_levels
          WHERE product_uuid = ? AND location_uuid = ?
        `).get(item.product_uuid, location_uuid);

        const available = stockLevel ? stockLevel.quantity : 0;

        if (available < item.quantity) {
          const product = db.prepare('SELECT name FROM products WHERE uuid = ?').get(item.product_uuid);
          insufficientItems.push({
            product: product.name,
            required: item.quantity,
            available
          });
        }
      }

      // Insert wastage header
      db.prepare(`
        INSERT INTO wastages (
          uuid, wastage_number, location_uuid, wastage_date,
          wastage_type, status, notes,
          created_at, last_modified, created_by
        ) VALUES (?, ?, ?, ?, ?, 'draft', ?, ?, ?, ?)
      `).run(
        wastageUuid,
        wastageNumber,
        location_uuid,
        wastage_date,
        wastage_type,
        notes || null,
        now,
        now,
        req.user.uuid
      );

      // Insert wastage items
      items.forEach(item => {
        const itemUuid = uuidv4();

        db.prepare(`
          INSERT INTO wastage_items (
            uuid, wastage_uuid, product_uuid, quantity, unit_id,
            reason, created_at, last_modified
          ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        `).run(
          itemUuid,
          wastageUuid,
          item.product_uuid,
          item.quantity,
          item.unit_id,
          item.reason || null,
          now,
          now
        );
      });

      // Add to sync queue
      const wastageData = db.prepare('SELECT * FROM wastages WHERE uuid = ?').get(wastageUuid);
      db.prepare(`
        INSERT INTO sync_queue (table_name, operation, record_uuid, payload, created_at)
        VALUES ('wastages', 'insert', ?, ?, datetime('now'))
      `).run(wastageUuid, JSON.stringify(wastageData));

      // Log audit
      db.prepare(`
        INSERT INTO audit_logs (table_name, record_uuid, operation, user_uuid, new_values)
        VALUES ('wastages', ?, 'insert', ?, ?)
      `).run(wastageUuid, req.user.uuid, JSON.stringify({ items: items.length }));

      return {
        success: true,
        insufficientItems: insufficientItems.length > 0 ? insufficientItems : null
      };
    });

    logger.info('Wastage created', {
      wastage_uuid: wastageUuid,
      wastage_number: wastageNumber,
      wastage_type,
      items_count: items.length,
      by_user: req.user.username
    });

    const response = {
      success: true,
      message: 'Wastage record created successfully',
      wastage: {
        uuid: wastageUuid,
        wastage_number: wastageNumber
      }
    };

    // Add warning if there are insufficient items
    if (result.insufficientItems) {
      response.warning = 'Some items have quantities exceeding available stock';
      response.insufficient_items = result.insufficientItems;
    }

    res.status(201).json(response);
  } catch (error) {
    logger.error('Create wastage error', { error: error.message, stack: error.stack });
    res.status(500).json({
      success: false,
      error: 'Failed to create wastage record'
    });
  }
}

/**
 * Update wastage status
 * PUT /api/wastage/:uuid/status
 */
function updateWastageStatus(req, res) {
  try {
    const { uuid } = req.params;
    const { status } = req.body;

    if (!['draft', 'approved', 'cancelled'].includes(status)) {
      return res.status(400).json({
        success: false,
        error: 'Invalid status. Must be: draft, approved, or cancelled'
      });
    }

    const db = getDatabase();

    // Get wastage
    const wastage = db.prepare('SELECT * FROM wastages WHERE uuid = ?').get(uuid);

    if (!wastage) {
      return res.status(404).json({
        success: false,
        error: 'Wastage record not found'
      });
    }

    // Cannot change status if already approved
    if (wastage.status === 'approved' && status !== 'approved') {
      return res.status(400).json({
        success: false,
        error: 'Cannot change status of approved wastage'
      });
    }

    const now = new Date().toISOString();

    const result = transaction(() => {
      // If approving, check stock availability
      if (status === 'approved' && wastage.status !== 'approved') {
        const items = db.prepare('SELECT * FROM wastage_items WHERE wastage_uuid = ?').all(uuid);
        const insufficientItems = [];

        for (const item of items) {
          const stockLevel = db.prepare(`
            SELECT quantity FROM stock_levels
            WHERE product_uuid = ? AND location_uuid = ?
          `).get(item.product_uuid, wastage.location_uuid);

          const available = stockLevel ? stockLevel.quantity : 0;

          if (available < item.quantity) {
            const product = db.prepare('SELECT name FROM products WHERE uuid = ?').get(item.product_uuid);
            insufficientItems.push({
              product: product.name,
              required: item.quantity,
              available
            });
          }
        }

        if (insufficientItems.length > 0) {
          throw new Error(JSON.stringify({
            message: 'Insufficient stock for one or more items',
            items: insufficientItems
          }));
        }
      }

      const updates = {
        status,
        last_modified: now
      };

      if (status === 'approved') {
        updates.approved_by = req.user.uuid;
        updates.approved_at = now;
      }

      const updateFields = Object.keys(updates).map(k => `${k} = ?`).join(', ');
      const updateValues = [...Object.values(updates), uuid];

      db.prepare(`
        UPDATE wastages SET ${updateFields} WHERE uuid = ?
      `).run(...updateValues);

      // Trigger will handle stock deduction if status is 'approved'

      // Add to sync queue
      const updatedWastage = db.prepare('SELECT * FROM wastages WHERE uuid = ?').get(uuid);
      db.prepare(`
        INSERT INTO sync_queue (table_name, operation, record_uuid, payload, created_at)
        VALUES ('wastages', 'update', ?, ?, datetime('now'))
      `).run(uuid, JSON.stringify(updatedWastage));

      // Log audit
      db.prepare(`
        INSERT INTO audit_logs (table_name, record_uuid, operation, user_uuid, old_values, new_values)
        VALUES ('wastages', ?, 'update', ?, ?, ?)
      `).run(uuid, req.user.uuid, JSON.stringify(wastage), JSON.stringify(updates));

      return { success: true };
    });

    logger.info('Wastage status updated', {
      wastage_uuid: uuid,
      old_status: wastage.status,
      new_status: status,
      by_user: req.user.username
    });

    res.json({
      success: true,
      message: 'Wastage status updated successfully',
      status
    });
  } catch (error) {
    // Check if error is from stock validation
    try {
      const parsedError = JSON.parse(error.message);
      return res.status(400).json({
        success: false,
        error: parsedError.message,
        insufficient_items: parsedError.items
      });
    } catch {
      // Not a JSON error, regular error
      logger.error('Update wastage status error', { error: error.message });
      res.status(500).json({
        success: false,
        error: 'Failed to update wastage status'
      });
    }
  }
}

/**
 * Delete wastage record
 * DELETE /api/wastage/:uuid
 */
function deleteWastage(req, res) {
  try {
    const { uuid } = req.params;
    const db = getDatabase();

    const wastage = db.prepare('SELECT * FROM wastages WHERE uuid = ?').get(uuid);

    if (!wastage) {
      return res.status(404).json({
        success: false,
        error: 'Wastage record not found'
      });
    }

    // Cannot delete approved wastages
    if (wastage.status === 'approved') {
      return res.status(400).json({
        success: false,
        error: 'Cannot delete approved wastage. Stock has already been deducted.'
      });
    }

    const result = transaction(() => {
      // Delete wastage items (CASCADE will handle this)
      db.prepare('DELETE FROM wastage_items WHERE wastage_uuid = ?').run(uuid);

      // Delete wastage
      db.prepare('DELETE FROM wastages WHERE uuid = ?').run(uuid);

      // Log audit
      db.prepare(`
        INSERT INTO audit_logs (table_name, record_uuid, operation, user_uuid, old_values)
        VALUES ('wastages', ?, 'delete', ?, ?)
      `).run(uuid, req.user.uuid, JSON.stringify(wastage));

      return { success: true };
    });

    logger.info('Wastage deleted', { wastage_uuid: uuid, by_user: req.user.username });

    res.json({
      success: true,
      message: 'Wastage record deleted successfully'
    });
  } catch (error) {
    logger.error('Delete wastage error', { error: error.message });
    res.status(500).json({
      success: false,
      error: 'Failed to delete wastage record'
    });
  }
}

/**
 * Get wastage summary/statistics
 * GET /api/wastage/summary
 */
function getWastageSummary(req, res) {
  try {
    const db = getDatabase();
    const { from_date, to_date, location_uuid } = req.query;

    let dateFilter = '';
    const params = [];

    if (from_date) {
      dateFilter += ' AND wastage_date >= ?';
      params.push(from_date);
    }

    if (to_date) {
      dateFilter += ' AND wastage_date <= ?';
      params.push(to_date);
    }

    if (location_uuid) {
      dateFilter += ' AND location_uuid = ?';
      params.push(location_uuid);
    }

    const summary = db.prepare(`
      SELECT
        COUNT(*) as total_records,
        COUNT(CASE WHEN status = 'approved' THEN 1 END) as approved_count,
        COUNT(CASE WHEN status = 'draft' THEN 1 END) as draft_count,
        COUNT(CASE WHEN wastage_type = 'damage' THEN 1 END) as damage_count,
        COUNT(CASE WHEN wastage_type = 'expiry' THEN 1 END) as expiry_count,
        COUNT(CASE WHEN wastage_type = 'spoilage' THEN 1 END) as spoilage_count,
        COUNT(CASE WHEN wastage_type = 'other' THEN 1 END) as other_count
      FROM wastages
      WHERE 1=1 ${dateFilter}
    `).get(...params);

    // Get top wasted products
    const topProducts = db.prepare(`
      SELECT
        p.name as product_name,
        p.sku,
        u.abbreviation as unit,
        SUM(wi.quantity) as total_quantity,
        COUNT(DISTINCT w.uuid) as wastage_count
      FROM wastage_items wi
      JOIN wastages w ON w.uuid = wi.wastage_uuid
      JOIN products p ON p.uuid = wi.product_uuid
      JOIN units u ON u.id = wi.unit_id
      WHERE w.status = 'approved' ${dateFilter}
      GROUP BY wi.product_uuid
      ORDER BY total_quantity DESC
      LIMIT 10
    `).all(...params);

    res.json({
      success: true,
      summary,
      top_wasted_products: topProducts
    });
  } catch (error) {
    logger.error('Get wastage summary error', { error: error.message });
    res.status(500).json({
      success: false,
      error: 'Failed to get wastage summary'
    });
  }
}

module.exports = {
  listWastage,
  getWastage,
  createWastage,
  updateWastageStatus,
  deleteWastage,
  getWastageSummary
};
