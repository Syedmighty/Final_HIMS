#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Quick setup for already cloned HIMS repository

.DESCRIPTION
    Use this if you already have the repository cloned.
    This script will just install dependencies and create helper scripts.
#>

Write-Host "`n🚀 HIMS Quick Setup`n" -ForegroundColor Cyan

# Navigate to script directory
Set-Location $PSScriptRoot

Write-Host "📦 Installing Flutter dependencies..." -ForegroundColor Yellow
Set-Location "flutter"
flutter pub get

Write-Host "`n📦 Installing Node.js dependencies..." -ForegroundColor Yellow
Set-Location "..\server"
npm install

Write-Host "`n✓ Setup complete!" -ForegroundColor Green
Write-Host "`nTo start the application:" -ForegroundColor Cyan
Write-Host "  cd .."
Write-Host "  .\setup-hims.ps1 -SkipClone -StartServers"
Write-Host "`nOr manually:"
Write-Host "  Backend:  cd server && npm start"
Write-Host "  Frontend: cd flutter && flutter run -d windows`n"
