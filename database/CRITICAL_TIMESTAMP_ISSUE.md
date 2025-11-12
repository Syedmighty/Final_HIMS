# ⚠️ CRITICAL: Timestamp Trigger Removal

## Issue Discovered: 2025-11-12

### **Problem**

The original v1.0_to_v1.0.1_migration.sql contained **broken SQL syntax** for timestamp triggers:

```sql
-- ❌ INVALID - SQLite doesn't support this syntax
CREATE TRIGGER trg_products_update_timestamp
BEFORE UPDATE ON products
FOR EACH ROW
BEGIN
  SELECT CASE
    WHEN NEW.last_modified = OLD.last_modified
    THEN datetime('now')
    ELSE NEW.last_modified
  END INTO NEW.last_modified;  -- ❌ SELECT...INTO not supported in SQLite triggers
END;
```

**Attempted fixes that also fail:**

```sql
-- ❌ ALSO INVALID - SET not supported in SQLite triggers
BEGIN
  SET NEW.last_modified = datetime('now');  -- ❌ SET not supported
END;
```

```sql
-- ❌ CAUSES INFINITE RECURSION
CREATE TRIGGER trg_products_update_timestamp
BEFORE UPDATE ON products
FOR EACH ROW
BEGIN
  UPDATE products SET last_modified = datetime('now') WHERE uuid = OLD.uuid;
  -- ❌ UPDATE inside BEFORE UPDATE = infinite loop!
END;
```

### **Root Cause**

SQLite has limited trigger capabilities:
- **No variable assignment**: Can't use `SET`, `SELECT...INTO`, or `:=`
- **Recursion risk**: UPDATE inside BEFORE UPDATE trigger causes infinite loop
- **No conditional column updates**: Can't selectively update only if unchanged

### **Impact**

**Severity:** HIGH
- Original migration script **WILL FAIL** with syntax error
- If manually created, triggers **WILL CAUSE DATABASE CORRUPTION** via infinite recursion
- `last_modified` timestamps **WILL NOT** auto-update without app-level handling

**Affected Tables:**
- products
- purchases
- issues
- stock_transfers
- wastage_returns
- All tables with `last_modified` column

### **Solution**

**Timestamp triggers REMOVED from migration script.**

Applications **MUST** handle `last_modified` updates explicitly:

#### Python (sqlite3)

```python
import sqlite3
from datetime import datetime

conn = sqlite3.connect('hims.db')
cursor = conn.cursor()

# ✅ CORRECT: Explicitly set last_modified
cursor.execute("""
  UPDATE products
  SET name = ?, last_modified = datetime('now')
  WHERE uuid = ?
""", (new_name, product_uuid))

conn.commit()
```

#### Node.js (better-sqlite3)

```javascript
const db = require('better-sqlite3')('hims.db');

// ✅ CORRECT: Include last_modified in UPDATE
const stmt = db.prepare(`
  UPDATE products
  SET name = ?, last_modified = datetime('now')
  WHERE uuid = ?
`);

stmt.run(newName, productUuid);
```

#### Flutter (Drift)

```dart
import 'package:drift/drift.dart';

// ✅ CORRECT: Use Drift's auto-update feature
await db.update(db.products).replace(
  product.copyWith(
    name: newName,
    lastModified: DateTime.now(),  // Explicitly set
  ),
);

// OR use Drift's beforeUpdate callback:
class AppDatabase extends _$AppDatabase {
  @override
  MigrationStrategy get migration => MigrationStrategy(
    beforeOpen: (details) async {
      // Enable triggers that DO work
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );

  // Override update to auto-set lastModified
  @override
  Future<int> update<T extends Table, D>(
    TableInfo<T, D> table,
    Insertable<D> entity, {
    Mode? mode,
  }) {
    if (entity is UpdateCompanion<D>) {
      // Add lastModified if table has it
      if (table.columnsByName.containsKey('last_modified')) {
        entity = entity.copyWith(
          lastModified: Value(DateTime.now()),
        ) as Insertable<D>;
      }
    }
    return super.update(table, entity, mode: mode);
  }
}
```

#### SQL Direct (for testing)

```sql
-- ✅ CORRECT: Always include last_modified in your UPDATE statements
UPDATE purchases
SET status = 'received',
    approved_by = 'user-uuid',
    last_modified = datetime('now')  -- ✅ Explicitly set
WHERE id = 123;
```

### **Why This Matters for LAN Sync**

The `last_modified` column is **CRITICAL** for sync conflict resolution:

```javascript
// Sync algorithm depends on last_modified
if (localRecord.last_modified > remoteRecord.last_modified) {
  // Local wins - push to server
  syncQueue.push({
    operation: 'update',
    payload: localRecord
  });
} else {
  // Remote wins - pull from server
  applyRemoteUpdate(remoteRecord);
}
```

**If last_modified is not updated:**
- Sync will think records haven't changed
- Conflicts won't be detected
- Data loss may occur during sync

### **Verification**

After deploying v1.0.1, verify your application updates timestamps:

```sql
-- Before update
SELECT uuid, name, last_modified FROM products WHERE uuid = 'test-uuid';
-- Result: test-uuid | Old Name | 2025-11-10 10:00:00

-- Run your app's update function
-- (e.g., updateProduct('test-uuid', 'New Name'))

-- After update
SELECT uuid, name, last_modified FROM products WHERE uuid = 'test-uuid';
-- Expected: test-uuid | New Name | 2025-11-12 14:30:00  ✅
-- BAD:      test-uuid | New Name | 2025-11-10 10:00:00  ❌ (timestamp not updated!)
```

### **Alternative Solutions Considered**

#### Option 1: Use AFTER UPDATE triggers (rejected)

```sql
-- Would work but has race conditions
CREATE TRIGGER trg_products_update_timestamp
AFTER UPDATE ON products
FOR EACH ROW
WHEN NEW.last_modified = OLD.last_modified
BEGIN
  UPDATE products SET last_modified = datetime('now') WHERE rowid = NEW.rowid;
END;
```

**Problems:**
- Race condition: Another UPDATE could happen between AFTER trigger and timestamp update
- Performance: Double UPDATE for every change
- Not atomic - sync timestamp might not match actual change

#### Option 2: Use generated columns (rejected)

```sql
ALTER TABLE products ADD COLUMN last_modified_auto TEXT
  GENERATED ALWAYS AS (datetime('now')) STORED;
```

**Problems:**
- SQLite's datetime('now') is evaluated at column creation, not on every update
- Would require schema migration (can't alter existing last_modified column)
- Not backwards compatible

#### Option 3: Application middleware (CHOSEN)

**Advantages:**
- ✅ Atomic with the actual data change
- ✅ Works reliably across all SQLite versions
- ✅ No performance penalty (single UPDATE)
- ✅ Application has full control
- ✅ Easy to add validation (e.g., prevent backdating)

**Disadvantages:**
- ⚠️ Developers must remember to include it
- ⚠️ Direct SQL access (e.g., sqlite3 CLI) won't auto-update
- ⚠️ Requires code changes in every app using the database

### **Migration Checklist**

For teams upgrading to v1.0.1:

- [ ] **Read this document** thoroughly
- [ ] **Audit all UPDATE statements** in your codebase
- [ ] **Add `last_modified = datetime('now')`** to every UPDATE
- [ ] **Test sync functionality** after changes
- [ ] **Update ORM/query builders** to auto-include last_modified
- [ ] **Add linting rule** to catch UPDATE without last_modified
- [ ] **Train developers** on the requirement
- [ ] **Update deployment docs** with this requirement

### **Rollout Strategy**

1. **Phase 1: Update application code**
   - Add last_modified to all UPDATE statements
   - Test thoroughly in staging
   - Verify sync still works

2. **Phase 2: Deploy updated apps**
   - Roll out to test devices first
   - Monitor for sync errors
   - Check last_modified values are updating

3. **Phase 3: Apply database migration**
   - Only after apps are updated
   - Run v1.0_to_v1.0.1_migration_CORRECTED.sql
   - Verify with verify_database.sql

4. **Phase 4: Monitor**
   - Watch for records with stale last_modified
   - Check sync_queue for unusual activity
   - Review conflict_logs for timestamp-related issues

### **Long-term Fix (Future v1.1+)**

Consider implementing a custom SQLite extension in C:

```c
// Custom last_modified updater (requires SQLite loadable extension)
void update_last_modified(sqlite3_context *ctx, int argc, sqlite3_value **argv) {
  // Called via: SELECT update_last_modified('products', 'uuid123')
  // Atomically updates last_modified for specified record
}
```

This would allow:
```sql
-- Future syntax (requires extension)
UPDATE products SET name = ?;
SELECT update_last_modified('products', last_insert_rowid());
```

But for v1.0.1, **application-layer handling is the pragmatic solution**.

---

## Summary

| Aspect | Status |
|--------|--------|
| **Timestamp triggers** | ❌ Removed (SQLite limitations) |
| **Application requirement** | ✅ MUST set last_modified on UPDATE |
| **Sync dependency** | ⚠️ CRITICAL - affects conflict resolution |
| **Migration impact** | ⚠️ Requires code changes before deploying |
| **Rollback** | ✅ Possible (restore from backup) |

**Bottom line:** Applications must explicitly manage `last_modified` timestamps. This is a **one-time migration task** but **ongoing development requirement**.

---

**Document Version:** 1.0
**Status:** CRITICAL - READ BEFORE DEPLOYING v1.0.1
**Last Updated:** 2025-11-12
