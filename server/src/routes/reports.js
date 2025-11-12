/**
 * Reports Routes
 */

const express = require('express');
const router = express.Router();
const reportsController = require('../controllers/reports');
const { authenticate } = require('../middleware/auth');

// All routes require authentication
router.use(authenticate);

// Reports - All available to authenticated users
router.get('/dashboard', reportsController.getDashboardSummary);
router.get('/sales', reportsController.getSalesReport);
router.get('/stock-valuation', reportsController.getStockValuation);
router.get('/low-stock', reportsController.getLowStockReport);
router.get('/purchases', reportsController.getPurchaseReport);
router.get('/profitability', reportsController.getProfitabilityReport);

module.exports = router;
