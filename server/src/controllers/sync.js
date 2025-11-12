/**
 * Sync Controller
 * Handles push/pull operations, conflict resolution, and sync session management
 * Implements last-write-wins with conflict logging
 */

const { getDatabase, transaction } = require('../config/database');
const logger = require('../config/logger');
const { validateSyncPayload } = require('../hooks/validatePayload');
const { v4: uuidv4 } = require('uuid');

const SYNC_BATCH_SIZE = parseInt(process.env.SYNC_BATCH_SIZE) || 200;

// Tables allowed for sync operations
const ALLOWED_TABLES = [
  'products', 'categories', 'units', 'suppliers', 'locations',
  'purchases', 'purchase_items', 'issues', 'issue_items',
  'transfers', 'transfer_items', 'wastages', 'wastage_items',
  'recipes', 'recipe_ingredients', 'invoices', 'invoice_items',
  'stock_levels', 'stock_adjustments'
];

/**
 * Push data from device to server
 * POST /sync/push
 * Accepts batch of changes from client
 */
async function pushData(req, res) {
  const startTime = Date.now();
  const { device_uuid, items } = req.body;

  if (!device_uuid || !items || !Array.isArray(items)) {
    return res.status(400).json({
      success: false,
      error: 'Missing device_uuid or items array'
    });
  }

  if (items.length > SYNC_BATCH_SIZE) {
    return res.status(400).json({
      success: false,
      error: `Batch size exceeds maximum (${SYNC_BATCH_SIZE}). Split into smaller batches.`
    });
  }

  const db = getDatabase();
  const results = [];
  let syncSessionUuid = null;

  try {
    // Create sync session
    syncSessionUuid = uuidv4();
    db.prepare(`
      INSERT INTO device_sync_sessions (uuid, device_uuid, sync_type, started_at, status)
      VALUES (?, ?, 'push', datetime('now'), 'in_progress')
    `).run(syncSessionUuid, device_uuid);

    let pushed = 0;
    let conflicts = 0;
    let errors = 0;

    // Process each item
    for (const item of items) {
      try {
        const { table_name, operation, record_uuid, payload, last_modified } = item;

        // Validate table
        if (!ALLOWED_TABLES.includes(table_name)) {
          results.push({
            record_uuid,
            success: false,
            error: `Table '${table_name}' not allowed for sync`
          });
          errors++;
          continue;
        }

        // Validate payload
        const validation = validateSyncPayload(table_name, payload);
        if (!validation.valid) {
          results.push({
            record_uuid,
            success: false,
            error: validation.error
          });
          errors++;
          continue;
        }

        // Validate last_modified
        if (!last_modified) {
          results.push({
            record_uuid,
            success: false,
            error: 'Missing last_modified field'
          });
          errors++;
          continue;
        }

        // Check for existing record
        const existingRecord = db.prepare(
          `SELECT last_modified FROM ${table_name} WHERE uuid = ?`
        ).get(record_uuid);

        // Conflict detection: compare timestamps
        if (existingRecord && existingRecord.last_modified) {
          const existingTime = new Date(existingRecord.last_modified).getTime();
          const incomingTime = new Date(last_modified).getTime();

          if (existingTime > incomingTime) {
            // Server version is newer - conflict
            logger.warn('Sync conflict detected', {
              table_name,
              record_uuid,
              server_time: existingRecord.last_modified,
              client_time: last_modified
            });

            // Log conflict
            db.prepare(`
              INSERT INTO conflict_logs (
                table_name, record_uuid, local_payload, remote_payload,
                local_last_modified, remote_last_modified, local_device_uuid,
                remote_device_uuid, resolution_strategy, resolved
              ) VALUES (?, ?, ?, ?, ?, ?, NULL, ?, 'remote_wins', 0)
            `).run(
              table_name,
              record_uuid,
              JSON.stringify(existingRecord),
              JSON.stringify(payload),
              existingRecord.last_modified,
              last_modified,
              device_uuid
            );

            results.push({
              record_uuid,
              success: false,
              conflict: true,
              message: 'Conflict detected: server version is newer',
              server_last_modified: existingRecord.last_modified
            });
            conflicts++;
            continue;
          }
        }

        // Apply changes based on operation
        const applyResult = transaction(() => {
          if (operation === 'insert' || operation === 'update') {
            // Upsert record
            const columns = Object.keys(payload).join(', ');
            const placeholders = Object.keys(payload).map(() => '?').join(', ');
            const updateSet = Object.keys(payload)
              .map(col => `${col} = excluded.${col}`)
              .join(', ');

            const stmt = db.prepare(`
              INSERT INTO ${table_name} (${columns})
              VALUES (${placeholders})
              ON CONFLICT(uuid) DO UPDATE SET ${updateSet}
            `);

            stmt.run(...Object.values(payload));

            // Audit log
            db.prepare(`
              INSERT INTO audit_logs (
                table_name, record_uuid, operation, new_values, device_uuid
              ) VALUES (?, ?, ?, ?, ?)
            `).run(table_name, record_uuid, operation, JSON.stringify(payload), device_uuid);

            return { success: true };
          } else if (operation === 'delete') {
            // Soft delete (if deleted_at field exists)
            const hasDeletedAt = db.prepare(
              `SELECT COUNT(*) as count FROM pragma_table_info('${table_name}') WHERE name = 'deleted_at'`
            ).get();

            if (hasDeletedAt.count > 0) {
              db.prepare(`
                UPDATE ${table_name}
                SET deleted_at = datetime('now'), deleted_by = ?
                WHERE uuid = ?
              `).run(payload.deleted_by || 'system', record_uuid);
            } else {
              // Hard delete
              db.prepare(`DELETE FROM ${table_name} WHERE uuid = ?`).run(record_uuid);
            }

            // Audit log
            db.prepare(`
              INSERT INTO audit_logs (
                table_name, record_uuid, operation, old_values, device_uuid
              ) VALUES (?, ?, 'delete', ?, ?)
            `).run(table_name, record_uuid, JSON.stringify(payload), device_uuid);

            return { success: true };
          }

          throw new Error(`Unknown operation: ${operation}`);
        });

        results.push({
          record_uuid,
          success: true,
          operation,
          table_name
        });
        pushed++;
      } catch (itemError) {
        logger.error('Item sync failed', {
          record_uuid: item.record_uuid,
          error: itemError.message
        });
        results.push({
          record_uuid: item.record_uuid,
          success: false,
          error: itemError.message
        });
        errors++;
      }
    }

    // Update sync session
    const duration = Date.now() - startTime;
    db.prepare(`
      UPDATE device_sync_sessions
      SET
        completed_at = datetime('now'),
        status = ?,
        records_pushed = ?,
        conflicts_detected = ?,
        errors_count = ?,
        duration_ms = ?
      WHERE uuid = ?
    `).run(
      errors > 0 ? 'partial' : 'completed',
      pushed,
      conflicts,
      errors,
      duration,
      syncSessionUuid
    );

    logger.info('Push sync completed', {
      device_uuid,
      pushed,
      conflicts,
      errors,
      duration_ms: duration
    });

    res.json({
      success: true,
      sync_session_uuid: syncSessionUuid,
      results,
      summary: {
        total: items.length,
        pushed,
        conflicts,
        errors,
        duration_ms: duration
      }
    });
  } catch (error) {
    logger.error('Push sync failed', {
      device_uuid,
      error: error.message,
      stack: error.stack
    });

    // Mark sync session as failed
    if (syncSessionUuid) {
      db.prepare(`
        UPDATE device_sync_sessions
        SET
          completed_at = datetime('now'),
          status = 'failed',
          error_details = ?
        WHERE uuid = ?
      `).run(JSON.stringify({ error: error.message }), syncSessionUuid);
    }

    res.status(500).json({
      success: false,
      error: 'Push sync failed',
      details: process.env.NODE_ENV === 'development' ? error.message : undefined
    });
  }
}

/**
 * Pull data from server to device
 * GET /sync/pull
 * Returns changes since last sync timestamp
 */
async function pullData(req, res) {
  const startTime = Date.now();
  const { device_uuid, since, tables, limit } = req.query;

  if (!device_uuid) {
    return res.status(400).json({
      success: false,
      error: 'Missing device_uuid'
    });
  }

  const db = getDatabase();
  let syncSessionUuid = null;

  try {
    // Create sync session
    syncSessionUuid = uuidv4();
    db.prepare(`
      INSERT INTO device_sync_sessions (uuid, device_uuid, sync_type, started_at, status)
      VALUES (?, ?, 'pull', datetime('now'), 'in_progress')
    `).run(syncSessionUuid, device_uuid);

    const sinceTimestamp = since || '1970-01-01 00:00:00';
    const requestedTables = tables ? tables.split(',') : ALLOWED_TABLES;
    const recordLimit = Math.min(parseInt(limit) || SYNC_BATCH_SIZE, SYNC_BATCH_SIZE);

    const changes = {};
    let totalRecords = 0;

    // Fetch changes for each table
    for (const tableName of requestedTables) {
      if (!ALLOWED_TABLES.includes(tableName)) {
        logger.warn('Pull sync: table not allowed', { table: tableName });
        continue;
      }

      // Check if table has last_modified column
      const hasLastModified = db.prepare(
        `SELECT COUNT(*) as count FROM pragma_table_info('${tableName}') WHERE name = 'last_modified'`
      ).get();

      if (hasLastModified.count === 0) {
        continue;
      }

      const records = db.prepare(`
        SELECT * FROM ${tableName}
        WHERE last_modified > ?
        AND (deleted_at IS NULL OR deleted_at > ?)
        ORDER BY last_modified ASC
        LIMIT ?
      `).all(sinceTimestamp, sinceTimestamp, recordLimit);

      if (records.length > 0) {
        changes[tableName] = records;
        totalRecords += records.length;
      }
    }

    // Update sync session
    const duration = Date.now() - startTime;
    db.prepare(`
      UPDATE device_sync_sessions
      SET
        completed_at = datetime('now'),
        status = 'completed',
        records_pulled = ?,
        duration_ms = ?
      WHERE uuid = ?
    `).run(totalRecords, duration, syncSessionUuid);

    logger.info('Pull sync completed', {
      device_uuid,
      since: sinceTimestamp,
      pulled: totalRecords,
      duration_ms: duration
    });

    res.json({
      success: true,
      sync_session_uuid: syncSessionUuid,
      changes,
      summary: {
        tables_synced: Object.keys(changes).length,
        total_records: totalRecords,
        duration_ms: duration,
        timestamp: new Date().toISOString()
      }
    });
  } catch (error) {
    logger.error('Pull sync failed', {
      device_uuid,
      error: error.message,
      stack: error.stack
    });

    // Mark sync session as failed
    if (syncSessionUuid) {
      db.prepare(`
        UPDATE device_sync_sessions
        SET
          completed_at = datetime('now'),
          status = 'failed',
          error_details = ?
        WHERE uuid = ?
      `).run(JSON.stringify({ error: error.message }), syncSessionUuid);
    }

    res.status(500).json({
      success: false,
      error: 'Pull sync failed',
      details: process.env.NODE_ENV === 'development' ? error.message : undefined
    });
  }
}

/**
 * Get unresolved conflicts
 * GET /sync/conflicts
 */
async function getConflicts(req, res) {
  try {
    const { device_uuid, resolved } = req.query;
    const db = getDatabase();

    let query = 'SELECT * FROM v_unresolved_conflicts';
    const params = [];

    if (resolved === 'false') {
      // Already filtered by view
    } else if (resolved === 'true') {
      query = `
        SELECT
          cl.*,
          ld.device_name AS local_device,
          rd.device_name AS remote_device
        FROM conflict_logs cl
        LEFT JOIN device_registrations ld ON ld.uuid = cl.local_device_uuid
        LEFT JOIN device_registrations rd ON rd.uuid = cl.remote_device_uuid
        WHERE cl.resolved = 1
        ORDER BY cl.resolved_at DESC
      `;
    }

    const conflicts = db.prepare(query).all(...params);

    res.json({
      success: true,
      conflicts,
      count: conflicts.length
    });
  } catch (error) {
    logger.error('Failed to fetch conflicts', { error: error.message });
    res.status(500).json({
      success: false,
      error: 'Failed to fetch conflicts'
    });
  }
}

/**
 * Resolve a conflict manually
 * POST /sync/conflicts/:conflict_id/resolve
 */
async function resolveConflict(req, res) {
  try {
    const { conflict_id } = req.params;
    const { resolution_strategy, user_uuid, notes } = req.body;

    if (!['local_wins', 'remote_wins', 'manual'].includes(resolution_strategy)) {
      return res.status(400).json({
        success: false,
        error: 'Invalid resolution_strategy. Must be: local_wins, remote_wins, or manual'
      });
    }

    const db = getDatabase();

    const result = transaction(() => {
      // Get conflict details
      const conflict = db.prepare('SELECT * FROM conflict_logs WHERE id = ?').get(conflict_id);

      if (!conflict) {
        throw new Error('Conflict not found');
      }

      if (conflict.resolved === 1) {
        throw new Error('Conflict already resolved');
      }

      // Mark as resolved
      db.prepare(`
        UPDATE conflict_logs
        SET
          resolved = 1,
          resolved_at = datetime('now'),
          resolved_by = ?,
          resolution_strategy = ?,
          notes = ?
        WHERE id = ?
      `).run(user_uuid, resolution_strategy, notes || '', conflict_id);

      // Apply resolution if not manual
      if (resolution_strategy !== 'manual') {
        const payload = resolution_strategy === 'local_wins'
          ? JSON.parse(conflict.local_payload)
          : JSON.parse(conflict.remote_payload);

        // Upsert the chosen version
        const columns = Object.keys(payload).join(', ');
        const placeholders = Object.keys(payload).map(() => '?').join(', ');
        const updateSet = Object.keys(payload)
          .map(col => `${col} = excluded.${col}`)
          .join(', ');

        db.prepare(`
          INSERT INTO ${conflict.table_name} (${columns})
          VALUES (${placeholders})
          ON CONFLICT(uuid) DO UPDATE SET ${updateSet}
        `).run(...Object.values(payload));
      }

      return { success: true };
    });

    logger.info('Conflict resolved', {
      conflict_id,
      resolution_strategy,
      user_uuid
    });

    res.json({
      success: true,
      message: 'Conflict resolved successfully',
      conflict_id,
      resolution_strategy
    });
  } catch (error) {
    logger.error('Conflict resolution failed', { error: error.message });
    res.status(500).json({
      success: false,
      error: error.message
    });
  }
}

module.exports = {
  pushData,
  pullData,
  getConflicts,
  resolveConflict
};
