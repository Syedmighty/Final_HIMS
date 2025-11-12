/**
 * Purchases Routes
 */

const express = require('express');
const router = express.Router();
const purchasesController = require('../controllers/purchases');
const { authenticate, requireStaff } = require('../middleware/auth');

// All routes require authentication
router.use(authenticate);

// Purchases
router.get('/', purchasesController.listPurchases);
router.get('/:uuid', purchasesController.getPurchase);
router.post('/', requireStaff, purchasesController.createPurchase);
router.put('/:uuid/status', requireStaff, purchasesController.updatePurchaseStatus);
router.delete('/:uuid', requireStaff, purchasesController.deletePurchase);

// Suppliers
router.get('/suppliers/list', purchasesController.listSuppliers);
router.post('/suppliers', requireStaff, purchasesController.createSupplier);

module.exports = router;
