#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Initialize HIMS SQLite database with schema

.DESCRIPTION
    Creates and initializes the HIMS database with all required tables,
    indexes, triggers, and initial data.
#>

Write-Host "`n🗄️  HIMS Database Initialization`n" -ForegroundColor Cyan

# Navigate to project root
$projectRoot = Split-Path -Parent $PSScriptRoot
Set-Location $projectRoot

Write-Host "Project root: $projectRoot" -ForegroundColor Gray

# Check if better-sqlite3 CLI is available via Node
$dbPath = Join-Path $projectRoot "database" "hims.db"
$sqlDir = Join-Path $projectRoot "sql"

# Ensure database directory exists
$dbDir = Split-Path -Parent $dbPath
if (-not (Test-Path $dbDir)) {
    New-Item -ItemType Directory -Path $dbDir | Out-Null
    Write-Host "✓ Created database directory" -ForegroundColor Green
}

# Backup existing database if it exists
if (Test-Path $dbPath) {
    $backupPath = Join-Path $dbDir "hims_backup_$(Get-Date -Format 'yyyyMMdd_HHmmss').db"
    Copy-Item $dbPath $backupPath
    Write-Host "✓ Backed up existing database to: $backupPath" -ForegroundColor Yellow
    Remove-Item $dbPath
}

Write-Host "✓ Creating new database: $dbPath" -ForegroundColor Green

# Create database initialization Node script
$initScript = @"
const Database = require('better-sqlite3');
const fs = require('fs');
const path = require('path');

const dbPath = path.join(__dirname, 'database', 'hims.db');
const sqlDir = path.join(__dirname, 'sql');

console.log('Creating database:', dbPath);

const db = new Database(dbPath);

// Configure database
db.pragma('journal_mode = WAL');
db.pragma('foreign_keys = ON');

console.log('Running schema migrations...');

// Read and execute SQL files in order
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

      // Split by semicolon and execute each statement
      const statements = sql.split(';').filter(s => s.trim().length > 0);

      for (const statement of statements) {
        try {
          db.exec(statement);
        } catch (err) {
          // Ignore "already exists" errors
          if (!err.message.includes('already exists')) {
            console.warn('    Warning:', err.message);
          }
        }
      }
    } else {
      console.warn('  File not found:', file);
    }
  }

  // Create schema_migrations table if it doesn't exist
  db.exec(\`
    CREATE TABLE IF NOT EXISTS schema_migrations (
      version TEXT PRIMARY KEY,
      applied_at DATETIME DEFAULT CURRENT_TIMESTAMP,
      description TEXT
    );
  \`);

  // Insert migration records
  const insertMigration = db.prepare(\`
    INSERT OR IGNORE INTO schema_migrations (version, description)
    VALUES (?, ?)
  \`);

  insertMigration.run('1.0.0', 'Initial schema');
  insertMigration.run('1.0.1', 'Device and sync hardening');

  // Insert default admin user if not exists
  const userCheck = db.prepare('SELECT COUNT(*) as count FROM users').get();

  if (userCheck.count === 0) {
    console.log('Creating default admin user...');

    // Default password: admin123 (should be changed after first login)
    const bcrypt = require('bcrypt');
    const defaultPassword = bcrypt.hashSync('admin123', 10);

    db.prepare(\`
      INSERT INTO users (username, email, password_hash, full_name, role, is_active)
      VALUES (?, ?, ?, ?, ?, ?)
    \`).run('admin', 'admin@hims.local', defaultPassword, 'System Administrator', 'admin', 1);

    console.log('✓ Default admin user created');
    console.log('  Username: admin');
    console.log('  Password: admin123');
    console.log('  ⚠️  Please change this password after first login!');
  }

  // Verify tables
  const tables = db.prepare(\`
    SELECT name FROM sqlite_master
    WHERE type='table' AND name NOT LIKE 'sqlite_%'
    ORDER BY name
  \`).all();

  console.log(\`\n✅ Database initialized successfully with \${tables.length} tables:\`);
  tables.forEach(t => console.log('  -', t.name));

  db.close();
  process.exit(0);

} catch (error) {
  console.error('❌ Database initialization failed:', error.message);
  console.error(error.stack);
  process.exit(1);
}
"@

# Save init script
$initScriptPath = Join-Path $projectRoot "init-database.js"
$initScript | Out-File -FilePath $initScriptPath -Encoding UTF8

Write-Host "Running database initialization..." -ForegroundColor Yellow

# Check if bcrypt is installed
$serverDir = Join-Path $projectRoot "server"
Set-Location $serverDir

$packageJson = Get-Content "package.json" | ConvertFrom-Json
if (-not $packageJson.dependencies.bcrypt -and -not $packageJson.dependencies.bcryptjs) {
    Write-Host "Installing bcrypt for password hashing..." -ForegroundColor Yellow
    npm install bcrypt --save
}

Set-Location $projectRoot

# Run the initialization
node $initScriptPath

if ($LASTEXITCODE -eq 0) {
    Write-Host "`n✅ Database initialization completed successfully!`n" -ForegroundColor Green
    Write-Host "Database location: $dbPath" -ForegroundColor Cyan
    Write-Host "`nYou can now start the backend server:`n" -ForegroundColor Yellow
    Write-Host "  cd server" -ForegroundColor White
    Write-Host "  npm start`n" -ForegroundColor White

    # Clean up init script
    Remove-Item $initScriptPath
} else {
    Write-Host "`n❌ Database initialization failed!`n" -ForegroundColor Red
    Write-Host "Check the error messages above for details.`n" -ForegroundColor Yellow
    exit 1
}
