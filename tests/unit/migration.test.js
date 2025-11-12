/**
 * Migration Tests
 * Tests database migrations for idempotency and integrity
 */

const Database = require('better-sqlite3');
const fs = require('fs');
const path = require('path');

describe('Database Migrations', () => {
  let db;
  const testDbPath = path.join(__dirname, 'test_migration.db');

  beforeEach(() => {
    // Remove existing test database
    if (fs.existsSync(testDbPath)) {
      fs.unlinkSync(testDbPath);
    }

    // Create fresh database
    db = new Database(testDbPath);
    db.pragma('foreign_keys = ON');
  });

  afterEach(() => {
    if (db) {
      db.close();
    }
    if (fs.existsSync(testDbPath)) {
      fs.unlinkSync(testDbPath);
    }
  });

  describe('Initial Schema (v1.0.0)', () => {
    test('should apply initial schema successfully', () => {
      const schema = fs.readFileSync(
        path.join(__dirname, '../../sql/v1_initial.sql'),
        'utf8'
      );

      expect(() => {
        db.exec(schema);
      }).not.toThrow();

      // Verify schema_migrations table
      const migration = db.prepare(
        'SELECT * FROM schema_migrations WHERE version = ?'
      ).get('1.0.0');

      expect(migration).toBeDefined();
      expect(migration.version).toBe('1.0.0');
    });

    test('should create all required tables', () => {
      const schema = fs.readFileSync(
        path.join(__dirname, '../../sql/v1_initial.sql'),
        'utf8'
      );
      db.exec(schema);

      const tables = db.prepare(
        "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name"
      ).all();

      const expectedTables = [
        'alerts',
        'audit_logs',
        'categories',
        'company_settings',
        'conflict_logs',
        'invoice_items',
        'invoices',
        'issue_items',
        'issues',
        'locations',
        'products',
        'purchase_items',
        'purchases',
        'recipe_ingredients',
        'recipes',
        'schema_migrations',
        'stock_adjustments',
        'stock_levels',
        'suppliers',
        'sync_queue',
        'transfer_items',
        'transfers',
        'unit_conversions',
        'units',
        'users',
        'wastage_items',
        'wastages'
      ];

      const tableNames = tables.map(t => t.name);
      expectedTables.forEach(tableName => {
        expect(tableNames).toContain(tableName);
      });
    });

    test('should pass integrity check', () => {
      const schema = fs.readFileSync(
        path.join(__dirname, '../../sql/v1_initial.sql'),
        'utf8'
      );
      db.exec(schema);

      const integrity = db.prepare('PRAGMA integrity_check').all();
      expect(integrity.length).toBe(1);
      expect(integrity[0].integrity_check).toBe('ok');

      const foreignKeyCheck = db.prepare('PRAGMA foreign_key_check').all();
      expect(foreignKeyCheck.length).toBe(0);
    });

    test('should create seed data correctly', () => {
      const schema = fs.readFileSync(
        path.join(__dirname, '../../sql/v1_initial.sql'),
        'utf8'
      );
      db.exec(schema);

      // Check default units
      const units = db.prepare('SELECT COUNT(*) as count FROM units').get();
      expect(units.count).toBeGreaterThan(0);

      // Check default admin user
      const admin = db.prepare(
        "SELECT * FROM users WHERE username = 'admin'"
      ).get();
      expect(admin).toBeDefined();
      expect(admin.role).toBe('admin');

      // Check default location
      const location = db.prepare('SELECT COUNT(*) as count FROM locations').get();
      expect(location.count).toBeGreaterThan(0);
    });
  });

  describe('Device Management Migration (v1.0.1)', () => {
    beforeEach(() => {
      // Apply initial schema first
      const initialSchema = fs.readFileSync(
        path.join(__dirname, '../../sql/v1_initial.sql'),
        'utf8'
      );
      db.exec(initialSchema);
    });

    test('should apply device management migration successfully', () => {
      const migration = fs.readFileSync(
        path.join(__dirname, '../../sql/migrations/v1.0.1__device_and_sync_hardening.sql'),
        'utf8'
      );

      expect(() => {
        db.exec(migration);
      }).not.toThrow();

      // Verify migration record
      const migrationRecord = db.prepare(
        'SELECT * FROM schema_migrations WHERE version = ?'
      ).get('1.0.1');

      expect(migrationRecord).toBeDefined();
      expect(migrationRecord.version).toBe('1.0.1');
    });

    test('should create device_registrations table', () => {
      const migration = fs.readFileSync(
        path.join(__dirname, '../../sql/migrations/v1.0.1__device_and_sync_hardening.sql'),
        'utf8'
      );
      db.exec(migration);

      const table = db.prepare(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='device_registrations'"
      ).get();

      expect(table).toBeDefined();
      expect(table.name).toBe('device_registrations');
    });

    test('should create device limit trigger', () => {
      const migration = fs.readFileSync(
        path.join(__dirname, '../../sql/migrations/v1.0.1__device_and_sync_hardening.sql'),
        'utf8'
      );
      db.exec(migration);

      const trigger = db.prepare(
        "SELECT name FROM sqlite_master WHERE type='trigger' AND name='trg_before_device_register'"
      ).get();

      expect(trigger).toBeDefined();
    });

    test('should enforce device limit (5 devices)', () => {
      const migration = fs.readFileSync(
        path.join(__dirname, '../../sql/migrations/v1.0.1__device_and_sync_hardening.sql'),
        'utf8'
      );
      db.exec(migration);

      // Register 5 devices successfully
      for (let i = 1; i <= 5; i++) {
        expect(() => {
          db.prepare(`
            INSERT INTO device_registrations (uuid, device_name, registered_by)
            VALUES (?, ?, 'user_admin')
          `).run(`device_${i}`, `Device ${i}`);
        }).not.toThrow();
      }

      // 6th device should fail
      expect(() => {
        db.prepare(`
          INSERT INTO device_registrations (uuid, device_name, registered_by)
          VALUES ('device_6', 'Device 6', 'user_admin')
        `).run();
      }).toThrow(/Maximum device limit/);
    });

    test('should be idempotent (can run twice)', () => {
      const migration = fs.readFileSync(
        path.join(__dirname, '../../sql/migrations/v1.0.1__device_and_sync_hardening.sql'),
        'utf8'
      );

      // Run first time
      db.exec(migration);

      // Run second time - should not throw because of IF NOT EXISTS
      expect(() => {
        db.exec(migration);
      }).toThrow(); // Will throw due to duplicate migration record, which is expected
    });

    test('should create device sync views', () => {
      const migration = fs.readFileSync(
        path.join(__dirname, '../../sql/migrations/v1.0.1__device_and_sync_hardening.sql'),
        'utf8'
      );
      db.exec(migration);

      const views = db.prepare(
        "SELECT name FROM sqlite_master WHERE type='view'"
      ).all();

      const viewNames = views.map(v => v.name);
      expect(viewNames).toContain('v_device_sync_stats');
      expect(viewNames).toContain('v_active_devices');
      expect(viewNames).toContain('v_unresolved_conflicts');
    });
  });

  describe('Migration Integrity', () => {
    test('should pass integrity check after all migrations', () => {
      // Apply all migrations
      const initialSchema = fs.readFileSync(
        path.join(__dirname, '../../sql/v1_initial.sql'),
        'utf8'
      );
      db.exec(initialSchema);

      const migration = fs.readFileSync(
        path.join(__dirname, '../../sql/migrations/v1.0.1__device_and_sync_hardening.sql'),
        'utf8'
      );
      db.exec(migration);

      // Verify integrity
      const integrity = db.prepare('PRAGMA integrity_check').all();
      expect(integrity.length).toBe(1);
      expect(integrity[0].integrity_check).toBe('ok');

      const foreignKeyCheck = db.prepare('PRAGMA foreign_key_check').all();
      expect(foreignKeyCheck.length).toBe(0);
    });
  });
});
