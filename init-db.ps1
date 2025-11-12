# HIMS Database Initialization Script
# Run this from the project root directory

Write-Host "`n🗄️  HIMS Database Initialization`n" -ForegroundColor Cyan

# Get current directory
$projectRoot = Get-Location
Write-Host "Project root: $projectRoot" -ForegroundColor Gray

# Set paths
$dbPath = Join-Path $projectRoot "database\hims.db"
$sqlDir = Join-Path $projectRoot "sql"

# Create database directory if needed
$dbDir = Join-Path $projectRoot "database"
if (-not (Test-Path $dbDir)) {
    New-Item -ItemType Directory -Path $dbDir | Out-Null
    Write-Host "✓ Created database directory" -ForegroundColor Green
}

# Backup existing database
if (Test-Path $dbPath) {
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $backupPath = Join-Path $dbDir "hims_backup_$timestamp.db"
    Copy-Item $dbPath $backupPath
    Write-Host "✓ Backed up existing database" -ForegroundColor Yellow
    Remove-Item $dbPath
}

Write-Host "✓ Creating new database" -ForegroundColor Green

# Create Node.js initialization script
$nodeScript = @'
const Database = require('better-sqlite3');
const fs = require('fs');
const path = require('path');

const dbPath = path.join(process.cwd(), 'database', 'hims.db');
const sqlDir = path.join(process.cwd(), 'sql');

console.log('Creating database:', dbPath);

const db = new Database(dbPath);

db.pragma('journal_mode = WAL');
db.pragma('foreign_keys = ON');

console.log('Running schema migrations...');

const sqlFiles = [
  'v1_initial.sql',
  'v1_triggers.sql',
  'migrations/v1.0.1__device_and_sync_hardening.sql'
];

try {
  for (const file of sqlFiles) {
    const filePath = path.join(sqlDir, file);
    if (fs.existsSync(filePath)) {
      console.log('  Executing:', file);
      const sql = fs.readFileSync(filePath, 'utf8');
      const statements = sql.split(';').filter(s => s.trim().length > 0);

      for (const statement of statements) {
        try {
          db.exec(statement);
        } catch (err) {
          if (!err.message.includes('already exists')) {
            console.warn('    Warning:', err.message);
          }
        }
      }
    } else {
      console.warn('  File not found:', file);
    }
  }

  db.exec(`
    CREATE TABLE IF NOT EXISTS schema_migrations (
      version TEXT PRIMARY KEY,
      applied_at DATETIME DEFAULT CURRENT_TIMESTAMP,
      description TEXT
    );
  `);

  const insertMigration = db.prepare(`
    INSERT OR IGNORE INTO schema_migrations (version, description)
    VALUES (?, ?)
  `);

  insertMigration.run('1.0.0', 'Initial schema');
  insertMigration.run('1.0.1', 'Device and sync hardening');

  const userCheck = db.prepare('SELECT COUNT(*) as count FROM users').get();

  if (userCheck.count === 0) {
    console.log('Creating default admin user...');

    const bcrypt = require('bcrypt');
    const defaultPassword = bcrypt.hashSync('admin123', 10);

    db.prepare(`
      INSERT INTO users (username, email, password_hash, full_name, role, is_active)
      VALUES (?, ?, ?, ?, ?, ?)
    `).run('admin', 'admin@hims.local', defaultPassword, 'System Administrator', 'admin', 1);

    console.log('✓ Default admin user created');
    console.log('  Username: admin');
    console.log('  Password: admin123');
    console.log('  ⚠️  Please change this password after first login!');
  }

  const tables = db.prepare(`
    SELECT name FROM sqlite_master
    WHERE type='table' AND name NOT LIKE 'sqlite_%'
    ORDER BY name
  `).all();

  console.log(`\n✅ Database initialized successfully with ${tables.length} tables:`);
  tables.forEach(t => console.log('  -', t.name));

  db.close();
  process.exit(0);

} catch (error) {
  console.error('❌ Database initialization failed:', error.message);
  console.error(error.stack);
  process.exit(1);
}
'@

# Save the Node script
$nodeScriptPath = "init-db-temp.js"
$nodeScript | Out-File -FilePath $nodeScriptPath -Encoding UTF8

Write-Host "Running database initialization..." -ForegroundColor Yellow

# Check if bcrypt is installed
Set-Location "server"
$packageJson = Get-Content "package.json" | ConvertFrom-Json
if (-not ($packageJson.dependencies.PSObject.Properties.Name -contains "bcrypt")) {
    Write-Host "Installing bcrypt..." -ForegroundColor Yellow
    npm install bcrypt --save | Out-Null
}
Set-Location ..

# Run initialization
node $nodeScriptPath

if ($LASTEXITCODE -eq 0) {
    Write-Host "`n✅ Database initialization completed!`n" -ForegroundColor Green
    Write-Host "Database: $dbPath" -ForegroundColor Cyan
    Write-Host "`nStart the server with:`n" -ForegroundColor Yellow
    Write-Host "  cd server" -ForegroundColor White
    Write-Host "  npm start`n" -ForegroundColor White
    Remove-Item $nodeScriptPath -ErrorAction SilentlyContinue
} else {
    Write-Host "`n❌ Initialization failed!`n" -ForegroundColor Red
    exit 1
}
