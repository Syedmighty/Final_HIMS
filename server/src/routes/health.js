/**
 * Health Check Routes
 */

const express = require('express');
const router = express.Router();
const { getDatabase, integrityCheck } = require('../config/database');

// Basic health check
router.get('/', (req, res) => {
  res.json({
    status: 'ok',
    timestamp: new Date().toISOString(),
    uptime: process.uptime(),
    environment: process.env.NODE_ENV || 'development'
  });
});

// Detailed health check
router.get('/detailed', (req, res) => {
  try {
    const db = getDatabase();
    const health = integrityCheck();

    // Get device count
    const { count: deviceCount } = db.prepare(
      'SELECT COUNT(*) as count FROM device_registrations WHERE is_active = 1'
    ).get();

    // Get unsynced items count
    const { count: unsyncedCount } = db.prepare(
      'SELECT COUNT(*) as count FROM sync_queue WHERE synced = 0'
    ).get();

    // Get unresolved conflicts count
    const { count: conflictsCount } = db.prepare(
      'SELECT COUNT(*) as count FROM conflict_logs WHERE resolved = 0'
    ).get();

    res.json({
      status: health.isHealthy ? 'ok' : 'degraded',
      timestamp: new Date().toISOString(),
      uptime: process.uptime(),
      database: {
        healthy: health.isHealthy,
        integrity: health.integrityCheck,
        foreignKeyCheck: health.foreignKeyCheck
      },
      stats: {
        active_devices: deviceCount,
        max_devices: parseInt(process.env.MAX_DEVICES) || 5,
        unsynced_items: unsyncedCount,
        unresolved_conflicts: conflictsCount
      },
      memory: {
        used: Math.round(process.memoryUsage().heapUsed / 1024 / 1024) + ' MB',
        total: Math.round(process.memoryUsage().heapTotal / 1024 / 1024) + ' MB'
      }
    });
  } catch (error) {
    res.status(500).json({
      status: 'error',
      error: error.message
    });
  }
});

// Metrics endpoint
router.get('/metrics', (req, res) => {
  try {
    const db = getDatabase();

    // Sync statistics
    const syncStats = db.prepare(`
      SELECT
        COUNT(*) as total_sessions,
        SUM(CASE WHEN status = 'completed' THEN 1 ELSE 0 END) as successful,
        SUM(CASE WHEN status = 'failed' THEN 1 ELSE 0 END) as failed,
        AVG(duration_ms) as avg_duration_ms
      FROM device_sync_sessions
      WHERE started_at > datetime('now', '-24 hours')
    `).get();

    // Active devices
    const activeDevices = db.prepare(`
      SELECT COUNT(*) as count FROM device_registrations WHERE is_active = 1
    `).get();

    res.json({
      sync: syncStats,
      devices: activeDevices,
      timestamp: new Date().toISOString()
    });
  } catch (error) {
    res.status(500).json({
      status: 'error',
      error: error.message
    });
  }
});

module.exports = router;
