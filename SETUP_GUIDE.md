# HIMS Setup Guide

Complete guide for setting up the Hotel Inventory Management System on Windows.

## Prerequisites

Before running the setup scripts, ensure you have installed:

1. **Git** - [Download here](https://git-scm.com/downloads)
2. **Node.js (v16+)** - [Download here](https://nodejs.org/)
3. **Flutter SDK** - [Download here](https://flutter.dev/docs/get-started/install)

Verify installations:
```powershell
git --version
node --version
flutter --version
```

## Setup Options

### Option 1: Fresh Installation (Clone + Setup)

For first-time setup on a new machine:

```powershell
# Download the setup script
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/Syedmighty/Final_HIMS/claude/initial-setup-011CV3nyDSqryfr3VpAaPiQP/setup-hims.ps1" -OutFile "setup-hims.ps1"

# Run the script
.\setup-hims.ps1

# Or run and auto-start servers
.\setup-hims.ps1 -StartServers

# Or specify install directory
.\setup-hims.ps1 -InstallDir "C:\Projects" -StartServers
```

### Option 2: Already Cloned Repository

If you already have the repository cloned:

```powershell
cd C:\Users\syediqbal29\Desktop\Hims-browser\Final_HIMS

# Quick setup (just install dependencies)
.\quick-setup.ps1

# Or full setup without cloning
.\setup-hims.ps1 -SkipClone
```

### Option 3: Manual Setup

Step by step manual setup:

```powershell
# 1. Clone repository
git clone https://github.com/Syedmighty/Final_HIMS.git
cd Final_HIMS

# 2. Checkout the correct branch
git checkout claude/initial-setup-011CV3nyDSqryfr3VpAaPiQP

# 3. Setup Flutter
cd flutter
flutter pub get

# 4. Setup Backend
cd ..\server
npm install

# 5. You're ready!
```

## Running the Application

After setup, you have several helper scripts:

### Start Everything (Recommended)

```powershell
.\start-all.ps1
```

This opens two windows:
- Backend server on `http://localhost:3000`
- Flutter app (Windows desktop)

### Start Backend Only

```powershell
.\start-backend.ps1
```

### Start Frontend Only

```powershell
.\start-frontend.ps1
```

### Manual Start

**Backend:**
```powershell
cd server
npm start
```

**Frontend:**
```powershell
cd flutter

# Windows Desktop
flutter run -d windows

# Web Browser
flutter run -d chrome

# List all available devices
flutter devices
```

## Project Structure

```
Final_HIMS/
├── setup-hims.ps1          # Main setup script
├── quick-setup.ps1         # Quick dependency installer
├── start-all.ps1           # Start both backend + frontend
├── start-backend.ps1       # Start backend only
├── start-frontend.ps1      # Start frontend only
│
├── server/                 # Node.js Backend
│   ├── src/
│   │   ├── controllers/   # 11 business logic modules
│   │   ├── routes/        # API routes
│   │   └── middleware/    # Auth, validation
│   ├── database/          # SQLite database
│   └── package.json
│
├── flutter/               # Flutter Frontend
│   ├── lib/
│   │   ├── core/         # Theme, utils, widgets
│   │   ├── models/       # Data models
│   │   ├── services/     # API service
│   │   ├── controllers/  # Riverpod state management
│   │   ├── screens/      # UI screens
│   │   └── main.dart     # Entry point
│   └── pubspec.yaml
│
└── docs/
    ├── API_ENDPOINTS.md       # Complete API documentation (91 endpoints)
    └── PROGRESS_REPORT.md     # Development progress
```

## Features

### Backend (Node.js + Express + SQLite)
- ✅ 91 RESTful API endpoints
- ✅ 11 modules: Auth, Products, Purchases, Issues, Transfers, Invoices, Wastage, Locations, Recipes, Reports, Settings
- ✅ JWT authentication
- ✅ Role-based access control
- ✅ SQLite database with complete schema
- ✅ Transaction management
- ✅ Input validation

### Frontend (Flutter)
- ✅ Responsive design (mobile, tablet, desktop)
- ✅ Material Design 3 with Inter font
- ✅ Riverpod state management
- ✅ Offline-first with Drift
- ✅ Dashboard with live metrics
- ✅ Inventory management with filters
- ✅ Reports and analytics
- ✅ Settings and configuration

## Troubleshooting

### Port 3000 Already in Use

```powershell
# Find process using port 3000
netstat -ano | findstr :3000

# Kill process (replace PID with actual process ID)
taskkill /PID <PID> /F
```

### Flutter Doctor Issues

```powershell
flutter doctor -v
```

Follow the instructions to fix any issues.

### Database Errors

The database is auto-created on first run. If you encounter issues:

```powershell
cd server\database
# Backup old database
mv hims.db hims.db.backup
# Restart backend to recreate
cd ..
npm start
```

### Clean Reinstall

```powershell
# Flutter
cd flutter
flutter clean
flutter pub get

# Backend
cd ..\server
Remove-Item node_modules -Recurse -Force
npm install
```

## Default Configuration

- **Backend URL**: `http://localhost:3000`
- **API Base**: `http://localhost:3000/api`
- **Database**: `server/database/hims.db`
- **Default Port**: 3000

To change the port, edit `server/src/index.js`:
```javascript
const PORT = process.env.PORT || 3000;
```

## API Documentation

View complete API documentation:
```powershell
# Open in default editor
code docs\API_ENDPOINTS.md

# Or view in browser (if using VS Code)
code --diff docs\API_ENDPOINTS.md
```

91 endpoints across 11 modules with full request/response examples.

## Development

### Backend Development

```powershell
cd server

# Start with auto-reload (if nodemon is installed)
npm run dev

# Or use standard start
npm start
```

### Frontend Development

```powershell
cd flutter

# Run with hot reload
flutter run -d windows

# Build for production
flutter build windows
```

### Database Management

The SQLite database can be viewed using:
- [DB Browser for SQLite](https://sqlitebrowser.org/)
- VS Code extension: SQLite Viewer

## Support

For issues or questions:
1. Check the troubleshooting section above
2. Review `docs/API_ENDPOINTS.md` for API details
3. Check `docs/PROGRESS_REPORT.md` for implementation status

## Next Steps

After successful setup:

1. ✅ Start the backend: `.\start-backend.ps1`
2. ✅ Start the frontend: `.\start-frontend.ps1`
3. ✅ Access the API: `http://localhost:3000/api`
4. ✅ Login with default credentials (shown in backend console)
5. ✅ Explore the responsive Flutter UI

Happy coding! 🚀
