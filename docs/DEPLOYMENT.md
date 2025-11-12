# HIMS Deployment Guide

**Version:** 1.0.1
**Target Environment:** Production
**Last Updated:** 2025-11-12

---

## 📋 Pre-Deployment Checklist

### System Requirements

- [ ] **Operating System:** Linux (Ubuntu 20.04+), Windows Server 2019+, or macOS 10.15+
- [ ] **Node.js:** v18.0.0 or higher
- [ ] **NPM:** v9.0.0 or higher
- [ ] **SQLite3:** v3.35.0 or higher
- [ ] **RAM:** Minimum 2GB, Recommended 4GB+
- [ ] **Storage:** Minimum 10GB free space
- [ ] **Network:** LAN connectivity for multi-device sync

### Pre-Flight Verification

- [ ] All tests passing (`npm test`)
- [ ] Database schema integrity verified
- [ ] Backup strategy in place
- [ ] Rollback plan documented
- [ ] Team notified of maintenance window

---

## 🚀 Deployment Steps

### Step 1: Backup Existing System

```bash
# Create backup directory
mkdir -p backups/$(date +%Y%m%d_%H%M%S)

# Backup database
cp database/hims.db backups/$(date +%Y%m%d_%H%M%S)/hims.db.backup

# Backup server configuration
cp server/.env backups/$(date +%Y%m%d_%H%M%S)/.env.backup

# Verify backup
ls -lh backups/$(date +%Y%m%d_%H%M%S)/
```

### Step 2: Stop Running Services

```bash
# If using PM2
pm2 stop hims-server

# If using systemd
sudo systemctl stop hims-server

# Or manually
pkill -f "node.*hims"
```

### Step 3: Update Code

```bash
# Pull latest code
git fetch origin
git checkout claude/initial-setup-011CV3nyDSqryfr3VpAaPiQP
git pull origin claude/initial-setup-011CV3nyDSqryfr3VpAaPiQP

# Install dependencies
cd server
npm ci --production

cd ../flutter
flutter pub get
```

### Step 4: Apply Database Migrations

```bash
# IMPORTANT: Always backup before migrations!

# Check current version
sqlite3 database/hims.db "SELECT * FROM schema_migrations ORDER BY applied_at DESC LIMIT 1;"

# Apply migrations (if needed)
# For v1.0.0 -> v1.0.1
sqlite3 database/hims.db < sql/migrations/v1.0.1__device_and_sync_hardening.sql

# Verify migration
sqlite3 database/hims.db "SELECT * FROM schema_migrations WHERE version='1.0.1';"

# Run integrity checks
sqlite3 database/hims.db "PRAGMA integrity_check;"
sqlite3 database/hims.db "PRAGMA foreign_key_check;"
```

### Step 5: Update Configuration

```bash
cd server

# Review and update .env
nano .env

# Required changes for production:
# - NODE_ENV=production
# - JWT_SECRET=<generate_new_secure_secret>
# - MAX_DEVICES=<your_limit>
# - LOG_LEVEL=info

# Validate .env
node -e "require('dotenv').config(); console.log('Environment variables loaded successfully');"
```

### Step 6: Change Default Credentials

```bash
# Generate new bcrypt hash for admin password
node -e "
const bcrypt = require('bcrypt');
const password = 'YOUR_NEW_SECURE_PASSWORD';
bcrypt.hash(password, 10, (err, hash) => {
  if (err) throw err;
  console.log('New password hash:', hash);
});
"

# Update database
sqlite3 database/hims.db "
UPDATE users
SET password_hash = 'YOUR_GENERATED_HASH_HERE',
    last_modified = datetime('now')
WHERE username = 'admin';
"

# Verify
sqlite3 database/hims.db "SELECT username, last_modified FROM users WHERE username='admin';"
```

### Step 7: Run Verification Script

```bash
# Run installation verification
./scripts/verify_installation.sh database/hims.db http://localhost:3000

# Should output: Installation verification completed successfully!
```

### Step 8: Start Services

#### Option A: Using PM2 (Recommended for Production)

```bash
cd server

# Install PM2 globally (if not installed)
npm install -g pm2

# Start with PM2
pm2 start src/index.js --name hims-server

# Save PM2 configuration
pm2 save

# Setup PM2 to start on system boot
pm2 startup

# View logs
pm2 logs hims-server

# Monitor
pm2 monit
```

#### Option B: Using systemd (Linux)

```bash
# Create systemd service file
sudo nano /etc/systemd/system/hims-server.service
```

```ini
[Unit]
Description=HIMS Sync Server
After=network.target

[Service]
Type=simple
User=www-data
WorkingDirectory=/path/to/Final_HIMS/server
ExecStart=/usr/bin/node src/index.js
Restart=on-failure
RestartSec=10
StandardOutput=syslog
StandardError=syslog
SyslogIdentifier=hims-server
Environment=NODE_ENV=production

[Install]
WantedBy=multi-user.target
```

```bash
# Reload systemd
sudo systemctl daemon-reload

# Enable service
sudo systemctl enable hims-server

# Start service
sudo systemctl start hims-server

# Check status
sudo systemctl status hims-server

# View logs
sudo journalctl -u hims-server -f
```

#### Option C: Docker (Optional)

```bash
# Build Docker image
docker build -t hims-server:1.0.1 -f server/Dockerfile .

# Run container
docker run -d \
  --name hims-server \
  -p 3000:3000 \
  -v $(pwd)/database:/app/database \
  -v $(pwd)/server/.env:/app/.env \
  --restart unless-stopped \
  hims-server:1.0.1

# View logs
docker logs -f hims-server
```

### Step 9: Post-Deployment Verification

```bash
# Test health endpoint
curl http://localhost:3000/api/health

# Expected: {"status":"ok",...}

# Test detailed health
curl http://localhost:3000/api/health/detailed | python3 -m json.tool

# Test device registration (from client device)
curl -X POST http://localhost:3000/api/devices/register \
  -H "Content-Type: application/json" \
  -d '{
    "device_uuid": "test_device_001",
    "device_name": "Test Device",
    "device_type": "desktop",
    "user_uuid": "user_admin"
  }'

# Expected: {"success":true,...}
```

### Step 10: Monitor Logs for 48 Hours

```bash
# Using PM2
pm2 logs hims-server --lines 100

# Using systemd
sudo journalctl -u hims-server -f --since "1 hour ago"

# Check for errors
grep -i error /path/to/server/logs/error.log

# Monitor database size
du -h database/hims.db

# Check active devices
sqlite3 database/hims.db "SELECT * FROM v_active_devices;"

# Check unresolved conflicts
sqlite3 database/hims.db "SELECT COUNT(*) FROM conflict_logs WHERE resolved=0;"
```

---

## 🔄 Rollback Procedure

If issues are encountered:

### 1. Stop Services

```bash
pm2 stop hims-server
# or
sudo systemctl stop hims-server
```

### 2. Restore Database Backup

```bash
# Identify latest backup
ls -lt backups/

# Restore
cp backups/YYYYMMDD_HHMMSS/hims.db.backup database/hims.db

# Verify
sqlite3 database/hims.db "PRAGMA integrity_check;"
```

### 3. Restore Code (if needed)

```bash
# Checkout previous stable version
git checkout <previous_stable_commit>

# Reinstall dependencies
cd server && npm ci
```

### 4. Restart Services

```bash
pm2 restart hims-server
# or
sudo systemctl start hims-server
```

### 5. Verify Rollback

```bash
./scripts/verify_installation.sh
```

---

## 📊 Post-Deployment Monitoring

### Key Metrics to Monitor

1. **Server Health**
   - Uptime: `pm2 status` or `systemctl status hims-server`
   - Memory usage: `pm2 monit` or `htop`
   - CPU usage

2. **Database Health**
   - Database size growth
   - Query performance
   - Integrity checks (run weekly)

3. **Sync Performance**
   - Active devices count
   - Sync session success rate
   - Conflict frequency
   - Average sync duration

4. **Application Metrics**
   - API response times
   - Error rates
   - Active users

### Monitoring Commands

```bash
# Server status
pm2 status

# Resource usage
pm2 monit

# Real-time logs
pm2 logs hims-server --lines 50

# Database stats
sqlite3 database/hims.db "
SELECT
  (SELECT COUNT(*) FROM device_registrations WHERE is_active=1) as active_devices,
  (SELECT COUNT(*) FROM sync_queue WHERE synced=0) as pending_sync,
  (SELECT COUNT(*) FROM conflict_logs WHERE resolved=0) as unresolved_conflicts,
  (SELECT COUNT(*) FROM audit_logs WHERE created_at > datetime('now', '-24 hours')) as operations_24h;
"

# Sync statistics
curl -s http://localhost:3000/api/health/metrics | python3 -m json.tool
```

---

## 🔒 Security Hardening (Production)

### 1. Firewall Configuration

```bash
# Allow only LAN access
sudo ufw allow from 192.168.1.0/24 to any port 3000

# If using systemd, restrict to localhost
# Update service to bind to 127.0.0.1 only
# Then use nginx as reverse proxy
```

### 2. Nginx Reverse Proxy (Recommended)

```nginx
server {
    listen 80;
    server_name hims.yourdomain.local;

    location / {
        proxy_pass http://localhost:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_cache_bypass $http_upgrade;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }

    # Rate limiting
    limit_req_zone $binary_remote_addr zone=api_limit:10m rate=10r/s;
    limit_req zone=api_limit burst=20 nodelay;
}
```

### 3. SSL/TLS (if needed)

```bash
# Generate self-signed certificate for LAN
sudo openssl req -x509 -nodes -days 365 \
  -newkey rsa:2048 \
  -keyout /etc/ssl/private/hims.key \
  -out /etc/ssl/certs/hims.crt
```

### 4. Database Encryption (Optional)

```bash
# Use SQLCipher for encryption at rest
# Update Node.js to use better-sqlite3 with sqlcipher
```

---

## 🗄️ Backup Strategy

### Automated Daily Backups

```bash
# Create backup script
cat > /usr/local/bin/hims-backup.sh <<'EOF'
#!/bin/bash
BACKUP_DIR="/backups/hims"
DATE=$(date +%Y%m%d_%H%M%S)
mkdir -p $BACKUP_DIR

# Backup database
cp /path/to/Final_HIMS/database/hims.db $BACKUP_DIR/hims_$DATE.db

# Compress
gzip $BACKUP_DIR/hims_$DATE.db

# Keep only last 30 days
find $BACKUP_DIR -name "hims_*.db.gz" -mtime +30 -delete

echo "Backup completed: hims_$DATE.db.gz"
EOF

chmod +x /usr/local/bin/hims-backup.sh

# Add to crontab (daily at 2 AM)
(crontab -l 2>/dev/null; echo "0 2 * * * /usr/local/bin/hims-backup.sh") | crontab -
```

---

## 📞 Support & Troubleshooting

### Common Issues

**Issue:** Server won't start
**Check:**
- `pm2 logs hims-server --err`
- Database file permissions
- Port 3000 availability: `netstat -tulpn | grep 3000`

**Issue:** High memory usage
**Solution:**
- Check for memory leaks: `pm2 monit`
- Restart server: `pm2 restart hims-server`
- Increase server memory if needed

**Issue:** Sync failures
**Check:**
- Network connectivity
- Device limit not exceeded
- Server logs for errors
- Database integrity

---

## ✅ Deployment Complete

Once all steps are verified:

- [ ] Server running and healthy
- [ ] All tests passing
- [ ] Monitoring in place
- [ ] Backup system active
- [ ] Team notified of successful deployment
- [ ] Documentation updated

**Deployment Date:** _________________
**Deployed By:** _________________
**Version:** 1.0.1
**Next Review:** _________________

---

**For support:** https://github.com/Syedmighty/Final_HIMS/issues
