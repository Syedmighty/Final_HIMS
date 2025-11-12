/**
 * Purchases Controller
 * Handles purchase orders, receiving goods, and supplier management
 */

const { getDatabase, transaction } = require('../config/database');
const logger = require('../config/logger');
const { v4: uuidv4 } = require('uuid');

/**
 * List all purchases
 * GET /api/purchases
 */
function listPurchases(req, res) {
  try {
    const db = getDatabase();
    const { status, supplier_uuid, location_uuid, from_date, to_date } = req.query;

    let query = `
      SELECT
        p.*,
        s.name as supplier_name,
        l.name as location_name,
        u1.full_name as created_by_name,
        u2.full_name as approved_by_name,
        COUNT(pi.id) as items_count
      FROM purchases p
      LEFT JOIN suppliers s ON s.uuid = p.supplier_uuid
      LEFT JOIN locations l ON l.uuid = p.location_uuid
      LEFT JOIN users u1 ON u1.uuid = p.created_by
      LEFT JOIN users u2 ON u2.uuid = p.approved_by
      LEFT JOIN purchase_items pi ON pi.purchase_uuid = p.uuid
      WHERE 1=1
    `;

    const params = [];

    if (status) {
      query += ' AND p.status = ?';
      params.push(status);
    }

    if (supplier_uuid) {
      query += ' AND p.supplier_uuid = ?';
      params.push(supplier_uuid);
    }

    if (location_uuid) {
      query += ' AND p.location_uuid = ?';
      params.push(location_uuid);
    }

    if (from_date) {
      query += ' AND p.purchase_date >= ?';
      params.push(from_date);
    }

    if (to_date) {
      query += ' AND p.purchase_date <= ?';
      params.push(to_date);
    }

    query += ' GROUP BY p.id ORDER BY p.purchase_date DESC, p.created_at DESC';

    const purchases = db.prepare(query).all(...params);

    res.json({
      success: true,
      purchases,
      count: purchases.length
    });
  } catch (error) {
    logger.error('List purchases error', { error: error.message });
    res.status(500).json({
      success: false,
      error: 'Failed to list purchases'
    });
  }
}

/**
 * Get single purchase with items
 * GET /api/purchases/:uuid
 */
function getPurchase(req, res) {
  try {
    const { uuid } = req.params;
    const db = getDatabase();

    const purchase = db.prepare(`
      SELECT
        p.*,
        s.name as supplier_name,
        s.contact_person,
        s.phone as supplier_phone,
        s.gst_number as supplier_gst,
        l.name as location_name,
        u1.full_name as created_by_name,
        u2.full_name as approved_by_name
      FROM purchases p
      LEFT JOIN suppliers s ON s.uuid = p.supplier_uuid
      LEFT JOIN locations l ON l.uuid = p.location_uuid
      LEFT JOIN users u1 ON u1.uuid = p.created_by
      LEFT JOIN users u2 ON u2.uuid = p.approved_by
      WHERE p.uuid = ?
    `).get(uuid);

    if (!purchase) {
      return res.status(404).json({
        success: false,
        error: 'Purchase not found'
      });
    }

    // Get purchase items
    const items = db.prepare(`
      SELECT
        pi.*,
        pr.name as product_name,
        pr.sku,
        u.abbreviation as unit
      FROM purchase_items pi
      LEFT JOIN products pr ON pr.uuid = pi.product_uuid
      LEFT JOIN units u ON u.id = pi.unit_id
      WHERE pi.purchase_uuid = ?
      ORDER BY pi.created_at
    `).all(uuid);

    res.json({
      success: true,
      purchase,
      items
    });
  } catch (error) {
    logger.error('Get purchase error', { error: error.message });
    res.status(500).json({
      success: false,
      error: 'Failed to get purchase'
    });
  }
}

/**
 * Create new purchase
 * POST /api/purchases
 */
function createPurchase(req, res) {
  try {
    const {
      supplier_uuid,
      location_uuid,
      purchase_date,
      invoice_number,
      invoice_date,
      notes,
      items
    } = req.body;

    // Validation
    if (!supplier_uuid || !location_uuid || !purchase_date) {
      return res.status(400).json({
        success: false,
        error: 'supplier_uuid, location_uuid, and purchase_date are required'
      });
    }

    if (!items || !Array.isArray(items) || items.length === 0) {
      return res.status(400).json({
        success: false,
        error: 'At least one item is required'
      });
    }

    const db = getDatabase();
    const purchaseUuid = uuidv4();
    const now = new Date().toISOString();

    // Generate purchase number
    const lastPurchase = db.prepare(
      "SELECT purchase_number FROM purchases ORDER BY id DESC LIMIT 1"
    ).get();

    let purchaseNumber = 'PUR0001';
    if (lastPurchase) {
      const lastNum = parseInt(lastPurchase.purchase_number.substring(3));
      purchaseNumber = `PUR${String(lastNum + 1).padStart(4, '0')}`;
    }

    const result = transaction(() => {
      // Calculate totals
      let totalAmount = 0;
      let gstAmount = 0;

      // Insert purchase header
      db.prepare(`
        INSERT INTO purchases (
          uuid, purchase_number, supplier_uuid, location_uuid,
          purchase_date, invoice_number, invoice_date,
          total_amount, gst_amount, grand_total, status, payment_status,
          notes, created_at, last_modified, created_by
        ) VALUES (?, ?, ?, ?, ?, ?, ?, 0, 0, 0, 'draft', 'pending', ?, ?, ?, ?)
      `).run(
        purchaseUuid,
        purchaseNumber,
        supplier_uuid,
        location_uuid,
        purchase_date,
        invoice_number || null,
        invoice_date || null,
        notes || null,
        now,
        now,
        req.user.uuid
      );

      // Insert purchase items
      items.forEach(item => {
        const itemUuid = uuidv4();
        const itemTotal = (item.quantity * item.unit_price);
        const itemGst = itemTotal * (item.gst_rate || 0) / 100;
        const itemTotalWithGst = itemTotal + itemGst;

        db.prepare(`
          INSERT INTO purchase_items (
            uuid, purchase_uuid, product_uuid, quantity, unit_id,
            unit_price, gst_rate, gst_amount, total_amount,
            notes, created_at, last_modified
          ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        `).run(
          itemUuid,
          purchaseUuid,
          item.product_uuid,
          item.quantity,
          item.unit_id,
          item.unit_price || 0,
          item.gst_rate || 0,
          itemGst,
          itemTotalWithGst,
          item.notes || null,
          now,
          now
        );

        totalAmount += itemTotal;
        gstAmount += itemGst;
      });

      // Update purchase totals (triggers will also calculate, but we do it explicitly)
      db.prepare(`
        UPDATE purchases
        SET total_amount = ?, gst_amount = ?, grand_total = ?, last_modified = ?
        WHERE uuid = ?
      `).run(totalAmount, gstAmount, totalAmount + gstAmount, now, purchaseUuid);

      // Add to sync queue
      const purchaseData = db.prepare('SELECT * FROM purchases WHERE uuid = ?').get(purchaseUuid);
      db.prepare(`
        INSERT INTO sync_queue (table_name, operation, record_uuid, payload, created_at)
        VALUES ('purchases', 'insert', ?, ?, datetime('now'))
      `).run(purchaseUuid, JSON.stringify(purchaseData));

      // Log audit
      db.prepare(`
        INSERT INTO audit_logs (table_name, record_uuid, operation, user_uuid, new_values)
        VALUES ('purchases', ?, 'insert', ?, ?)
      `).run(purchaseUuid, req.user.uuid, JSON.stringify({ items: items.length }));

      return { success: true };
    });

    logger.info('Purchase created', {
      purchase_uuid: purchaseUuid,
      purchase_number: purchaseNumber,
      items_count: items.length,
      by_user: req.user.username
    });

    res.status(201).json({
      success: true,
      message: 'Purchase created successfully',
      purchase: {
        uuid: purchaseUuid,
        purchase_number: purchaseNumber
      }
    });
  } catch (error) {
    logger.error('Create purchase error', { error: error.message, stack: error.stack });
    res.status(500).json({
      success: false,
      error: 'Failed to create purchase'
    });
  }
}

/**
 * Update purchase status
 * PUT /api/purchases/:uuid/status
 */
function updatePurchaseStatus(req, res) {
  try {
    const { uuid } = req.params;
    const { status } = req.body;

    if (!['draft', 'ordered', 'received', 'cancelled'].includes(status)) {
      return res.status(400).json({
        success: false,
        error: 'Invalid status. Must be: draft, ordered, received, or cancelled'
      });
    }

    const db = getDatabase();

    // Get purchase
    const purchase = db.prepare('SELECT * FROM purchases WHERE uuid = ?').get(uuid);

    if (!purchase) {
      return res.status(404).json({
        success: false,
        error: 'Purchase not found'
      });
    }

    // Cannot change status if already received
    if (purchase.status === 'received' && status !== 'received') {
      return res.status(400).json({
        success: false,
        error: 'Cannot change status of received purchase'
      });
    }

    const now = new Date().toISOString();

    const result = transaction(() => {
      const updates = {
        status,
        last_modified: now
      };

      if (status === 'received') {
        updates.approved_by = req.user.uuid;
        updates.approved_at = now;
      }

      const updateFields = Object.keys(updates).map(k => `${k} = ?`).join(', ');
      const updateValues = [...Object.values(updates), uuid];

      db.prepare(`
        UPDATE purchases SET ${updateFields} WHERE uuid = ?
      `).run(...updateValues);

      // Triggers will handle stock updates if status is 'received'

      // Add to sync queue
      const updatedPurchase = db.prepare('SELECT * FROM purchases WHERE uuid = ?').get(uuid);
      db.prepare(`
        INSERT INTO sync_queue (table_name, operation, record_uuid, payload, created_at)
        VALUES ('purchases', 'update', ?, ?, datetime('now'))
      `).run(uuid, JSON.stringify(updatedPurchase));

      // Log audit
      db.prepare(`
        INSERT INTO audit_logs (table_name, record_uuid, operation, user_uuid, old_values, new_values)
        VALUES ('purchases', ?, 'update', ?, ?, ?)
      `).run(uuid, req.user.uuid, JSON.stringify(purchase), JSON.stringify(updates));

      return { success: true };
    });

    logger.info('Purchase status updated', {
      purchase_uuid: uuid,
      old_status: purchase.status,
      new_status: status,
      by_user: req.user.username
    });

    res.json({
      success: true,
      message: 'Purchase status updated successfully',
      status
    });
  } catch (error) {
    logger.error('Update purchase status error', { error: error.message });
    res.status(500).json({
      success: false,
      error: 'Failed to update purchase status'
    });
  }
}

/**
 * Delete purchase
 * DELETE /api/purchases/:uuid
 */
function deletePurchase(req, res) {
  try {
    const { uuid } = req.params;
    const db = getDatabase();

    const purchase = db.prepare('SELECT * FROM purchases WHERE uuid = ?').get(uuid);

    if (!purchase) {
      return res.status(404).json({
        success: false,
        error: 'Purchase not found'
      });
    }

    // Cannot delete received purchases
    if (purchase.status === 'received') {
      return res.status(400).json({
        success: false,
        error: 'Cannot delete received purchase. Stock has already been updated.'
      });
    }

    const result = transaction(() => {
      // Delete purchase items (CASCADE will handle this)
      db.prepare('DELETE FROM purchase_items WHERE purchase_uuid = ?').run(uuid);

      // Delete purchase
      db.prepare('DELETE FROM purchases WHERE uuid = ?').run(uuid);

      // Log audit
      db.prepare(`
        INSERT INTO audit_logs (table_name, record_uuid, operation, user_uuid, old_values)
        VALUES ('purchases', ?, 'delete', ?, ?)
      `).run(uuid, req.user.uuid, JSON.stringify(purchase));

      return { success: true };
    });

    logger.info('Purchase deleted', { purchase_uuid: uuid, by_user: req.user.username });

    res.json({
      success: true,
      message: 'Purchase deleted successfully'
    });
  } catch (error) {
    logger.error('Delete purchase error', { error: error.message });
    res.status(500).json({
      success: false,
      error: 'Failed to delete purchase'
    });
  }
}

// ============================================================================
// SUPPLIERS
// ============================================================================

/**
 * List all suppliers
 * GET /api/suppliers
 */
function listSuppliers(req, res) {
  try {
    const db = getDatabase();
    const { active_only } = req.query;

    let query = 'SELECT * FROM suppliers WHERE 1=1';

    if (active_only === 'true') {
      query += ' AND is_active = 1 AND deleted_at IS NULL';
    }

    query += ' ORDER BY name ASC';

    const suppliers = db.prepare(query).all();

    res.json({
      success: true,
      suppliers,
      count: suppliers.length
    });
  } catch (error) {
    logger.error('List suppliers error', { error: error.message });
    res.status(500).json({
      success: false,
      error: 'Failed to list suppliers'
    });
  }
}

/**
 * Create supplier
 * POST /api/suppliers
 */
function createSupplier(req, res) {
  try {
    const {
      name,
      contact_person,
      phone,
      email,
      address,
      gst_number,
      credit_days
    } = req.body;

    if (!name) {
      return res.status(400).json({
        success: false,
        error: 'Name is required'
      });
    }

    const db = getDatabase();
    const supplierUuid = uuidv4();
    const now = new Date().toISOString();

    const result = transaction(() => {
      db.prepare(`
        INSERT INTO suppliers (
          uuid, name, contact_person, phone, email, address,
          gst_number, credit_days, is_active,
          created_at, last_modified, created_by
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, 1, ?, ?, ?)
      `).run(
        supplierUuid,
        name,
        contact_person || null,
        phone || null,
        email || null,
        address || null,
        gst_number || null,
        credit_days || 0,
        now,
        now,
        req.user.uuid
      );

      // Add to sync queue
      db.prepare(`
        INSERT INTO sync_queue (table_name, operation, record_uuid, payload, created_at)
        VALUES ('suppliers', 'insert', ?, ?, datetime('now'))
      `).run(supplierUuid, JSON.stringify({
        uuid: supplierUuid,
        name,
        contact_person,
        phone,
        email,
        address,
        gst_number,
        credit_days: credit_days || 0,
        is_active: 1,
        created_at: now,
        last_modified: now,
        created_by: req.user.uuid
      }));

      return { success: true };
    });

    logger.info('Supplier created', { supplier_uuid: supplierUuid, name });

    res.status(201).json({
      success: true,
      message: 'Supplier created successfully',
      supplier: {
        uuid: supplierUuid,
        name
      }
    });
  } catch (error) {
    logger.error('Create supplier error', { error: error.message });
    res.status(500).json({
      success: false,
      error: 'Failed to create supplier'
    });
  }
}

module.exports = {
  listPurchases,
  getPurchase,
  createPurchase,
  updatePurchaseStatus,
  deletePurchase,
  listSuppliers,
  createSupplier
};
