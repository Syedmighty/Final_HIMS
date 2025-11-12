/**
 * Settings Routes
 */

const express = require('express');
const router = express.Router();
const settingsController = require('../controllers/settings');
const { authenticate, requireManager, requireAdmin } = require('../middleware/auth');

// All routes require authentication
router.use(authenticate);

// Company settings
router.get('/company', settingsController.getCompanySettings);
router.put('/company', requireManager, settingsController.updateCompanySettings);

// System information
router.get('/system-info', settingsController.getSystemInfo);

// Data export/backup
router.get('/export', requireManager, settingsController.exportData);
router.post('/backup', requireAdmin, settingsController.createBackup);

// Audit logs
router.get('/audit-logs', requireManager, settingsController.getAuditLogs);

// Maintenance
router.post('/maintenance/clear-old-data', requireAdmin, settingsController.clearOldData);

module.exports = router;
