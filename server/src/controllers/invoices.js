/**
 * Invoices Controller
 * Handles sales invoices, stock deduction, and customer management
 */

const { getDatabase, transaction } = require('../config/database');
const logger = require('../config/logger');
const { v4: uuidv4 } = require('uuid');

/**
 * List all invoices
 * GET /api/invoices
 */
function listInvoices(req, res) {
  try {
    const db = getDatabase();
    const { status, invoice_type, from_date, to_date, customer } = req.query;

    let query = `
      SELECT
        i.*,
        u1.full_name as created_by_name,
        u2.full_name as finalized_by_name,
        COUNT(ii.id) as items_count
      FROM invoices i
      LEFT JOIN users u1 ON u1.uuid = i.created_by
      LEFT JOIN users u2 ON u2.uuid = i.finalized_by
      LEFT JOIN invoice_items ii ON ii.invoice_uuid = i.uuid
      WHERE 1=1
    `;

    const params = [];

    if (status) {
      query += ' AND i.status = ?';
      params.push(status);
    }

    if (invoice_type) {
      query += ' AND i.invoice_type = ?';
      params.push(invoice_type);
    }

    if (from_date) {
      query += ' AND i.invoice_date >= ?';
      params.push(from_date);
    }

    if (to_date) {
      query += ' AND i.invoice_date <= ?';
      params.push(to_date);
    }

    if (customer) {
      query += ' AND (i.customer_name LIKE ? OR i.customer_phone LIKE ?)';
      params.push(`%${customer}%`, `%${customer}%`);
    }

    query += ' GROUP BY i.id ORDER BY i.invoice_date DESC, i.created_at DESC';

    const invoices = db.prepare(query).all(...params);

    res.json({
      success: true,
      invoices,
      count: invoices.length
    });
  } catch (error) {
    logger.error('List invoices error', { error: error.message });
    res.status(500).json({
      success: false,
      error: 'Failed to list invoices'
    });
  }
}

/**
 * Get single invoice with items
 * GET /api/invoices/:uuid
 */
function getInvoice(req, res) {
  try {
    const { uuid } = req.params;
    const db = getDatabase();

    const invoice = db.prepare(`
      SELECT
        i.*,
        u1.full_name as created_by_name,
        u2.full_name as finalized_by_name
      FROM invoices i
      LEFT JOIN users u1 ON u1.uuid = i.created_by
      LEFT JOIN users u2 ON u2.uuid = i.finalized_by
      WHERE i.uuid = ?
    `).get(uuid);

    if (!invoice) {
      return res.status(404).json({
        success: false,
        error: 'Invoice not found'
      });
    }

    // Get invoice items
    const items = db.prepare(`
      SELECT
        ii.*,
        p.name as product_name,
        p.sku,
        u.abbreviation as unit
      FROM invoice_items ii
      LEFT JOIN products p ON p.uuid = ii.product_uuid
      LEFT JOIN units u ON u.id = ii.unit_id
      WHERE ii.invoice_uuid = ?
      ORDER BY ii.created_at
    `).all(uuid);

    res.json({
      success: true,
      invoice,
      items
    });
  } catch (error) {
    logger.error('Get invoice error', { error: error.message });
    res.status(500).json({
      success: false,
      error: 'Failed to get invoice'
    });
  }
}

/**
 * Create new invoice
 * POST /api/invoices
 */
function createInvoice(req, res) {
  try {
    const {
      invoice_date,
      customer_name,
      customer_phone,
      customer_address,
      customer_gst,
      invoice_type,
      discount_amount,
      notes,
      items
    } = req.body;

    // Validation
    if (!invoice_date) {
      return res.status(400).json({
        success: false,
        error: 'invoice_date is required'
      });
    }

    if (!items || !Array.isArray(items) || items.length === 0) {
      return res.status(400).json({
        success: false,
        error: 'At least one item is required'
      });
    }

    const db = getDatabase();
    const invoiceUuid = uuidv4();
    const now = new Date().toISOString();

    // Generate invoice number
    const lastInvoice = db.prepare(
      "SELECT invoice_number FROM invoices ORDER BY id DESC LIMIT 1"
    ).get();

    let invoiceNumber = 'INV0001';
    if (lastInvoice) {
      const lastNum = parseInt(lastInvoice.invoice_number.substring(3));
      invoiceNumber = `INV${String(lastNum + 1).padStart(4, '0')}`;
    }

    const result = transaction(() => {
      // Insert invoice header
      db.prepare(`
        INSERT INTO invoices (
          uuid, invoice_number, invoice_date,
          customer_name, customer_phone, customer_address, customer_gst,
          invoice_type, payment_status, discount_amount,
          subtotal, gst_amount, grand_total, status,
          notes, created_at, last_modified, created_by
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'pending', ?, 0, 0, 0, 'draft', ?, ?, ?, ?)
      `).run(
        invoiceUuid,
        invoiceNumber,
        invoice_date,
        customer_name || null,
        customer_phone || null,
        customer_address || null,
        customer_gst || null,
        invoice_type || 'cash',
        discount_amount || 0,
        notes || null,
        now,
        now,
        req.user.uuid
      );

      // Insert invoice items and calculate totals
      let subtotal = 0;
      let totalGst = 0;

      items.forEach(item => {
        const itemUuid = uuidv4();
        const lineTotal = item.quantity * item.unit_price;
        const itemDiscountAmount = lineTotal * (item.discount_percent || 0) / 100;
        const taxableAmount = lineTotal - itemDiscountAmount;
        const itemGst = taxableAmount * (item.gst_rate || 0) / 100;
        const itemTotalWithGst = taxableAmount + itemGst;

        db.prepare(`
          INSERT INTO invoice_items (
            uuid, invoice_uuid, product_uuid, quantity, unit_id,
            unit_price, discount_percent, discount_amount,
            gst_rate, gst_amount, total_amount,
            created_at, last_modified
          ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        `).run(
          itemUuid,
          invoiceUuid,
          item.product_uuid,
          item.quantity,
          item.unit_id,
          item.unit_price || 0,
          item.discount_percent || 0,
          itemDiscountAmount,
          item.gst_rate || 0,
          itemGst,
          itemTotalWithGst,
          now,
          now
        );

        subtotal += taxableAmount;
        totalGst += itemGst;
      });

      // Update invoice totals (triggers will also calculate, but we do it explicitly)
      const invoiceDiscountAmount = discount_amount || 0;
      const grandTotal = subtotal + totalGst - invoiceDiscountAmount;

      db.prepare(`
        UPDATE invoices
        SET subtotal = ?, gst_amount = ?, grand_total = ?, last_modified = ?
        WHERE uuid = ?
      `).run(subtotal, totalGst, grandTotal, now, invoiceUuid);

      // Add to sync queue
      const invoiceData = db.prepare('SELECT * FROM invoices WHERE uuid = ?').get(invoiceUuid);
      db.prepare(`
        INSERT INTO sync_queue (table_name, operation, record_uuid, payload, created_at)
        VALUES ('invoices', 'insert', ?, ?, datetime('now'))
      `).run(invoiceUuid, JSON.stringify(invoiceData));

      // Log audit
      db.prepare(`
        INSERT INTO audit_logs (table_name, record_uuid, operation, user_uuid, new_values)
        VALUES ('invoices', ?, 'insert', ?, ?)
      `).run(invoiceUuid, req.user.uuid, JSON.stringify({ items: items.length }));

      return { success: true };
    });

    logger.info('Invoice created', {
      invoice_uuid: invoiceUuid,
      invoice_number: invoiceNumber,
      items_count: items.length,
      by_user: req.user.username
    });

    res.status(201).json({
      success: true,
      message: 'Invoice created successfully',
      invoice: {
        uuid: invoiceUuid,
        invoice_number: invoiceNumber
      }
    });
  } catch (error) {
    logger.error('Create invoice error', { error: error.message, stack: error.stack });
    res.status(500).json({
      success: false,
      error: 'Failed to create invoice'
    });
  }
}

/**
 * Update invoice status
 * PUT /api/invoices/:uuid/status
 */
function updateInvoiceStatus(req, res) {
  try {
    const { uuid } = req.params;
    const { status, location_uuid } = req.body;

    if (!['draft', 'finalized', 'cancelled'].includes(status)) {
      return res.status(400).json({
        success: false,
        error: 'Invalid status. Must be: draft, finalized, or cancelled'
      });
    }

    if (status === 'finalized' && !location_uuid) {
      return res.status(400).json({
        success: false,
        error: 'location_uuid is required when finalizing invoice'
      });
    }

    const db = getDatabase();

    // Get invoice
    const invoice = db.prepare('SELECT * FROM invoices WHERE uuid = ?').get(uuid);

    if (!invoice) {
      return res.status(404).json({
        success: false,
        error: 'Invoice not found'
      });
    }

    // Cannot change status if already finalized
    if (invoice.status === 'finalized' && status !== 'finalized') {
      return res.status(400).json({
        success: false,
        error: 'Cannot change status of finalized invoice'
      });
    }

    const now = new Date().toISOString();

    const result = transaction(() => {
      // If finalizing, check stock availability first
      if (status === 'finalized' && invoice.status !== 'finalized') {
        const items = db.prepare('SELECT * FROM invoice_items WHERE invoice_uuid = ?').all(uuid);
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

        if (insufficientItems.length > 0) {
          throw new Error(JSON.stringify({
            message: 'Insufficient stock for one or more items',
            items: insufficientItems
          }));
        }

        // Deduct stock for all items
        for (const item of items) {
          // Create stock adjustment entry
          const adjustmentUuid = uuidv4();
          db.prepare(`
            INSERT INTO stock_adjustments (
              uuid, product_uuid, location_uuid, quantity,
              adjustment_type, reference_type, reference_uuid,
              notes, created_at, last_modified, created_by
            ) VALUES (?, ?, ?, ?, 'sale', 'invoice', ?, ?, ?, ?, ?)
          `).run(
            adjustmentUuid,
            item.product_uuid,
            location_uuid,
            -item.quantity,
            uuid,
            `Invoice ${invoice.invoice_number}`,
            now,
            now,
            req.user.uuid
          );

          // Update stock_levels
          db.prepare(`
            INSERT INTO stock_levels (product_uuid, location_uuid, quantity, last_updated)
            VALUES (?, ?, ?, ?)
            ON CONFLICT(product_uuid, location_uuid)
            DO UPDATE SET
              quantity = quantity + excluded.quantity,
              last_updated = excluded.last_updated
          `).run(item.product_uuid, location_uuid, -item.quantity, now);
        }
      }

      const updates = {
        status,
        last_modified: now
      };

      if (status === 'finalized') {
        updates.finalized_by = req.user.uuid;
        updates.finalized_at = now;
        updates.payment_status = invoice.invoice_type === 'cash' ? 'paid' : 'pending';
      }

      const updateFields = Object.keys(updates).map(k => `${k} = ?`).join(', ');
      const updateValues = [...Object.values(updates), uuid];

      db.prepare(`
        UPDATE invoices SET ${updateFields} WHERE uuid = ?
      `).run(...updateValues);

      // Add to sync queue
      const updatedInvoice = db.prepare('SELECT * FROM invoices WHERE uuid = ?').get(uuid);
      db.prepare(`
        INSERT INTO sync_queue (table_name, operation, record_uuid, payload, created_at)
        VALUES ('invoices', 'update', ?, ?, datetime('now'))
      `).run(uuid, JSON.stringify(updatedInvoice));

      // Log audit
      db.prepare(`
        INSERT INTO audit_logs (table_name, record_uuid, operation, user_uuid, old_values, new_values)
        VALUES ('invoices', ?, 'update', ?, ?, ?)
      `).run(uuid, req.user.uuid, JSON.stringify(invoice), JSON.stringify(updates));

      return { success: true };
    });

    logger.info('Invoice status updated', {
      invoice_uuid: uuid,
      old_status: invoice.status,
      new_status: status,
      by_user: req.user.username
    });

    res.json({
      success: true,
      message: 'Invoice status updated successfully',
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
      logger.error('Update invoice status error', { error: error.message });
      res.status(500).json({
        success: false,
        error: 'Failed to update invoice status'
      });
    }
  }
}

/**
 * Delete invoice
 * DELETE /api/invoices/:uuid
 */
function deleteInvoice(req, res) {
  try {
    const { uuid } = req.params;
    const db = getDatabase();

    const invoice = db.prepare('SELECT * FROM invoices WHERE uuid = ?').get(uuid);

    if (!invoice) {
      return res.status(404).json({
        success: false,
        error: 'Invoice not found'
      });
    }

    // Cannot delete finalized invoices
    if (invoice.status === 'finalized') {
      return res.status(400).json({
        success: false,
        error: 'Cannot delete finalized invoice. Stock has already been deducted.'
      });
    }

    const result = transaction(() => {
      // Delete invoice items (CASCADE will handle this)
      db.prepare('DELETE FROM invoice_items WHERE invoice_uuid = ?').run(uuid);

      // Delete invoice
      db.prepare('DELETE FROM invoices WHERE uuid = ?').run(uuid);

      // Log audit
      db.prepare(`
        INSERT INTO audit_logs (table_name, record_uuid, operation, user_uuid, old_values)
        VALUES ('invoices', ?, 'delete', ?, ?)
      `).run(uuid, req.user.uuid, JSON.stringify(invoice));

      return { success: true };
    });

    logger.info('Invoice deleted', { invoice_uuid: uuid, by_user: req.user.username });

    res.json({
      success: true,
      message: 'Invoice deleted successfully'
    });
  } catch (error) {
    logger.error('Delete invoice error', { error: error.message });
    res.status(500).json({
      success: false,
      error: 'Failed to delete invoice'
    });
  }
}

/**
 * Get invoice summary/statistics
 * GET /api/invoices/summary
 */
function getInvoiceSummary(req, res) {
  try {
    const db = getDatabase();
    const { from_date, to_date } = req.query;

    let dateFilter = '';
    const params = [];

    if (from_date) {
      dateFilter += ' AND invoice_date >= ?';
      params.push(from_date);
    }

    if (to_date) {
      dateFilter += ' AND invoice_date <= ?';
      params.push(to_date);
    }

    const summary = db.prepare(`
      SELECT
        COUNT(*) as total_invoices,
        COUNT(CASE WHEN status = 'finalized' THEN 1 END) as finalized_count,
        COUNT(CASE WHEN status = 'draft' THEN 1 END) as draft_count,
        COUNT(CASE WHEN invoice_type = 'cash' THEN 1 END) as cash_count,
        COUNT(CASE WHEN invoice_type = 'credit' THEN 1 END) as credit_count,
        COALESCE(SUM(CASE WHEN status = 'finalized' THEN grand_total ELSE 0 END), 0) as total_sales,
        COALESCE(SUM(CASE WHEN status = 'finalized' AND payment_status = 'paid' THEN grand_total ELSE 0 END), 0) as paid_amount,
        COALESCE(SUM(CASE WHEN status = 'finalized' AND payment_status != 'paid' THEN grand_total ELSE 0 END), 0) as pending_amount
      FROM invoices
      WHERE 1=1 ${dateFilter}
    `).get(...params);

    res.json({
      success: true,
      summary
    });
  } catch (error) {
    logger.error('Get invoice summary error', { error: error.message });
    res.status(500).json({
      success: false,
      error: 'Failed to get invoice summary'
    });
  }
}

/**
 * Update payment status
 * PUT /api/invoices/:uuid/payment
 */
function updatePaymentStatus(req, res) {
  try {
    const { uuid } = req.params;
    const { payment_status, amount_paid } = req.body;

    if (!['pending', 'partial', 'paid'].includes(payment_status)) {
      return res.status(400).json({
        success: false,
        error: 'Invalid payment status'
      });
    }

    const db = getDatabase();
    const invoice = db.prepare('SELECT * FROM invoices WHERE uuid = ?').get(uuid);

    if (!invoice) {
      return res.status(404).json({
        success: false,
        error: 'Invoice not found'
      });
    }

    if (invoice.status !== 'finalized') {
      return res.status(400).json({
        success: false,
        error: 'Can only update payment status for finalized invoices'
      });
    }

    const now = new Date().toISOString();

    db.prepare(`
      UPDATE invoices
      SET payment_status = ?, last_modified = ?
      WHERE uuid = ?
    `).run(payment_status, now, uuid);

    logger.info('Payment status updated', {
      invoice_uuid: uuid,
      payment_status,
      by_user: req.user.username
    });

    res.json({
      success: true,
      message: 'Payment status updated successfully'
    });
  } catch (error) {
    logger.error('Update payment status error', { error: error.message });
    res.status(500).json({
      success: false,
      error: 'Failed to update payment status'
    });
  }
}

module.exports = {
  listInvoices,
  getInvoice,
  createInvoice,
  updateInvoiceStatus,
  deleteInvoice,
  getInvoiceSummary,
  updatePaymentStatus
};
