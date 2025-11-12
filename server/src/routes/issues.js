/**
 * Issues (Stock Out) Routes
 */

const express = require('express');
const router = express.Router();
const issuesController = require('../controllers/issues');
const { authenticate, requireStaff } = require('../middleware/auth');

// All routes require authentication
router.use(authenticate);

// Issues
router.get('/', issuesController.listIssues);
router.get('/:uuid', issuesController.getIssue);
router.post('/', requireStaff, issuesController.createIssue);
router.put('/:uuid/status', requireStaff, issuesController.updateIssueStatus);
router.delete('/:uuid', requireStaff, issuesController.deleteIssue);

// Stock validation
router.post('/check-stock', issuesController.checkStockAvailability);

module.exports = router;
