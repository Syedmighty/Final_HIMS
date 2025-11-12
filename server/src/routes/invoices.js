/**
 * Invoices Routes
 */

const express = require('express');
const router = express.Router();
const invoicesController = require('../controllers/invoices');
const { authenticate, requireStaff } = require('../middleware/auth');

// All routes require authentication
router.use(authenticate);

// Invoices
router.get('/', invoicesController.listInvoices);
router.get('/summary', invoicesController.getInvoiceSummary);
router.get('/:uuid', invoicesController.getInvoice);
router.post('/', requireStaff, invoicesController.createInvoice);
router.put('/:uuid/status', requireStaff, invoicesController.updateInvoiceStatus);
router.put('/:uuid/payment', requireStaff, invoicesController.updatePaymentStatus);
router.delete('/:uuid', requireStaff, invoicesController.deleteInvoice);

module.exports = router;
