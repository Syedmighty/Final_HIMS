/**
 * Authentication Middleware
 * JWT token validation and user authentication
 */

const jwt = require('jsonwebtoken');
const { getDatabase } = require('../config/database');
const logger = require('../config/logger');

const JWT_SECRET = process.env.JWT_SECRET || 'change_this_in_production';
const JWT_EXPIRY = process.env.JWT_EXPIRY || '24h';

/**
 * Generate JWT token for user
 * @param {Object} user - User object
 * @returns {string} JWT token
 */
function generateToken(user) {
  const payload = {
    uuid: user.uuid,
    username: user.username,
    role: user.role,
    full_name: user.full_name
  };

  return jwt.sign(payload, JWT_SECRET, { expiresIn: JWT_EXPIRY });
}

/**
 * Verify JWT token
 * @param {string} token - JWT token
 * @returns {Object|null} Decoded token payload or null
 */
function verifyToken(token) {
  try {
    return jwt.verify(token, JWT_SECRET);
  } catch (error) {
    return null;
  }
}

/**
 * Authentication middleware
 * Validates JWT token from Authorization header
 */
function authenticate(req, res, next) {
  try {
    // Get token from header
    const authHeader = req.headers.authorization;

    if (!authHeader || !authHeader.startsWith('Bearer ')) {
      return res.status(401).json({
        success: false,
        error: 'No token provided. Authorization header required.'
      });
    }

    const token = authHeader.substring(7); // Remove 'Bearer ' prefix

    // Verify token
    const decoded = verifyToken(token);

    if (!decoded) {
      return res.status(401).json({
        success: false,
        error: 'Invalid or expired token'
      });
    }

    // Verify user still exists and is active
    const db = getDatabase();
    const user = db.prepare(
      'SELECT uuid, username, role, full_name, is_active FROM users WHERE uuid = ?'
    ).get(decoded.uuid);

    if (!user) {
      return res.status(401).json({
        success: false,
        error: 'User not found'
      });
    }

    if (!user.is_active) {
      return res.status(403).json({
        success: false,
        error: 'User account is inactive'
      });
    }

    // Attach user to request object
    req.user = user;
    next();
  } catch (error) {
    logger.error('Authentication error', { error: error.message });
    res.status(500).json({
      success: false,
      error: 'Authentication failed'
    });
  }
}

/**
 * Optional authentication middleware
 * Attaches user if token is valid, but doesn't require it
 */
function optionalAuth(req, res, next) {
  try {
    const authHeader = req.headers.authorization;

    if (authHeader && authHeader.startsWith('Bearer ')) {
      const token = authHeader.substring(7);
      const decoded = verifyToken(token);

      if (decoded) {
        const db = getDatabase();
        const user = db.prepare(
          'SELECT uuid, username, role, full_name, is_active FROM users WHERE uuid = ?'
        ).get(decoded.uuid);

        if (user && user.is_active) {
          req.user = user;
        }
      }
    }

    next();
  } catch (error) {
    // Continue without user
    next();
  }
}

/**
 * Role-based authorization middleware
 * @param {Array<string>} allowedRoles - Array of allowed roles
 * @returns {Function} Middleware function
 */
function authorize(...allowedRoles) {
  return (req, res, next) => {
    if (!req.user) {
      return res.status(401).json({
        success: false,
        error: 'Authentication required'
      });
    }

    if (!allowedRoles.includes(req.user.role)) {
      logger.warn('Authorization failed', {
        user: req.user.username,
        role: req.user.role,
        required: allowedRoles
      });

      return res.status(403).json({
        success: false,
        error: 'Insufficient permissions',
        required_role: allowedRoles,
        user_role: req.user.role
      });
    }

    next();
  };
}

/**
 * Require admin role
 */
const requireAdmin = authorize('admin');

/**
 * Require admin or manager role
 */
const requireManager = authorize('admin', 'manager');

/**
 * Require any authenticated user except viewer
 */
const requireStaff = authorize('admin', 'manager', 'staff');

module.exports = {
  authenticate,
  optionalAuth,
  authorize,
  requireAdmin,
  requireManager,
  requireStaff,
  generateToken,
  verifyToken
};
