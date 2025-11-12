# HIMS - Hotel Inventory Management System

**Version:** 1.0.1
**Status:** Production Ready
**Last Updated:** 2025-11-12

---

## 🎯 Overview

HIMS is a complete **offline-first** Hotel Inventory Management System with real-time LAN synchronization capabilities. Built for multi-device environments with a focus on data integrity, conflict resolution, and device limit enforcement.

### Key Features

- ✅ **Offline-First Architecture** - Works without internet, syncs when connected
- ✅ **Multi-Device Sync** - LAN-based synchronization with device limit enforcement (default: 5 devices)
- ✅ **Stock Automation** - Automatic stock level updates via database triggers
- ✅ **Conflict Resolution** - Last-write-wins with manual override capabilities
- ✅ **Comprehensive Auditing** - Full audit trail for all operations
- ✅ **Cross-Platform** - Flutter frontend (Desktop/Web/Mobile) + Node.js backend
- ✅ **Production-Ready** - Extensive test coverage, security hardening, and deployment guides

---

## 📁 Project Structure

```
Final_HIMS/
├── sql/                      # Database schemas and migrations
│   ├── v1_initial.sql       # Core schema v1.0.0
│   ├── v1_triggers.sql      # Stock automation triggers
│   └── migrations/
│       └── v1.0.1__device_and_sync_hardening.sql
├── server/                   # Node.js sync server
│   ├── src/
│   │   ├── controllers/     # Device & sync controllers
│   │   ├── routes/          # API routes
│   │   ├── config/          # Database & logger config
│   │   └── hooks/           # Validation hooks
│   ├── package.json
│   └── .env.example
├── flutter/                  # Flutter client app
│   └── lib/
│       └── services/
│           └── sync_service.dart
├── tests/                    # Test suites
│   ├── unit/                # Unit tests (migration, triggers)
│   └── integration/         # Integration tests (sync, device management)
└── docs/                     # Documentation
    ├── API.md               # API documentation
    ├── DEPLOYMENT.md        # Deployment guide
    └── MIGRATION_GUIDE.md   # Migration instructions
```

---

## 🚀 Quick Start

### Prerequisites

- **Node.js** >= 18.0.0
- **npm** >= 9.0.0
- **SQLite3** >= 3.35.0
- **Flutter** >= 3.10.0 (for client app)

### 1. Database Setup

```bash
# Create database directory
mkdir -p database

# Initialize database with schema
sqlite3 database/hims.db < sql/v1_initial.sql

# Apply triggers
sqlite3 database/hims.db < sql/v1_triggers.sql

# Apply device management migration
sqlite3 database/hims.db < sql/migrations/v1.0.1__device_and_sync_hardening.sql

# Verify integrity
sqlite3 database/hims.db "PRAGMA integrity_check;"
sqlite3 database/hims.db "PRAGMA foreign_key_check;"
```

### 2. Server Setup

```bash
cd server

# Install dependencies
npm install

# Copy environment configuration
cp .env.example .env

# Edit .env with your settings
nano .env

# Start server
npm start

# Or for development with auto-reload
npm run dev
```

The server will start on `http://localhost:3000`

### 3. Run Tests

```bash
cd server
npm test

# Watch mode
npm run test:watch

# With coverage
npm test -- --coverage
```

### 4. Flutter Client Setup

```bash
cd flutter

# Install dependencies
flutter pub get

# Run on desktop
flutter run -d windows  # or macos, linux

# Build for production
flutter build windows --release
```

---

## 🔧 Configuration

### Environment Variables (server/.env)

```env
# Server Settings
PORT=3000
NODE_ENV=production
HOST=0.0.0.0

# Database
DB_PATH=../database/hims.db
DB_BACKUP_PATH=../database/backups

# Device Management
MAX_DEVICES=5
DEVICE_HEARTBEAT_TIMEOUT_HOURS=24
AUTO_DEACTIVATE_STALE_DEVICES_DAYS=30

# Security
JWT_SECRET=your_secure_random_string_here
JWT_EXPIRY=24h
BCRYPT_ROUNDS=10

# Rate Limiting
RATE_LIMIT_WINDOW_MS=60000
RATE_LIMIT_MAX_REQUESTS=20

# Sync Settings
SYNC_BATCH_SIZE=200
MAX_SYNC_RETRIES=3
SYNC_RETRY_DELAY_MS=2000

# Logging
LOG_LEVEL=info
LOG_FILE_PATH=./logs/server.log
```

### Default Credentials

**Username:** `admin`
**Password:** `admin123`
**⚠️ MUST BE CHANGED IN PRODUCTION**

---

## 📊 Core Modules

### 1. Inventory Management
- Product CRUD with SKU tracking
- Category management
- Multi-unit support with conversions
- Stock level monitoring
- Low stock alerts

### 2. Purchases
- Vendor management
- Purchase order creation
- Receive goods with automatic stock updates
- GST calculation and tracking

### 3. Issues (Stock Out)
- Stock withdrawal tracking
- Prevents negative stock
- Inter-location transfers support
- Audit trail

### 4. Transfers
- Cross-location stock movement
- Automatic stock deduction/addition
- Validation before completion

### 5. Wastage & Returns
- Damage/expiry tracking
- Return management
- Reason tracking

### 6. Invoicing
- Cash/Credit invoice types
- Automatic tax calculation
- PDF generation support
- Stock deduction on finalization

### 7. Reports
- Sales summaries
- Purchase analysis
- Stock valuation
- Profitability reports

### 8. Device Management
- Device registration with limits
- Heartbeat tracking
- Admin controls for device activation/deactivation
- Automatic stale device cleanup

### 9. Sync System
- Push/Pull synchronization
- Conflict detection and resolution
- Sync session tracking
- Error recovery

---

## 🔐 Security Features

- ✅ **Password Hashing** - bcrypt with configurable rounds
- ✅ **SQL Injection Prevention** - Parameterized queries only
- ✅ **Rate Limiting** - Configurable per-endpoint limits
- ✅ **CORS Protection** - Configurable origins
- ✅ **Helmet.js** - Security headers
- ✅ **Role-Based Access Control** - Admin/Manager/Staff/Viewer roles
- ✅ **Audit Logging** - All operations logged with user/device tracking

---

## 📡 API Endpoints

### Health
- `GET /api/health` - Basic health check
- `GET /api/health/detailed` - Detailed system status
- `GET /api/health/metrics` - Sync and device metrics

### Device Management
- `POST /api/devices/register` - Register new device
- `POST /api/devices/heartbeat` - Update device heartbeat
- `GET /api/devices` - List all devices
- `GET /api/devices/:uuid/stats` - Device sync statistics

### Admin Device Control
- `POST /api/admin/devices/:uuid/deactivate` - Deactivate device
- `POST /api/admin/devices/:uuid/reactivate` - Reactivate device
- `POST /api/admin/devices/cleanup-stale` - Auto-cleanup stale devices

### Sync Operations
- `POST /api/sync/push` - Push local changes to server
- `GET /api/sync/pull` - Pull server changes
- `GET /api/sync/conflicts` - List conflicts
- `POST /api/sync/conflicts/:id/resolve` - Resolve conflict

See [docs/API.md](docs/API.md) for complete API documentation.

---

## 🧪 Testing

### Test Coverage

- **Migration Tests** - Schema and migration integrity
- **Trigger Tests** - Stock automation and validation
- **Integration Tests** - End-to-end sync workflows
- **Device Limit Tests** - MAX_DEVICES enforcement

### Running Tests

```bash
# All tests
npm test

# Specific test suite
npm test -- migration.test.js
npm test -- trigger.test.js
npm test -- sync.test.js

# With coverage
npm test -- --coverage
```

---

## 📦 Deployment

### Production Deployment Checklist

1. ✅ Backup existing database
2. ✅ Update environment variables (`.env`)
3. ✅ Change default admin password
4. ✅ Run migrations
5. ✅ Run verification scripts
6. ✅ Test sync on staging environment
7. ✅ Monitor logs for 48 hours post-deployment

See [docs/DEPLOYMENT.md](docs/DEPLOYMENT.md) for detailed deployment instructions.

---

## 🔄 Database Migrations

### Applying Migrations

```bash
# Backup first!
cp database/hims.db database/hims.db.backup_$(date +%Y%m%d_%H%M%S)

# Apply migration
sqlite3 database/hims.db < sql/migrations/v1.0.1__device_and_sync_hardening.sql

# Verify
sqlite3 database/hims.db "PRAGMA integrity_check;"
sqlite3 database/hims.db "SELECT * FROM schema_migrations;"
```

See [docs/MIGRATION_GUIDE.md](docs/MIGRATION_GUIDE.md) for complete migration procedures.

---

## 🐛 Troubleshooting

### Common Issues

**Issue:** Device registration fails with "Maximum device limit reached"
**Solution:** Admin must deactivate inactive devices via `/api/admin/devices/:uuid/deactivate`

**Issue:** Sync conflicts appearing frequently
**Solution:** Check system clocks are synchronized across devices (use NTP)

**Issue:** "Database is locked" errors
**Solution:** Ensure transactions are properly committed, check for long-running queries

**Issue:** Stock levels incorrect
**Solution:** Recompute from `stock_adjustments` table (source of truth)

---

## 📝 Licensing & Support

**License:** MIT
**Support:** GitHub Issues at https://github.com/Syedmighty/Final_HIMS/issues

---

## 🤝 Contributing

1. Fork the repository
2. Create feature branch (`git checkout -b feature/amazing-feature`)
3. Commit changes (`git commit -m 'Add amazing feature'`)
4. Push to branch (`git push origin feature/amazing-feature`)
5. Open Pull Request

---

## 📚 Additional Documentation

- [API Documentation](docs/API.md)
- [Deployment Guide](docs/DEPLOYMENT.md)
- [Migration Guide](docs/MIGRATION_GUIDE.md)
- [Database Schema Reference](docs/SCHEMA.md)

---

**Built with ❤️ for the hospitality industry**
