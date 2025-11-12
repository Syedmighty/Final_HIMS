/**
 * Transfers Controller
 * Handles cross-location stock movement with validation and logging
 * Follows HIMS_FEATURE_SPEC_MASTER Section 5: Transfers Module
 */

const { getDatabase, transaction } = require('../config/database');
const logger = require('../config/logger');
const { v4: uuidv4 } = require('uuid');

/**
 * List all transfers
 * GET /api/transfers
 */
function listTransfers(req, res) {
  try {
    const db = getDatabase();
    const { status, from_location_uuid, to_location_uuid, from_date, to_date } = req.query;

    let query = `
      SELECT
        t.*,
        l1.name as from_location_name,
        l2.name as to_location_name,
        u1.full_name as created_by_name,
        u2.full_name as completed_by_name,
        COUNT(ti.id) as items_count
      FROM transfers t
      LEFT JOIN locations l1 ON l1.uuid = t.from_location_uuid
      LEFT JOIN locations l2 ON l2.uuid = t.to_location_uuid
      LEFT JOIN users u1 ON u1.uuid = t.created_by
      LEFT JOIN users u2 ON u2.uuid = t.completed_by
      LEFT JOIN transfer_items ti ON ti.transfer_uuid = t.uuid
      WHERE 1=1
    `;

    const params = [];

    if (status) {
      query += ' AND t.status = ?';
      params.push(status);
    }

    if (from_location_uuid) {
      query += ' AND t.from_location_uuid = ?';
      params.push(from_location_uuid);
    }

    if (to_location_uuid) {
      query += ' AND t.to_location_uuid = ?';
      params.push(to_location_uuid);
    }

    if (from_date) {
      query += ' AND t.transfer_date >= ?';
      params.push(from_date);
    }

    if (to_date) {
      query += ' AND t.transfer_date <= ?';
      params.push(to_date);
    }

    query += ' GROUP BY t.id ORDER BY t.transfer_date DESC, t.created_at DESC';

    const transfers = db.prepare(query).all(...params);

    res.json({
      success: true,
      transfers,
      count: transfers.length
    });
  } catch (error) {
    logger.error('List transfers error', { error: error.message });
    res.status(500).json({
      success: false,
      error: 'Failed to list transfers'
    });
  }
}

/**
 * Get single transfer with items
 * GET /api/transfers/:uuid
 */
function getTransfer(req, res) {
  try {
    const { uuid } = req.params;
    const db = getDatabase();

    const transfer = db.prepare(`
      SELECT
        t.*,
        l1.name as from_location_name,
        l2.name as to_location_name,
        u1.full_name as created_by_name,
        u2.full_name as completed_by_name
      FROM transfers t
      LEFT JOIN locations l1 ON l1.uuid = t.from_location_uuid
      LEFT JOIN locations l2 ON l2.uuid = t.to_location_uuid
      LEFT JOIN users u1 ON u1.uuid = t.created_by
      LEFT JOIN users u2 ON u2.uuid = t.completed_by
      WHERE t.uuid = ?
    `).get(uuid);

    if (!transfer) {
      return res.status(404).json({
        success: false,
        error: 'Transfer not found'
      });
    }

    // Get transfer items with stock availability
    const items = db.prepare(`
      SELECT
        ti.*,
        p.name as product_name,
        p.sku,
        u.abbreviation as unit,
        sl.quantity as available_at_source
      FROM transfer_items ti
      LEFT JOIN products p ON p.uuid = ti.product_uuid
      LEFT JOIN units u ON u.id = ti.unit_id
      LEFT JOIN stock_levels sl ON sl.product_uuid = ti.product_uuid AND sl.location_uuid = ?
      WHERE ti.transfer_uuid = ?
      ORDER BY ti.created_at
    `).all(transfer.from_location_uuid, uuid);

    res.json({
      success: true,
      transfer,
      items
    });
  } catch (error) {
    logger.error('Get transfer error', { error: error.message });
    res.status(500).json({
      success: false,
      error: 'Failed to get transfer'
    });
  }
}

/**
 * Create new transfer
 * POST /api/transfers
 *
 * Business Logic:
 * - Validates from_location != to_location
 * - Checks stock availability at source
 * - Creates transfer in draft status
 * - Stock is moved when status changes to 'completed'
 * - Triggers handle bidirectional stock updates
 */
function createTransfer(req, res) {
  try {
    const {
      from_location_uuid,
      to_location_uuid,
      transfer_date,
      notes,
      items
    } = req.body;

    // Validation
    if (!from_location_uuid || !to_location_uuid || !transfer_date) {
      return res.status(400).json({
        success: false,
        error: 'from_location_uuid, to_location_uuid, and transfer_date are required'
      });
    }

    if (!items || !Array.isArray(items) || items.length === 0) {
      return res.status(400).json({
        success: false,
        error: 'At least one item is required'
      });
    }

    // Cannot transfer to same location
    if (from_location_uuid === to_location_uuid) {
      return res.status(400).json({
        success: false,
        error: 'Source and destination locations must be different'
      });
    }

    const db = getDatabase();
    const transferUuid = uuidv4();
    const now = new Date().toISOString();

    // Generate transfer number
    const lastTransfer = db.prepare(
      "SELECT transfer_number FROM transfers ORDER BY id DESC LIMIT 1"
    ).get();

    let transferNumber = 'TRF0001';
    if (lastTransfer) {
      const lastNum = parseInt(lastTransfer.transfer_number.substring(3));
      transferNumber = `TRF${String(lastNum + 1).padStart(4, '0')}`;
    }

    const result = transaction(() => {
      // Check stock availability at source BEFORE creating
      const insufficientItems = [];

      for (const item of items) {
        const stockLevel = db.prepare(`
          SELECT quantity FROM stock_levels
          WHERE product_uuid = ? AND location_uuid = ?
        `).get(item.product_uuid, from_location_uuid);

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
          message: 'Insufficient stock at source location for one or more items',
          items: insufficientItems
        }));
      }

      // Insert transfer header
      db.prepare(`
        INSERT INTO transfers (
          uuid, transfer_number, from_location_uuid, to_location_uuid,
          transfer_date, status, notes,
          created_at, last_modified, created_by
        ) VALUES (?, ?, ?, ?, ?, 'draft', ?, ?, ?, ?)
      `).run(
        transferUuid,
        transferNumber,
        from_location_uuid,
        to_location_uuid,
        transfer_date,
        notes || null,
        now,
        now,
        req.user.uuid
      );

      // Insert transfer items
      items.forEach(item => {
        const itemUuid = uuidv4();

        db.prepare(`
          INSERT INTO transfer_items (
            uuid, transfer_uuid, product_uuid, quantity, unit_id,
            notes, created_at, last_modified
          ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        `).run(
          itemUuid,
          transferUuid,
          item.product_uuid,
          item.quantity,
          item.unit_id,
          item.notes || null,
          now,
          now
        );
      });

      // Add to sync queue
      const transferData = db.prepare('SELECT * FROM transfers WHERE uuid = ?').get(transferUuid);
      db.prepare(`
        INSERT INTO sync_queue (table_name, operation, record_uuid, payload, created_at)
        VALUES ('transfers', 'insert', ?, ?, datetime('now'))
      `).run(transferUuid, JSON.stringify(transferData));

      // Log audit
      db.prepare(`
        INSERT INTO audit_logs (table_name, record_uuid, operation, user_uuid, new_values)
        VALUES ('transfers', ?, 'insert', ?, ?)
      `).run(transferUuid, req.user.uuid, JSON.stringify({ items: items.length }));

      return { success: true };
    });

    logger.info('Transfer created', {
      transfer_uuid: transferUuid,
      transfer_number: transferNumber,
      from: from_location_uuid,
      to: to_location_uuid,
      items_count: items.length,
      by_user: req.user.username
    });

    res.status(201).json({
      success: true,
      message: 'Transfer created successfully',
      transfer: {
        uuid: transferUuid,
        transfer_number: transferNumber
      }
    });
  } catch (error) {
    // Check if error is stock validation
    if (error.message.includes('Insufficient stock')) {
      try {
        const errorData = JSON.parse(error.message);
        logger.warn('Transfer creation failed: insufficient stock', errorData);
        return res.status(400).json({
          success: false,
          error: errorData.message,
          insufficient_items: errorData.items
        });
      } catch (e) {
        // Not a JSON error, fall through
      }
    }

    logger.error('Create transfer error', { error: error.message, stack: error.stack });
    res.status(500).json({
      success: false,
      error: 'Failed to create transfer'
    });
  }
}

/**
 * Update transfer status
 * PUT /api/transfers/:uuid/status
 *
 * Status workflow: draft → in_transit → completed → cancelled
 * Stock is moved via triggers when status changes to 'completed'
 * Triggers handle:
 * - Deduction from source location
 * - Addition to destination location
 * - Stock adjustment entries for both locations
 */
function updateTransferStatus(req, res) {
  try {
    const { uuid } = req.params;
    const { status } = req.body;

    if (!['draft', 'in_transit', 'completed', 'cancelled'].includes(status)) {
      return res.status(400).json({
        success: false,
        error: 'Invalid status. Must be: draft, in_transit, completed, or cancelled'
      });
    }

    const db = getDatabase();

    // Get transfer
    const transfer = db.prepare('SELECT * FROM transfers WHERE uuid = ?').get(uuid);

    if (!transfer) {
      return res.status(404).json({
        success: false,
        error: 'Transfer not found'
      });
    }

    // Cannot change status if already completed
    if (transfer.status === 'completed' && status !== 'completed') {
      return res.status(400).json({
        success: false,
        error: 'Cannot change status of completed transfer. Stock has already been moved.'
      });
    }

    const now = new Date().toISOString();

    try {
      const result = transaction(() => {
        const updates = {
          status,
          last_modified: now
        };

        if (status === 'completed') {
          updates.completed_by = req.user.uuid;
          updates.completed_at = now;
        }

        const updateFields = Object.keys(updates).map(k => `${k} = ?`).join(', ');
        const updateValues = [...Object.values(updates), uuid];

        db.prepare(`
          UPDATE transfers SET ${updateFields} WHERE uuid = ?
        `).run(...updateValues);

        // Triggers will handle:
        // - trg_before_transfer_check_stock validates stock at source
        // - trg_after_transfer_completed deducts from source and adds to destination

        // Add to sync queue
        const updatedTransfer = db.prepare('SELECT * FROM transfers WHERE uuid = ?').get(uuid);
        db.prepare(`
          INSERT INTO sync_queue (table_name, operation, record_uuid, payload, created_at)
          VALUES ('transfers', 'update', ?, ?, datetime('now'))
        `).run(uuid, JSON.stringify(updatedTransfer));

        // Log audit
        db.prepare(`
          INSERT INTO audit_logs (table_name, record_uuid, operation, user_uuid, old_values, new_values)
          VALUES ('transfers', ?, 'update', ?, ?, ?)
        `).run(uuid, req.user.uuid, JSON.stringify(transfer), JSON.stringify(updates));

        return { success: true };
      });

      logger.info('Transfer status updated', {
        transfer_uuid: uuid,
        old_status: transfer.status,
        new_status: status,
        by_user: req.user.username
      });

      res.json({
        success: true,
        message: 'Transfer status updated successfully',
        status
      });
    } catch (dbError) {
      // Check if trigger raised error due to insufficient stock
      if (dbError.message.includes('Insufficient stock')) {
        logger.warn('Transfer completion failed: insufficient stock at source', {
          transfer_uuid: uuid,
          error: dbError.message
        });

        return res.status(400).json({
          success: false,
          error: 'Insufficient stock at source location for this transfer',
          details: dbError.message
        });
      }

      throw dbError;
    }
  } catch (error) {
    logger.error('Update transfer status error', { error: error.message });
    res.status(500).json({
      success: false,
      error: 'Failed to update transfer status'
    });
  }
}

/**
 * Delete transfer
 * DELETE /api/transfers/:uuid
 * Can only delete draft or cancelled transfers
 */
function deleteTransfer(req, res) {
  try {
    const { uuid } = req.params;
    const db = getDatabase();

    const transfer = db.prepare('SELECT * FROM transfers WHERE uuid = ?').get(uuid);

    if (!transfer) {
      return res.status(404).json({
        success: false,
        error: 'Transfer not found'
      });
    }

    // Cannot delete completed transfers
    if (transfer.status === 'completed') {
      return res.status(400).json({
        success: false,
        error: 'Cannot delete completed transfer. Stock has already been moved.'
      });
    }

    const result = transaction(() => {
      // Delete transfer items (CASCADE will handle this)
      db.prepare('DELETE FROM transfer_items WHERE transfer_uuid = ?').run(uuid);

      // Delete transfer
      db.prepare('DELETE FROM transfers WHERE uuid = ?').run(uuid);

      // Log audit
      db.prepare(`
        INSERT INTO audit_logs (table_name, record_uuid, operation, user_uuid, old_values)
        VALUES ('transfers', ?, 'delete', ?, ?)
      `).run(uuid, req.user.uuid, JSON.stringify(transfer));

      return { success: true };
    });

    logger.info('Transfer deleted', { transfer_uuid: uuid, by_user: req.user.username });

    res.json({
      success: true,
      message: 'Transfer deleted successfully'
    });
  } catch (error) {
    logger.error('Delete transfer error', { error: error.message });
    res.status(500).json({
      success: false,
      error: 'Failed to delete transfer'
    });
  }
}

module.exports = {
  listTransfers,
  getTransfer,
  createTransfer,
  updateTransferStatus,
  deleteTransfer
};
