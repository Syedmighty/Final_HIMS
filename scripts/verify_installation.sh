#!/bin/bash

# ============================================================================
# HIMS Installation Verification Script
# ============================================================================
# Purpose: Verify database integrity, schema version, and server health
# Usage: ./scripts/verify_installation.sh [database_path]
# ============================================================================

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
DB_PATH="${1:-database/hims.db}"
SERVER_URL="${2:-http://localhost:3000}"

echo "============================================================================"
echo "HIMS Installation Verification"
echo "============================================================================"
echo ""

# Check if database exists
echo -n "Checking database file... "
if [ ! -f "$DB_PATH" ]; then
    echo -e "${RED}FAILED${NC}"
    echo "Database file not found at: $DB_PATH"
    exit 1
fi
echo -e "${GREEN}OK${NC}"

# Check database integrity
echo -n "Running PRAGMA integrity_check... "
INTEGRITY_RESULT=$(sqlite3 "$DB_PATH" "PRAGMA integrity_check;" 2>&1)
if [ "$INTEGRITY_RESULT" != "ok" ]; then
    echo -e "${RED}FAILED${NC}"
    echo "$INTEGRITY_RESULT"
    exit 1
fi
echo -e "${GREEN}OK${NC}"

# Check foreign key constraints
echo -n "Running PRAGMA foreign_key_check... "
FK_RESULT=$(sqlite3 "$DB_PATH" "PRAGMA foreign_key_check;" 2>&1)
if [ -n "$FK_RESULT" ]; then
    echo -e "${RED}FAILED${NC}"
    echo "Foreign key violations found:"
    echo "$FK_RESULT"
    exit 1
fi
echo -e "${GREEN}OK${NC}"

# Check schema version
echo -n "Checking schema version... "
SCHEMA_VERSION=$(sqlite3 "$DB_PATH" "SELECT version FROM schema_migrations ORDER BY applied_at DESC LIMIT 1;" 2>&1)
if [ -z "$SCHEMA_VERSION" ]; then
    echo -e "${RED}FAILED${NC}"
    echo "No schema migrations found"
    exit 1
fi
echo -e "${GREEN}OK${NC} (Version: $SCHEMA_VERSION)"

# Count tables
echo -n "Counting tables... "
TABLE_COUNT=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM sqlite_master WHERE type='table';" 2>&1)
echo -e "${GREEN}OK${NC} (Found: $TABLE_COUNT tables)"

# Count triggers
echo -n "Counting triggers... "
TRIGGER_COUNT=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM sqlite_master WHERE type='trigger';" 2>&1)
echo -e "${GREEN}OK${NC} (Found: $TRIGGER_COUNT triggers)"

# Count indexes
echo -n "Counting indexes... "
INDEX_COUNT=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM sqlite_master WHERE type='index' AND name NOT LIKE 'sqlite_%';" 2>&1)
echo -e "${GREEN}OK${NC} (Found: $INDEX_COUNT indexes)"

# Check required tables
echo ""
echo "Verifying required tables..."
REQUIRED_TABLES=(
    "schema_migrations"
    "users"
    "products"
    "categories"
    "units"
    "suppliers"
    "locations"
    "purchases"
    "purchase_items"
    "issues"
    "issue_items"
    "transfers"
    "transfer_items"
    "wastages"
    "wastage_items"
    "stock_levels"
    "stock_adjustments"
    "invoices"
    "invoice_items"
    "device_registrations"
    "device_sync_sessions"
    "sync_queue"
    "conflict_logs"
    "audit_logs"
    "alerts"
)

MISSING_TABLES=()
for table in "${REQUIRED_TABLES[@]}"; do
    EXISTS=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='$table';" 2>&1)
    if [ "$EXISTS" -eq 0 ]; then
        MISSING_TABLES+=("$table")
        echo -e "  ${RED}✗${NC} $table"
    else
        echo -e "  ${GREEN}✓${NC} $table"
    fi
done

if [ ${#MISSING_TABLES[@]} -gt 0 ]; then
    echo ""
    echo -e "${RED}ERROR: Missing tables: ${MISSING_TABLES[*]}${NC}"
    exit 1
fi

# Check seed data
echo ""
echo "Verifying seed data..."

ADMIN_EXISTS=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM users WHERE username='admin';" 2>&1)
if [ "$ADMIN_EXISTS" -eq 0 ]; then
    echo -e "  ${RED}✗${NC} Default admin user"
else
    echo -e "  ${GREEN}✓${NC} Default admin user"
fi

UNIT_COUNT=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM units;" 2>&1)
if [ "$UNIT_COUNT" -eq 0 ]; then
    echo -e "  ${RED}✗${NC} Base units"
else
    echo -e "  ${GREEN}✓${NC} Base units (Count: $UNIT_COUNT)"
fi

LOCATION_COUNT=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM locations;" 2>&1)
if [ "$LOCATION_COUNT" -eq 0 ]; then
    echo -e "  ${RED}✗${NC} Default location"
else
    echo -e "  ${GREEN}✓${NC} Default location (Count: $LOCATION_COUNT)"
fi

# Check device registrations
echo ""
echo "Device Management Status..."
ACTIVE_DEVICES=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM device_registrations WHERE is_active=1;" 2>&1)
TOTAL_DEVICES=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM device_registrations;" 2>&1)
echo "  Active devices: $ACTIVE_DEVICES / 5 (max)"
echo "  Total registered: $TOTAL_DEVICES"

# Check server health (if server is running)
echo ""
echo "Checking server health..."
if command -v curl &> /dev/null; then
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$SERVER_URL/api/health" 2>&1 || echo "000")

    if [ "$HTTP_CODE" -eq 200 ]; then
        echo -e "  ${GREEN}✓${NC} Server is running and healthy"

        # Get detailed health
        HEALTH_JSON=$(curl -s "$SERVER_URL/api/health/detailed" 2>&1)
        if [ $? -eq 0 ]; then
            echo ""
            echo "Server Health Details:"
            echo "$HEALTH_JSON" | python3 -m json.tool 2>/dev/null || echo "$HEALTH_JSON"
        fi
    else
        echo -e "  ${YELLOW}⚠${NC} Server not responding (HTTP $HTTP_CODE)"
        echo "     Make sure the server is running: cd server && npm start"
    fi
else
    echo -e "  ${YELLOW}⚠${NC} curl not installed, skipping server check"
fi

# Check for unresolved conflicts
echo ""
UNRESOLVED_CONFLICTS=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM conflict_logs WHERE resolved=0;" 2>&1)
if [ "$UNRESOLVED_CONFLICTS" -gt 0 ]; then
    echo -e "${YELLOW}WARNING: $UNRESOLVED_CONFLICTS unresolved sync conflicts${NC}"
fi

# Check for unsynced items
UNSYNCED_ITEMS=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM sync_queue WHERE synced=0;" 2>&1)
if [ "$UNSYNCED_ITEMS" -gt 0 ]; then
    echo -e "${YELLOW}INFO: $UNSYNCED_ITEMS items pending sync${NC}"
fi

# Final summary
echo ""
echo "============================================================================"
echo -e "${GREEN}Installation verification completed successfully!${NC}"
echo "============================================================================"
echo ""
echo "Next steps:"
echo "  1. Change default admin password"
echo "  2. Configure .env file in server directory"
echo "  3. Start server: cd server && npm start"
echo "  4. Register devices via API or Flutter app"
echo ""
