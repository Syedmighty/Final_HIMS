/**
 * Authentication Routes
 */

const express = require('express');
const router = express.Router();
const authController = require('../controllers/auth');
const { authenticate, requireAdmin, requireManager } = require('../middleware/auth');

// Public routes
router.post('/login', authController.login);

// Protected routes (require authentication)
router.get('/me', authenticate, authController.getCurrentUser);
router.post('/change-password', authenticate, authController.changePassword);

// User management (Admin/Manager only)
router.get('/users', authenticate, requireManager, authController.listUsers);
router.post('/users', authenticate, requireAdmin, authController.createUser);
router.put('/users/:uuid', authenticate, requireAdmin, authController.updateUser);
router.delete('/users/:uuid', authenticate, requireAdmin, authController.deleteUser);

module.exports = router;
