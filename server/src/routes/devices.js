/**
 * Device Management Routes
 */

const express = require('express');
const router = express.Router();
const deviceController = require('../controllers/devices');

// Public device routes
router.post('/register', deviceController.registerDevice);
router.post('/heartbeat', deviceController.updateHeartbeat);
router.get('/', deviceController.getDevices);
router.get('/:device_uuid/stats', deviceController.getDeviceStats);

// Admin device routes
router.post('/:device_uuid/deactivate', deviceController.deactivateDevice);
router.post('/:device_uuid/reactivate', deviceController.reactivateDevice);
router.post('/cleanup-stale', deviceController.cleanupStaleDevices);

module.exports = router;
