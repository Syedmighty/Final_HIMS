# 🏨 Final HIMS - Hotel Inventory Management System

> **Complete offline-first inventory management solution for hotels and restaurants**

[![Version](https://img.shields.io/badge/version-1.0.0-blue.svg)](https://github.com/Syedmighty/Final_HIMS)
[![Database](https://img.shields.io/badge/database-SQLite-green.svg)](./database/)
[![License](https://img.shields.io/badge/license-Proprietary-red.svg)]()

---

## 📖 Overview

Final HIMS is a comprehensive inventory management system designed specifically for hotel and restaurant operations. Built with an **offline-first architecture**, it enables seamless stock tracking, purchase management, recipe costing, and reporting without requiring constant internet connectivity.

### Key Capabilities

- ✅ **Daily Purchase Recording** - Track purchases from multiple suppliers with GST support
- ✅ **Stock Issuance to Kitchens** - Control stock distribution across departments
- ✅ **Wastage & Return Tracking** - Monitor spoilage, damage, and supplier returns
- ✅ **Recipe Costing** - Calculate exact cost and profit margin per dish
- ✅ **Batch & Expiry Management** - Track batches with automatic expiry alerts
- ✅ **Multi-Location Support** - Manage multiple stores, kitchens, and bars
- ✅ **Automated Stock Updates** - Real-time stock levels via database triggers
- ✅ **Comprehensive Reporting** - Daily, weekly, monthly reports with analytics
- ✅ **Role-Based Access Control** - Secure access for admins, managers, chefs, accountants
- ✅ **LAN Synchronization** - Sync data across devices within hotel network

---

## 🏗️ Architecture

### Technology Stack

| Component | Technology | Purpose |
|-----------|-----------|---------|
| **Database** | SQLite 3.35+ | Offline-first local storage |
| **Mobile App** | Flutter (planned) | Cross-platform UI for Android/iOS/Windows |
| **Backend Sync** | Node.js (planned) | LAN-based master server for synchronization |
| **ORM** | Drift (planned) | Type-safe database access in Flutter |

### System Design

```
┌─────────────────────────────────────────────────────────────┐
│                    Master PC (Central Server)                │
│  ┌─────────────────────────────────────────────────────┐    │
│  │  Node.js Sync Server + Master SQLite Database       │    │
│  └─────────────────────────────────────────────────────┘    │
└──────────────────────┬──────────────────────────────────────┘
                       │ LAN Network
         ┌─────────────┼─────────────┬─────────────┐
         │             │             │             │
    ┌────▼───┐   ┌────▼───┐   ┌────▼───┐   ┌────▼───┐
    │Mobile 1│   │Mobile 2│   │Mobile 3│   │Tablet  │
    │Store   │   │Kitchen │   │Bar     │   │Manager │
    │Manager │   │Chef    │   │Staff   │   │Reports │
    └────────┘   └────────┘   └────────┘   └────────┘
     (SQLite)     (SQLite)     (SQLite)     (SQLite)
```

**How it works:**
1. Each device runs a local SQLite database (instant, offline)
2. All changes logged to `sync_queue` table
3. Periodic sync with master PC via LAN (Node.js REST API)
4. Conflict resolution via timestamps and conflict logs
5. No internet required - fully operational offline

---

## 📂 Project Structure

```
Final_HIMS/
├── database/                    # ✅ COMPLETED
│   ├── v1_initial.sql          # Complete database schema with triggers
│   ├── seed_test_data.sql      # Sample data for testing
│   ├── README.md               # Comprehensive database documentation
│   └── migrations/             # Future schema updates
│
├── backend/                     # 🚧 PLANNED
│   ├── src/
│   │   ├── server.js           # Express.js server
│   │   ├── sync/               # Sync controller
│   │   ├── api/                # REST API routes
│   │   └── utils/              # Helpers
│   └── package.json
│
├── mobile/                      # 🚧 PLANNED
│   ├── lib/
│   │   ├── database/           # Drift ORM models
│   │   ├── screens/            # UI screens
│   │   ├── services/           # Business logic
│   │   └── widgets/            # Reusable components
│   └── pubspec.yaml
│
├── docs/                        # 📝 IN PROGRESS
│   ├── PRD.md                  # Product Requirements Document
│   ├── API.md                  # API documentation
│   └── USER_GUIDE.md           # End-user manual
│
└── README.md                    # This file
```

---

## 🚀 Quick Start

### 1. Database Setup

The database is the foundation - start here:

```bash
# Navigate to database directory
cd database/

# Create the database
sqlite3 hims.db < v1_initial.sql

# (Optional) Load test data
sqlite3 hims.db < seed_test_data.sql

# Verify installation
sqlite3 hims.db "SELECT * FROM schema_migrations;"
```

**Expected output:**
```
1|1.0.0|Initial schema with all core tables|SHA256_PLACEHOLDER|2025-11-11...
```

For detailed database documentation, see **[database/README.md](./database/README.md)**.

### 2. Explore the Schema

```bash
# List all tables
sqlite3 hims.db ".tables"

# View current stock
sqlite3 hims.db "SELECT * FROM vw_current_stock;"

# Check active alerts
sqlite3 hims.db "SELECT * FROM vw_active_alerts;"
```

---

## 📊 Database Features

### Highlights

| Feature | Description | Tables Involved |
|---------|-------------|-----------------|
| **Master Data** | Products, suppliers, locations, users | `products`, `suppliers`, `locations`, `users`, `categories`, `units` |
| **Transactions** | Purchases, issues, wastage, transfers | `purchases`, `issues`, `wastage_returns`, `stock_transfers` |
| **Stock Management** | Real-time stock levels with triggers | `stock_levels`, `stock_adjustments` |
| **Batch Tracking** | Expiry dates, lot numbers, FIFO | `product_batches` |
| **Unit Conversions** | Flexible per-product conversions | `unit_conversions` (e.g., "1 pc = 1.5 kg") |
| **Alerts** | Low stock, expiring items | `stock_alerts` (auto-generated) |
| **Recipe Costing** | Ingredient costs, profit margins | `recipes`, `recipe_ingredients` |
| **RBAC** | Role-based permissions | `roles`, `user_roles` |
| **Sync** | LAN synchronization queue | `sync_queue`, `conflict_logs` |
| **Audit** | Complete action history | `audit_logs`, `stock_adjustments` |

### Database Stats

- **Tables:** 26
- **Views:** 8 (for reporting)
- **Triggers:** 12-15 (for automation, timestamp triggers handled by app layer)
- **Indexes:** 50+ (for performance)
- **Default Data:** Units, categories, locations, roles

---

## 📈 Sample Reports

The database includes pre-built views for common reports:

### Current Stock Overview
```sql
SELECT * FROM vw_current_stock WHERE is_below_reorder = 1;
```

### Daily Purchase Summary
```sql
SELECT * FROM vw_daily_purchase_summary WHERE purchase_date = date('now');
```

### Expiring Items (Next 30 Days)
```sql
SELECT * FROM vw_expiring_batches ORDER BY days_to_expiry;
```

### Recipe Profitability
```sql
SELECT * FROM vw_recipe_costing ORDER BY profit_margin DESC;
```

### Supplier Performance
```sql
SELECT * FROM vw_supplier_performance ORDER BY total_amount_paid DESC;
```

For more examples, see **[database/README.md](./database/README.md#-reporting-queries)**.

---

## 🔐 Security Features

- **Password Hashing:** Bcrypt for user credentials
- **Soft Deletes:** Records never truly deleted (audit trail)
- **Audit Logs:** Every user action tracked with timestamps
- **Role-Based Access:** Granular permissions per user role
- **Foreign Key Constraints:** Prevent orphaned records
- **Transaction Safety:** SQLite WAL mode for concurrency

---

## 🧪 Testing

### Database Tests

```bash
# Run schema
sqlite3 test.db < database/v1_initial.sql

# Load test data
sqlite3 test.db < database/seed_test_data.sql

# Verify stock automation
sqlite3 test.db <<EOF
-- Check stock after purchase
SELECT p.name, sl.quantity
FROM stock_levels sl
JOIN products p ON sl.product_uuid = p.uuid
WHERE sl.location_id = 1;

-- Check stock adjustments logged
SELECT COUNT(*) FROM stock_adjustments;
EOF
```

### Test Scenarios

✅ **Purchase workflow:** draft → received → stock updated
✅ **Issue workflow:** pending → issued → stock decremented
✅ **Insufficient stock:** Issue should fail with error
✅ **Expiry alerts:** Auto-generated for batches <30 days
✅ **Reorder alerts:** Auto-generated when stock ≤ reorder_level
✅ **Unit conversions:** 1 piece = 1.5 kg calculated correctly
✅ **Wastage tracking:** Stock decremented, adjustment logged
✅ **Recipe costing:** Ingredient costs summed accurately

---

## 🗓️ Roadmap

### Phase 1: Database Foundation ✅ COMPLETE
- [x] Complete schema design (30+ tables)
- [x] Automated stock triggers
- [x] Batch tracking & expiry alerts
- [x] Unit conversion system
- [x] RBAC with roles
- [x] Sync queue & conflict logs
- [x] Comprehensive documentation

### Phase 2: Backend API (Next)
- [ ] Node.js Express server
- [ ] REST API for CRUD operations
- [ ] LAN sync controller
- [ ] Conflict resolution logic
- [ ] Authentication middleware
- [ ] Report generation endpoints

### Phase 3: Mobile App (After Backend)
- [ ] Flutter app with Drift ORM
- [ ] Purchase entry screens
- [ ] Stock issue screens
- [ ] Dashboard with charts
- [ ] Offline-first data layer
- [ ] Background sync service
- [ ] Report viewer (PDF export)

### Phase 4: Advanced Features
- [ ] Barcode/QR scanning
- [ ] Multi-branch support (hotel chains)
- [ ] Menu engineering analytics
- [ ] Auto-reorder via ML predictions
- [ ] WhatsApp/Email report scheduling
- [ ] Biometric authentication

---

## 📚 Documentation

| Document | Description | Status |
|----------|-------------|--------|
| [Database README](./database/README.md) | Complete database guide, queries, troubleshooting | ✅ Complete |
| [Database Schema](./database/v1_initial.sql) | Full SQL with comments | ✅ Complete |
| [Test Data](./database/seed_test_data.sql) | Sample data for development | ✅ Complete |
| API Documentation | REST API endpoints (future) | 🚧 Planned |
| User Guide | End-user manual (future) | 🚧 Planned |
| PRD | Product requirements (internal) | 📝 In Progress |

---

## 🤝 Team

**Project Owner:** Hotel Management Team
**Database Architect:** Reviewed and approved 2025-11-11
**Development Team:** In progress

---

## 📞 Support

For technical questions about the database:
1. Check **[database/README.md](./database/README.md)** (comprehensive guide)
2. Review SQL comments in `v1_initial.sql`
3. Test with `seed_test_data.sql`
4. Contact development team

---

## 📝 Changelog

### v1.0.1 - 2025-11-12 (Production Hardening - CRITICAL UPDATE)

**Fixed:**
- ⚠️ **CRITICAL:** Removed broken timestamp triggers (SQLite syntax incompatibility)
- Fixed trigger aggregation: `trg_after_issue_approved` now uses SUM() for correct multi-item handling
- Fixed trigger aggregation: `trg_after_transfer_completed` now uses SUM() properly
- Added `trg_before_transfer_check_stock` to prevent insufficient stock transfers
- Added NULL safety to all triggers (COALESCE for modified_by fields)
- Added NULL checks for foreign key fields (from_location_id, to_location_id)
- Added HAVING clauses to GROUP BY statements to prevent zero-quantity logs
- Added LIMIT 1 to EXISTS queries for performance
- Fixed schema version to INSERT (not UPDATE) to preserve history
- Fixed system user insertion to be idempotent (prevents duplicate key errors)
- Fixed seed data unit conversion: 330ml can = 0.33L (was 330L!)

**Changed:**
- **BREAKING:** Applications MUST now explicitly set `last_modified` on UPDATE operations
- Moved verification queries after COMMIT for accuracy
- Improved error messages in triggers

**Added:**
- `CRITICAL_TIMESTAMP_ISSUE.md` - Essential reading for developers
- `v1.0.1_CORRECTIONS_SUMMARY.md` - Complete list of fixes
- `v1.0_to_v1.0.1_migration_CORRECTED.sql` - Production-ready migration script

**Database Status:** ✅ Production Ready (requires app code updates for timestamps)
**Urgency:** HIGH - Apply within 30 days, update apps first

### v1.0.0 - 2025-11-11 (Database Release)

**Added:**
- Complete database schema with 26 tables
- 15 automated triggers for stock management
- Unit conversion system with `unit_conversions` table
- Batch tracking with `product_batches` and expiry alerts
- Role-based access control (RBAC) with 4 default roles
- Stock alerts for reorder and expiry scenarios
- Sync infrastructure (`sync_queue`, `conflict_logs`)
- Comprehensive audit logs
- 8 pre-built reporting views
- Seed data with 50+ test records
- Full documentation in database/README.md

**Database Status:** ⚠️ Superseded by v1.0.1

---

## 📄 License

Proprietary - All rights reserved by Hotel Management

---

**Built with ❤️ for the hospitality industry**