/**
 * Database Configuration and Connection
 * Uses better-sqlite3 for synchronous SQLite operations
 */

const Database = require('better-sqlite3');
const path = require('path');
const fs = require('fs');

let db = null;

/**
 * Initialize database connection
 * @param {string} dbPath - Path to SQLite database file
 * @returns {Database} SQLite database instance
 */
function initDatabase(dbPath = null) {
  if (db) {
    return db;
  }

  const finalPath = dbPath || process.env.DB_PATH || path.join(__dirname, '../../../database/hims.db');

  // Ensure database directory exists
  const dbDir = path.dirname(finalPath);
  if (!fs.existsSync(dbDir)) {
    fs.mkdirSync(dbDir, { recursive: true });
  }

  try {
    db = new Database(finalPath, {
      verbose: process.env.NODE_ENV === 'development' ? console.log : null
    });

    // Configure database
    db.pragma('journal_mode = WAL');
    db.pragma('foreign_keys = ON');
    db.pragma('synchronous = NORMAL');
    db.pragma('temp_store = MEMORY');
    db.pragma('cache_size = -64000'); // 64MB cache

    console.log(`✅ Database connected: ${finalPath}`);

    // Verify schema version
    const migration = db.prepare('SELECT version FROM schema_migrations ORDER BY applied_at DESC LIMIT 1').get();
    if (migration) {
      console.log(`📊 Schema version: ${migration.version}`);
    }

    return db;
  } catch (error) {
    console.error('❌ Database initialization failed:', error.message);
    throw error;
  }
}

/**
 * Get database instance
 * @returns {Database}
 */
function getDatabase() {
  if (!db) {
    return initDatabase();
  }
  return db;
}

/**
 * Close database connection
 */
function closeDatabase() {
  if (db) {
    db.close();
    db = null;
    console.log('🔒 Database connection closed');
  }
}

/**
 * Execute query with transaction support
 * @param {Function} callback - Function to execute within transaction
 * @returns {any} Result of callback
 */
function transaction(callback) {
  const database = getDatabase();
  const transactionFn = database.transaction(callback);
  return transactionFn();
}

/**
 * Run database integrity check
 * @returns {Object} Integrity check results
 */
function integrityCheck() {
  const database = getDatabase();
  const result = database.prepare('PRAGMA integrity_check').all();
  const foreignKeyCheck = database.prepare('PRAGMA foreign_key_check').all();

  return {
    integrityCheck: result,
    foreignKeyCheck: foreignKeyCheck,
    isHealthy: result.length === 1 && result[0].integrity_check === 'ok' && foreignKeyCheck.length === 0
  };
}

/**
 * Backup database
 * @param {string} backupPath - Path to backup location
 */
function backupDatabase(backupPath = null) {
  const database = getDatabase();
  const timestamp = new Date().toISOString().replace(/[:.]/g, '-');
  const backupDir = backupPath || process.env.DB_BACKUP_PATH || path.join(__dirname, '../../../database/backups');

  if (!fs.existsSync(backupDir)) {
    fs.mkdirSync(backupDir, { recursive: true });
  }

  const backupFile = path.join(backupDir, `hims_backup_${timestamp}.db`);
  database.backup(backupFile);

  console.log(`💾 Database backed up to: ${backupFile}`);
  return backupFile;
}

module.exports = {
  initDatabase,
  getDatabase,
  closeDatabase,
  transaction,
  integrityCheck,
  backupDatabase
};
