/**
 * Transfers Routes
 */

const express = require('express');
const router = express.Router();
const transfersController = require('../controllers/transfers');
const { authenticate, requireStaff } = require('../middleware/auth');

// All routes require authentication
router.use(authenticate);

// Transfers
router.get('/', transfersController.listTransfers);
router.get('/:uuid', transfersController.getTransfer);
router.post('/', requireStaff, transfersController.createTransfer);
router.put('/:uuid/status', requireStaff, transfersController.updateTransferStatus);
router.delete('/:uuid', requireStaff, transfersController.deleteTransfer);

module.exports = router;
