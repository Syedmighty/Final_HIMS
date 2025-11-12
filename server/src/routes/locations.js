/**
 * Locations Routes
 */

const express = require('express');
const router = express.Router();
const locationsController = require('../controllers/locations');
const { authenticate, requireStaff, requireManager } = require('../middleware/auth');

// All routes require authentication
router.use(authenticate);

// Locations
router.get('/', locationsController.listLocations);
router.get('/:uuid', locationsController.getLocation);
router.get('/:uuid/stock-summary', locationsController.getLocationStockSummary);
router.post('/', requireManager, locationsController.createLocation);
router.put('/:uuid', requireManager, locationsController.updateLocation);
router.delete('/:uuid', requireManager, locationsController.deleteLocation);

module.exports = router;
