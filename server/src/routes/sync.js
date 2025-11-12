/**
 * Sync Routes
 */

const express = require('express');
const router = express.Router();
const syncController = require('../controllers/sync');

// Sync operations
router.post('/push', syncController.pushData);
router.get('/pull', syncController.pullData);

// Conflict management
router.get('/conflicts', syncController.getConflicts);
router.post('/conflicts/:conflict_id/resolve', syncController.resolveConflict);

module.exports = router;
