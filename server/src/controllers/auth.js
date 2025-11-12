/**
 * Authentication Controller
 * Handles user login, logout, registration, and token management
 */

const bcrypt = require('bcrypt');
const { getDatabase, transaction } = require('../config/database');
const { generateToken } = require('../middleware/auth');
const logger = require('../config/logger');
const { v4: uuidv4 } = require('uuid');

const BCRYPT_ROUNDS = parseInt(process.env.BCRYPT_ROUNDS) || 10;

/**
 * User login
 * POST /api/auth/login
 */
async function login(req, res) {
  try {
    const { username, password, device_uuid } = req.body;

    if (!username || !password) {
      return res.status(400).json({
        success: false,
        error: 'Username and password are required'
      });
    }

    const db = getDatabase();

    // Get user
    const user = db.prepare(
      'SELECT * FROM users WHERE username = ? AND is_active = 1'
    ).get(username);

    if (!user) {
      logger.warn('Login failed: user not found', { username });
      return res.status(401).json({
        success: false,
        error: 'Invalid username or password'
      });
    }

    // Verify password
    const passwordMatch = await bcrypt.compare(password, user.password_hash);

    if (!passwordMatch) {
      logger.warn('Login failed: invalid password', { username });
      return res.status(401).json({
        success: false,
        error: 'Invalid username or password'
      });
    }

    // Generate token
    const token = generateToken(user);

    // Log audit
    db.prepare(`
      INSERT INTO audit_logs (table_name, operation, user_uuid, device_uuid, new_values)
      VALUES ('users', 'login', ?, ?, ?)
    `).run(user.uuid, device_uuid || null, JSON.stringify({ username }));

    logger.info('User logged in', {
      username,
      role: user.role,
      device_uuid
    });

    // Return user data and token
    res.json({
      success: true,
      token,
      user: {
        uuid: user.uuid,
        username: user.username,
        full_name: user.full_name,
        role: user.role,
        email: user.email
      }
    });
  } catch (error) {
    logger.error('Login error', { error: error.message, stack: error.stack });
    res.status(500).json({
      success: false,
      error: 'Login failed'
    });
  }
}

/**
 * Get current user
 * GET /api/auth/me
 */
function getCurrentUser(req, res) {
  try {
    if (!req.user) {
      return res.status(401).json({
        success: false,
        error: 'Not authenticated'
      });
    }

    const db = getDatabase();
    const user = db.prepare(
      'SELECT uuid, username, full_name, role, email, phone, created_at FROM users WHERE uuid = ?'
    ).get(req.user.uuid);

    if (!user) {
      return res.status(404).json({
        success: false,
        error: 'User not found'
      });
    }

    res.json({
      success: true,
      user
    });
  } catch (error) {
    logger.error('Get current user error', { error: error.message });
    res.status(500).json({
      success: false,
      error: 'Failed to get user'
    });
  }
}

/**
 * Change password
 * POST /api/auth/change-password
 */
async function changePassword(req, res) {
  try {
    const { current_password, new_password } = req.body;

    if (!current_password || !new_password) {
      return res.status(400).json({
        success: false,
        error: 'Current password and new password are required'
      });
    }

    if (new_password.length < 6) {
      return res.status(400).json({
        success: false,
        error: 'New password must be at least 6 characters'
      });
    }

    const db = getDatabase();

    // Get user with password hash
    const user = db.prepare(
      'SELECT * FROM users WHERE uuid = ?'
    ).get(req.user.uuid);

    // Verify current password
    const passwordMatch = await bcrypt.compare(current_password, user.password_hash);

    if (!passwordMatch) {
      return res.status(401).json({
        success: false,
        error: 'Current password is incorrect'
      });
    }

    // Hash new password
    const newPasswordHash = await bcrypt.hash(new_password, BCRYPT_ROUNDS);

    // Update password
    db.prepare(`
      UPDATE users
      SET password_hash = ?, last_modified = datetime('now')
      WHERE uuid = ?
    `).run(newPasswordHash, req.user.uuid);

    // Log audit
    db.prepare(`
      INSERT INTO audit_logs (table_name, operation, user_uuid, new_values)
      VALUES ('users', 'update', ?, ?)
    `).run(req.user.uuid, JSON.stringify({ action: 'password_changed' }));

    logger.info('Password changed', { user_uuid: req.user.uuid });

    res.json({
      success: true,
      message: 'Password changed successfully'
    });
  } catch (error) {
    logger.error('Change password error', { error: error.message });
    res.status(500).json({
      success: false,
      error: 'Failed to change password'
    });
  }
}

/**
 * Create new user (Admin only)
 * POST /api/auth/users
 */
async function createUser(req, res) {
  try {
    const {
      username,
      password,
      full_name,
      role,
      email,
      phone
    } = req.body;

    // Validation
    if (!username || !password || !full_name || !role) {
      return res.status(400).json({
        success: false,
        error: 'Username, password, full_name, and role are required'
      });
    }

    if (!['admin', 'manager', 'staff', 'viewer'].includes(role)) {
      return res.status(400).json({
        success: false,
        error: 'Invalid role. Must be: admin, manager, staff, or viewer'
      });
    }

    if (password.length < 6) {
      return res.status(400).json({
        success: false,
        error: 'Password must be at least 6 characters'
      });
    }

    const db = getDatabase();

    // Check if username already exists
    const existing = db.prepare(
      'SELECT uuid FROM users WHERE username = ?'
    ).get(username);

    if (existing) {
      return res.status(409).json({
        success: false,
        error: 'Username already exists'
      });
    }

    // Hash password
    const passwordHash = await bcrypt.hash(password, BCRYPT_ROUNDS);

    // Create user
    const userUuid = uuidv4();

    const result = transaction(() => {
      db.prepare(`
        INSERT INTO users (
          uuid, username, password_hash, full_name, role,
          email, phone, is_active, created_at, last_modified, created_by
        ) VALUES (?, ?, ?, ?, ?, ?, ?, 1, datetime('now'), datetime('now'), ?)
      `).run(
        userUuid,
        username,
        passwordHash,
        full_name,
        role,
        email || null,
        phone || null,
        req.user.uuid
      );

      // Log audit
      db.prepare(`
        INSERT INTO audit_logs (table_name, record_uuid, operation, user_uuid, new_values)
        VALUES ('users', ?, 'insert', ?, ?)
      `).run(
        userUuid,
        req.user.uuid,
        JSON.stringify({ username, full_name, role })
      );

      return { success: true };
    });

    logger.info('User created', {
      created_user: username,
      role,
      by_user: req.user.username
    });

    res.status(201).json({
      success: true,
      message: 'User created successfully',
      user: {
        uuid: userUuid,
        username,
        full_name,
        role,
        email
      }
    });
  } catch (error) {
    logger.error('Create user error', { error: error.message });
    res.status(500).json({
      success: false,
      error: 'Failed to create user'
    });
  }
}

/**
 * List all users (Admin/Manager only)
 * GET /api/auth/users
 */
function listUsers(req, res) {
  try {
    const db = getDatabase();
    const { active_only } = req.query;

    let query = `
      SELECT
        uuid, username, full_name, role, email, phone,
        is_active, created_at, last_modified
      FROM users
    `;

    if (active_only === 'true') {
      query += ' WHERE is_active = 1';
    }

    query += ' ORDER BY created_at DESC';

    const users = db.prepare(query).all();

    res.json({
      success: true,
      users,
      count: users.length
    });
  } catch (error) {
    logger.error('List users error', { error: error.message });
    res.status(500).json({
      success: false,
      error: 'Failed to list users'
    });
  }
}

/**
 * Update user (Admin only)
 * PUT /api/auth/users/:uuid
 */
function updateUser(req, res) {
  try {
    const { uuid } = req.params;
    const { full_name, role, email, phone, is_active } = req.body;

    const db = getDatabase();

    // Check user exists
    const user = db.prepare('SELECT * FROM users WHERE uuid = ?').get(uuid);

    if (!user) {
      return res.status(404).json({
        success: false,
        error: 'User not found'
      });
    }

    // Prevent deactivating yourself
    if (uuid === req.user.uuid && is_active === 0) {
      return res.status(400).json({
        success: false,
        error: 'Cannot deactivate your own account'
      });
    }

    // Build update query
    const updates = [];
    const values = [];

    if (full_name !== undefined) {
      updates.push('full_name = ?');
      values.push(full_name);
    }
    if (role !== undefined) {
      if (!['admin', 'manager', 'staff', 'viewer'].includes(role)) {
        return res.status(400).json({
          success: false,
          error: 'Invalid role'
        });
      }
      updates.push('role = ?');
      values.push(role);
    }
    if (email !== undefined) {
      updates.push('email = ?');
      values.push(email);
    }
    if (phone !== undefined) {
      updates.push('phone = ?');
      values.push(phone);
    }
    if (is_active !== undefined) {
      updates.push('is_active = ?');
      values.push(is_active ? 1 : 0);
    }

    if (updates.length === 0) {
      return res.status(400).json({
        success: false,
        error: 'No fields to update'
      });
    }

    updates.push('last_modified = datetime(\'now\')');
    values.push(uuid);

    const result = transaction(() => {
      db.prepare(`
        UPDATE users SET ${updates.join(', ')} WHERE uuid = ?
      `).run(...values);

      // Log audit
      db.prepare(`
        INSERT INTO audit_logs (table_name, record_uuid, operation, user_uuid, new_values)
        VALUES ('users', ?, 'update', ?, ?)
      `).run(uuid, req.user.uuid, JSON.stringify(req.body));

      return { success: true };
    });

    logger.info('User updated', { updated_user: uuid, by_user: req.user.username });

    res.json({
      success: true,
      message: 'User updated successfully'
    });
  } catch (error) {
    logger.error('Update user error', { error: error.message });
    res.status(500).json({
      success: false,
      error: 'Failed to update user'
    });
  }
}

/**
 * Delete user (Admin only)
 * DELETE /api/auth/users/:uuid
 */
function deleteUser(req, res) {
  try {
    const { uuid } = req.params;
    const db = getDatabase();

    // Prevent deleting yourself
    if (uuid === req.user.uuid) {
      return res.status(400).json({
        success: false,
        error: 'Cannot delete your own account'
      });
    }

    // Check user exists
    const user = db.prepare('SELECT * FROM users WHERE uuid = ?').get(uuid);

    if (!user) {
      return res.status(404).json({
        success: false,
        error: 'User not found'
      });
    }

    // Soft delete
    const result = transaction(() => {
      db.prepare(`
        UPDATE users
        SET is_active = 0, deleted_at = datetime('now'), deleted_by = ?, last_modified = datetime('now')
        WHERE uuid = ?
      `).run(req.user.uuid, uuid);

      // Log audit
      db.prepare(`
        INSERT INTO audit_logs (table_name, record_uuid, operation, user_uuid, old_values)
        VALUES ('users', ?, 'delete', ?, ?)
      `).run(uuid, req.user.uuid, JSON.stringify(user));

      return { success: true };
    });

    logger.info('User deleted', { deleted_user: uuid, by_user: req.user.username });

    res.json({
      success: true,
      message: 'User deleted successfully'
    });
  } catch (error) {
    logger.error('Delete user error', { error: error.message });
    res.status(500).json({
      success: false,
      error: 'Failed to delete user'
    });
  }
}

module.exports = {
  login,
  getCurrentUser,
  changePassword,
  createUser,
  listUsers,
  updateUser,
  deleteUser
};
