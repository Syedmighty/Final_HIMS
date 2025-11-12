/**
 * Issues (Stock Out) Controller
 * Handles stock withdrawal, inter-location issues, and stock validation
 * Follows HIMS_FEATURE_SPEC_MASTER Section 5: Issues Module
 */

const { getDatabase, transaction } = require('../config/database');
const logger = require('../config/logger');
const { v4: uuidv4 } = require('uuid');

/**
 * List all issues
 * GET /api/issues
 */
function listIssues(req, res) {
  try {
    const db = getDatabase();
    const { status, from_location_uuid, to_location_uuid, from_date, to_date } = req.query;

    let query = `
      SELECT
        i.*,
        l1.name as from_location_name,
        l2.name as to_location_name,
        u1.full_name as created_by_name,
        u2.full_name as issued_by_name,
        COUNT(ii.id) as items_count
      FROM issues i
      LEFT JOIN locations l1 ON l1.uuid = i.from_location_uuid
      LEFT JOIN locations l2 ON l2.uuid = i.to_location_uuid
      LEFT JOIN users u1 ON u1.uuid = i.created_by
      LEFT JOIN users u2 ON u2.uuid = i.issued_by
      LEFT JOIN issue_items ii ON ii.issue_uuid = i.uuid
      WHERE 1=1
    `;

    const params = [];

    if (status) {
      query += ' AND i.status = ?';
      params.push(status);
    }

    if (from_location_uuid) {
      query += ' AND i.from_location_uuid = ?';
      params.push(from_location_uuid);
    }

    if (to_location_uuid) {
      query += ' AND i.to_location_uuid = ?';
      params.push(to_location_uuid);
    }

    if (from_date) {
      query += ' AND i.issue_date >= ?';
      params.push(from_date);
    }

    if (to_date) {
      query += ' AND i.issue_date <= ?';
      params.push(to_date);
    }

    query += ' GROUP BY i.id ORDER BY i.issue_date DESC, i.created_at DESC';

    const issues = db.prepare(query).all(...params);

    res.json({
      success: true,
      issues,
      count: issues.length
    });
  } catch (error) {
    logger.error('List issues error', { error: error.message });
    res.status(500).json({
      success: false,
      error: 'Failed to list issues'
    });
  }
}

/**
 * Get single issue with items
 * GET /api/issues/:uuid
 */
function getIssue(req, res) {
  try {
    const { uuid } = req.params;
    const db = getDatabase();

    const issue = db.prepare(`
      SELECT
        i.*,
        l1.name as from_location_name,
        l2.name as to_location_name,
        u1.full_name as created_by_name,
        u2.full_name as issued_by_name
      FROM issues i
      LEFT JOIN locations l1 ON l1.uuid = i.from_location_uuid
      LEFT JOIN locations l2 ON l2.uuid = i.to_location_uuid
      LEFT JOIN users u1 ON u1.uuid = i.created_by
      LEFT JOIN users u2 ON u2.uuid = i.issued_by
      WHERE i.uuid = ?
    `).get(uuid);

    if (!issue) {
      return res.status(404).json({
        success: false,
        error: 'Issue not found'
      });
    }

    // Get issue items with stock availability check
    const items = db.prepare(`
      SELECT
        ii.*,
        p.name as product_name,
        p.sku,
        u.abbreviation as unit,
        sl.quantity as available_stock
      FROM issue_items ii
      LEFT JOIN products p ON p.uuid = ii.product_uuid
      LEFT JOIN units u ON u.id = ii.unit_id
      LEFT JOIN stock_levels sl ON sl.product_uuid = ii.product_uuid AND sl.location_uuid = ?
      WHERE ii.issue_uuid = ?
      ORDER BY ii.created_at
    `).all(issue.from_location_uuid, uuid);

    res.json({
      success: true,
      issue,
      items
    });
  } catch (error) {
    logger.error('Get issue error', { error: error.message });
    res.status(500).json({
      success: false,
      error: 'Failed to get issue'
    });
  }
}

/**
 * Create new issue (stock out)
 * POST /api/issues
 *
 * Business Logic:
 * - Check stock availability before creating
 * - Create issue in draft status
 * - Stock is deducted only when status changes to 'issued'
 * - Trigger validates stock before allowing status change
 */
function createIssue(req, res) {
  try {
    const {
      from_location_uuid,
      to_location_uuid,
      issue_date,
      reason,
      notes,
      items
    } = req.body;

    // Validation
    if (!from_location_uuid || !issue_date) {
      return res.status(400).json({
        success: false,
        error: 'from_location_uuid and issue_date are required'
      });
    }

    if (!items || !Array.isArray(items) || items.length === 0) {
      return res.status(400).json({
        success: false,
        error: 'At least one item is required'
      });
    }

    // Cannot issue to same location
    if (to_location_uuid && from_location_uuid === to_location_uuid) {
      return res.status(400).json({
        success: false,
        error: 'Cannot issue to the same location. Use transfers for inter-location movement.'
      });
    }

    const db = getDatabase();
    const issueUuid = uuidv4();
    const now = new Date().toISOString();

    // Generate issue number
    const lastIssue = db.prepare(
      "SELECT issue_number FROM issues ORDER BY id DESC LIMIT 1"
    ).get();

    let issueNumber = 'ISS0001';
    if (lastIssue) {
      const lastNum = parseInt(lastIssue.issue_number.substring(3));
      issueNumber = `ISS${String(lastNum + 1).padStart(4, '0')}`;
    }

    const result = transaction(() => {
      // Check stock availability for all items BEFORE creating
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
          message: 'Insufficient stock for one or more items',
          items: insufficientItems
        }));
      }

      // Insert issue header
      db.prepare(`
        INSERT INTO issues (
          uuid, issue_number, from_location_uuid, to_location_uuid,
          issue_date, status, reason, notes,
          created_at, last_modified, created_by
        ) VALUES (?, ?, ?, ?, ?, 'draft', ?, ?, ?, ?, ?)
      `).run(
        issueUuid,
        issueNumber,
        from_location_uuid,
        to_location_uuid || null,
        issue_date,
        reason || null,
        notes || null,
        now,
        now,
        req.user.uuid
      );

      // Insert issue items
      items.forEach(item => {
        const itemUuid = uuidv4();

        db.prepare(`
          INSERT INTO issue_items (
            uuid, issue_uuid, product_uuid, quantity, unit_id,
            notes, created_at, last_modified
          ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        `).run(
          itemUuid,
          issueUuid,
          item.product_uuid,
          item.quantity,
          item.unit_id,
          item.notes || null,
          now,
          now
        );
      });

      // Add to sync queue
      const issueData = db.prepare('SELECT * FROM issues WHERE uuid = ?').get(issueUuid);
      db.prepare(`
        INSERT INTO sync_queue (table_name, operation, record_uuid, payload, created_at)
        VALUES ('issues', 'insert', ?, ?, datetime('now'))
      `).run(issueUuid, JSON.stringify(issueData));

      // Log audit
      db.prepare(`
        INSERT INTO audit_logs (table_name, record_uuid, operation, user_uuid, new_values)
        VALUES ('issues', ?, 'insert', ?, ?)
      `).run(issueUuid, req.user.uuid, JSON.stringify({ items: items.length }));

      return { success: true };
    });

    logger.info('Issue created', {
      issue_uuid: issueUuid,
      issue_number: issueNumber,
      items_count: items.length,
      by_user: req.user.username
    });

    res.status(201).json({
      success: true,
      message: 'Issue created successfully',
      issue: {
        uuid: issueUuid,
        issue_number: issueNumber
      }
    });
  } catch (error) {
    // Check if error is stock validation
    if (error.message.includes('Insufficient stock')) {
      try {
        const errorData = JSON.parse(error.message);
        logger.warn('Issue creation failed: insufficient stock', errorData);
        return res.status(400).json({
          success: false,
          error: errorData.message,
          insufficient_items: errorData.items
        });
      } catch (e) {
        // Not a JSON error, fall through
      }
    }

    logger.error('Create issue error', { error: error.message, stack: error.stack });
    res.status(500).json({
      success: false,
      error: 'Failed to create issue'
    });
  }
}

/**
 * Update issue status
 * PUT /api/issues/:uuid/status
 *
 * Status workflow: draft → issued → cancelled
 * Stock is deducted via trigger when status changes to 'issued'
 * Trigger prevents issuing if insufficient stock
 */
function updateIssueStatus(req, res) {
  try {
    const { uuid } = req.params;
    const { status } = req.body;

    if (!['draft', 'issued', 'cancelled'].includes(status)) {
      return res.status(400).json({
        success: false,
        error: 'Invalid status. Must be: draft, issued, or cancelled'
      });
    }

    const db = getDatabase();

    // Get issue
    const issue = db.prepare('SELECT * FROM issues WHERE uuid = ?').get(uuid);

    if (!issue) {
      return res.status(404).json({
        success: false,
        error: 'Issue not found'
      });
    }

    // Cannot change status if already issued
    if (issue.status === 'issued' && status !== 'issued') {
      return res.status(400).json({
        success: false,
        error: 'Cannot change status of issued stock. Stock has already been deducted.'
      });
    }

    const now = new Date().toISOString();

    try {
      const result = transaction(() => {
        const updates = {
          status,
          last_modified: now
        };

        if (status === 'issued') {
          updates.issued_by = req.user.uuid;
          updates.issued_at = now;
        }

        const updateFields = Object.keys(updates).map(k => `${k} = ?`).join(', ');
        const updateValues = [...Object.values(updates), uuid];

        db.prepare(`
          UPDATE issues SET ${updateFields} WHERE uuid = ?
        `).run(...updateValues);

        // Trigger trg_before_issue_check_stock will validate stock availability
        // Trigger trg_after_issue_approved will deduct stock if status = 'issued'

        // Add to sync queue
        const updatedIssue = db.prepare('SELECT * FROM issues WHERE uuid = ?').get(uuid);
        db.prepare(`
          INSERT INTO sync_queue (table_name, operation, record_uuid, payload, created_at)
          VALUES ('issues', 'update', ?, ?, datetime('now'))
        `).run(uuid, JSON.stringify(updatedIssue));

        // Log audit
        db.prepare(`
          INSERT INTO audit_logs (table_name, record_uuid, operation, user_uuid, old_values, new_values)
          VALUES ('issues', ?, 'update', ?, ?, ?)
        `).run(uuid, req.user.uuid, JSON.stringify(issue), JSON.stringify(updates));

        return { success: true };
      });

      logger.info('Issue status updated', {
        issue_uuid: uuid,
        old_status: issue.status,
        new_status: status,
        by_user: req.user.username
      });

      res.json({
        success: true,
        message: 'Issue status updated successfully',
        status
      });
    } catch (dbError) {
      // Check if trigger raised error due to insufficient stock
      if (dbError.message.includes('Insufficient stock')) {
        logger.warn('Issue approval failed: insufficient stock', {
          issue_uuid: uuid,
          error: dbError.message
        });

        return res.status(400).json({
          success: false,
          error: 'Insufficient stock for one or more items in this issue',
          details: dbError.message
        });
      }

      throw dbError;
    }
  } catch (error) {
    logger.error('Update issue status error', { error: error.message });
    res.status(500).json({
      success: false,
      error: 'Failed to update issue status'
    });
  }
}

/**
 * Delete issue
 * DELETE /api/issues/:uuid
 * Can only delete draft or cancelled issues
 */
function deleteIssue(req, res) {
  try {
    const { uuid } = req.params;
    const db = getDatabase();

    const issue = db.prepare('SELECT * FROM issues WHERE uuid = ?').get(uuid);

    if (!issue) {
      return res.status(404).json({
        success: false,
        error: 'Issue not found'
      });
    }

    // Cannot delete issued issues
    if (issue.status === 'issued') {
      return res.status(400).json({
        success: false,
        error: 'Cannot delete issued stock. Stock has already been deducted.'
      });
    }

    const result = transaction(() => {
      // Delete issue items (CASCADE will handle this)
      db.prepare('DELETE FROM issue_items WHERE issue_uuid = ?').run(uuid);

      // Delete issue
      db.prepare('DELETE FROM issues WHERE uuid = ?').run(uuid);

      // Log audit
      db.prepare(`
        INSERT INTO audit_logs (table_name, record_uuid, operation, user_uuid, old_values)
        VALUES ('issues', ?, 'delete', ?, ?)
      `).run(uuid, req.user.uuid, JSON.stringify(issue));

      return { success: true };
    });

    logger.info('Issue deleted', { issue_uuid: uuid, by_user: req.user.username });

    res.json({
      success: true,
      message: 'Issue deleted successfully'
    });
  } catch (error) {
    logger.error('Delete issue error', { error: error.message });
    res.status(500).json({
      success: false,
      error: 'Failed to delete issue'
    });
  }
}

/**
 * Check stock availability for issue
 * POST /api/issues/check-stock
 *
 * Validates stock before issue creation
 */
function checkStockAvailability(req, res) {
  try {
    const { from_location_uuid, items } = req.body;

    if (!from_location_uuid || !items || !Array.isArray(items)) {
      return res.status(400).json({
        success: false,
        error: 'from_location_uuid and items array are required'
      });
    }

    const db = getDatabase();
    const stockCheck = [];

    items.forEach(item => {
      const stockLevel = db.prepare(`
        SELECT
          sl.quantity as available,
          p.name as product_name,
          p.reorder_level,
          u.abbreviation as unit
        FROM stock_levels sl
        LEFT JOIN products p ON p.uuid = sl.product_uuid
        LEFT JOIN units u ON u.id = ?
        WHERE sl.product_uuid = ? AND sl.location_uuid = ?
      `).get(item.unit_id, item.product_uuid, from_location_uuid);

      const available = stockLevel ? stockLevel.quantity : 0;
      const sufficient = available >= item.quantity;

      stockCheck.push({
        product_uuid: item.product_uuid,
        product_name: stockLevel ? stockLevel.product_name : 'Unknown',
        unit: stockLevel ? stockLevel.unit : '',
        requested: item.quantity,
        available,
        sufficient,
        after_issue: available - item.quantity,
        below_reorder: stockLevel && (available - item.quantity) < stockLevel.reorder_level
      });
    });

    const allSufficient = stockCheck.every(item => item.sufficient);

    res.json({
      success: true,
      all_sufficient: allSufficient,
      items: stockCheck
    });
  } catch (error) {
    logger.error('Check stock availability error', { error: error.message });
    res.status(500).json({
      success: false,
      error: 'Failed to check stock availability'
    });
  }
}

module.exports = {
  listIssues,
  getIssue,
  createIssue,
  updateIssueStatus,
  deleteIssue,
  checkStockAvailability
};
