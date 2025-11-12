#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Complete setup script for HIMS (Hotel Inventory Management System)

.DESCRIPTION
    This script will:
    1. Clone the HIMS repository
    2. Install Flutter dependencies
    3. Install Node.js backend dependencies
    4. Initialize the database
    5. Optionally start both backend and frontend

.PARAMETER SkipClone
    Skip cloning if repository already exists

.PARAMETER RepoUrl
    GitHub repository URL (default: https://github.com/Syedmighty/Final_HIMS.git)

.PARAMETER Branch
    Branch to checkout (default: claude/initial-setup-011CV3nyDSqryfr3VpAaPiQP)

.PARAMETER InstallDir
    Directory where to install (default: current directory)

.PARAMETER StartServers
    Automatically start backend and frontend after setup

.EXAMPLE
    .\setup-hims.ps1
    Basic setup in current directory

.EXAMPLE
    .\setup-hims.ps1 -InstallDir "C:\Projects" -StartServers
    Install to specific directory and start servers
#>

param(
    [switch]$SkipClone = $false,
    [string]$RepoUrl = "https://github.com/Syedmighty/Final_HIMS.git",
    [string]$Branch = "claude/initial-setup-011CV3nyDSqryfr3VpAaPiQP",
    [string]$InstallDir = (Get-Location).Path,
    [switch]$StartServers = $false
)

# Color output functions
function Write-ColorOutput {
    param([string]$Message, [string]$Color = "White")
    Write-Host $Message -ForegroundColor $Color
}

function Write-Success { param([string]$Message) Write-ColorOutput "✓ $Message" "Green" }
function Write-Error { param([string]$Message) Write-ColorOutput "✗ $Message" "Red" }
function Write-Info { param([string]$Message) Write-ColorOutput "ℹ $Message" "Cyan" }
function Write-Warning { param([string]$Message) Write-ColorOutput "⚠ $Message" "Yellow" }
function Write-Step { param([string]$Message) Write-ColorOutput "`n▶ $Message" "Magenta" }

# Error handling
$ErrorActionPreference = "Stop"

# Banner
Write-Host ""
Write-ColorOutput "╔════════════════════════════════════════════════════════════╗" "Cyan"
Write-ColorOutput "║                                                            ║" "Cyan"
Write-ColorOutput "║        HIMS Setup Script - Hotel Inventory System          ║" "Cyan"
Write-ColorOutput "║                                                            ║" "Cyan"
Write-ColorOutput "╚════════════════════════════════════════════════════════════╝" "Cyan"
Write-Host ""

# Check prerequisites
Write-Step "Checking Prerequisites..."

# Check Git
try {
    $gitVersion = git --version
    Write-Success "Git is installed: $gitVersion"
} catch {
    Write-Error "Git is not installed. Please install Git from https://git-scm.com/"
    exit 1
}

# Check Node.js
try {
    $nodeVersion = node --version
    $npmVersion = npm --version
    Write-Success "Node.js is installed: $nodeVersion"
    Write-Success "npm is installed: v$npmVersion"
} catch {
    Write-Error "Node.js is not installed. Please install from https://nodejs.org/"
    exit 1
}

# Check Flutter
try {
    $flutterVersion = flutter --version | Select-Object -First 1
    Write-Success "Flutter is installed: $flutterVersion"
} catch {
    Write-Error "Flutter is not installed. Please install from https://flutter.dev/"
    exit 1
}

# Clone repository
if (-not $SkipClone) {
    Write-Step "Cloning Repository..."

    $projectPath = Join-Path $InstallDir "Final_HIMS"

    if (Test-Path $projectPath) {
        Write-Warning "Directory 'Final_HIMS' already exists at $projectPath"
        $response = Read-Host "Do you want to delete and re-clone? (y/N)"
        if ($response -eq 'y' -or $response -eq 'Y') {
            Write-Info "Removing existing directory..."
            Remove-Item -Path $projectPath -Recurse -Force
        } else {
            Write-Info "Using existing directory..."
            Set-Location $projectPath
            git pull origin $Branch
            $SkipClone = $true
        }
    }

    if (-not $SkipClone) {
        Write-Info "Cloning from $RepoUrl..."
        git clone $RepoUrl $projectPath
        Set-Location $projectPath
        Write-Success "Repository cloned successfully"
    }
} else {
    Write-Info "Skipping clone step..."
    $projectPath = Join-Path $InstallDir "Final_HIMS"
    Set-Location $projectPath
}

# Checkout branch
Write-Step "Checking out branch: $Branch..."
try {
    git checkout $Branch
    git pull origin $Branch
    Write-Success "Branch checked out successfully"
} catch {
    Write-Error "Failed to checkout branch: $_"
    exit 1
}

# Setup Flutter
Write-Step "Setting up Flutter Frontend..."

Set-Location "flutter"

Write-Info "Running flutter doctor..."
flutter doctor

Write-Info "Installing Flutter dependencies..."
flutter pub get

if ($LASTEXITCODE -eq 0) {
    Write-Success "Flutter dependencies installed successfully"
} else {
    Write-Error "Failed to install Flutter dependencies"
    exit 1
}

# Setup Node.js Backend
Write-Step "Setting up Node.js Backend..."

Set-Location "..\server"

Write-Info "Installing Node.js dependencies..."
npm install

if ($LASTEXITCODE -eq 0) {
    Write-Success "Node.js dependencies installed successfully"
} else {
    Write-Error "Failed to install Node.js dependencies"
    exit 1
}

# Check/Create database directory
Write-Step "Setting up Database..."

if (-not (Test-Path "database")) {
    Write-Info "Creating database directory..."
    New-Item -ItemType Directory -Path "database" | Out-Null
}

if (Test-Path "database\hims.db") {
    Write-Success "Database file exists"
} else {
    Write-Warning "Database file not found. It will be created on first server start."
}

# Create start scripts
Write-Step "Creating Helper Scripts..."

Set-Location ".."

# Create start-backend script
$startBackendScript = @"
#!/usr/bin/env pwsh
Write-Host "Starting HIMS Backend Server..." -ForegroundColor Cyan
Set-Location "server"
npm start
"@

$startBackendScript | Out-File -FilePath "start-backend.ps1" -Encoding UTF8
Write-Success "Created start-backend.ps1"

# Create start-frontend script
$startFrontendScript = @"
#!/usr/bin/env pwsh
Write-Host "Starting HIMS Flutter Frontend..." -ForegroundColor Cyan
Set-Location "flutter"

Write-Host "`nAvailable devices:" -ForegroundColor Yellow
flutter devices

Write-Host "`nStarting on Windows desktop..." -ForegroundColor Green
flutter run -d windows
"@

$startFrontendScript | Out-File -FilePath "start-frontend.ps1" -Encoding UTF8
Write-Success "Created start-frontend.ps1"

# Create start-all script
$startAllScript = @"
#!/usr/bin/env pwsh
Write-Host "Starting HIMS - Full Stack..." -ForegroundColor Cyan

# Start backend in new window
Write-Host "Starting backend server..." -ForegroundColor Yellow
Start-Process pwsh -ArgumentList "-NoExit", "-Command", "& '`$((Get-Location).Path)\start-backend.ps1'"

# Wait a bit for backend to start
Write-Host "Waiting for backend to initialize..." -ForegroundColor Yellow
Start-Sleep -Seconds 3

# Start frontend in new window
Write-Host "Starting frontend..." -ForegroundColor Yellow
Start-Process pwsh -ArgumentList "-NoExit", "-Command", "& '`$((Get-Location).Path)\start-frontend.ps1'"

Write-Host "`n✓ Both servers are starting in separate windows!" -ForegroundColor Green
Write-Host "Backend: http://localhost:3000" -ForegroundColor Cyan
Write-Host "Frontend: Will open automatically" -ForegroundColor Cyan
"@

$startAllScript | Out-File -FilePath "start-all.ps1" -Encoding UTF8
Write-Success "Created start-all.ps1"

# Create README for scripts
$readmeScript = @"
# HIMS Helper Scripts

## Available Scripts

### start-backend.ps1
Starts the Node.js backend server on port 3000

``````powershell
.\start-backend.ps1
``````

### start-frontend.ps1
Starts the Flutter frontend (Windows desktop by default)

``````powershell
.\start-frontend.ps1
``````

### start-all.ps1
Starts both backend and frontend in separate windows

``````powershell
.\start-all.ps1
``````

## Manual Commands

### Backend
``````powershell
cd server
npm start
``````

### Frontend
``````powershell
cd flutter
flutter run -d windows  # Windows
flutter run -d chrome   # Web
flutter run -d macos    # macOS
``````

## First Time Setup

The database will be automatically created on first backend start.
Default admin credentials will be shown in the backend console.
"@

$readmeScript | Out-File -FilePath "SCRIPTS_README.md" -Encoding UTF8
Write-Success "Created SCRIPTS_README.md"

# Summary
Write-Host ""
Write-ColorOutput "╔════════════════════════════════════════════════════════════╗" "Green"
Write-ColorOutput "║                                                            ║" "Green"
Write-ColorOutput "║              Setup Completed Successfully! ✓               ║" "Green"
Write-ColorOutput "║                                                            ║" "Green"
Write-ColorOutput "╚════════════════════════════════════════════════════════════╝" "Green"
Write-Host ""

Write-Info "Project Location: $((Get-Location).Path)"
Write-Host ""

Write-ColorOutput "Next Steps:" "Yellow"
Write-Host "  1. Start backend:  .\start-backend.ps1"
Write-Host "  2. Start frontend: .\start-frontend.ps1"
Write-Host "  3. Or start both:  .\start-all.ps1"
Write-Host ""

Write-ColorOutput "Useful Commands:" "Yellow"
Write-Host "  Backend:  cd server && npm start"
Write-Host "  Frontend: cd flutter && flutter run -d windows"
Write-Host ""

Write-ColorOutput "API Documentation:" "Yellow"
Write-Host "  View: docs\API_ENDPOINTS.md"
Write-Host "  Base URL: http://localhost:3000/api"
Write-Host ""

# Start servers if requested
if ($StartServers) {
    Write-Step "Starting Servers..."
    & ".\start-all.ps1"
} else {
    Write-Info "To start the application, run: .\start-all.ps1"
}

Write-Host ""
Write-Success "All done! Happy coding! 🚀"
Write-Host ""
