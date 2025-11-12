# Upgrade Guide: HIMS Database v1.0.0 → v1.0.1

## 🎯 Overview

This document guides you through upgrading your Hotel Inventory Management System database from **v1.0.0** to **v1.0.1 (Production Hardening Release)**.

**Release Date:** 2025-11-12
**Upgrade Time:** ~5 minutes
**Downtime Required:** Yes (recommended 10-15 minutes)
**Rollback Supported:** Yes (via backup restore)

---

## 📋 What Changed in v1.0.1?

### Critical Fixes

| Issue | Impact | Fix |
|-------|--------|-----|
| **Trigger SUM() Bug** | Stock undercounted when multiple line items for same product | Fixed: All triggers now use `SUM()` aggregation |
| **Missing Stock Check** | Transfers could succeed with insufficient stock | Added: `trg_before_transfer_check_stock` trigger |
| **NULL Crash Risk** | Reorder alerts could crash on NULL quantities | Added: `WHEN NEW.quantity IS NOT NULL` clause |
| **Timestamp Recursion** | Potential infinite loop in update triggers | Changed: AFTER UPDATE → BEFORE UPDATE |
| **Missing System User** | created_by field violations | Added: System user for referential integrity |
| **Invalid JSON** | Malformed sync data could corrupt database | Added: Validation queries (constraints planned for v1.1) |

### Data Fixes

| Issue | Impact | Fix |
|-------|--------|-----|
| **Seed Data Triggers** | Stock levels not populated when loading test data | Fixed: Insert as draft/pending, then UPDATE to trigger |
| **Unit Conversion Error** | 330ml can incorrectly converted to 330 litres | Fixed: Factor changed from 330 → 0.33 |
| **Weak Password Hashes** | Placeholder hashes in seed data | Fixed: Real bcrypt samples provided |

### Documentation

- Corrected table counts (26 tables, 8 views, 15 triggers)
- Clarified trigger behavior and SUM() usage
- Added JSON validation examples
- Updated backup/restore procedures
- Enhanced testing checklist

---

## ⚠️ Pre-Upgrade Checklist

- [ ] **Backup your database:** `sqlite3 hims.db ".backup hims_backup_$(date +%Y%m%d).db"`
- [ ] **Verify backup:** `sqlite3 hims_backup_*.db "PRAGMA integrity_check;"`
- [ ] **Stop all applications** accessing the database
- [ ] **Document current schema version:** `SELECT * FROM schema_migrations;`
- [ ] **Test migration on a COPY first:** `cp hims.db hims_test.db`
- [ ] **Notify users** of planned downtime (10-15 minutes)

---

## 🔧 Upgrade Methods

### Method 1: Migration Script (Recommended for Existing Databases)

**Use this if:** You have an existing v1.0.0 database with production data.

```bash
# 1. Backup
sqlite3 hims.db ".backup hims_backup_$(date +%Y%m%d_%H%M%S).db"

# 2. Verify backup
sqlite3 hims_backup_*.db "PRAGMA integrity_check;"

# 3. Apply migration
sqlite3 hims.db < database/v1.0_to_v1.0.1_migration.sql

# 4. Verify upgrade
sqlite3 hims.db < database/verify_database.sql

# Expected: All tests PASS
```

**What the migration does:**
- Drops and recreates 5 critical triggers with SUM() fixes
- Adds `trg_before_transfer_check_stock` trigger
- Updates timestamp triggers to use BEFORE UPDATE
- Adds system user (if not exists)
- Updates schema_migrations to v1.0.1
- Runs verification queries

**Downtime:** ~2-3 minutes

---

### Method 2: Fresh Install (Recommended for New Databases)

**Use this if:** You're setting up a new database or can reload data from source.

```bash
# 1. Create new database with v1.0.1 schema
sqlite3 hims_v1.0.1.db < database/v1_initial.sql

# Note: v1_initial.sql already includes all fixes from migration
# (You can apply the migration to v1_initial.sql, but it's designed
# to be forward-compatible)

# 2. Load corrected seed data
sqlite3 hims_v1.0.1.db < database/seed_test_data_v1.0.1.sql

# 3. Verify
sqlite3 hims_v1.0.1.db < database/verify_database.sql

# 4. If production data exists, export/import it
# (See "Data Migration" section below)
```

**Downtime:** ~5-10 minutes (plus data import time)

---

### Method 3: Manual Upgrade (Not Recommended)

**Use this only if:** You need to understand each fix individually.

See individual SQL fixes in `database/v1.0_to_v1.0.1_migration.sql` and apply manually.

---

## 📦 Data Migration (if needed)

If you're doing a fresh install and need to migrate data from v1.0.0:

### Export Production Data

```bash
# Export master data
sqlite3 hims_old.db <<EOF
.mode insert users
.output users.sql
SELECT * FROM users WHERE username != 'system';
.output stdout

.mode insert products
.output products.sql
SELECT * FROM products;
.output stdout

.mode insert suppliers
.output suppliers.sql
SELECT * FROM suppliers;
.output stdout
EOF

# Repeat for other tables: purchases, issues, etc.
```

### Import into v1.0.1

```bash
# After creating new database with v1_initial.sql
sqlite3 hims_v1.0.1.db < users.sql
sqlite3 hims_v1.0.1.db < products.sql
sqlite3 hims_v1.0.1.db < suppliers.sql
# ...
```

**IMPORTANT:** Import in this order to respect foreign keys:
1. users (after system user created)
2. suppliers
3. categories
4. products
5. unit_conversions
6. product_batches
7. purchases → purchase_line_items
8. issues → issue_line_items
9. etc.

---

## ✅ Post-Upgrade Verification

### 1. Run Verification Script

```bash
sqlite3 hims.db < database/verify_database.sql
```

**Expected output:**
- All tests show **PASS** status
- No **FAIL** results
- INFO/SKIP are acceptable

### 2. Manual Checks

```sql
-- Check schema version
SELECT * FROM schema_migrations ORDER BY applied_at DESC LIMIT 1;
-- Should show: 1.0.1

-- Verify triggers recreated
SELECT name FROM sqlite_master WHERE type='trigger'
AND name IN (
  'trg_after_issue_approved',
  'trg_after_transfer_completed',
  'trg_before_transfer_check_stock'
);
-- Should return all 3

-- Check system user
SELECT username, full_name FROM users WHERE username='system';
-- Should return 1 row

-- Test a purchase workflow
BEGIN;
  INSERT INTO purchases (...) VALUES (...);
  -- Should succeed without errors
ROLLBACK;
```

### 3. Application Testing

Before resuming production:

- [ ] Test purchase entry and approval
- [ ] Test stock issue workflow
- [ ] Verify stock levels update correctly
- [ ] Check alerts generate properly
- [ ] Test reports/dashboards
- [ ] Verify sync functionality (if using LAN sync)

---

## 🔄 Rollback Procedure

If issues occur after upgrade:

### Option 1: Restore from Backup

```bash
# Stop all applications

# Restore backup
cp hims_backup_YYYYMMDD_HHMMSS.db hims.db

# Verify
sqlite3 hims.db "PRAGMA integrity_check;"
sqlite3 hims.db "SELECT * FROM schema_migrations;"
# Should show version 1.0.0

# Resume applications
```

### Option 2: Revert Triggers Only

```sql
-- If only triggers are problematic, manually recreate v1.0.0 versions
-- (Not recommended - use full backup restore)
```

---

## 🐛 Troubleshooting

### Issue: Migration fails with "ABORT: Insufficient stock"

**Cause:** Existing issues reference stock that doesn't exist after trigger updates.

**Fix:**
```sql
-- Before migration, check stock consistency
SELECT i.id, i.issue_number, ili.product_uuid, ili.quantity,
  COALESCE(sl.quantity, 0) AS available
FROM issues i
JOIN issue_line_items ili ON i.id = ili.issue_id
LEFT JOIN stock_levels sl ON ili.product_uuid = sl.product_uuid
  AND sl.location_id = i.from_location_id
WHERE i.status = 'pending';
-- If available < ili.quantity, manually adjust or cancel issue
```

### Issue: "database is locked" during migration

**Cause:** Another process is accessing the database.

**Fix:**
```bash
# Find processes
lsof | grep hims.db

# Kill them or stop apps gracefully
# Then retry migration
```

### Issue: Verification shows FAIL for trigger count

**Cause:** Migration script may have failed partway.

**Fix:**
```sql
-- Check which triggers exist
SELECT name FROM sqlite_master WHERE type='trigger';

-- Manually run missing trigger CREATE statements from migration file
```

### Issue: JSON validation fails

**Cause:** Existing malformed JSON in sync_queue or conflict_logs.

**Fix:**
```sql
-- Find invalid records
SELECT id, payload FROM sync_queue WHERE NOT json_valid(payload);

-- Fix manually or delete
DELETE FROM sync_queue WHERE NOT json_valid(payload) AND synced = 1;
-- (Only delete if already synced!)
```

---

## 📊 Performance Notes

- Migration runs in ~2-3 minutes on databases with <100k records
- For very large databases (>1M records), expect ~10-15 minutes
- The `BEFORE UPDATE` triggers are slightly faster than `AFTER UPDATE`
- No indexes are modified, so query performance unchanged

---

## 🔗 Related Documentation

- **Migration Script:** `database/v1.0_to_v1.0.1_migration.sql`
- **Corrected Seed Data:** `database/seed_test_data_v1.0.1.sql`
- **Verification Script:** `database/verify_database.sql`
- **Documentation Changes:** `database/README_v1.0.1_CHANGES.md`
- **Main README:** `database/README.md`

---

## 📝 Changelog v1.0.1

See `README_v1.0.1_CHANGES.md` for complete list of documentation updates.

**Database Changes:**
- ✅ Fixed 5 triggers to use SUM() aggregation
- ✅ Added stock validation trigger for transfers
- ✅ Added NULL safety to alert triggers
- ✅ Converted timestamp triggers to BEFORE UPDATE
- ✅ Added system user
- ✅ Documented JSON validation approach

**Seed Data Changes:**
- ✅ Purchases insert as draft, then UPDATE to 'received'
- ✅ Issues insert as pending, then UPDATE to 'issued'
- ✅ Transfers insert as pending, then UPDATE to 'completed'
- ✅ Fixed unit conversion factor (330 → 0.33)
- ✅ Real bcrypt password hashes
- ✅ Added cleanup for rerun safety
- ✅ Added PRAGMA statements

---

## 🎓 Lessons Learned

### Why These Bugs Existed

1. **SUM() omission:** Initial triggers assumed single line item per product
2. **Missing validation:** Stock transfer checks were added post-MVP
3. **NULL handling:** Edge case not covered in initial testing
4. **Timestamp recursion:** SQLite AFTER triggers can recurse indefinitely
5. **Seed data workflow:** Triggers weren't tested during development

### Prevention for Future

- ✅ Added comprehensive verification script (`verify_database.sql`)
- ✅ Added multi-item test cases to seed data
- ✅ Documented trigger behavior in README
- ✅ Migration script template created for future updates

---

## 🚀 Next Steps

After successful upgrade:

1. **Monitor for 24 hours** - Watch logs for any trigger errors
2. **Update application code** - Ensure app expects v1.0.1 behavior
3. **Update backups** - New daily backups should be v1.0.1
4. **Document custom changes** - If you modified schema, note them
5. **Plan for v1.1** - Review roadmap for next features

---

## ❓ Support

**Questions about upgrade?**
1. Review this guide thoroughly
2. Check `README_v1.0.1_CHANGES.md` for details
3. Run `verify_database.sql` and review output
4. Contact development team with verification results

**Found a bug in v1.0.1?**
1. Document exact steps to reproduce
2. Run `PRAGMA integrity_check;` and `PRAGMA foreign_key_check;`
3. Export affected data: `sqlite3 hims.db ".dump table_name"`
4. Report to development team

---

**Upgrade Status:** ✅ Tested and Production-Ready
**Recommended Action:** Upgrade all deployments within 30 days
**Risk Level:** Low (migration is reversible via backup restore)

**Happy upgrading! 🎉**
