/**
 * Wastage Routes
 */

const express = require('express');
const router = express.Router();
const wastageController = require('../controllers/wastage');
const { authenticate, requireStaff } = require('../middleware/auth');

// All routes require authentication
router.use(authenticate);

// Wastage
router.get('/', wastageController.listWastage);
router.get('/summary', wastageController.getWastageSummary);
router.get('/:uuid', wastageController.getWastage);
router.post('/', requireStaff, wastageController.createWastage);
router.put('/:uuid/status', requireStaff, wastageController.updateWastageStatus);
router.delete('/:uuid', requireStaff, wastageController.deleteWastage);

module.exports = router;
