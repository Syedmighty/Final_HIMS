/**
 * Device Management Controller
 * Handles device registration, heartbeat, and admin operations
 * ENFORCES MAX_DEVICES limit (server is authoritative)
 */

const { getDatabase, transaction } = require('../config/database');
const logger = require('../config/logger');
const { v4: uuidv4 } = require('uuid');

const MAX_DEVICES = parseInt(process.env.MAX_DEVICES) || 5;
const HEARTBEAT_TIMEOUT_HOURS = parseInt(process.env.DEVICE_HEARTBEAT_TIMEOUT_HOURS) || 24;

/**
 * Register a new device
 * POST /devices/register
 * Enforces MAX_DEVICES limit
 */
async function registerDevice(req, res) {
  try {
    const {
      device_uuid,
      device_name,
      device_type,
      os_info,
      app_version,
      user_uuid,
      metadata
    } = req.body;

    // Validation
    if (!device_uuid || !device_name || !user_uuid) {
      return res.status(400).json({
        success: false,
        error: 'Missing required fields: device_uuid, device_name, user_uuid'
      });
    }

    const db = getDatabase();

    // Check if device already exists
    const existingDevice = db.prepare(
      'SELECT * FROM device_registrations WHERE uuid = ? AND is_active = 1'
    ).get(device_uuid);

    if (existingDevice) {
      // Device already registered, update heartbeat
      db.prepare(`
        UPDATE device_registrations
        SET last_heartbeat = datetime('now'),
            device_name = ?,
            device_type = ?,
            os_info = ?,
            app_version = ?,
            metadata = ?
        WHERE uuid = ?
      `).run(device_name, device_type, os_info, app_version, JSON.stringify(metadata || {}), device_uuid);

      logger.info('Device re-registered (updated heartbeat)', { device_uuid, device_name });

      return res.json({
        success: true,
        message: 'Device updated successfully',
        device: {
          uuid: device_uuid,
          device_name,
          is_new: false
        }
      });
    }

    // Check current active device count
    const { count } = db.prepare(
      'SELECT COUNT(*) as count FROM device_registrations WHERE is_active = 1'
    ).get();

    if (count >= MAX_DEVICES) {
      logger.warn('Device registration blocked: MAX_DEVICES limit reached', {
        device_uuid,
        device_name,
        current_count: count,
        max_devices: MAX_DEVICES
      });

      return res.status(403).json({
        success: false,
        error: `Maximum device limit reached (${MAX_DEVICES}). Please contact administrator to deactivate inactive devices.`,
        current_devices: count,
        max_devices: MAX_DEVICES
      });
    }

    // Register new device
    const result = transaction(() => {
      db.prepare(`
        INSERT INTO device_registrations (
          uuid, device_name, device_type, os_info, app_version,
          last_heartbeat, registered_at, registered_by, is_active, metadata
        ) VALUES (?, ?, ?, ?, ?, datetime('now'), datetime('now'), ?, 1, ?)
      `).run(
        device_uuid,
        device_name,
        device_type || 'unknown',
        os_info,
        app_version,
        user_uuid,
        JSON.stringify(metadata || {})
      );

      // Log audit
      db.prepare(`
        INSERT INTO audit_logs (table_name, record_uuid, operation, new_values, user_uuid, device_uuid)
        VALUES ('device_registrations', ?, 'insert', ?, ?, ?)
      `).run(
        device_uuid,
        JSON.stringify({ device_name, device_type, registered_by: user_uuid }),
        user_uuid,
        device_uuid
      );

      return { success: true };
    });

    logger.info('New device registered successfully', {
      device_uuid,
      device_name,
      device_type,
      user_uuid,
      active_devices: count + 1
    });

    res.status(201).json({
      success: true,
      message: 'Device registered successfully',
      device: {
        uuid: device_uuid,
        device_name,
        device_type,
        is_new: true,
        active_devices: count + 1,
        max_devices: MAX_DEVICES
      }
    });
  } catch (error) {
    logger.error('Device registration failed', { error: error.message, stack: error.stack });
    res.status(500).json({
      success: false,
      error: 'Device registration failed',
      details: process.env.NODE_ENV === 'development' ? error.message : undefined
    });
  }
}

/**
 * Update device heartbeat
 * POST /devices/heartbeat
 */
async function updateHeartbeat(req, res) {
  try {
    const { device_uuid } = req.body;

    if (!device_uuid) {
      return res.status(400).json({
        success: false,
        error: 'Missing device_uuid'
      });
    }

    const db = getDatabase();

    const result = db.prepare(`
      UPDATE device_registrations
      SET last_heartbeat = datetime('now')
      WHERE uuid = ? AND is_active = 1
    `).run(device_uuid);

    if (result.changes === 0) {
      logger.warn('Heartbeat update failed: Device not found or inactive', { device_uuid });
      return res.status(404).json({
        success: false,
        error: 'Device not found or inactive'
      });
    }

    logger.debug('Heartbeat updated', { device_uuid });

    res.json({
      success: true,
      message: 'Heartbeat updated',
      timestamp: new Date().toISOString()
    });
  } catch (error) {
    logger.error('Heartbeat update failed', { error: error.message });
    res.status(500).json({
      success: false,
      error: 'Heartbeat update failed'
    });
  }
}

/**
 * Get all registered devices
 * GET /devices
 */
async function getDevices(req, res) {
  try {
    const db = getDatabase();
    const { active_only } = req.query;

    let query = `
      SELECT
        dr.*,
        u.full_name as registered_by_name,
        CAST((julianday('now') - julianday(dr.last_heartbeat)) * 24 * 60 AS INTEGER) as minutes_since_heartbeat,
        CASE
          WHEN (julianday('now') - julianday(dr.last_heartbeat)) * 24 < 1 THEN 'online'
          WHEN (julianday('now') - julianday(dr.last_heartbeat)) * 24 < 24 THEN 'idle'
          ELSE 'stale'
        END as device_status
      FROM device_registrations dr
      LEFT JOIN users u ON u.uuid = dr.registered_by
    `;

    if (active_only === 'true') {
      query += ' WHERE dr.is_active = 1';
    }

    query += ' ORDER BY dr.last_heartbeat DESC';

    const devices = db.prepare(query).all();

    res.json({
      success: true,
      devices,
      count: devices.length,
      max_devices: MAX_DEVICES
    });
  } catch (error) {
    logger.error('Failed to fetch devices', { error: error.message });
    res.status(500).json({
      success: false,
      error: 'Failed to fetch devices'
    });
  }
}

/**
 * Get device sync statistics
 * GET /devices/:device_uuid/stats
 */
async function getDeviceStats(req, res) {
  try {
    const { device_uuid } = req.params;
    const db = getDatabase();

    const stats = db.prepare(`
      SELECT * FROM v_device_sync_stats WHERE device_uuid = ?
    `).get(device_uuid);

    if (!stats) {
      return res.status(404).json({
        success: false,
        error: 'Device not found'
      });
    }

    res.json({
      success: true,
      stats
    });
  } catch (error) {
    logger.error('Failed to fetch device stats', { error: error.message });
    res.status(500).json({
      success: false,
      error: 'Failed to fetch device stats'
    });
  }
}

/**
 * Deactivate a device (Admin only)
 * POST /admin/devices/:device_uuid/deactivate
 */
async function deactivateDevice(req, res) {
  try {
    const { device_uuid } = req.params;
    const { reason, user_uuid } = req.body;

    if (!user_uuid) {
      return res.status(400).json({
        success: false,
        error: 'Missing user_uuid (admin user)'
      });
    }

    const db = getDatabase();

    // Verify user is admin
    const user = db.prepare('SELECT role FROM users WHERE uuid = ?').get(user_uuid);
    if (!user || user.role !== 'admin') {
      return res.status(403).json({
        success: false,
        error: 'Unauthorized: Admin access required'
      });
    }

    const result = transaction(() => {
      const updateResult = db.prepare(`
        UPDATE device_registrations
        SET
          is_active = 0,
          deactivated_at = datetime('now'),
          deactivated_by = ?,
          deactivation_reason = ?
        WHERE uuid = ? AND is_active = 1
      `).run(user_uuid, reason || 'Manually deactivated by admin', device_uuid);

      if (updateResult.changes === 0) {
        throw new Error('Device not found or already inactive');
      }

      // Log audit
      db.prepare(`
        INSERT INTO audit_logs (table_name, record_uuid, operation, new_values, user_uuid, device_uuid)
        VALUES ('device_registrations', ?, 'update', ?, ?, ?)
      `).run(
        device_uuid,
        JSON.stringify({ is_active: 0, deactivated_by: user_uuid, reason }),
        user_uuid,
        device_uuid
      );

      return { success: true };
    });

    logger.info('Device deactivated', { device_uuid, reason, by_user: user_uuid });

    res.json({
      success: true,
      message: 'Device deactivated successfully',
      device_uuid
    });
  } catch (error) {
    logger.error('Device deactivation failed', { error: error.message });
    res.status(500).json({
      success: false,
      error: error.message
    });
  }
}

/**
 * Reactivate a device (Admin only)
 * POST /admin/devices/:device_uuid/reactivate
 */
async function reactivateDevice(req, res) {
  try {
    const { device_uuid } = req.params;
    const { user_uuid } = req.body;

    if (!user_uuid) {
      return res.status(400).json({
        success: false,
        error: 'Missing user_uuid (admin user)'
      });
    }

    const db = getDatabase();

    // Verify user is admin
    const user = db.prepare('SELECT role FROM users WHERE uuid = ?').get(user_uuid);
    if (!user || user.role !== 'admin') {
      return res.status(403).json({
        success: false,
        error: 'Unauthorized: Admin access required'
      });
    }

    // Check device limit
    const { count } = db.prepare(
      'SELECT COUNT(*) as count FROM device_registrations WHERE is_active = 1'
    ).get();

    if (count >= MAX_DEVICES) {
      return res.status(403).json({
        success: false,
        error: `Cannot reactivate: Maximum device limit reached (${MAX_DEVICES})`,
        current_devices: count,
        max_devices: MAX_DEVICES
      });
    }

    const result = db.prepare(`
      UPDATE device_registrations
      SET
        is_active = 1,
        last_heartbeat = datetime('now'),
        deactivated_at = NULL,
        deactivated_by = NULL,
        deactivation_reason = NULL
      WHERE uuid = ? AND is_active = 0
    `).run(device_uuid);

    if (result.changes === 0) {
      return res.status(404).json({
        success: false,
        error: 'Device not found or already active'
      });
    }

    logger.info('Device reactivated', { device_uuid, by_user: user_uuid });

    res.json({
      success: true,
      message: 'Device reactivated successfully',
      device_uuid
    });
  } catch (error) {
    logger.error('Device reactivation failed', { error: error.message });
    res.status(500).json({
      success: false,
      error: 'Device reactivation failed'
    });
  }
}

/**
 * Auto-cleanup stale devices (called periodically by server)
 * POST /admin/devices/cleanup-stale
 */
async function cleanupStaleDevices(req, res) {
  try {
    const { user_uuid } = req.body;
    const db = getDatabase();

    const daysThreshold = parseInt(process.env.AUTO_DEACTIVATE_STALE_DEVICES_DAYS) || 30;

    const result = db.prepare(`
      UPDATE device_registrations
      SET
        is_active = 0,
        deactivated_at = datetime('now'),
        deactivation_reason = 'Auto-deactivated: No heartbeat for ${daysThreshold}+ days'
      WHERE is_active = 1
      AND (julianday('now') - julianday(last_heartbeat)) > ?
      AND deactivated_at IS NULL
    `).run(daysThreshold);

    logger.info('Stale devices cleaned up', {
      deactivated_count: result.changes,
      threshold_days: daysThreshold,
      by_user: user_uuid
    });

    res.json({
      success: true,
      message: 'Stale devices cleaned up',
      deactivated_count: result.changes
    });
  } catch (error) {
    logger.error('Stale device cleanup failed', { error: error.message });
    res.status(500).json({
      success: false,
      error: 'Cleanup failed'
    });
  }
}

module.exports = {
  registerDevice,
  updateHeartbeat,
  getDevices,
  getDeviceStats,
  deactivateDevice,
  reactivateDevice,
  cleanupStaleDevices
};
