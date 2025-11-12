/**
 * Settings Controller
 * Handles company profile, system settings, and data export/import
 */

const { getDatabase, transaction, backupDatabase } = require('../config/database');
const logger = require('../config/logger');
const fs = require('fs');
const path = require('path');

/**
 * Get company settings
 * GET /api/settings/company
 */
function getCompanySettings(req, res) {
  try {
    const db = getDatabase();

    const settings = db.prepare('SELECT * FROM company_settings WHERE id = 1').get();

    if (!settings) {
      return res.status(404).json({
        success: false,
        error: 'Company settings not found'
      });
    }

    res.json({
      success: true,
      settings
    });
  } catch (error) {
    logger.error('Get company settings error', { error: error.message });
    res.status(500).json({
      success: false,
      error: 'Failed to get company settings'
    });
  }
}

/**
 * Update company settings
 * PUT /api/settings/company
 */
function updateCompanySettings(req, res) {
  try {
    const {
      company_name,
      address,
      phone,
      email,
      gst_number,
      logo_path,
      currency,
      decimal_places,
      date_format,
      time_zone,
      financial_year_start
    } = req.body;

    const db = getDatabase();

    // Get current settings
    const currentSettings = db.prepare('SELECT * FROM company_settings WHERE id = 1').get();

    if (!currentSettings) {
      return res.status(404).json({
        success: false,
        error: 'Company settings not found'
      });
    }

    const now = new Date().toISOString();

    const result = transaction(() => {
      const updates = {};
      if (company_name !== undefined) updates.company_name = company_name;
      if (address !== undefined) updates.address = address;
      if (phone !== undefined) updates.phone = phone;
      if (email !== undefined) updates.email = email;
      if (gst_number !== undefined) updates.gst_number = gst_number;
      if (logo_path !== undefined) updates.logo_path = logo_path;
      if (currency !== undefined) updates.currency = currency;
      if (decimal_places !== undefined) updates.decimal_places = decimal_places;
      if (date_format !== undefined) updates.date_format = date_format;
      if (time_zone !== undefined) updates.time_zone = time_zone;
      if (financial_year_start !== undefined) updates.financial_year_start = financial_year_start;
      updates.last_modified = now;

      const updateFields = Object.keys(updates).map(k => `${k} = ?`).join(', ');
      const updateValues = [...Object.values(updates)];

      db.prepare(`
        UPDATE company_settings SET ${updateFields} WHERE id = 1
      `).run(...updateValues);

      // Log audit
      db.prepare(`
        INSERT INTO audit_logs (table_name, record_uuid, operation, user_uuid, old_values, new_values)
        VALUES ('company_settings', '1', 'update', ?, ?, ?)
      `).run(req.user.uuid, JSON.stringify(currentSettings), JSON.stringify(updates));

      return { success: true };
    });

    logger.info('Company settings updated', { by_user: req.user.username });

    const updatedSettings = db.prepare('SELECT * FROM company_settings WHERE id = 1').get();

    res.json({
      success: true,
      message: 'Company settings updated successfully',
      settings: updatedSettings
    });
  } catch (error) {
    logger.error('Update company settings error', { error: error.message });
    res.status(500).json({
      success: false,
      error: 'Failed to update company settings'
    });
  }
}

/**
 * Get system information
 * GET /api/settings/system-info
 */
function getSystemInfo(req, res) {
  try {
    const db = getDatabase();

    // Database statistics
    const stats = {
      products: db.prepare('SELECT COUNT(*) as count FROM products WHERE is_active = 1').get(),
      locations: db.prepare('SELECT COUNT(*) as count FROM locations WHERE is_active = 1').get(),
      suppliers: db.prepare('SELECT COUNT(*) as count FROM suppliers WHERE is_active = 1').get(),
      users: db.prepare('SELECT COUNT(*) as count FROM users WHERE is_active = 1').get(),
      invoices: db.prepare('SELECT COUNT(*) as count FROM invoices WHERE status = \'finalized\'').get(),
      purchases: db.prepare('SELECT COUNT(*) as count FROM purchases WHERE status = \'received\'').get(),
      recipes: db.prepare('SELECT COUNT(*) as count FROM recipes WHERE is_active = 1').get(),
      devices: db.prepare('SELECT COUNT(*) as count FROM device_registrations WHERE is_active = 1').get()
    };

    // Database file size
    const dbPath = process.env.DATABASE_PATH || './data/hims.db';
    let dbSize = 0;
    try {
      const stat = fs.statSync(dbPath);
      dbSize = stat.size;
    } catch (e) {
      logger.warn('Could not get database file size', { error: e.message });
    }

    // Sync statistics
    const syncStats = {
      pending_sync: db.prepare('SELECT COUNT(*) as count FROM sync_queue WHERE synced_at IS NULL').get(),
      unresolved_conflicts: db.prepare('SELECT COUNT(*) as count FROM conflict_logs WHERE resolved_at IS NULL').get()
    };

    res.json({
      success: true,
      system_info: {
        version: '1.0.1',
        database_size_bytes: dbSize,
        database_size_mb: (dbSize / (1024 * 1024)).toFixed(2),
        ...stats,
        ...syncStats,
        node_version: process.version,
        platform: process.platform,
        uptime_seconds: process.uptime()
      }
    });
  } catch (error) {
    logger.error('Get system info error', { error: error.message });
    res.status(500).json({
      success: false,
      error: 'Failed to get system information'
    });
  }
}

/**
 * Export data to JSON
 * GET /api/settings/export
 */
function exportData(req, res) {
  try {
    const { tables } = req.query;
    const db = getDatabase();

    const exportTables = tables
      ? tables.split(',')
      : ['products', 'categories', 'units', 'suppliers', 'locations', 'recipes', 'users'];

    const exportData = {
      export_date: new Date().toISOString(),
      version: '1.0.1',
      data: {}
    };

    exportTables.forEach(tableName => {
      try {
        const data = db.prepare(`SELECT * FROM ${tableName}`).all();
        exportData.data[tableName] = data;
      } catch (error) {
        logger.warn(`Could not export table ${tableName}`, { error: error.message });
      }
    });

    logger.info('Data exported', {
      tables: exportTables.length,
      by_user: req.user.username
    });

    res.json({
      success: true,
      export: exportData
    });
  } catch (error) {
    logger.error('Export data error', { error: error.message });
    res.status(500).json({
      success: false,
      error: 'Failed to export data'
    });
  }
}

/**
 * Backup database
 * POST /api/settings/backup
 */
function createBackup(req, res) {
  try {
    const backupPath = backupDatabase();

    logger.info('Database backup created', {
      backup_path: backupPath,
      by_user: req.user.username
    });

    res.json({
      success: true,
      message: 'Database backup created successfully',
      backup_path: backupPath,
      timestamp: new Date().toISOString()
    });
  } catch (error) {
    logger.error('Create backup error', { error: error.message });
    res.status(500).json({
      success: false,
      error: 'Failed to create database backup'
    });
  }
}

/**
 * Get audit logs
 * GET /api/settings/audit-logs
 */
function getAuditLogs(req, res) {
  try {
    const db = getDatabase();
    const { table_name, user_uuid, from_date, limit = 100, offset = 0 } = req.query;

    let query = `
      SELECT
        a.*,
        u.full_name as user_name,
        u.username
      FROM audit_logs a
      LEFT JOIN users u ON u.uuid = a.user_uuid
      WHERE 1=1
    `;

    const params = [];

    if (table_name) {
      query += ' AND a.table_name = ?';
      params.push(table_name);
    }

    if (user_uuid) {
      query += ' AND a.user_uuid = ?';
      params.push(user_uuid);
    }

    if (from_date) {
      query += ' AND a.timestamp >= ?';
      params.push(from_date);
    }

    query += ' ORDER BY a.timestamp DESC LIMIT ? OFFSET ?';
    params.push(parseInt(limit), parseInt(offset));

    const logs = db.prepare(query).all(...params);

    // Get total count
    let countQuery = 'SELECT COUNT(*) as count FROM audit_logs WHERE 1=1';
    const countParams = [];

    if (table_name) {
      countQuery += ' AND table_name = ?';
      countParams.push(table_name);
    }

    if (user_uuid) {
      countQuery += ' AND user_uuid = ?';
      countParams.push(user_uuid);
    }

    if (from_date) {
      countQuery += ' AND timestamp >= ?';
      countParams.push(from_date);
    }

    const { count } = db.prepare(countQuery).get(...countParams);

    res.json({
      success: true,
      logs,
      count,
      limit: parseInt(limit),
      offset: parseInt(offset)
    });
  } catch (error) {
    logger.error('Get audit logs error', { error: error.message });
    res.status(500).json({
      success: false,
      error: 'Failed to get audit logs'
    });
  }
}

/**
 * Clear old data (maintenance operation)
 * POST /api/settings/maintenance/clear-old-data
 */
function clearOldData(req, res) {
  try {
    const { days_old = 365 } = req.body;

    if (!req.user || req.user.role !== 'admin') {
      return res.status(403).json({
        success: false,
        error: 'Only administrators can perform this operation'
      });
    }

    const db = getDatabase();
    const cutoffDate = new Date();
    cutoffDate.setDate(cutoffDate.getDate() - parseInt(days_old));
    const cutoffISO = cutoffDate.toISOString();

    const result = transaction(() => {
      // Clear old audit logs
      const auditResult = db.prepare(`
        DELETE FROM audit_logs WHERE timestamp < ?
      `).run(cutoffISO);

      // Clear synced items from sync queue
      const syncResult = db.prepare(`
        DELETE FROM sync_queue WHERE synced_at IS NOT NULL AND synced_at < ?
      `).run(cutoffISO);

      // Clear resolved conflicts
      const conflictResult = db.prepare(`
        DELETE FROM conflict_logs WHERE resolved_at IS NOT NULL AND resolved_at < ?
      `).run(cutoffISO);

      return {
        audit_logs_deleted: auditResult.changes,
        sync_queue_deleted: syncResult.changes,
        conflicts_deleted: conflictResult.changes
      };
    });

    logger.info('Old data cleared', {
      days_old,
      ...result,
      by_user: req.user.username
    });

    res.json({
      success: true,
      message: 'Old data cleared successfully',
      ...result
    });
  } catch (error) {
    logger.error('Clear old data error', { error: error.message });
    res.status(500).json({
      success: false,
      error: 'Failed to clear old data'
    });
  }
}

module.exports = {
  getCompanySettings,
  updateCompanySettings,
  getSystemInfo,
  exportData,
  createBackup,
  getAuditLogs,
  clearOldData
};
