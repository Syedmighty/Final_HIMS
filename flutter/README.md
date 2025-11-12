# HIMS Flutter Frontend

Responsive Flutter frontend for the Hotel Inventory Management System.

## Features

- **Responsive Design**: Single codebase for Windows, macOS, Web, Android, and iOS
- **Adaptive Layouts**: Automatically switches between desktop, tablet, and mobile layouts
- **Offline-First**: Local database with sync capabilities using Drift
- **State Management**: Riverpod for predictable state management
- **Material Design 3**: Modern UI with Inter font family

## Architecture

```
lib/
├── core/
│   ├── theme/          # App colors, text styles, theme data
│   ├── utils/          # Responsive utilities
│   └── widgets/        # Reusable widgets
├── models/             # Data models
├── services/           # API service, sync service
├── controllers/        # Riverpod controllers
└── screens/            # UI screens
    ├── dashboard/
    ├── inventory/
    ├── reports/
    ├── settings/
    └── shared/
```

## Setup

### Prerequisites

- Flutter SDK 3.0.0 or higher
- Dart SDK 3.0.0 or higher

### Installation

1. Install dependencies:
```bash
cd flutter
flutter pub get
```

2. Run code generation (for Drift):
```bash
flutter pub run build_runner build
```

3. Run the app:
```bash
# Desktop (Windows/macOS/Linux)
flutter run -d windows
flutter run -d macos
flutter run -d linux

# Web
flutter run -d chrome

# Mobile (requires emulator/device)
flutter run -d android
flutter run -d ios
```

## Responsive Breakpoints

- **Mobile**: < 700px
- **Tablet**: 700px - 1100px
- **Desktop**: > 1100px

## API Configuration

The app connects to the HIMS backend at `http://localhost:3000/api`. To change the API URL, update the `_baseUrl` in `lib/services/api_service.dart`.

## State Management

This app uses Riverpod for state management. Controllers are located in `lib/controllers/` and follow the StateNotifier pattern.

## Code Generation

Run this command whenever you modify Drift database models:

```bash
flutter pub run build_runner build --delete-conflicting-outputs
```

## Building for Production

### Web
```bash
flutter build web
```

### Desktop
```bash
flutter build windows
flutter build macos
flutter build linux
```

### Mobile
```bash
flutter build apk           # Android APK
flutter build appbundle     # Android App Bundle
flutter build ios           # iOS
```

## Key Dependencies

- `flutter_riverpod`: State management
- `google_fonts`: Inter font family
- `http`: REST API client
- `intl`: Number and date formatting
- `drift`: Local SQLite database
- `drift_flutter`: Flutter integration for Drift

## Screens

### Dashboard
- Quick actions (Purchase, Issue, Invoice, Transfer)
- Key metrics (Sales, Stock value, Low stock alerts)
- Live alerts
- Recent transactions

### Inventory
- Product list with search and filters
- Stock status indicators
- Category filtering
- Responsive grid (desktop) and list (mobile)

### Reports
- Overview report
- Sales analytics (coming soon)
- Stock reports
- Low stock alerts

### Settings
- Company settings
- User management
- Appearance preferences
- Data sync options

## Contributing

Follow the existing code structure and patterns when adding new features.
