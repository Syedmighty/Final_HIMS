/**
 * Reports Controller
 * Provides business intelligence and analytics across all modules
 */

const { getDatabase } = require('../config/database');
const logger = require('../config/logger');

/**
 * Get sales report
 * GET /api/reports/sales
 */
function getSalesReport(req, res) {
  try {
    const db = getDatabase();
    const { from_date, to_date, location_uuid } = req.query;

    let dateFilter = '';
    const params = [];

    if (from_date) {
      dateFilter += ' AND i.invoice_date >= ?';
      params.push(from_date);
    }

    if (to_date) {
      dateFilter += ' AND i.invoice_date <= ?';
      params.push(to_date);
    }

    // Overall summary
    const summary = db.prepare(`
      SELECT
        COUNT(*) as total_invoices,
        COUNT(DISTINCT i.customer_phone) as unique_customers,
        COALESCE(SUM(i.grand_total), 0) as total_revenue,
        COALESCE(SUM(i.subtotal), 0) as subtotal,
        COALESCE(SUM(i.gst_amount), 0) as total_gst,
        COALESCE(SUM(i.discount_amount), 0) as total_discount,
        COALESCE(AVG(i.grand_total), 0) as average_invoice_value,
        COUNT(CASE WHEN i.invoice_type = 'cash' THEN 1 END) as cash_invoices,
        COUNT(CASE WHEN i.invoice_type = 'credit' THEN 1 END) as credit_invoices,
        COALESCE(SUM(CASE WHEN i.payment_status = 'paid' THEN i.grand_total ELSE 0 END), 0) as paid_amount,
        COALESCE(SUM(CASE WHEN i.payment_status != 'paid' THEN i.grand_total ELSE 0 END), 0) as pending_amount
      FROM invoices i
      WHERE i.status = 'finalized' ${dateFilter}
    `).get(...params);

    // Sales by date
    const salesByDate = db.prepare(`
      SELECT
        DATE(i.invoice_date) as date,
        COUNT(*) as invoices_count,
        COALESCE(SUM(i.grand_total), 0) as total_revenue
      FROM invoices i
      WHERE i.status = 'finalized' ${dateFilter}
      GROUP BY DATE(i.invoice_date)
      ORDER BY date DESC
      LIMIT 30
    `).all(...params);

    // Top selling products
    const topProducts = db.prepare(`
      SELECT
        p.name as product_name,
        p.sku,
        COUNT(DISTINCT ii.invoice_uuid) as times_sold,
        COALESCE(SUM(ii.quantity), 0) as total_quantity_sold,
        u.abbreviation as unit,
        COALESCE(SUM(ii.total_amount), 0) as total_revenue
      FROM invoice_items ii
      JOIN invoices i ON i.uuid = ii.invoice_uuid
      JOIN products p ON p.uuid = ii.product_uuid
      LEFT JOIN units u ON u.id = ii.unit_id
      WHERE i.status = 'finalized' ${dateFilter}
      GROUP BY ii.product_uuid
      ORDER BY total_quantity_sold DESC
      LIMIT 10
    `).all(...params);

    // Sales by payment type
    const paymentTypeSummary = db.prepare(`
      SELECT
        invoice_type,
        COUNT(*) as count,
        COALESCE(SUM(grand_total), 0) as total_amount
      FROM invoices
      WHERE status = 'finalized' ${dateFilter}
      GROUP BY invoice_type
    `).all(...params);

    res.json({
      success: true,
      summary,
      sales_by_date: salesByDate,
      top_selling_products: topProducts,
      payment_type_summary: paymentTypeSummary
    });
  } catch (error) {
    logger.error('Get sales report error', { error: error.message });
    res.status(500).json({
      success: false,
      error: 'Failed to generate sales report'
    });
  }
}

/**
 * Get stock valuation report
 * GET /api/reports/stock-valuation
 */
function getStockValuation(req, res) {
  try {
    const db = getDatabase();
    const { location_uuid } = req.query;

    let locationFilter = '';
    const params = [];

    if (location_uuid) {
      locationFilter = ' AND sl.location_uuid = ?';
      params.push(location_uuid);
    }

    // Overall stock valuation
    const summary = db.prepare(`
      SELECT
        COUNT(DISTINCT sl.product_uuid) as total_products,
        COALESCE(SUM(sl.quantity), 0) as total_quantity,
        COALESCE(SUM(sl.quantity * p.cost_price), 0) as total_cost_value,
        COALESCE(SUM(sl.quantity * p.selling_price), 0) as total_selling_value,
        COALESCE(SUM(sl.quantity * (p.selling_price - p.cost_price)), 0) as potential_profit
      FROM stock_levels sl
      JOIN products p ON p.uuid = sl.product_uuid
      WHERE sl.quantity > 0 ${locationFilter}
    `).get(...params);

    // Stock valuation by location
    const byLocation = db.prepare(`
      SELECT
        l.name as location_name,
        l.location_type,
        COUNT(DISTINCT sl.product_uuid) as products_count,
        COALESCE(SUM(sl.quantity), 0) as total_quantity,
        COALESCE(SUM(sl.quantity * p.cost_price), 0) as cost_value,
        COALESCE(SUM(sl.quantity * p.selling_price), 0) as selling_value
      FROM stock_levels sl
      JOIN products p ON p.uuid = sl.product_uuid
      JOIN locations l ON l.uuid = sl.location_uuid
      WHERE sl.quantity > 0
      GROUP BY sl.location_uuid
      ORDER BY cost_value DESC
    `).all();

    // Top value products in stock
    const topValueProducts = db.prepare(`
      SELECT
        p.name as product_name,
        p.sku,
        COALESCE(SUM(sl.quantity), 0) as total_quantity,
        u.abbreviation as unit,
        p.cost_price,
        COALESCE(SUM(sl.quantity * p.cost_price), 0) as total_value
      FROM stock_levels sl
      JOIN products p ON p.uuid = sl.product_uuid
      LEFT JOIN units u ON u.id = p.default_unit_id
      WHERE sl.quantity > 0 ${locationFilter}
      GROUP BY sl.product_uuid
      ORDER BY total_value DESC
      LIMIT 10
    `).all(...params);

    res.json({
      success: true,
      summary,
      by_location: byLocation,
      top_value_products: topValueProducts
    });
  } catch (error) {
    logger.error('Get stock valuation error', { error: error.message });
    res.status(500).json({
      success: false,
      error: 'Failed to generate stock valuation report'
    });
  }
}

/**
 * Get low stock alert report
 * GET /api/reports/low-stock
 */
function getLowStockReport(req, res) {
  try {
    const db = getDatabase();
    const { location_uuid } = req.query;

    let locationFilter = '';
    const params = [];

    if (location_uuid) {
      locationFilter = ' AND sl.location_uuid = ?';
      params.push(location_uuid);
    }

    // Low stock items (below reorder level)
    const lowStockItems = db.prepare(`
      SELECT
        p.name as product_name,
        p.sku,
        l.name as location_name,
        sl.quantity as current_stock,
        p.reorder_level,
        p.min_stock_level,
        u.abbreviation as unit,
        (p.reorder_level - sl.quantity) as shortage,
        p.cost_price,
        ((p.reorder_level - sl.quantity) * p.cost_price) as estimated_reorder_cost
      FROM stock_levels sl
      JOIN products p ON p.uuid = sl.product_uuid
      JOIN locations l ON l.uuid = sl.location_uuid
      LEFT JOIN units u ON u.id = p.default_unit_id
      WHERE sl.quantity > 0
        AND sl.quantity <= p.reorder_level
        ${locationFilter}
      ORDER BY (sl.quantity - p.min_stock_level) ASC
    `).all(...params);

    // Critical stock (below minimum level)
    const criticalStockItems = lowStockItems.filter(item =>
      item.current_stock <= item.min_stock_level
    );

    // Out of stock (but previously stocked)
    const outOfStockItems = db.prepare(`
      SELECT DISTINCT
        p.name as product_name,
        p.sku,
        l.name as location_name,
        p.reorder_level,
        u.abbreviation as unit,
        p.cost_price,
        (p.reorder_level * p.cost_price) as estimated_reorder_cost
      FROM products p
      JOIN locations l ON 1=1
      LEFT JOIN units u ON u.id = p.default_unit_id
      WHERE p.is_active = 1
        AND p.uuid IN (
          SELECT DISTINCT product_uuid
          FROM stock_adjustments
          WHERE location_uuid = l.uuid
        )
        AND p.uuid NOT IN (
          SELECT product_uuid
          FROM stock_levels
          WHERE location_uuid = l.uuid AND quantity > 0
        )
        ${locationFilter ? 'AND l.uuid = ?' : ''}
      ORDER BY p.name ASC
    `).all(...params);

    // Summary
    const summary = {
      total_low_stock: lowStockItems.length,
      critical_stock: criticalStockItems.length,
      out_of_stock: outOfStockItems.length,
      total_alerts: lowStockItems.length + outOfStockItems.length,
      estimated_reorder_cost: [
        ...lowStockItems,
        ...outOfStockItems
      ].reduce((sum, item) => sum + (item.estimated_reorder_cost || 0), 0)
    };

    res.json({
      success: true,
      summary,
      low_stock_items: lowStockItems,
      critical_stock_items: criticalStockItems,
      out_of_stock_items: outOfStockItems
    });
  } catch (error) {
    logger.error('Get low stock report error', { error: error.message });
    res.status(500).json({
      success: false,
      error: 'Failed to generate low stock report'
    });
  }
}

/**
 * Get purchase report
 * GET /api/reports/purchases
 */
function getPurchaseReport(req, res) {
  try {
    const db = getDatabase();
    const { from_date, to_date, supplier_uuid } = req.query;

    let filters = '';
    const params = [];

    if (from_date) {
      filters += ' AND p.purchase_date >= ?';
      params.push(from_date);
    }

    if (to_date) {
      filters += ' AND p.purchase_date <= ?';
      params.push(to_date);
    }

    if (supplier_uuid) {
      filters += ' AND p.supplier_uuid = ?';
      params.push(supplier_uuid);
    }

    // Purchase summary
    const summary = db.prepare(`
      SELECT
        COUNT(*) as total_purchases,
        COUNT(DISTINCT p.supplier_uuid) as unique_suppliers,
        COALESCE(SUM(p.grand_total), 0) as total_amount,
        COALESCE(SUM(p.gst_amount), 0) as total_gst,
        COALESCE(AVG(p.grand_total), 0) as average_purchase_value,
        COUNT(CASE WHEN p.status = 'received' THEN 1 END) as received_count,
        COUNT(CASE WHEN p.status = 'draft' THEN 1 END) as draft_count,
        COUNT(CASE WHEN p.status = 'ordered' THEN 1 END) as ordered_count
      FROM purchases p
      WHERE 1=1 ${filters}
    `).get(...params);

    // Purchases by supplier
    const bySupplier = db.prepare(`
      SELECT
        s.name as supplier_name,
        COUNT(*) as purchase_count,
        COALESCE(SUM(p.grand_total), 0) as total_amount,
        COALESCE(AVG(p.grand_total), 0) as average_amount
      FROM purchases p
      JOIN suppliers s ON s.uuid = p.supplier_uuid
      WHERE p.status = 'received' ${filters}
      GROUP BY p.supplier_uuid
      ORDER BY total_amount DESC
      LIMIT 10
    `).all(...params);

    // Most purchased products
    const topProducts = db.prepare(`
      SELECT
        pr.name as product_name,
        pr.sku,
        COALESCE(SUM(pi.quantity), 0) as total_quantity,
        u.abbreviation as unit,
        COUNT(DISTINCT pi.purchase_uuid) as purchase_count,
        COALESCE(SUM(pi.total_amount), 0) as total_amount
      FROM purchase_items pi
      JOIN purchases p ON p.uuid = pi.purchase_uuid
      JOIN products pr ON pr.uuid = pi.product_uuid
      LEFT JOIN units u ON u.id = pi.unit_id
      WHERE p.status = 'received' ${filters}
      GROUP BY pi.product_uuid
      ORDER BY total_quantity DESC
      LIMIT 10
    `).all(...params);

    res.json({
      success: true,
      summary,
      by_supplier: bySupplier,
      top_purchased_products: topProducts
    });
  } catch (error) {
    logger.error('Get purchase report error', { error: error.message });
    res.status(500).json({
      success: false,
      error: 'Failed to generate purchase report'
    });
  }
}

/**
 * Get profitability report
 * GET /api/reports/profitability
 */
function getProfitabilityReport(req, res) {
  try {
    const db = getDatabase();
    const { from_date, to_date } = req.query;

    let dateFilter = '';
    const params = [];

    if (from_date) {
      dateFilter += ' AND i.invoice_date >= ?';
      params.push(from_date);
    }

    if (to_date) {
      dateFilter += ' AND i.invoice_date <= ?';
      params.push(to_date);
    }

    // Overall profitability (simplified - actual cost per sale would need more complex tracking)
    const salesSummary = db.prepare(`
      SELECT
        COALESCE(SUM(i.grand_total), 0) as total_revenue,
        COALESCE(SUM(i.subtotal), 0) as subtotal,
        COALESCE(SUM(i.gst_amount), 0) as total_gst,
        COUNT(*) as total_invoices
      FROM invoices i
      WHERE i.status = 'finalized' ${dateFilter}
    `).get(...params);

    // Product-level profitability (from invoice items)
    const productProfitability = db.prepare(`
      SELECT
        p.name as product_name,
        p.sku,
        COALESCE(SUM(ii.quantity), 0) as total_sold,
        u.abbreviation as unit,
        COALESCE(SUM(ii.total_amount), 0) as total_revenue,
        p.cost_price,
        (COALESCE(SUM(ii.quantity), 0) * p.cost_price) as estimated_cost,
        (COALESCE(SUM(ii.total_amount), 0) - (COALESCE(SUM(ii.quantity), 0) * p.cost_price)) as estimated_profit,
        CASE
          WHEN COALESCE(SUM(ii.total_amount), 0) > 0 THEN
            ROUND(((COALESCE(SUM(ii.total_amount), 0) - (COALESCE(SUM(ii.quantity), 0) * p.cost_price)) / COALESCE(SUM(ii.total_amount), 0) * 100), 2)
          ELSE 0
        END as profit_margin_percent
      FROM invoice_items ii
      JOIN invoices i ON i.uuid = ii.invoice_uuid
      JOIN products p ON p.uuid = ii.product_uuid
      LEFT JOIN units u ON u.id = ii.unit_id
      WHERE i.status = 'finalized' ${dateFilter}
      GROUP BY ii.product_uuid
      ORDER BY estimated_profit DESC
      LIMIT 20
    `).all(...params);

    // Calculate total estimated cost and profit
    const totalEstimatedCost = productProfitability.reduce((sum, item) =>
      sum + (item.estimated_cost || 0), 0
    );
    const totalEstimatedProfit = productProfitability.reduce((sum, item) =>
      sum + (item.estimated_profit || 0), 0
    );

    const summary = {
      ...salesSummary,
      total_estimated_cost: totalEstimatedCost,
      total_estimated_profit: totalEstimatedProfit,
      estimated_profit_margin: salesSummary.total_revenue > 0
        ? ((totalEstimatedProfit / salesSummary.total_revenue) * 100).toFixed(2)
        : 0
    };

    // Best performers
    const bestPerformers = productProfitability.filter(p => p.estimated_profit > 0).slice(0, 10);

    // Worst performers
    const worstPerformers = [...productProfitability]
      .sort((a, b) => a.estimated_profit - b.estimated_profit)
      .slice(0, 10);

    res.json({
      success: true,
      summary,
      product_profitability: productProfitability,
      best_performers: bestPerformers,
      worst_performers: worstPerformers
    });
  } catch (error) {
    logger.error('Get profitability report error', { error: error.message });
    res.status(500).json({
      success: false,
      error: 'Failed to generate profitability report'
    });
  }
}

/**
 * Get dashboard summary with key metrics
 * GET /api/reports/dashboard
 */
function getDashboardSummary(req, res) {
  try {
    const db = getDatabase();

    // Today's date
    const today = new Date().toISOString().split('T')[0];

    // Sales today
    const salesToday = db.prepare(`
      SELECT
        COUNT(*) as invoices_count,
        COALESCE(SUM(grand_total), 0) as total_revenue
      FROM invoices
      WHERE status = 'finalized' AND DATE(invoice_date) = ?
    `).get(today);

    // Low stock alerts
    const lowStockCount = db.prepare(`
      SELECT COUNT(*) as count
      FROM stock_levels sl
      JOIN products p ON p.uuid = sl.product_uuid
      WHERE sl.quantity > 0 AND sl.quantity <= p.reorder_level
    `).get();

    // Pending purchases
    const pendingPurchases = db.prepare(`
      SELECT COUNT(*) as count, COALESCE(SUM(grand_total), 0) as total_amount
      FROM purchases
      WHERE status IN ('draft', 'ordered')
    `).get();

    // Total stock value
    const stockValue = db.prepare(`
      SELECT
        COALESCE(SUM(sl.quantity * p.cost_price), 0) as total_value
      FROM stock_levels sl
      JOIN products p ON p.uuid = sl.product_uuid
      WHERE sl.quantity > 0
    `).get();

    // This month's sales
    const thisMonth = new Date().toISOString().substring(0, 7); // YYYY-MM
    const monthSales = db.prepare(`
      SELECT
        COUNT(*) as invoices_count,
        COALESCE(SUM(grand_total), 0) as total_revenue
      FROM invoices
      WHERE status = 'finalized' AND strftime('%Y-%m', invoice_date) = ?
    `).get(thisMonth);

    // Recent activities (last 10)
    const recentInvoices = db.prepare(`
      SELECT
        'invoice' as type,
        uuid,
        invoice_number as reference,
        grand_total as amount,
        created_at
      FROM invoices
      ORDER BY created_at DESC
      LIMIT 5
    `).all();

    const recentPurchases = db.prepare(`
      SELECT
        'purchase' as type,
        uuid,
        purchase_number as reference,
        grand_total as amount,
        created_at
      FROM purchases
      ORDER BY created_at DESC
      LIMIT 5
    `).all();

    const recentActivities = [...recentInvoices, ...recentPurchases]
      .sort((a, b) => new Date(b.created_at) - new Date(a.created_at))
      .slice(0, 10);

    res.json({
      success: true,
      sales_today: salesToday,
      sales_this_month: monthSales,
      low_stock_alerts: lowStockCount.count,
      pending_purchases: pendingPurchases,
      total_stock_value: stockValue.total_value,
      recent_activities: recentActivities
    });
  } catch (error) {
    logger.error('Get dashboard summary error', { error: error.message });
    res.status(500).json({
      success: false,
      error: 'Failed to generate dashboard summary'
    });
  }
}

module.exports = {
  getSalesReport,
  getStockValuation,
  getLowStockReport,
  getPurchaseReport,
  getProfitabilityReport,
  getDashboardSummary
};
