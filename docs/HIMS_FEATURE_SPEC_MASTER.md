# HIMS - Hotel Inventory Management System
## Complete Feature Specification & Implementation Blueprint

**Version:** 2.0.0
**Last Updated:** 2025-11-12
**Status:** Production-Ready Specification
**Document Owner:** Technical Architecture Team

---

## Document Control

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0.0 | 2025-11-11 | System | Initial database design |
| 1.0.1 | 2025-11-12 | System | Production hardening fixes |
| 2.0.0 | 2025-11-12 | System | Device management + Complete spec |

**Approvals:**

| Role | Name | Signature | Date |
|------|------|-----------|------|
| Product Owner | [To be filled] | _________ | _____ |
| Tech Lead | [To be filled] | _________ | _____ |
| Security Officer | [To be filled] | _________ | _____ |

---

## Table of Contents

1. [System Overview](#1-system-overview)
2. [Frontend (Flutter) Architecture](#2-frontend-flutter-architecture)
3. [Backend (Node.js Sync Server)](#3-backend-nodejs-sync-server)
4. [Database Design (v1.0.1 Hardened)](#4-database-design-v101-hardened)
5. [Core Modules](#5-core-modules)
6. [Device Management & Licensing](#6-device-management--licensing)
7. [Error Handling & Recovery](#7-error-handling--recovery)
8. [Security Model](#8-security-model)
9. [UI/UX Design](#9-uiux-design)
10. [Testing & Deployment](#10-testing--deployment)

---

# 1. System Overview

## 1.1 Purpose

HIMS (Hotel Inventory Management System) is a comprehensive, **offline-first** inventory and invoicing solution designed specifically for hotels, restaurants, and hospitality businesses.

**Primary Goals:**
- Track inventory across multiple locations (stores, kitchens, bars)
- Manage purchases from suppliers with GST compliance
- Issue stock to departments with automated accounting
- Generate invoices (cash/credit) with inventory deduction
- Calculate recipe costs and profit margins
- Produce daily/monthly reports
- Synchronize data across devices via LAN (no internet required)

**Key Differentiators:**
- ✅ **100% Offline Operation** - Works without internet
- ✅ **Multi-Device LAN Sync** - Centralized PC + mobile devices
- ✅ **Zero Data Loss** - All operations logged and auditable
- ✅ **Recipe Costing** - Ingredient-level profit analysis
- ✅ **GST Compliant** - Indian tax regulations built-in
- ✅ **Device Limit Enforcement** - License tier management

---

## 1.2 Offline-First Architecture

```
┌────────────────────────────────────────────────────────────────┐
│                    OFFLINE-FIRST DESIGN                         │
└────────────────────────────────────────────────────────────────┘

Every Device = Complete Database Copy (SQLite)
    ↓
All Operations Execute Locally (Instant Response)
    ↓
Changes Logged to sync_queue Table
    ↓
Periodic Sync to Central Server (LAN Only)
    ↓
Conflict Resolution via last_modified Timestamps
    ↓
Bi-Directional Data Flow (Push + Pull)

┌─────────────────────────────────────────────────────────────────┐
│  Master PC (Central Node.js + SQLite)                           │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  Full Database + Sync Service                            │  │
│  │  - Receives changes from all devices                     │  │
│  │  - Sends updates to all devices                          │  │
│  │  - Resolves conflicts                                    │  │
│  │  - Enforces device limits                                │  │
│  └──────────────────────────────────────────────────────────┘  │
└────────────────────────┬───────────────────────────────────────┘
                         │ LAN Network (192.168.x.x)
          ┌──────────────┼──────────────┬─────────────┐
          │              │              │             │
      Mobile 1       Mobile 2      Tablet        Windows PC
      (Store)        (Kitchen)      (Bar)         (Office)
       SQLite         SQLite        SQLite        SQLite
       ↓ sync         ↓ sync        ↓ sync       ↓ sync
       Local          Local         Local        Local
       Operations     Operations    Operations   Operations
```

---

## 1.3 Core Principles

### Principle 1: Data Consistency
**Rule:** Every write operation MUST update `last_modified` timestamp.

```dart
// ✅ CORRECT
await db.update(products).replace(
  product.copyWith(
    name: newName,
    lastModified: DateTime.now(), // Required!
  ),
);

// ❌ WRONG - Will break sync
await db.update(products).replace(
  product.copyWith(name: newName),
);
```

**Why:** Sync relies on `last_modified` to detect changes and resolve conflicts.

---

### Principle 2: Responsiveness
**Rule:** UI must respond within 100ms for all operations.

**How:**
- All database operations are local (SQLite)
- Heavy computations run in background isolates
- UI updates optimistically (assume success, rollback on error)
- Sync happens asynchronously

```dart
// Example: Optimistic UI Update
Future<void> createPurchase(Purchase purchase) async {
  // 1. Update UI immediately
  state = state.copyWith(
    purchases: [...state.purchases, purchase],
    isLoading: false,
  );

  try {
    // 2. Save to local database
    await db.into(db.purchases).insert(purchase);

    // 3. Queue for sync (async, non-blocking)
    await syncQueue.add(SyncOperation(
      table: 'purchases',
      uuid: purchase.uuid,
      operation: 'insert',
    ));
  } catch (e) {
    // 4. Rollback UI on error
    state = state.copyWith(
      purchases: state.purchases.where((p) => p.uuid != purchase.uuid).toList(),
      error: e.toString(),
    );
  }
}
```

---

### Principle 3: Sync-First Logic
**Rule:** Design every feature assuming sync will happen.

**Checklist:**
- [ ] Does this operation update `last_modified`?
- [ ] Is this operation idempotent (safe to replay)?
- [ ] Can this operation be reversed if sync fails?
- [ ] Does this operation have a conflict resolution strategy?
- [ ] Is this operation atomic (all-or-nothing)?

**Example: Purchase Approval**

```sql
-- ✅ CORRECT - Idempotent, reversible, conflict-safe
UPDATE purchases
SET
  status = 'received',
  approved_by = ?,
  approved_at = datetime('now'),
  last_modified = datetime('now')  -- Sync dependency
WHERE uuid = ?
AND status != 'received';  -- Idempotent: won't re-approve

-- Trigger will update stock_levels (logged in stock_adjustments for rollback)
```

---

## 1.4 Technology Stack

| Layer | Technology | Version | Purpose |
|-------|-----------|---------|---------|
| **Mobile/Desktop** | Flutter | 3.16+ | Cross-platform UI |
| **State Management** | Riverpod | 2.4+ | Reactive state |
| **Local Database** | SQLite | 3.35+ | Offline storage |
| **ORM** | Drift | 2.14+ | Type-safe DB access |
| **Sync Server** | Node.js | 20+ LTS | Central coordinator |
| **DB Driver (Node)** | better-sqlite3 | 9.2+ | Fast SQLite |
| **HTTP Client** | Dio | 5.4+ | Network requests |
| **PDF Generation** | pdf | 3.10+ | Invoice PDFs |
| **Charts** | fl_chart | 0.66+ | Analytics |

**Supported Platforms:**
- ✅ Android 6.0+ (API 23+)
- ✅ iOS 12+
- ✅ Windows 10+
- ✅ Web (Chrome, Edge, Firefox)
- ✅ macOS 10.14+
- ✅ Linux (Ubuntu 20.04+)

---

## 1.5 System Requirements

### Minimum Hardware

**Master PC (Central Server):**
- CPU: Dual-core 2.0 GHz+
- RAM: 4 GB
- Storage: 50 GB available
- Network: 100 Mbps LAN

**Client Devices:**
- Mobile: Android 6.0+ / iOS 12+, 2GB RAM
- Tablet: 7" screen, 2GB RAM
- Desktop: Windows 10+, 4GB RAM

### Network Requirements

- **LAN:** 100 Mbps minimum
- **Router:** Support for static IP assignment
- **Latency:** <10ms within LAN
- **Internet:** NOT required (LAN-only operation)

---

# 2. Frontend (Flutter) Architecture

## 2.1 Project Structure

```
lib/
├── main.dart                      # App entry point
├── app.dart                       # MaterialApp config
│
├── core/                          # Core utilities
│   ├── constants/
│   │   ├── app_constants.dart     # Global constants
│   │   ├── database_constants.dart
│   │   └── api_constants.dart
│   ├── theme/
│   │   ├── app_theme.dart         # Material theme
│   │   ├── colors.dart
│   │   └── text_styles.dart
│   ├── utils/
│   │   ├── date_utils.dart
│   │   ├── currency_utils.dart
│   │   └── validators.dart
│   ├── errors/
│   │   ├── app_exception.dart
│   │   └── error_handler.dart
│   └── network/
│       ├── dio_client.dart
│       └── network_info.dart
│
├── data/                          # Data layer
│   ├── database/
│   │   ├── database.dart          # Drift database
│   │   ├── tables/                # Table definitions
│   │   │   ├── products_table.dart
│   │   │   ├── purchases_table.dart
│   │   │   └── ...
│   │   ├── daos/                  # Data Access Objects
│   │   │   ├── products_dao.dart
│   │   │   ├── purchases_dao.dart
│   │   │   └── ...
│   │   └── migrations/
│   │       └── migration_v1_to_v2.dart
│   ├── repositories/              # Repository pattern
│   │   ├── product_repository.dart
│   │   ├── purchase_repository.dart
│   │   └── sync_repository.dart
│   ├── models/                    # Data models
│   │   ├── product.dart
│   │   ├── purchase.dart
│   │   └── ...
│   └── services/
│       ├── sync_service.dart
│       ├── device_service.dart
│       └── pdf_service.dart
│
├── domain/                        # Business logic
│   ├── entities/
│   │   ├── product_entity.dart
│   │   └── ...
│   ├── usecases/
│   │   ├── create_purchase_usecase.dart
│   │   ├── approve_purchase_usecase.dart
│   │   └── ...
│   └── validators/
│       ├── purchase_validator.dart
│       └── invoice_validator.dart
│
├── presentation/                  # UI layer
│   ├── providers/                 # Riverpod providers
│   │   ├── product_provider.dart
│   │   ├── purchase_provider.dart
│   │   └── auth_provider.dart
│   ├── screens/
│   │   ├── dashboard/
│   │   │   ├── dashboard_screen.dart
│   │   │   └── widgets/
│   │   ├── inventory/
│   │   │   ├── products_screen.dart
│   │   │   ├── add_product_screen.dart
│   │   │   └── widgets/
│   │   ├── purchases/
│   │   ├── issues/
│   │   ├── invoices/
│   │   ├── reports/
│   │   ├── settings/
│   │   └── auth/
│   ├── widgets/                   # Shared widgets
│   │   ├── common/
│   │   │   ├── responsive_scaffold.dart
│   │   │   ├── data_table_widget.dart
│   │   │   ├── dashboard_card.dart
│   │   │   └── loading_overlay.dart
│   │   ├── forms/
│   │   │   ├── custom_text_field.dart
│   │   │   ├── dropdown_field.dart
│   │   │   └── date_picker_field.dart
│   │   └── dialogs/
│   │       ├── confirm_dialog.dart
│   │       └── error_dialog.dart
│   └── routes/
│       └── app_router.dart        # Navigation
│
└── generated/                     # Auto-generated
    └── database.g.dart            # Drift generated code
```

---

## 2.2 State Management (Riverpod)

### Provider Structure

```dart
// Example: Products Provider Hierarchy

// 1. Database Provider (Global)
final databaseProvider = Provider<AppDatabase>((ref) {
  return AppDatabase();
});

// 2. DAO Provider
final productsDAOProvider = Provider<ProductsDAO>((ref) {
  final db = ref.watch(databaseProvider);
  return db.productsDAO;
});

// 3. Repository Provider
final productsRepositoryProvider = Provider<ProductRepository>((ref) {
  final dao = ref.watch(productsDAOProvider);
  return ProductRepository(dao);
});

// 4. State Notifier Provider (Business Logic)
final productsProvider = StateNotifierProvider<ProductsNotifier, ProductsState>((ref) {
  final repository = ref.watch(productsRepositoryProvider);
  return ProductsNotifier(repository);
});

// 5. UI consumes via Consumer
class ProductsScreen extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final productsState = ref.watch(productsProvider);

    return productsState.when(
      data: (products) => ProductsList(products),
      loading: () => LoadingWidget(),
      error: (error, stack) => ErrorWidget(error),
    );
  }
}
```

### State Classes

```dart
// Sealed state class for type-safe states
@freezed
class ProductsState with _$ProductsState {
  const factory ProductsState.initial() = _Initial;
  const factory ProductsState.loading() = _Loading;
  const factory ProductsState.loaded(List<Product> products) = _Loaded;
  const factory ProductsState.error(String message) = _Error;
}

// State Notifier
class ProductsNotifier extends StateNotifier<ProductsState> {
  final ProductRepository _repository;

  ProductsNotifier(this._repository) : super(const ProductsState.initial()) {
    loadProducts();
  }

  Future<void> loadProducts() async {
    state = const ProductsState.loading();
    try {
      final products = await _repository.getAllProducts();
      state = ProductsState.loaded(products);
    } catch (e) {
      state = ProductsState.error(e.toString());
    }
  }

  Future<void> createProduct(Product product) async {
    try {
      await _repository.insert(product);
      await loadProducts(); // Reload list
    } catch (e) {
      state = ProductsState.error(e.toString());
    }
  }

  Future<void> updateProduct(Product product) async {
    try {
      await _repository.update(product);
      await loadProducts();
    } catch (e) {
      state = ProductsState.error(e.toString());
    }
  }

  Future<void> deleteProduct(String uuid) async {
    try {
      await _repository.delete(uuid);
      await loadProducts();
    } catch (e) {
      state = ProductsState.error(e.toString());
    }
  }
}
```

---

## 2.3 Database Integration (Drift)

### Table Definition

```dart
// data/database/tables/products_table.dart
@DataClassName('Product')
class Products extends Table {
  // Primary key
  IntColumn get id => integer().autoIncrement()();

  // UUID for sync
  TextColumn get uuid => text().withLength(min: 36, max: 36)
      .customConstraint('UNIQUE NOT NULL DEFAULT (hex(randomblob(16)))')();

  // Core fields
  TextColumn get name => text().withLength(max: 255)();
  TextColumn get sku => text().withLength(max: 50).nullable()();
  IntColumn get categoryId => integer().nullable()
      .references(Categories, #id, onDelete: KeyAction.setNull)();
  IntColumn get defaultUnitId => integer()
      .references(Units, #id, onDelete: KeyAction.restrict)();
  IntColumn get baseUnitId => integer()
      .references(Units, #id, onDelete: KeyAction.restrict)();

  // Inventory
  RealColumn get reorderLevel => real().withDefault(const Constant(0))();
  RealColumn get reorderQuantity => real().withDefault(const Constant(0))();

  // GST
  TextColumn get hsnCode => text().withLength(max: 20).nullable()();
  RealColumn get taxRate => real().withDefault(const Constant(0))();

  // Status
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();

  // Audit
  DateTimeColumn get createdAt => dateTime()
      .withDefault(Constant(DateTime.now()))();
  DateTimeColumn get lastModified => dateTime()
      .withDefault(Constant(DateTime.now()))();
  TextColumn get createdBy => text().nullable()();
  TextColumn get modifiedBy => text().nullable()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  TextColumn get deletedBy => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
    'CHECK (reorder_level >= 0)',
    'CHECK (reorder_quantity >= 0)',
    'CHECK (tax_rate >= 0 AND tax_rate <= 100)',
  ];
}
```

### DAO (Data Access Object)

```dart
// data/database/daos/products_dao.dart
@DriftAccessor(tables: [Products, Categories, Units])
class ProductsDAO extends DatabaseAccessor<AppDatabase> with _$ProductsDAOMixin {
  ProductsDAO(AppDatabase db) : super(db);

  // Get all active products with joins
  Future<List<ProductWithDetails>> getAllProductsWithDetails() {
    final query = select(products)
      ..where((p) => p.isActive.equals(true))
      ..orderBy([(p) => OrderingTerm.asc(p.name)]);

    return query.join([
      leftOuterJoin(categories, categories.id.equalsExp(products.categoryId)),
      innerJoin(units, units.id.equalsExp(products.defaultUnitId)),
    ]).map((row) {
      return ProductWithDetails(
        product: row.readTable(products),
        category: row.readTableOrNull(categories),
        unit: row.readTable(units),
      );
    }).get();
  }

  // Get single product by UUID
  Future<Product?> getProductByUuid(String uuid) {
    return (select(products)..where((p) => p.uuid.equals(uuid))).getSingleOrNull();
  }

  // Create product
  Future<int> createProduct(ProductsCompanion product) {
    return into(products).insert(product.copyWith(
      lastModified: Value(DateTime.now()), // ✅ Always set!
    ));
  }

  // Update product
  Future<bool> updateProduct(Product product) {
    return update(products).replace(product.copyWith(
      lastModified: DateTime.now(), // ✅ Critical for sync!
    ));
  }

  // Soft delete
  Future<int> softDeleteProduct(String uuid, String deletedBy) {
    return (update(products)..where((p) => p.uuid.equals(uuid))).write(
      ProductsCompanion(
        isActive: const Value(false),
        deletedAt: Value(DateTime.now()),
        deletedBy: Value(deletedBy),
        lastModified: Value(DateTime.now()),
      ),
    );
  }

  // Search products
  Stream<List<Product>> searchProducts(String query) {
    return (select(products)
      ..where((p) => p.name.contains(query) | p.sku.contains(query))
      ..where((p) => p.isActive.equals(true))
      ..orderBy([(p) => OrderingTerm.asc(p.name)]))
      .watch();
  }

  // Get low stock products
  Stream<List<ProductWithStock>> getLowStockProducts() {
    // This would join with stock_levels table
    // Complex query - implement based on need
    throw UnimplementedError('Implement with stock_levels join');
  }
}

// Helper class for joined data
class ProductWithDetails {
  final Product product;
  final Category? category;
  final Unit unit;

  ProductWithDetails({
    required this.product,
    this.category,
    required this.unit,
  });
}
```

---

## 2.4 Responsive UI System

### Breakpoints

```dart
// core/theme/breakpoints.dart
class Breakpoints {
  static const double mobile = 600;
  static const double tablet = 900;
  static const double desktop = 1200;
  static const double wide = 1600;

  static bool isMobile(BuildContext context) {
    return MediaQuery.of(context).size.width < mobile;
  }

  static bool isTablet(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    return width >= mobile && width < desktop;
  }

  static bool isDesktop(BuildContext context) {
    return MediaQuery.of(context).size.width >= desktop;
  }

  static bool isWide(BuildContext context) {
    return MediaQuery.of(context).size.width >= wide;
  }

  static int getGridColumns(BuildContext context) {
    if (isWide(context)) return 4;
    if (isDesktop(context)) return 3;
    if (isTablet(context)) return 2;
    return 1;
  }
}
```

### Responsive Scaffold

```dart
// presentation/widgets/common/responsive_scaffold.dart
class ResponsiveScaffold extends StatelessWidget {
  final String title;
  final Widget body;
  final Widget? floatingActionButton;
  final List<Widget>? actions;

  const ResponsiveScaffold({
    required this.title,
    required this.body,
    this.floatingActionButton,
    this.actions,
  });

  @override
  Widget build(BuildContext context) {
    if (Breakpoints.isMobile(context)) {
      // Mobile: Full-screen with app bar
      return Scaffold(
        appBar: AppBar(
          title: Text(title),
          actions: actions,
        ),
        body: body,
        floatingActionButton: floatingActionButton,
        drawer: const AppDrawer(),
      );
    } else {
      // Desktop/Tablet: Sidebar + topbar
      return Scaffold(
        body: Row(
          children: [
            // Permanent sidebar on desktop
            if (!Breakpoints.isTablet(context))
              const SizedBox(
                width: 250,
                child: AppSidebar(),
              ),

            // Main content area
            Expanded(
              child: Column(
                children: [
                  // Top bar
                  Container(
                    height: 64,
                    decoration: BoxDecoration(
                      color: Theme.of(context).cardColor,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        if (Breakpoints.isTablet(context))
                          IconButton(
                            icon: const Icon(Icons.menu),
                            onPressed: () {
                              Scaffold.of(context).openDrawer();
                            },
                          ),
                        const SizedBox(width: 16),
                        Text(
                          title,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const Spacer(),
                        if (actions != null) ...actions!,
                      ],
                    ),
                  ),

                  // Body
                  Expanded(child: body),
                ],
              ),
            ),
          ],
        ),
        floatingActionButton: floatingActionButton,
        drawer: Breakpoints.isTablet(context) ? const AppDrawer() : null,
      );
    }
  }
}
```

---

## 2.5 Error Handling

### Exception Hierarchy

```dart
// core/errors/app_exception.dart
abstract class AppException implements Exception {
  final String message;
  final String? code;
  final dynamic details;

  AppException(this.message, {this.code, this.details});

  @override
  String toString() => 'AppException: $message${code != null ? ' ($code)' : ''}';
}

class DatabaseException extends AppException {
  DatabaseException(super.message, {super.code, super.details});
}

class NetworkException extends AppException {
  NetworkException(super.message, {super.code, super.details});
}

class ValidationException extends AppException {
  final Map<String, String> fieldErrors;

  ValidationException(super.message, this.fieldErrors, {super.code})
      : super(details: fieldErrors);
}

class SyncException extends AppException {
  SyncException(super.message, {super.code, super.details});
}

class AuthException extends AppException {
  AuthException(super.message, {super.code, super.details});
}

class DeviceLimitException extends AppException {
  final int maxAllowed;
  final int currentActive;

  DeviceLimitException(super.message, this.maxAllowed, this.currentActive)
      : super(details: {'max_allowed': maxAllowed, 'current_active': currentActive});
}
```

### Error Handler

```dart
// core/errors/error_handler.dart
class ErrorHandler {
  static String getUserMessage(dynamic error) {
    if (error is ValidationException) {
      return 'Validation error: ${error.fieldErrors.values.join(', ')}';
    } else if (error is DatabaseException) {
      if (error.message.contains('UNIQUE constraint')) {
        return 'This record already exists';
      } else if (error.message.contains('FOREIGN KEY constraint')) {
        return 'Cannot delete: record is in use';
      } else if (error.message.contains('Insufficient stock')) {
        return 'Insufficient stock for this operation';
      }
      return 'Database error: ${error.message}';
    } else if (error is NetworkException) {
      return 'Network error: Please check your connection';
    } else if (error is SyncException) {
      return 'Sync failed: ${error.message}';
    } else if (error is DeviceLimitException) {
      return 'Maximum ${error.maxAllowed} devices allowed. ${error.currentActive} currently active.';
    } else if (error is AuthException) {
      return 'Authentication error: ${error.message}';
    } else {
      return 'An unexpected error occurred: $error';
    }
  }

  static void showErrorDialog(BuildContext context, dynamic error) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Error'),
        content: Text(getUserMessage(error)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  static void showErrorSnackBar(BuildContext context, dynamic error) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(getUserMessage(error)),
        backgroundColor: Colors.red,
        action: SnackBarAction(
          label: 'Dismiss',
          textColor: Colors.white,
          onPressed: () {
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
          },
        ),
      ),
    );
  }

  static Future<void> logError(dynamic error, StackTrace? stack) async {
    // Log to file or remote service
    print('ERROR: $error');
    if (stack != null) {
      print('STACK: $stack');
    }

    // TODO: Send to crash reporting service (e.g., Sentry, Crashlytics)
  }
}
```

---

## 2.6 Local Caching Strategy

### Cache Implementation

```dart
// data/services/cache_service.dart
class CacheService {
  static const String _cacheBox = 'app_cache';
  static final _prefs = SharedPreferences.getInstance();

  // Cache with TTL
  static Future<void> set<T>(String key, T value, {Duration? ttl}) async {
    final prefs = await _prefs;
    final cacheEntry = CacheEntry(
      value: jsonEncode(value),
      cachedAt: DateTime.now(),
      expiresAt: ttl != null ? DateTime.now().add(ttl) : null,
    );

    await prefs.setString(key, jsonEncode(cacheEntry.toJson()));
  }

  // Get cached value
  static Future<T?> get<T>(String key, {T Function(Map<String, dynamic>)? fromJson}) async {
    final prefs = await _prefs;
    final cached = prefs.getString(key);

    if (cached == null) return null;

    try {
      final cacheEntry = CacheEntry.fromJson(jsonDecode(cached));

      // Check expiration
      if (cacheEntry.expiresAt != null && DateTime.now().isAfter(cacheEntry.expiresAt!)) {
        await remove(key);
        return null;
      }

      final value = jsonDecode(cacheEntry.value);
      return fromJson != null ? fromJson(value) : value as T;
    } catch (e) {
      await remove(key);
      return null;
    }
  }

  // Remove cache
  static Future<void> remove(String key) async {
    final prefs = await _prefs;
    await prefs.remove(key);
  }

  // Clear all cache
  static Future<void> clearAll() async {
    final prefs = await _prefs;
    await prefs.clear();
  }
}

class CacheEntry {
  final String value;
  final DateTime cachedAt;
  final DateTime? expiresAt;

  CacheEntry({
    required this.value,
    required this.cachedAt,
    this.expiresAt,
  });

  Map<String, dynamic> toJson() => {
    'value': value,
    'cachedAt': cachedAt.toIso8601String(),
    'expiresAt': expiresAt?.toIso8601String(),
  };

  factory CacheEntry.fromJson(Map<String, dynamic> json) => CacheEntry(
    value: json['value'],
    cachedAt: DateTime.parse(json['cachedAt']),
    expiresAt: json['expiresAt'] != null ? DateTime.parse(json['expiresAt']) : null,
  );
}
```

**Usage Example:**

```dart
// Cache dashboard stats for 5 minutes
await CacheService.set('dashboard_stats', stats, ttl: const Duration(minutes: 5));

// Retrieve cached stats
final cachedStats = await CacheService.get<DashboardStats>(
  'dashboard_stats',
  fromJson: DashboardStats.fromJson,
);

if (cachedStats != null) {
  // Use cached data
  return cachedStats;
} else {
  // Fetch fresh data
  final freshStats = await fetchDashboardStats();
  await CacheService.set('dashboard_stats', freshStats, ttl: const Duration(minutes: 5));
  return freshStats;
}
```

---

## 2.7 Theme System

### App Theme

```dart
// core/theme/app_theme.dart
class AppTheme {
  static ThemeData get lightTheme => ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: Brightness.light,
    ),
    appBarTheme: const AppBarTheme(
      centerTitle: false,
      elevation: 0,
      scrolledUnderElevation: 2,
    ),
    cardTheme: CardTheme(
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    ),
    dataTableTheme: DataTableThemeData(
      headingRowColor: MaterialStateProperty.all(AppColors.primary.withOpacity(0.1)),
      dataRowColor: MaterialStateProperty.resolveWith((states) {
        if (states.contains(MaterialState.selected)) {
          return AppColors.primary.withOpacity(0.2);
        }
        return null;
      }),
    ),
  );

  static ThemeData get darkTheme => ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: Brightness.dark,
    ),
    // Similar configuration for dark mode
  );
}

// core/theme/colors.dart
class AppColors {
  static const Color primary = Color(0xFF1976D2); // Blue
  static const Color secondary = Color(0xFFFFA726); // Orange
  static const Color success = Color(0xFF4CAF50); // Green
  static const Color error = Color(0xFFF44336); // Red
  static const Color warning = Color(0xFFFF9800); // Amber
  static const Color info = Color(0xFF2196F3); // Light Blue

  // Status colors
  static const Color statusActive = success;
  static const Color statusPending = warning;
  static const Color statusBlocked = error;
  static const Color statusInactive = Color(0xFF9E9E9E); // Grey

  // Chart colors
  static const List<Color> chartColors = [
    Color(0xFF1976D2),
    Color(0xFFFFA726),
    Color(0xFF4CAF50),
    Color(0xFFE91E63),
    Color(0xFF9C27B0),
    Color(0xFF00BCD4),
  ];
}
```

---

# 3. Backend (Node.js Sync Server)

## 3.1 Server Architecture

```
┌─────────────────────────────────────────────────────────────┐
│              Node.js Sync Server (Master PC)                │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌─────────────────────────────────────────────────────┐  │
│  │           Express.js REST API Layer                  │  │
│  ├─────────────────────────────────────────────────────┤  │
│  │  /api/auth/*         - JWT authentication           │  │
│  │  /api/devices/*      - Device registration/mgmt     │  │
│  │  /api/sync/*         - Sync push/pull endpoints     │  │
│  │  /api/health         - Health check                 │  │
│  └─────────────────────────────────────────────────────┘  │
│                         ↓                                   │
│  ┌─────────────────────────────────────────────────────┐  │
│  │         Business Logic / Sync Manager               │  │
│  ├─────────────────────────────────────────────────────┤  │
│  │  - Conflict resolution (last-write-wins)            │  │
│  │  - Device limit enforcement                         │  │
│  │  - Rate limiting (5min minimum sync interval)       │  │
│  │  - JSON validation                                  │  │
│  │  - Transaction management                           │  │
│  └─────────────────────────────────────────────────────┘  │
│                         ↓                                   │
│  ┌─────────────────────────────────────────────────────┐  │
│  │        Database Layer (better-sqlite3)              │  │
│  ├─────────────────────────────────────────────────────┤  │
│  │  SQLite 3.35+ (WAL mode, journaling enabled)        │  │
│  │  - Full schema with all tables                      │  │
│  │  - Triggers for stock automation                    │  │
│  │  - Views for reporting                              │  │
│  └─────────────────────────────────────────────────────┘  │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

---

## 3.2 Server Setup

### Installation

```bash
# Create project directory
mkdir hims-sync-server
cd hims-sync-server

# Initialize Node.js project
npm init -y

# Install dependencies
npm install express better-sqlite3 jsonwebtoken bcrypt dotenv cors helmet
npm install --save-dev nodemon @types/node

# Project structure
mkdir -p src/{routes,controllers,services,middleware,utils}
mkdir -p database/backups
```

### Main Server File

```javascript
// src/server.js
const express = require('express');
const cors = require('cors');
const helmet = require('helmet');
const Database = require('better-sqlite3');
const path = require('path');
require('dotenv').config();

const authRoutes = require('./routes/auth');
const deviceRoutes = require('./routes/devices');
const syncRoutes = require('./routes/sync');

const app = express();
const PORT = process.env.PORT || 3000;

// Database initialization
const dbPath = path.join(__dirname, '../database/hims.db');
const db = new Database(dbPath);

// Enable WAL mode for better concurrency
db.pragma('journal_mode = WAL');
db.pragma('foreign_keys = ON');

// Make database available to routes
app.locals.db = db;

// Middleware
app.use(helmet()); // Security headers
app.use(cors({
  origin: process.env.ALLOWED_ORIGINS?.split(',') || ['http://localhost:*'],
  credentials: true,
}));
app.use(express.json({ limit: '10mb' }));
app.use(express.urlencoded({ extended: true }));

// Request logging
app.use((req, res, next) => {
  console.log(`[${new Date().toISOString()}] ${req.method} ${req.path}`);
  next();
});

// Routes
app.use('/api/auth', authRoutes);
app.use('/api/devices', deviceRoutes);
app.use('/api/sync', syncRoutes);

// Health check
app.get('/api/health', (req, res) => {
  res.json({
    status: 'ok',
    timestamp: new Date().toISOString(),
    uptime: process.uptime(),
    database: db.open ? 'connected' : 'disconnected',
  });
});

// Error handler
app.use((err, req, res, next) => {
  console.error('Error:', err);
  res.status(err.status || 500).json({
    error: err.message || 'Internal server error',
    code: err.code || 'INTERNAL_ERROR',
  });
});

// Start server
app.listen(PORT, '0.0.0.0', () => {
  console.log(`✅ HIMS Sync Server running on port ${PORT}`);
  console.log(`📁 Database: ${dbPath}`);
  console.log(`🌐 Local: http://localhost:${PORT}`);

  // Get local IP
  const { networkInterfaces } = require('os');
  const nets = networkInterfaces();
  for (const name of Object.keys(nets)) {
    for (const net of nets[name]) {
      if (net.family === 'IPv4' && !net.internal) {
        console.log(`🌐 Network: http://${net.address}:${PORT}`);
      }
    }
  }
});

// Graceful shutdown
process.on('SIGINT', () => {
  console.log('\n🛑 Shutting down server...');
  db.close();
  process.exit(0);
});
```

---

## 3.3 Authentication System

### JWT Middleware

```javascript
// src/middleware/auth.js
const jwt = require('jsonwebtoken');

const JWT_SECRET = process.env.JWT_SECRET || 'your-secret-key-change-in-production';

function authenticateToken(req, res, next) {
  const authHeader = req.headers['authorization'];
  const token = authHeader && authHeader.split(' ')[1]; // Bearer TOKEN

  if (!token) {
    return res.status(401).json({ error: 'Access token required' });
  }

  jwt.verify(token, JWT_SECRET, (err, user) => {
    if (err) {
      return res.status(403).json({ error: 'Invalid or expired token' });
    }
    req.user = user;
    next();
  });
}

function generateToken(payload, expiresIn = '24h') {
  return jwt.sign(payload, JWT_SECRET, { expiresIn });
}

module.exports = { authenticateToken, generateToken };
```

### Auth Routes

```javascript
// src/routes/auth.js
const express = require('express');
const bcrypt = require('bcrypt');
const { generateToken } = require('../middleware/auth');

const router = express.Router();

// Login endpoint
router.post('/login', async (req, res) => {
  const db = req.app.locals.db;
  const { username, password } = req.body;

  if (!username || !password) {
    return res.status(400).json({ error: 'Username and password required' });
  }

  try {
    // Find user
    const user = db.prepare(`
      SELECT u.*, r.role_name, r.permissions
      FROM users u
      LEFT JOIN user_roles ur ON u.id = ur.user_id
      LEFT JOIN roles r ON ur.role_id = r.id
      WHERE u.username = ? AND u.is_active = 1
    `).get(username);

    if (!user) {
      return res.status(401).json({ error: 'Invalid credentials' });
    }

    // Verify password
    const passwordMatch = await bcrypt.compare(password, user.password_hash);
    if (!passwordMatch) {
      return res.status(401).json({ error: 'Invalid credentials' });
    }

    // Generate token
    const token = generateToken({
      uuid: user.uuid,
      username: user.username,
      role: user.role_name,
      permissions: user.permissions ? JSON.parse(user.permissions) : [],
    });

    res.json({
      token,
      user: {
        uuid: user.uuid,
        username: user.username,
        full_name: user.full_name,
        email: user.email,
        role: user.role_name,
      },
    });
  } catch (error) {
    console.error('Login error:', error);
    res.status(500).json({ error: 'Login failed' });
  }
});

// Token refresh endpoint
router.post('/refresh', (req, res) => {
  const { token } = req.body;

  if (!token) {
    return res.status(400).json({ error: 'Token required' });
  }

  try {
    const decoded = jwt.verify(token, JWT_SECRET);
    const newToken = generateToken({
      uuid: decoded.uuid,
      username: decoded.username,
      role: decoded.role,
      permissions: decoded.permissions,
    });

    res.json({ token: newToken });
  } catch (error) {
    res.status(403).json({ error: 'Invalid token' });
  }
});

module.exports = router;
```

---

## 3.4 Device Management Endpoints

```javascript
// src/routes/devices.js
const express = require('express');
const { authenticateToken } = require('../middleware/auth');
const { v4: uuidv4 } = require('uuid');

const router = express.Router();

// Register device
router.post('/register', async (req, res) => {
  const db = req.app.locals.db;
  const { device_uuid, device_name, device_type, ip_address } = req.body;

  if (!device_uuid || !device_name || !device_type) {
    return res.status(400).json({ error: 'Missing required fields' });
  }

  try {
    // Check device limit
    const settings = db.prepare('SELECT max_devices FROM system_settings WHERE id = 1').get();
    const activeCount = db.prepare(
      'SELECT COUNT(*) as count FROM devices WHERE status = ?'
    ).get('active').count;

    if (activeCount >= settings.max_devices) {
      return res.status(403).json({
        error: 'MAX_DEVICE_LIMIT_REACHED',
        message: `Maximum ${settings.max_devices} devices allowed. Currently ${activeCount} active.`,
        max_devices: settings.max_devices,
        current_active: activeCount,
      });
    }

    // Check if device already exists
    const existing = db.prepare('SELECT uuid FROM devices WHERE device_uuid = ?').get(device_uuid);

    if (existing) {
      return res.status(409).json({
        error: 'DEVICE_ALREADY_REGISTERED',
        message: 'This device is already registered',
      });
    }

    // Register device
    const uuid = uuidv4();
    db.prepare(`
      INSERT INTO devices (
        uuid, device_uuid, device_name, device_type, ip_address, status
      ) VALUES (?, ?, ?, ?, ?, 'pending')
    `).run(uuid, device_uuid, device_name, device_type, ip_address);

    res.status(201).json({
      status: 'REGISTERED',
      device_status: 'pending',
      message: 'Device registered. Awaiting admin approval.',
    });
  } catch (error) {
    console.error('Device registration error:', error);
    res.status(500).json({ error: 'Registration failed' });
  }
});

// Check device status
router.get('/status/:device_uuid', (req, res) => {
  const db = req.app.locals.db;
  const { device_uuid } = req.params;

  try {
    const device = db.prepare(`
      SELECT uuid, device_uuid, device_name, status, last_seen, blocked_reason
      FROM devices
      WHERE device_uuid = ?
    `).get(device_uuid);

    if (!device) {
      return res.status(404).json({ error: 'Device not found' });
    }

    res.json({
      status: device.status,
      device_uuid: device.device_uuid,
      device_name: device.device_name,
      last_seen: device.last_seen,
      blocked_reason: device.blocked_reason,
    });
  } catch (error) {
    console.error('Device status error:', error);
    res.status(500).json({ error: 'Failed to fetch device status' });
  }
});

// List all devices (admin only)
router.get('/list', authenticateToken, (req, res) => {
  const db = req.app.locals.db;

  // Check admin permission
  if (req.user.role !== 'admin') {
    return res.status(403).json({ error: 'Admin access required' });
  }

  try {
    const devices = db.prepare(`
      SELECT
        uuid,
        device_uuid,
        device_name,
        device_type,
        status,
        ip_address,
        last_seen,
        total_syncs,
        failed_syncs,
        registered_at,
        blocked_reason
      FROM devices
      ORDER BY registered_at DESC
    `).all();

    res.json({ devices });
  } catch (error) {
    console.error('Device list error:', error);
    res.status(500).json({ error: 'Failed to fetch devices' });
  }
});

// Approve device (admin only)
router.post('/approve/:device_uuid', authenticateToken, (req, res) => {
  const db = req.app.locals.db;
  const { device_uuid } = req.params;

  if (req.user.role !== 'admin') {
    return res.status(403).json({ error: 'Admin access required' });
  }

  try {
    const result = db.prepare(`
      UPDATE devices
      SET status = 'active', approved_by = ?, approved_at = datetime('now')
      WHERE device_uuid = ? AND status = 'pending'
    `).run(req.user.uuid, device_uuid);

    if (result.changes === 0) {
      return res.status(404).json({ error: 'Device not found or already processed' });
    }

    res.json({ message: 'Device approved successfully' });
  } catch (error) {
    console.error('Device approval error:', error);
    res.status(500).json({ error: 'Failed to approve device' });
  }
});

// Block device (admin only)
router.post('/block/:device_uuid', authenticateToken, (req, res) => {
  const db = req.app.locals.db;
  const { device_uuid } = req.params;
  const { reason } = req.body;

  if (req.user.role !== 'admin') {
    return res.status(403).json({ error: 'Admin access required' });
  }

  try {
    db.prepare(`
      UPDATE devices
      SET status = 'blocked', blocked_reason = ?, blocked_by = ?, blocked_at = datetime('now')
      WHERE device_uuid = ?
    `).run(reason || 'Blocked by admin', req.user.uuid, device_uuid);

    res.json({ message: 'Device blocked successfully' });
  } catch (error) {
    console.error('Device block error:', error);
    res.status(500).json({ error: 'Failed to block device' });
  }
});

module.exports = router;
```

---

## 3.5 Sync Endpoints

### Sync Push (Device → Server)

```javascript
// src/routes/sync.js
const express = require('express');
const { authenticateToken } = require('../middleware/auth');

const router = express.Router();

// Push changes from device to server
router.post('/push', authenticateToken, (req, res) => {
  const db = req.app.locals.db;
  const { device_uuid, changes } = req.body;

  if (!device_uuid || !Array.isArray(changes)) {
    return res.status(400).json({ error: 'Invalid request format' });
  }

  // Verify device is active
  const device = db.prepare('SELECT status FROM devices WHERE device_uuid = ?').get(device_uuid);

  if (!device) {
    return res.status(404).json({ error: 'Device not registered' });
  }

  if (device.status !== 'active') {
    return res.status(403).json({ error: `Device status: ${device.status}` });
  }

  // Check rate limiting (5 minutes minimum)
  const lastSync = db.prepare(`
    SELECT last_sync_time
    FROM device_sessions
    WHERE device_uuid = ?
    ORDER BY session_start DESC
    LIMIT 1
  `).get(device_uuid);

  if (lastSync) {
    const timeSinceSync = Date.now() - new Date(lastSync.last_sync_time).getTime();
    const minInterval = 5 * 60 * 1000; // 5 minutes

    if (timeSinceSync < minInterval) {
      return res.status(429).json({
        error: 'RATE_LIMIT_EXCEEDED',
        message: 'Please wait 5 minutes between syncs',
        retry_after: Math.ceil((minInterval - timeSinceSync) / 1000),
      });
    }
  }

  const results = {
    success: [],
    conflicts: [],
    errors: [],
  };

  // Process changes in transaction
  const processChanges = db.transaction(() => {
    for (const change of changes) {
      try {
        const { table, operation, uuid, data } = change;

        // Validate change
        if (!table || !operation || !uuid) {
          results.errors.push({
            uuid,
            error: 'Missing required fields',
          });
          continue;
        }

        // Check for conflicts
        if (operation === 'update') {
          const existing = db.prepare(
            `SELECT last_modified FROM ${table} WHERE uuid = ?`
          ).get(uuid);

          if (existing && data.last_modified) {
            const existingTime = new Date(existing.last_modified).getTime();
            const incomingTime = new Date(data.last_modified).getTime();

            if (existingTime > incomingTime) {
              // Server has newer data - conflict
              results.conflicts.push({
                uuid,
                table,
                server_timestamp: existing.last_modified,
                device_timestamp: data.last_modified,
              });
              continue;
            }
          }
        }

        // Execute operation
        switch (operation) {
          case 'insert':
            insertRecord(db, table, data);
            break;
          case 'update':
            updateRecord(db, table, uuid, data);
            break;
          case 'delete':
            softDeleteRecord(db, table, uuid, req.user.uuid);
            break;
          default:
            throw new Error(`Unknown operation: ${operation}`);
        }

        results.success.push({ uuid, table, operation });
      } catch (error) {
        results.errors.push({
          uuid: change.uuid,
          error: error.message,
        });
      }
    }

    // Update device sync stats
    db.prepare(`
      UPDATE devices
      SET
        last_seen = datetime('now'),
        total_syncs = total_syncs + 1,
        failed_syncs = failed_syncs + ?
      WHERE device_uuid = ?
    `).run(results.errors.length > 0 ? 1 : 0, device_uuid);

    // Log sync session
    db.prepare(`
      INSERT INTO device_sessions (
        device_uuid, session_start, session_end, last_sync_time,
        records_pushed, records_pulled, sync_status
      ) VALUES (?, datetime('now'), datetime('now'), datetime('now'), ?, 0, ?)
    `).run(device_uuid, results.success.length, results.errors.length > 0 ? 'partial' : 'success');
  });

  try {
    processChanges();

    res.json({
      status: 'ok',
      results,
      timestamp: new Date().toISOString(),
    });
  } catch (error) {
    console.error('Sync push error:', error);
    res.status(500).json({ error: 'Sync failed', details: error.message });
  }
});

// Pull changes from server to device
router.post('/pull', authenticateToken, (req, res) => {
  const db = req.app.locals.db;
  const { device_uuid, last_sync_time } = req.body;

  if (!device_uuid) {
    return res.status(400).json({ error: 'device_uuid required' });
  }

  // Verify device is active
  const device = db.prepare('SELECT status FROM devices WHERE device_uuid = ?').get(device_uuid);

  if (!device || device.status !== 'active') {
    return res.status(403).json({ error: 'Device not active' });
  }

  try {
    const changes = [];
    const tables = [
      'units', 'categories', 'suppliers', 'products', 'locations',
      'purchases', 'purchase_line_items', 'issues', 'issue_line_items',
      'stock_transfers', 'stock_transfer_items', 'invoices', 'invoice_line_items',
      'wastages', 'stock_returns', 'users', 'recipes', 'recipe_items',
    ];

    // Fetch changes since last sync
    const syncTime = last_sync_time || '1970-01-01 00:00:00';

    for (const table of tables) {
      const records = db.prepare(`
        SELECT * FROM ${table}
        WHERE last_modified > ?
        ORDER BY last_modified ASC
      `).all(syncTime);

      for (const record of records) {
        changes.push({
          table,
          uuid: record.uuid,
          operation: record.deleted_at ? 'delete' : 'upsert',
          data: record,
        });
      }
    }

    // Update device last_seen
    db.prepare(`
      UPDATE devices
      SET last_seen = datetime('now')
      WHERE device_uuid = ?
    `).run(device_uuid);

    res.json({
      status: 'ok',
      changes,
      timestamp: new Date().toISOString(),
      count: changes.length,
    });
  } catch (error) {
    console.error('Sync pull error:', error);
    res.status(500).json({ error: 'Sync failed', details: error.message });
  }
});

// Helper functions
function insertRecord(db, table, data) {
  const keys = Object.keys(data).join(', ');
  const placeholders = Object.keys(data).map(() => '?').join(', ');
  const values = Object.values(data);

  db.prepare(`INSERT INTO ${table} (${keys}) VALUES (${placeholders})`).run(...values);
}

function updateRecord(db, table, uuid, data) {
  const setClause = Object.keys(data).map(key => `${key} = ?`).join(', ');
  const values = [...Object.values(data), uuid];

  db.prepare(`UPDATE ${table} SET ${setClause} WHERE uuid = ?`).run(...values);
}

function softDeleteRecord(db, table, uuid, deletedBy) {
  db.prepare(`
    UPDATE ${table}
    SET
      is_active = 0,
      deleted_at = datetime('now'),
      deleted_by = ?,
      last_modified = datetime('now')
    WHERE uuid = ?
  `).run(deletedBy, uuid);
}

module.exports = router;
```

---

## 3.6 Environment Configuration

```bash
# .env file
PORT=3000
NODE_ENV=production

# Database
DB_PATH=./database/hims.db
BACKUP_PATH=./database/backups

# Security
JWT_SECRET=your-very-secure-secret-key-change-this-in-production
BCRYPT_ROUNDS=10

# CORS
ALLOWED_ORIGINS=http://192.168.1.*

# Rate Limiting
SYNC_MIN_INTERVAL=300000  # 5 minutes in milliseconds

# Logging
LOG_LEVEL=info
LOG_FILE=./logs/server.log
```

---

## 3.7 Automated Backup System

```javascript
// src/utils/backup.js
const Database = require('better-sqlite3');
const path = require('path');
const fs = require('fs');

class BackupManager {
  constructor(dbPath, backupDir) {
    this.dbPath = dbPath;
    this.backupDir = backupDir;

    // Ensure backup directory exists
    if (!fs.existsSync(backupDir)) {
      fs.mkdirSync(backupDir, { recursive: true });
    }
  }

  // Create backup
  createBackup() {
    const timestamp = new Date().toISOString().replace(/[:.]/g, '-');
    const backupFile = path.join(this.backupDir, `hims-backup-${timestamp}.db`);

    try {
      const db = new Database(this.dbPath);
      db.backup(backupFile, {
        progress({ totalPages, remainingPages }) {
          const percent = ((totalPages - remainingPages) / totalPages * 100).toFixed(1);
          console.log(`Backup progress: ${percent}%`);
        },
      });
      db.close();

      console.log(`✅ Backup created: ${backupFile}`);
      this.cleanOldBackups();

      return backupFile;
    } catch (error) {
      console.error('❌ Backup failed:', error);
      throw error;
    }
  }

  // Clean old backups (keep last 30)
  cleanOldBackups() {
    const files = fs.readdirSync(this.backupDir)
      .filter(f => f.startsWith('hims-backup-') && f.endsWith('.db'))
      .map(f => ({
        name: f,
        path: path.join(this.backupDir, f),
        time: fs.statSync(path.join(this.backupDir, f)).mtime.getTime(),
      }))
      .sort((a, b) => b.time - a.time);

    // Keep last 30 backups
    const toDelete = files.slice(30);

    for (const file of toDelete) {
      fs.unlinkSync(file.path);
      console.log(`🗑️  Deleted old backup: ${file.name}`);
    }
  }

  // Schedule automatic backups
  startAutoBackup(intervalHours = 24) {
    console.log(`⏰ Auto-backup scheduled every ${intervalHours} hours`);

    // Initial backup
    this.createBackup();

    // Schedule recurring backups
    setInterval(() => {
      this.createBackup();
    }, intervalHours * 60 * 60 * 1000);
  }
}

module.exports = BackupManager;

// Usage in server.js:
// const BackupManager = require('./utils/backup');
// const backupManager = new BackupManager(dbPath, './database/backups');
// backupManager.startAutoBackup(24); // Backup every 24 hours
```

---

# 4. Database Design (v1.0.1 Hardened)

## 4.1 Complete Schema Overview

### Master Data Tables (10 tables)

| Table | Purpose | Key Constraints |
|-------|---------|----------------|
| `units` | Measurement units (kg, L, pieces) | UNIQUE name |
| `categories` | Product categories | UNIQUE name |
| `suppliers` | Vendor information | UNIQUE name, GST validation |
| `products` | Inventory items | FK to units/categories |
| `locations` | Storage locations | UNIQUE name |
| `users` | System users | UNIQUE username, bcrypt password |
| `roles` | User roles (admin, manager, staff) | UNIQUE role_name |
| `user_roles` | User-role mapping | Composite FK |
| `unit_conversions` | Product-specific conversions | FK to products/units |
| `product_batches` | Batch/lot tracking | FK to products, expiry dates |

### Transaction Tables (11 tables)

| Table | Purpose | Status Flow |
|-------|---------|-------------|
| `purchases` | Purchase orders | draft → received → cancelled |
| `purchase_line_items` | Purchase details | FK to purchases |
| `issues` | Stock issues | pending → issued → cancelled |
| `issue_line_items` | Issue details | FK to issues |
| `stock_transfers` | Location transfers | pending → completed → cancelled |
| `stock_transfer_items` | Transfer details | FK to stock_transfers |
| `invoices` | Sales invoices | draft → paid → cancelled |
| `invoice_line_items` | Invoice details | FK to invoices |
| `wastages` | Damaged/expired stock | FK to products/locations |
| `stock_returns` | Vendor returns | FK to purchases/products |
| `recipes` | Recipe definitions | FK to products (output) |
| `recipe_items` | Ingredient lists | FK to recipes/products |

### Analytics Tables (5 tables)

| Table | Purpose | Auto-Updated By |
|-------|---------|----------------|
| `stock_levels` | Current inventory | Triggers |
| `stock_adjustments` | Audit trail | Triggers |
| `stock_alerts` | Low stock warnings | Triggers |
| `conflict_logs` | Sync conflicts | Sync service |
| `sync_queue` | Pending changes | Application |

### System Tables (4 tables)

| Table | Purpose |
|-------|---------|
| `system_settings` | Global config (single row) |
| `devices` | Device registry |
| `device_sessions` | Sync history |
| `schema_migrations` | Version tracking |

**Total: 30 tables**

---

## 4.2 Critical Triggers

### Stock Automation Triggers

```sql
-- 1. Purchase Received → Increase Stock
CREATE TRIGGER trg_after_purchase_received
AFTER UPDATE OF status ON purchases
WHEN NEW.status = 'received'
  AND OLD.status != 'received'
  AND NEW.target_location_id IS NOT NULL
BEGIN
  -- Increase stock
  INSERT INTO stock_levels (location_id, product_uuid, quantity, last_updated, updated_by)
  SELECT
    NEW.target_location_id,
    pli.product_uuid,
    SUM(pli.quantity),
    datetime('now'),
    COALESCE(NEW.modified_by, 'system')
  FROM purchase_line_items pli
  WHERE pli.purchase_id = NEW.id
  GROUP BY pli.product_uuid
  HAVING SUM(pli.quantity) > 0
  ON CONFLICT(location_id, product_uuid) DO UPDATE SET
    quantity = stock_levels.quantity + excluded.quantity,
    last_updated = excluded.last_updated,
    updated_by = excluded.updated_by;

  -- Log adjustments
  INSERT INTO stock_adjustments (
    location_id, product_uuid, quantity_change, adjustment_type,
    reference_type, reference_id, adjusted_by
  )
  SELECT
    NEW.target_location_id,
    pli.product_uuid,
    SUM(pli.quantity),
    'purchase_received',
    'purchase',
    NEW.uuid,
    COALESCE(NEW.modified_by, 'system')
  FROM purchase_line_items pli
  WHERE pli.purchase_id = NEW.id
  GROUP BY pli.product_uuid
  HAVING SUM(pli.quantity) > 0;
END;

-- 2. Issue Approved → Decrease Source, Increase Destination
CREATE TRIGGER trg_after_issue_approved
AFTER UPDATE OF status ON issues
WHEN NEW.status = 'issued'
  AND OLD.status != 'issued'
  AND NEW.from_location_id IS NOT NULL
  AND NEW.to_location_id IS NOT NULL
BEGIN
  -- Decrease from source
  UPDATE stock_levels
  SET
    quantity = stock_levels.quantity - (
      SELECT COALESCE(SUM(ili.quantity), 0)
      FROM issue_line_items ili
      WHERE ili.issue_id = NEW.id AND ili.product_uuid = stock_levels.product_uuid
    ),
    last_updated = datetime('now'),
    updated_by = COALESCE(NEW.modified_by, 'system')
  WHERE location_id = NEW.from_location_id
  AND product_uuid IN (SELECT product_uuid FROM issue_line_items WHERE issue_id = NEW.id);

  -- Increase at destination
  INSERT INTO stock_levels (location_id, product_uuid, quantity, last_updated, updated_by)
  SELECT
    NEW.to_location_id,
    ili.product_uuid,
    SUM(ili.quantity),
    datetime('now'),
    COALESCE(NEW.modified_by, 'system')
  FROM issue_line_items ili
  WHERE ili.issue_id = NEW.id
  GROUP BY ili.product_uuid
  HAVING SUM(ili.quantity) > 0
  ON CONFLICT(location_id, product_uuid) DO UPDATE SET
    quantity = stock_levels.quantity + excluded.quantity,
    last_updated = excluded.last_updated,
    updated_by = excluded.updated_by;

  -- Log adjustments (both source and destination)
  INSERT INTO stock_adjustments (
    location_id, product_uuid, quantity_change, adjustment_type,
    reference_type, reference_id, adjusted_by
  )
  SELECT
    NEW.from_location_id,
    ili.product_uuid,
    -SUM(ili.quantity),
    'issue_out',
    'issue',
    NEW.uuid,
    COALESCE(NEW.modified_by, 'system')
  FROM issue_line_items ili
  WHERE ili.issue_id = NEW.id
  GROUP BY ili.product_uuid
  HAVING SUM(ili.quantity) > 0
  UNION ALL
  SELECT
    NEW.to_location_id,
    ili.product_uuid,
    SUM(ili.quantity),
    'issue_in',
    'issue',
    NEW.uuid,
    COALESCE(NEW.modified_by, 'system')
  FROM issue_line_items ili
  WHERE ili.issue_id = NEW.id
  GROUP BY ili.product_uuid
  HAVING SUM(ili.quantity) > 0;
END;

-- 3. Invoice Paid → Decrease Stock
CREATE TRIGGER trg_after_invoice_paid
AFTER UPDATE OF status ON invoices
WHEN NEW.status = 'paid'
  AND OLD.status != 'paid'
  AND NEW.from_location_id IS NOT NULL
BEGIN
  -- Decrease stock
  UPDATE stock_levels
  SET
    quantity = stock_levels.quantity - (
      SELECT COALESCE(SUM(invli.quantity), 0)
      FROM invoice_line_items invli
      WHERE invli.invoice_id = NEW.id AND invli.product_uuid = stock_levels.product_uuid
    ),
    last_updated = datetime('now'),
    updated_by = COALESCE(NEW.modified_by, 'system')
  WHERE location_id = NEW.from_location_id
  AND product_uuid IN (SELECT product_uuid FROM invoice_line_items WHERE invoice_id = NEW.id);

  -- Log adjustments
  INSERT INTO stock_adjustments (
    location_id, product_uuid, quantity_change, adjustment_type,
    reference_type, reference_id, adjusted_by
  )
  SELECT
    NEW.from_location_id,
    invli.product_uuid,
    -SUM(invli.quantity),
    'invoice_sale',
    'invoice',
    NEW.uuid,
    COALESCE(NEW.modified_by, 'system')
  FROM invoice_line_items invli
  WHERE invli.invoice_id = NEW.id
  GROUP BY invli.product_uuid
  HAVING SUM(invli.quantity) > 0;
END;
```

---

## 4.3 Stock Validation Triggers

```sql
-- Prevent insufficient stock for issues
CREATE TRIGGER trg_before_issue_check_stock
BEFORE UPDATE OF status ON issues
WHEN NEW.status = 'issued'
  AND OLD.status != 'issued'
BEGIN
  SELECT CASE
    WHEN EXISTS (
      SELECT 1
      FROM issue_line_items ili
      LEFT JOIN stock_levels sl ON ili.product_uuid = sl.product_uuid
        AND sl.location_id = NEW.from_location_id
      WHERE ili.issue_id = NEW.id
        AND (sl.quantity IS NULL OR sl.quantity < ili.quantity)
      LIMIT 1
    )
    THEN RAISE(ABORT, 'Insufficient stock for issue')
  END;
END;

-- Prevent insufficient stock for transfers
CREATE TRIGGER trg_before_transfer_check_stock
BEFORE UPDATE OF status ON stock_transfers
WHEN NEW.status = 'completed'
  AND OLD.status != 'completed'
BEGIN
  SELECT CASE
    WHEN EXISTS (
      SELECT 1
      FROM stock_transfer_items sti
      LEFT JOIN stock_levels sl ON sti.product_uuid = sl.product_uuid
        AND sl.location_id = NEW.from_location_id
      WHERE sti.transfer_id = NEW.id
        AND (sl.quantity IS NULL OR sl.quantity < sti.quantity)
      LIMIT 1
    )
    THEN RAISE(ABORT, 'Insufficient stock for transfer')
  END;
END;

-- Prevent insufficient stock for invoices
CREATE TRIGGER trg_before_invoice_check_stock
BEFORE UPDATE OF status ON invoices
WHEN NEW.status = 'paid'
  AND OLD.status != 'paid'
BEGIN
  SELECT CASE
    WHEN EXISTS (
      SELECT 1
      FROM invoice_line_items invli
      LEFT JOIN stock_levels sl ON invli.product_uuid = sl.product_uuid
        AND sl.location_id = NEW.from_location_id
      WHERE invli.invoice_id = NEW.id
        AND (sl.quantity IS NULL OR sl.quantity < invli.quantity)
      LIMIT 1
    )
    THEN RAISE(ABORT, 'Insufficient stock for invoice')
  END;
END;
```

---

## 4.4 Low Stock Alert Triggers

```sql
-- Create alert when stock falls below reorder level
CREATE TRIGGER trg_after_stock_update_check_alert
AFTER UPDATE OF quantity ON stock_levels
WHEN NEW.quantity <= (
  SELECT reorder_level FROM products WHERE uuid = NEW.product_uuid
)
BEGIN
  INSERT INTO stock_alerts (
    product_uuid,
    location_id,
    alert_type,
    current_quantity,
    reorder_level,
    alert_message
  )
  SELECT
    NEW.product_uuid,
    NEW.location_id,
    'low_stock',
    NEW.quantity,
    p.reorder_level,
    'Stock level (' || NEW.quantity || ') below reorder point (' || p.reorder_level || ')'
  FROM products p
  WHERE p.uuid = NEW.product_uuid
  AND NOT EXISTS (
    SELECT 1 FROM stock_alerts
    WHERE product_uuid = NEW.product_uuid
      AND location_id = NEW.location_id
      AND alert_type = 'low_stock'
      AND resolved_at IS NULL
    LIMIT 1
  );
END;
```

---

## 4.5 Key Indexes for Performance

```sql
-- Products
CREATE INDEX idx_products_uuid ON products(uuid);
CREATE INDEX idx_products_category ON products(category_id) WHERE is_active = 1;
CREATE INDEX idx_products_name ON products(name) WHERE is_active = 1;
CREATE INDEX idx_products_sku ON products(sku) WHERE sku IS NOT NULL;

-- Stock levels
CREATE UNIQUE INDEX idx_stock_levels_location_product ON stock_levels(location_id, product_uuid);
CREATE INDEX idx_stock_levels_low_stock ON stock_levels(quantity)
  WHERE quantity <= (SELECT reorder_level FROM products WHERE uuid = product_uuid);

-- Purchases
CREATE INDEX idx_purchases_uuid ON purchases(uuid);
CREATE INDEX idx_purchases_status ON purchases(status);
CREATE INDEX idx_purchases_supplier ON purchases(supplier_id);
CREATE INDEX idx_purchases_date ON purchases(purchase_date);

-- Issues
CREATE INDEX idx_issues_uuid ON issues(uuid);
CREATE INDEX idx_issues_status ON issues(status);
CREATE INDEX idx_issues_from_location ON issues(from_location_id);
CREATE INDEX idx_issues_to_location ON issues(to_location_id);

-- Invoices
CREATE INDEX idx_invoices_uuid ON invoices(uuid);
CREATE INDEX idx_invoices_number ON invoices(invoice_number);
CREATE INDEX idx_invoices_status ON invoices(status);
CREATE INDEX idx_invoices_date ON invoices(invoice_date);

-- Sync
CREATE INDEX idx_sync_queue_status ON sync_queue(sync_status, created_at);
CREATE INDEX idx_stock_adjustments_product ON stock_adjustments(product_uuid, adjusted_at);

-- Devices
CREATE UNIQUE INDEX idx_devices_device_uuid ON devices(device_uuid);
CREATE INDEX idx_devices_status ON devices(status);

-- Users
CREATE UNIQUE INDEX idx_users_username ON users(username);
CREATE INDEX idx_users_uuid ON users(uuid);
```

---

## 4.6 Essential Views

### Current Stock View

```sql
CREATE VIEW vw_current_stock AS
SELECT
  sl.id,
  sl.location_id,
  l.location_name,
  sl.product_uuid,
  p.name AS product_name,
  p.sku,
  c.category_name,
  sl.quantity,
  u.unit_name AS default_unit,
  p.reorder_level,
  CASE
    WHEN sl.quantity <= p.reorder_level THEN 'low'
    WHEN sl.quantity <= p.reorder_level * 1.5 THEN 'warning'
    ELSE 'ok'
  END AS stock_status,
  sl.last_updated
FROM stock_levels sl
INNER JOIN products p ON sl.product_uuid = p.uuid
INNER JOIN locations l ON sl.location_id = l.id
INNER JOIN units u ON p.default_unit_id = u.id
LEFT JOIN categories c ON p.category_id = c.id
WHERE p.is_active = 1
ORDER BY l.location_name, p.name;
```

### Low Stock Alert View

```sql
CREATE VIEW vw_low_stock AS
SELECT
  p.uuid AS product_uuid,
  p.name AS product_name,
  p.sku,
  c.category_name,
  sl.location_id,
  l.location_name,
  sl.quantity AS current_quantity,
  p.reorder_level,
  p.reorder_quantity AS suggested_order,
  u.unit_name,
  (p.reorder_level - sl.quantity) AS shortage
FROM stock_levels sl
INNER JOIN products p ON sl.product_uuid = p.uuid
INNER JOIN locations l ON sl.location_id = l.id
INNER JOIN units u ON p.default_unit_id = u.id
LEFT JOIN categories c ON p.category_id = c.id
WHERE p.is_active = 1
  AND sl.quantity <= p.reorder_level
ORDER BY shortage DESC;
```

### Expiring Batches View

```sql
CREATE VIEW vw_expiring_batches AS
SELECT
  pb.id,
  pb.batch_number,
  pb.product_uuid,
  p.name AS product_name,
  p.sku,
  pb.expiry_date,
  julianday(pb.expiry_date) - julianday('now') AS days_until_expiry,
  pb.quantity_remaining,
  u.unit_name,
  pb.location_id,
  l.location_name,
  CASE
    WHEN julianday(pb.expiry_date) - julianday('now') < 0 THEN 'expired'
    WHEN julianday(pb.expiry_date) - julianday('now') <= 7 THEN 'critical'
    WHEN julianday(pb.expiry_date) - julianday('now') <= 30 THEN 'warning'
    ELSE 'ok'
  END AS expiry_status
FROM product_batches pb
INNER JOIN products p ON pb.product_uuid = p.uuid
INNER JOIN locations l ON pb.location_id = l.id
INNER JOIN units u ON p.default_unit_id = u.id
WHERE pb.quantity_remaining > 0
  AND p.is_active = 1
  AND julianday(pb.expiry_date) - julianday('now') <= 30
ORDER BY days_until_expiry ASC;
```

### Stock Movement History View

```sql
CREATE VIEW vw_stock_movements AS
SELECT
  sa.id,
  sa.adjusted_at AS movement_date,
  sa.adjustment_type AS movement_type,
  sa.product_uuid,
  p.name AS product_name,
  sa.quantity_change,
  CASE
    WHEN sa.quantity_change > 0 THEN 'IN'
    WHEN sa.quantity_change < 0 THEN 'OUT'
    ELSE 'NONE'
  END AS direction,
  sa.location_id,
  l.location_name,
  sa.reference_type,
  sa.reference_id,
  sa.adjusted_by,
  u.username AS adjusted_by_username
FROM stock_adjustments sa
INNER JOIN products p ON sa.product_uuid = p.uuid
INNER JOIN locations l ON sa.location_id = l.id
LEFT JOIN users u ON sa.adjusted_by = u.uuid
ORDER BY sa.adjusted_at DESC;
```

---

# 5. Core Modules

## 5.1 Module Overview

HIMS consists of 11 primary modules:

| # | Module | Purpose | Key Features |
|---|--------|---------|--------------|
| 1 | **Inventory** | Product master management | CRUD, categories, units, batch tracking |
| 2 | **Purchases** | Vendor procurement | PO creation, receiving, GST, auto-stock update |
| 3 | **Issues** | Inter-location transfers | Issue creation, approval, dual stock update |
| 4 | **Transfers** | Stock movement | Transfer requests, completion, validation |
| 5 | **Wastage** | Loss tracking | Damage, expiry, spoilage recording |
| 6 | **Returns** | Vendor returns | Return to supplier, refund tracking |
| 7 | **Invoices** | Sales/billing | Cash/credit invoices, PDF generation, stock deduction |
| 8 | **Recipes** | Dish costing | Ingredient lists, cost calculation, profit margins |
| 9 | **Reports** | Analytics | Sales, purchases, stock valuation, P&L |
| 10 | **Settings** | Configuration | Company profile, GST setup, device management |
| 11 | **Sync** | Data synchronization | LAN sync, conflict resolution, status monitoring |

---

## 5.2 Module 1: Inventory Management

### Purpose
Centralized product master management with category organization, multi-unit support, and batch/expiry tracking.

### Features

#### 5.2.1 Product CRUD

**Screen: Products List**
- DataTable with search, filter, sort
- Columns: Name, SKU, Category, Unit, Stock, Reorder Level, Status
- Actions: Add, Edit, Delete (soft delete), View Details

**Flutter Implementation:**

```dart
// presentation/screens/inventory/products_screen.dart
class ProductsScreen extends ConsumerStatefulWidget {
  @override
  _ProductsScreenState createState() => _ProductsScreenState();
}

class _ProductsScreenState extends ConsumerState<ProductsScreen> {
  String _searchQuery = '';
  int? _selectedCategoryId;

  @override
  void initState() {
    super.initState();
    // Load products on init
    Future.microtask(() => ref.read(productsProvider.notifier).loadProducts());
  }

  @override
  Widget build(BuildContext context) {
    final productsState = ref.watch(productsProvider);
    final categories = ref.watch(categoriesProvider);

    return ResponsiveScaffold(
      title: 'Products',
      actions: [
        IconButton(
          icon: Icon(Icons.sync),
          onPressed: () => ref.read(syncProvider.notifier).syncNow(),
        ),
      ],
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.pushNamed(context, '/products/add'),
        icon: Icon(Icons.add),
        label: Text('Add Product'),
      ),
      body: Column(
        children: [
          // Search and filter bar
          Padding(
            padding: EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: 'Search products...',
                      prefixIcon: Icon(Icons.search),
                    ),
                    onChanged: (value) {
                      setState(() => _searchQuery = value);
                      _filterProducts();
                    },
                  ),
                ),
                SizedBox(width: 16),
                DropdownButton<int>(
                  value: _selectedCategoryId,
                  hint: Text('All Categories'),
                  items: [
                    DropdownMenuItem(value: null, child: Text('All')),
                    ...categories.map((c) => DropdownMenuItem(
                      value: c.id,
                      child: Text(c.categoryName),
                    )),
                  ],
                  onChanged: (value) {
                    setState(() => _selectedCategoryId = value);
                    _filterProducts();
                  },
                ),
              ],
            ),
          ),

          // Products data table
          Expanded(
            child: productsState.when(
              data: (products) => SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SingleChildScrollView(
                  child: DataTable(
                    columns: [
                      DataColumn(label: Text('Name')),
                      DataColumn(label: Text('SKU')),
                      DataColumn(label: Text('Category')),
                      DataColumn(label: Text('Stock')),
                      DataColumn(label: Text('Reorder Level')),
                      DataColumn(label: Text('Status')),
                      DataColumn(label: Text('Actions')),
                    ],
                    rows: products.map((product) => DataRow(
                      cells: [
                        DataCell(Text(product.name)),
                        DataCell(Text(product.sku ?? '-')),
                        DataCell(Text(product.category?.categoryName ?? '-')),
                        DataCell(Text('${product.totalStock} ${product.unit.unitName}')),
                        DataCell(Text('${product.reorderLevel}')),
                        DataCell(_buildStatusChip(product.stockStatus)),
                        DataCell(Row(
                          children: [
                            IconButton(
                              icon: Icon(Icons.edit),
                              onPressed: () => _editProduct(product),
                            ),
                            IconButton(
                              icon: Icon(Icons.delete),
                              onPressed: () => _deleteProduct(product),
                            ),
                          ],
                        )),
                      ],
                    )).toList(),
                  ),
                ),
              ),
              loading: () => Center(child: CircularProgressIndicator()),
              error: (error, stack) => Center(child: Text('Error: $error')),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusChip(String status) {
    Color color;
    switch (status) {
      case 'low':
        color = AppColors.error;
        break;
      case 'warning':
        color = AppColors.warning;
        break;
      default:
        color = AppColors.success;
    }

    return Chip(
      label: Text(status.toUpperCase()),
      backgroundColor: color.withOpacity(0.2),
      labelStyle: TextStyle(color: color, fontWeight: FontWeight.bold),
    );
  }

  void _filterProducts() {
    ref.read(productsProvider.notifier).filter(
      query: _searchQuery,
      categoryId: _selectedCategoryId,
    );
  }

  void _editProduct(Product product) {
    Navigator.pushNamed(context, '/products/edit', arguments: product);
  }

  Future<void> _deleteProduct(Product product) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete Product'),
        content: Text('Are you sure you want to delete "${product.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            child: Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await ref.read(productsProvider.notifier).deleteProduct(product.uuid);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Product deleted successfully')),
        );
      } catch (e) {
        ErrorHandler.showErrorSnackBar(context, e);
      }
    }
  }
}
```

#### 5.2.2 Add/Edit Product Form

```dart
// presentation/screens/inventory/add_product_screen.dart
class AddProductScreen extends ConsumerStatefulWidget {
  final Product? product; // null for add, populated for edit

  const AddProductScreen({this.product});

  @override
  _AddProductScreenState createState() => _AddProductScreenState();
}

class _AddProductScreenState extends ConsumerState<AddProductScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _skuController;
  late TextEditingController _hsnController;
  late TextEditingController _reorderLevelController;
  late TextEditingController _reorderQuantityController;
  late TextEditingController _taxRateController;

  int? _selectedCategoryId;
  int? _selectedDefaultUnitId;
  int? _selectedBaseUnitId;
  bool _isActive = true;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    final p = widget.product;
    _nameController = TextEditingController(text: p?.name);
    _skuController = TextEditingController(text: p?.sku);
    _hsnController = TextEditingController(text: p?.hsnCode);
    _reorderLevelController = TextEditingController(text: p?.reorderLevel.toString() ?? '0');
    _reorderQuantityController = TextEditingController(text: p?.reorderQuantity.toString() ?? '0');
    _taxRateController = TextEditingController(text: p?.taxRate.toString() ?? '0');

    if (p != null) {
      _selectedCategoryId = p.categoryId;
      _selectedDefaultUnitId = p.defaultUnitId;
      _selectedBaseUnitId = p.baseUnitId;
      _isActive = p.isActive;
    }
  }

  @override
  Widget build(BuildContext context) {
    final categories = ref.watch(categoriesProvider);
    final units = ref.watch(unitsProvider);

    return ResponsiveScaffold(
      title: widget.product == null ? 'Add Product' : 'Edit Product',
      body: Form(
        key: _formKey,
        child: ListView(
          padding: EdgeInsets.all(16),
          children: [
            // Name
            TextFormField(
              controller: _nameController,
              decoration: InputDecoration(labelText: 'Product Name *'),
              validator: (v) => v?.isEmpty ?? true ? 'Required' : null,
            ),
            SizedBox(height: 16),

            // SKU
            TextFormField(
              controller: _skuController,
              decoration: InputDecoration(labelText: 'SKU'),
            ),
            SizedBox(height: 16),

            // Category
            DropdownButtonFormField<int>(
              value: _selectedCategoryId,
              decoration: InputDecoration(labelText: 'Category'),
              items: categories.map((c) => DropdownMenuItem(
                value: c.id,
                child: Text(c.categoryName),
              )).toList(),
              onChanged: (value) => setState(() => _selectedCategoryId = value),
            ),
            SizedBox(height: 16),

            // Default Unit
            DropdownButtonFormField<int>(
              value: _selectedDefaultUnitId,
              decoration: InputDecoration(labelText: 'Default Unit *'),
              items: units.map((u) => DropdownMenuItem(
                value: u.id,
                child: Text(u.unitName),
              )).toList(),
              onChanged: (value) => setState(() => _selectedDefaultUnitId = value),
              validator: (v) => v == null ? 'Required' : null,
            ),
            SizedBox(height: 16),

            // Base Unit
            DropdownButtonFormField<int>(
              value: _selectedBaseUnitId,
              decoration: InputDecoration(labelText: 'Base Unit *'),
              items: units.map((u) => DropdownMenuItem(
                value: u.id,
                child: Text(u.unitName),
              )).toList(),
              onChanged: (value) => setState(() => _selectedBaseUnitId = value),
              validator: (v) => v == null ? 'Required' : null,
            ),
            SizedBox(height: 16),

            // Reorder Level
            TextFormField(
              controller: _reorderLevelController,
              decoration: InputDecoration(labelText: 'Reorder Level'),
              keyboardType: TextInputType.number,
              validator: (v) {
                final val = double.tryParse(v ?? '');
                return val == null || val < 0 ? 'Must be >= 0' : null;
              },
            ),
            SizedBox(height: 16),

            // Reorder Quantity
            TextFormField(
              controller: _reorderQuantityController,
              decoration: InputDecoration(labelText: 'Reorder Quantity'),
              keyboardType: TextInputType.number,
            ),
            SizedBox(height: 16),

            // HSN Code
            TextFormField(
              controller: _hsnController,
              decoration: InputDecoration(labelText: 'HSN Code'),
            ),
            SizedBox(height: 16),

            // Tax Rate
            TextFormField(
              controller: _taxRateController,
              decoration: InputDecoration(labelText: 'Tax Rate (%)'),
              keyboardType: TextInputType.number,
              validator: (v) {
                final val = double.tryParse(v ?? '');
                return val == null || val < 0 || val > 100 ? 'Must be 0-100' : null;
              },
            ),
            SizedBox(height: 16),

            // Active status
            SwitchListTile(
              title: Text('Active'),
              value: _isActive,
              onChanged: (value) => setState(() => _isActive = value),
            ),
            SizedBox(height: 32),

            // Submit button
            ElevatedButton(
              onPressed: _isLoading ? null : _submit,
              child: _isLoading
                  ? CircularProgressIndicator()
                  : Text(widget.product == null ? 'Add Product' : 'Save Changes'),
              style: ElevatedButton.styleFrom(
                padding: EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final product = Product(
        id: widget.product?.id ?? 0,
        uuid: widget.product?.uuid ?? '',
        name: _nameController.text,
        sku: _skuController.text.isEmpty ? null : _skuController.text,
        categoryId: _selectedCategoryId,
        defaultUnitId: _selectedDefaultUnitId!,
        baseUnitId: _selectedBaseUnitId!,
        reorderLevel: double.parse(_reorderLevelController.text),
        reorderQuantity: double.parse(_reorderQuantityController.text),
        hsnCode: _hsnController.text.isEmpty ? null : _hsnController.text,
        taxRate: double.parse(_taxRateController.text),
        isActive: _isActive,
        createdAt: widget.product?.createdAt ?? DateTime.now(),
        lastModified: DateTime.now(), // ✅ Critical!
      );

      if (widget.product == null) {
        await ref.read(productsProvider.notifier).createProduct(product);
      } else {
        await ref.read(productsProvider.notifier).updateProduct(product);
      }

      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Product saved successfully')),
      );
    } catch (e) {
      ErrorHandler.showErrorSnackBar(context, e);
    } finally {
      setState(() => _isLoading = false);
    }
  }
}
```

#### 5.2.3 Stock Levels View

```dart
// presentation/screens/inventory/stock_levels_screen.dart
class StockLevelsScreen extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stockLevels = ref.watch(stockLevelsProvider);
    final selectedLocation = ref.watch(selectedLocationProvider);

    return ResponsiveScaffold(
      title: 'Stock Levels',
      body: Column(
        children: [
          // Location filter
          Padding(
            padding: EdgeInsets.all(16),
            child: DropdownButton<int>(
              value: selectedLocation,
              hint: Text('All Locations'),
              isExpanded: true,
              items: ref.watch(locationsProvider).map((loc) {
                return DropdownMenuItem(
                  value: loc.id,
                  child: Text(loc.locationName),
                );
              }).toList(),
              onChanged: (value) {
                ref.read(selectedLocationProvider.notifier).state = value;
              },
            ),
          ),

          // Stock levels table
          Expanded(
            child: stockLevels.when(
              data: (levels) => ListView.builder(
                itemCount: levels.length,
                itemBuilder: (context, index) {
                  final level = levels[index];
                  return Card(
                    margin: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: _getStatusColor(level.stockStatus),
                        child: Icon(Icons.inventory, color: Colors.white),
                      ),
                      title: Text(level.productName),
                      subtitle: Text('${level.locationName} • ${level.categoryName ?? 'No category'}'),
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '${level.quantity} ${level.defaultUnit}',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            'Reorder: ${level.reorderLevel}',
                            style: TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                        ],
                      ),
                      onTap: () => _showStockDetails(context, level),
                    ),
                  );
                },
              ),
              loading: () => Center(child: CircularProgressIndicator()),
              error: (error, stack) => Center(child: Text('Error: $error')),
            ),
          ),
        ],
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'low':
        return AppColors.error;
      case 'warning':
        return AppColors.warning;
      default:
        return AppColors.success;
    }
  }

  void _showStockDetails(BuildContext context, StockLevel level) {
    showModalBottomSheet(
      context: context,
      builder: (context) => StockDetailsSheet(level),
    );
  }
}
```

---

## 5.3 Module 2: Purchase Management

### Purpose
Manage purchase orders from suppliers with GST compliance, receiving workflow, and automatic stock updates.

### Workflow

```
1. Create Purchase Order (status: 'draft')
   ↓
2. Add Line Items (products + quantities + prices)
   ↓
3. Submit for Approval (status: 'pending')
   ↓
4. Manager Approves (status: 'approved')
   ↓
5. Mark as Received (status: 'received')
   ↓
6. **TRIGGER FIRES** → Stock increases at target location
   ↓
7. Stock adjustments logged for audit trail
```

### Features

#### 5.3.1 Create Purchase Order

```dart
// presentation/screens/purchases/create_purchase_screen.dart
class CreatePurchaseScreen extends ConsumerStatefulWidget {
  @override
  _CreatePurchaseScreenState createState() => _CreatePurchaseScreenState();
}

class _CreatePurchaseScreenState extends ConsumerState<CreatePurchaseScreen> {
  final _formKey = GlobalKey<FormState>();

  int? _selectedSupplierId;
  int? _selectedLocationId;
  DateTime _purchaseDate = DateTime.now();
  DateTime? _expectedDeliveryDate;
  String _notes = '';

  final List<PurchaseLineItem> _lineItems = [];

  @override
  Widget build(BuildContext context) {
    final suppliers = ref.watch(suppliersProvider);
    final locations = ref.watch(locationsProvider);

    return ResponsiveScaffold(
      title: 'Create Purchase Order',
      body: Form(
        key: _formKey,
        child: ListView(
          padding: EdgeInsets.all(16),
          children: [
            // Supplier
            DropdownButtonFormField<int>(
              value: _selectedSupplierId,
              decoration: InputDecoration(labelText: 'Supplier *'),
              items: suppliers.map((s) => DropdownMenuItem(
                value: s.id,
                child: Text(s.supplierName),
              )).toList(),
              onChanged: (value) => setState(() => _selectedSupplierId = value),
              validator: (v) => v == null ? 'Required' : null,
            ),
            SizedBox(height: 16),

            // Target Location
            DropdownButtonFormField<int>(
              value: _selectedLocationId,
              decoration: InputDecoration(labelText: 'Deliver To *'),
              items: locations.map((l) => DropdownMenuItem(
                value: l.id,
                child: Text(l.locationName),
              )).toList(),
              onChanged: (value) => setState(() => _selectedLocationId = value),
              validator: (v) => v == null ? 'Required' : null,
            ),
            SizedBox(height: 16),

            // Purchase Date
            ListTile(
              title: Text('Purchase Date'),
              subtitle: Text(DateFormat('dd/MM/yyyy').format(_purchaseDate)),
              trailing: Icon(Icons.calendar_today),
              onTap: () async {
                final date = await showDatePicker(
                  context: context,
                  initialDate: _purchaseDate,
                  firstDate: DateTime(2020),
                  lastDate: DateTime.now(),
                );
                if (date != null) {
                  setState(() => _purchaseDate = date);
                }
              },
            ),

            // Expected Delivery Date
            ListTile(
              title: Text('Expected Delivery'),
              subtitle: Text(_expectedDeliveryDate != null
                  ? DateFormat('dd/MM/yyyy').format(_expectedDeliveryDate!)
                  : 'Not set'),
              trailing: Icon(Icons.calendar_today),
              onTap: () async {
                final date = await showDatePicker(
                  context: context,
                  initialDate: _expectedDeliveryDate ?? DateTime.now().add(Duration(days: 7)),
                  firstDate: DateTime.now(),
                  lastDate: DateTime.now().add(Duration(days: 365)),
                );
                if (date != null) {
                  setState(() => _expectedDeliveryDate = date);
                }
              },
            ),
            SizedBox(height: 16),

            // Line Items Section
            Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Line Items', style: Theme.of(context).textTheme.titleLarge),
                        TextButton.icon(
                          onPressed: _addLineItem,
                          icon: Icon(Icons.add),
                          label: Text('Add Item'),
                        ),
                      ],
                    ),
                    SizedBox(height: 16),
                    if (_lineItems.isEmpty)
                      Center(
                        child: Padding(
                          padding: EdgeInsets.all(32),
                          child: Text('No items added yet'),
                        ),
                      )
                    else
                      ..._lineItems.asMap().entries.map((entry) {
                        final index = entry.key;
                        final item = entry.value;
                        return _buildLineItemCard(index, item);
                      }).toList(),

                    // Totals
                    if (_lineItems.isNotEmpty) ...[
                      Divider(),
                      _buildTotalsSection(),
                    ],
                  ],
                ),
              ),
            ),
            SizedBox(height: 16),

            // Notes
            TextFormField(
              decoration: InputDecoration(labelText: 'Notes'),
              maxLines: 3,
              onChanged: (value) => _notes = value,
            ),
            SizedBox(height: 32),

            // Submit Buttons
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => _savePurchase(status: 'draft'),
                    child: Text('Save as Draft'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.grey,
                      padding: EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                ),
                SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => _savePurchase(status: 'pending'),
                    child: Text('Submit for Approval'),
                    style: ElevatedButton.styleFrom(
                      padding: EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLineItemCard(int index, PurchaseLineItem item) {
    return Card(
      margin: EdgeInsets.only(bottom: 8),
      child: ListTile(
        title: Text(item.productName),
        subtitle: Text('${item.quantity} ${item.unitName} @ ₹${item.unitPrice}'),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('₹${item.lineTotal.toStringAsFixed(2)}',
                style: TextStyle(fontWeight: FontWeight.bold)),
            IconButton(
              icon: Icon(Icons.edit),
              onPressed: () => _editLineItem(index),
            ),
            IconButton(
              icon: Icon(Icons.delete),
              onPressed: () => setState(() => _lineItems.removeAt(index)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTotalsSection() {
    final subtotal = _lineItems.fold(0.0, (sum, item) => sum + item.lineTotal);
    final tax = _lineItems.fold(0.0, (sum, item) => sum + (item.lineTotal * item.taxRate / 100));
    final total = subtotal + tax;

    return Column(
      children: [
        _buildTotalRow('Subtotal:', subtotal),
        _buildTotalRow('Tax:', tax),
        _buildTotalRow('Total:', total, isBold: true),
      ],
    );
  }

  Widget _buildTotalRow(String label, double amount, {bool isBold = false}) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontWeight: isBold ? FontWeight.bold : null)),
          Text('₹${amount.toStringAsFixed(2)}',
              style: TextStyle(fontWeight: isBold ? FontWeight.bold : null)),
        ],
      ),
    );
  }

  void _addLineItem() {
    showDialog(
      context: context,
      builder: (context) => AddPurchaseLineItemDialog(
        onAdd: (item) {
          setState(() => _lineItems.add(item));
        },
      ),
    );
  }

  void _editLineItem(int index) {
    showDialog(
      context: context,
      builder: (context) => AddPurchaseLineItemDialog(
        item: _lineItems[index],
        onAdd: (item) {
          setState(() => _lineItems[index] = item);
        },
      ),
    );
  }

  Future<void> _savePurchase({required String status}) async {
    if (!_formKey.currentState!.validate()) return;

    if (_lineItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Please add at least one item')),
      );
      return;
    }

    try {
      final purchase = Purchase(
        uuid: '', // Will be generated
        purchaseNumber: '', // Will be generated
        supplierId: _selectedSupplierId!,
        targetLocationId: _selectedLocationId!,
        purchaseDate: _purchaseDate,
        expectedDeliveryDate: _expectedDeliveryDate,
        status: status,
        notes: _notes,
        createdAt: DateTime.now(),
        lastModified: DateTime.now(),
        lineItems: _lineItems,
      );

      await ref.read(purchasesProvider.notifier).createPurchase(purchase);

      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Purchase order created successfully')),
      );
    } catch (e) {
      ErrorHandler.showErrorSnackBar(context, e);
    }
  }
}
```

#### 5.3.2 Purchase Approval & Receiving

```dart
// Business logic: Approve and receive purchase
class PurchasesNotifier extends StateNotifier<AsyncValue<List<Purchase>>> {
  final PurchaseRepository _repository;

  PurchasesNotifier(this._repository) : super(const AsyncValue.loading());

  Future<void> approvePurchase(String uuid, String approvedBy) async {
    try {
      await _repository.updateStatus(
        uuid: uuid,
        status: 'approved',
        approvedBy: approvedBy,
        approvedAt: DateTime.now(),
        lastModified: DateTime.now(), // ✅ Critical!
      );

      await loadPurchases();
    } catch (e, stack) {
      state = AsyncValue.error(e, stack);
    }
  }

  Future<void> markAsReceived(String uuid, String receivedBy) async {
    try {
      // This will trigger the database trigger to update stock levels
      await _repository.updateStatus(
        uuid: uuid,
        status: 'received', // ⚡ Trigger fires here!
        receivedBy: receivedBy,
        receivedAt: DateTime.now(),
        lastModified: DateTime.now(),
      );

      await loadPurchases();

      // Show success message
      print('✅ Purchase marked as received. Stock levels updated automatically.');
    } catch (e, stack) {
      state = AsyncValue.error(e, stack);
    }
  }
}
```

---

## 5.4 Module 3: Issues Management

### Purpose
Transfer stock between locations (e.g., Main Store → Kitchen, Kitchen → Bar).

### Workflow

```
1. Create Issue (status: 'pending')
   ↓
2. Add Line Items (products + quantities)
   ↓
3. Submit for Approval
   ↓
4. Manager Approves (status: 'issued')
   ↓
5. **TRIGGER FIRES**:
   - Decreases stock at source location
   - Increases stock at destination location
   - Logs both adjustments
```

### Key Validation
- **Stock check trigger**: Prevents approval if insufficient stock at source

```dart
// Business logic
Future<void> approveIssue(String uuid, String approvedBy) async {
  try {
    // Database trigger will validate stock availability
    await _repository.updateStatus(
      uuid: uuid,
      status: 'issued',
      approvedBy: approvedBy,
      approvedAt: DateTime.now(),
      lastModified: DateTime.now(),
    );

    // If we reach here, stock was sufficient and transfer completed
    print('✅ Issue approved. Stock transferred successfully.');
  } on DatabaseException catch (e) {
    if (e.message.contains('Insufficient stock')) {
      throw AppException('Cannot approve: Insufficient stock at source location');
    }
    rethrow;
  }
}
```

---

## 5.5 Module 4: Invoice Management

### Purpose
Generate sales invoices (cash/credit) with automatic stock deduction and PDF generation.

### Features

#### 5.5.1 Invoice Creation

```dart
// Invoice types
enum InvoiceType { cash, credit }

class Invoice {
  final String uuid;
  final String invoiceNumber;
  final int? customerId;
  final String customerName; // For walk-in customers
  final InvoiceType invoiceType;
  final int fromLocationId;
  final DateTime invoiceDate;
  final String status; // draft, paid, cancelled
  final double subtotal;
  final double taxAmount;
  final double discountAmount;
  final double totalAmount;
  final List<InvoiceLineItem> lineItems;
  // ...
}

// Business logic: Create and finalize invoice
Future<void> finalizeInvoice(String uuid, String finalizedBy) async {
  try {
    // Change status to 'paid' triggers stock deduction
    await _repository.updateStatus(
      uuid: uuid,
      status: 'paid',
      finalizedBy: finalizedBy,
      lastModified: DateTime.now(),
    );

    // Generate PDF
    final invoice = await _repository.getByUuid(uuid);
    final pdfFile = await _pdfService.generateInvoicePDF(invoice);

    print('✅ Invoice finalized. Stock deducted. PDF: ${pdfFile.path}');
  } on DatabaseException catch (e) {
    if (e.message.contains('Insufficient stock')) {
      throw AppException('Cannot finalize: Insufficient stock for sale');
    }
    rethrow;
  }
}
```

#### 5.5.2 PDF Generation

```dart
// data/services/pdf_service.dart
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

class PDFService {
  Future<File> generateInvoicePDF(Invoice invoice) async {
    final pdf = pw.Document();

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // Header
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('INVOICE', style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold)),
                      pw.Text('Invoice #: ${invoice.invoiceNumber}'),
                      pw.Text('Date: ${DateFormat('dd/MM/yyyy').format(invoice.invoiceDate)}'),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text('Your Company Name', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
                      pw.Text('GST: XXXXXXXXXXXX'),
                      pw.Text('Phone: +91 XXXXXXXXXX'),
                    ],
                  ),
                ],
              ),
              pw.SizedBox(height: 20),

              // Customer Info
              pw.Container(
                padding: pw.EdgeInsets.all(10),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('Bill To:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                    pw.Text(invoice.customerName),
                    if (invoice.customer != null) ...[
                      pw.Text('Phone: ${invoice.customer!.phone}'),
                      if (invoice.customer!.gstNumber != null)
                        pw.Text('GST: ${invoice.customer!.gstNumber}'),
                    ],
                  ],
                ),
              ),
              pw.SizedBox(height: 20),

              // Line Items Table
              pw.Table(
                border: pw.TableBorder.all(),
                children: [
                  // Header
                  pw.TableRow(
                    decoration: pw.BoxDecoration(color: PdfColors.grey300),
                    children: [
                      _buildTableCell('Item', isHeader: true),
                      _buildTableCell('Qty', isHeader: true),
                      _buildTableCell('Rate', isHeader: true),
                      _buildTableCell('Tax', isHeader: true),
                      _buildTableCell('Amount', isHeader: true),
                    ],
                  ),
                  // Items
                  ...invoice.lineItems.map((item) => pw.TableRow(
                    children: [
                      _buildTableCell(item.productName),
                      _buildTableCell('${item.quantity} ${item.unitName}'),
                      _buildTableCell('₹${item.unitPrice.toStringAsFixed(2)}'),
                      _buildTableCell('${item.taxRate}%'),
                      _buildTableCell('₹${item.lineTotal.toStringAsFixed(2)}'),
                    ],
                  )),
                ],
              ),
              pw.SizedBox(height: 20),

              // Totals
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.end,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      _buildTotalRow('Subtotal:', invoice.subtotal),
                      _buildTotalRow('Tax:', invoice.taxAmount),
                      if (invoice.discountAmount > 0)
                        _buildTotalRow('Discount:', -invoice.discountAmount),
                      pw.Divider(),
                      _buildTotalRow('Total:', invoice.totalAmount, isBold: true),
                    ],
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );

    // Save to file
    final output = await getTemporaryDirectory();
    final file = File('${output.path}/invoice_${invoice.invoiceNumber}.pdf');
    await file.writeAsBytes(await pdf.save());

    return file;
  }

  pw.Widget _buildTableCell(String text, {bool isHeader = false}) {
    return pw.Padding(
      padding: pw.EdgeInsets.all(5),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontWeight: isHeader ? pw.FontWeight.bold : pw.FontWeight.normal,
        ),
      ),
    );
  }

  pw.Widget _buildTotalRow(String label, double amount, {bool isBold = false}) {
    return pw.Padding(
      padding: pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(label, style: pw.TextStyle(fontWeight: isBold ? pw.FontWeight.bold : null)),
          pw.SizedBox(width: 50),
          pw.Text('₹${amount.toStringAsFixed(2)}',
              style: pw.TextStyle(fontWeight: isBold ? pw.FontWeight.bold : null)),
        ],
      ),
    );
  }
}
```

---

## 5.6 Module 5: Recipe Management

### Purpose
Define recipe ingredient lists, calculate costs, and track profit margins.

### Features

```dart
class Recipe {
  final String uuid;
  final String recipeName;
  final String? productUuid; // Output product (e.g., "Chicken Biryani")
  final double expectedYield; // Quantity produced
  final int yieldUnitId;
  final double totalCost; // Calculated from ingredients
  final double sellingPrice;
  final double profitMargin; // Calculated: (selling - cost) / selling * 100
  final List<RecipeItem> ingredients;
  // ...
}

class RecipeItem {
  final String productUuid;
  final double quantity;
  final int unitId;
  final double unitCost; // Cost per unit
  final double lineCost; // quantity * unitCost
  // ...
}

// Business logic: Calculate recipe cost
Future<void> calculateRecipeCost(String recipeUuid) async {
  final recipe = await _repository.getByUuid(recipeUuid);

  double totalCost = 0.0;

  for (final ingredient in recipe.ingredients) {
    // Get latest purchase price for ingredient
    final avgPrice = await _purchaseRepository.getAveragePrice(ingredient.productUuid);
    final lineCost = ingredient.quantity * avgPrice;
    totalCost += lineCost;
  }

  // Calculate profit margin
  final profitMargin = recipe.sellingPrice > 0
      ? ((recipe.sellingPrice - totalCost) / recipe.sellingPrice * 100)
      : 0.0;

  // Update recipe
  await _repository.update(recipe.copyWith(
    totalCost: totalCost,
    profitMargin: profitMargin,
    lastModified: DateTime.now(),
  ));

  print('✅ Recipe cost updated: ₹$totalCost, Margin: ${profitMargin.toStringAsFixed(2)}%');
}
```

---

## 5.7 Module 6: Reports

### Purpose
Generate analytics and business intelligence reports.

### Report Types

| Report | Data Source | Key Metrics |
|--------|-------------|-------------|
| **Sales Summary** | invoices + invoice_line_items | Daily/monthly revenue, payment type split |
| **Purchase Summary** | purchases + purchase_line_items | Vendor-wise spending, GST breakdown |
| **Stock Valuation** | stock_levels + latest purchase prices | Location-wise inventory value |
| **Profit & Loss** | invoices (revenue) + purchases (COGS) | Gross profit, net profit, margins |
| **Low Stock Alert** | vw_low_stock view | Products below reorder level |
| **Expiring Items** | vw_expiring_batches view | Items expiring within 30 days |
| **Stock Movement** | stock_adjustments | All stock in/out transactions |
| **Top Products** | invoice_line_items | Best-selling products |
| **Vendor Performance** | purchases + suppliers | Delivery time, order frequency |

### Example: Sales Summary Report

```dart
class SalesReportScreen extends ConsumerStatefulWidget {
  @override
  _SalesReportScreenState createState() => _SalesReportScreenState();
}

class _SalesReportScreenState extends ConsumerState<SalesReportScreen> {
  DateTime _fromDate = DateTime.now().subtract(Duration(days: 30));
  DateTime _toDate = DateTime.now();

  @override
  Widget build(BuildContext context) {
    final reportData = ref.watch(salesReportProvider(_fromDate, _toDate));

    return ResponsiveScaffold(
      title: 'Sales Report',
      actions: [
        IconButton(
          icon: Icon(Icons.download),
          onPressed: () => _exportToExcel(),
        ),
      ],
      body: Column(
        children: [
          // Date range selector
          Padding(
            padding: EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: ListTile(
                    title: Text('From'),
                    subtitle: Text(DateFormat('dd/MM/yyyy').format(_fromDate)),
                    onTap: () => _selectDate(isFromDate: true),
                  ),
                ),
                Expanded(
                  child: ListTile(
                    title: Text('To'),
                    subtitle: Text(DateFormat('dd/MM/yyyy').format(_toDate)),
                    onTap: () => _selectDate(isFromDate: false),
                  ),
                ),
              ],
            ),
          ),

          // Report content
          Expanded(
            child: reportData.when(
              data: (data) => SingleChildScrollView(
                padding: EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Summary cards
                    GridView.count(
                      crossAxisCount: Breakpoints.getGridColumns(context),
                      shrinkWrap: true,
                      physics: NeverScrollableScrollPhysics(),
                      children: [
                        _buildSummaryCard(
                          'Total Sales',
                          '₹${data.totalSales.toStringAsFixed(2)}',
                          Icons.attach_money,
                          AppColors.success,
                        ),
                        _buildSummaryCard(
                          'Total Invoices',
                          '${data.invoiceCount}',
                          Icons.receipt,
                          AppColors.primary,
                        ),
                        _buildSummaryCard(
                          'Average Invoice',
                          '₹${data.avgInvoiceValue.toStringAsFixed(2)}',
                          Icons.shopping_cart,
                          AppColors.info,
                        ),
                        _buildSummaryCard(
                          'Tax Collected',
                          '₹${data.totalTax.toStringAsFixed(2)}',
                          Icons.account_balance,
                          AppColors.warning,
                        ),
                      ],
                    ),
                    SizedBox(height: 32),

                    // Cash vs Credit split
                    Text('Payment Type Breakdown', style: Theme.of(context).textTheme.titleLarge),
                    SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: Card(
                            child: Padding(
                              padding: EdgeInsets.all(16),
                              child: Column(
                                children: [
                                  Text('Cash', style: TextStyle(fontSize: 18)),
                                  SizedBox(height: 8),
                                  Text(
                                    '₹${data.cashSales.toStringAsFixed(2)}',
                                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                                  ),
                                  Text('${data.cashPercentage.toStringAsFixed(1)}%'),
                                ],
                              ),
                            ),
                          ),
                        ),
                        SizedBox(width: 16),
                        Expanded(
                          child: Card(
                            child: Padding(
                              padding: EdgeInsets.all(16),
                              child: Column(
                                children: [
                                  Text('Credit', style: TextStyle(fontSize: 18)),
                                  SizedBox(height: 8),
                                  Text(
                                    '₹${data.creditSales.toStringAsFixed(2)}',
                                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                                  ),
                                  Text('${data.creditPercentage.toStringAsFixed(1)}%'),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 32),

                    // Daily sales chart
                    Text('Daily Sales Trend', style: Theme.of(context).textTheme.titleLarge),
                    SizedBox(height: 16),
                    SizedBox(
                      height: 300,
                      child: LineChart(
                        LineChartData(
                          // Chart configuration
                          lineBarsData: [
                            LineChartBarData(
                              spots: data.dailySales.map((day) {
                                return FlSpot(
                                  day.date.millisecondsSinceEpoch.toDouble(),
                                  day.amount,
                                );
                              }).toList(),
                              isCurved: true,
                              color: AppColors.primary,
                            ),
                          ],
                        ),
                      ),
                    ),

                    // Top products table
                    SizedBox(height: 32),
                    Text('Top Selling Products', style: Theme.of(context).textTheme.titleLarge),
                    SizedBox(height: 16),
                    DataTable(
                      columns: [
                        DataColumn(label: Text('Product')),
                        DataColumn(label: Text('Quantity')),
                        DataColumn(label: Text('Revenue')),
                      ],
                      rows: data.topProducts.map((product) {
                        return DataRow(cells: [
                          DataCell(Text(product.name)),
                          DataCell(Text('${product.quantitySold}')),
                          DataCell(Text('₹${product.revenue.toStringAsFixed(2)}')),
                        ]);
                      }).toList(),
                    ),
                  ],
                ),
              ),
              loading: () => Center(child: CircularProgressIndicator()),
              error: (error, stack) => Center(child: Text('Error: $error')),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCard(String title, String value, IconData icon, Color color) {
    return Card(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 40, color: color),
            SizedBox(height: 8),
            Text(title, style: TextStyle(fontSize: 14, color: Colors.grey)),
            SizedBox(height: 4),
            Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  Future<void> _selectDate({required bool isFromDate}) async {
    final date = await showDatePicker(
      context: context,
      initialDate: isFromDate ? _fromDate : _toDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );

    if (date != null) {
      setState(() {
        if (isFromDate) {
          _fromDate = date;
        } else {
          _toDate = date;
        }
      });
    }
  }

  Future<void> _exportToExcel() async {
    // TODO: Implement Excel export
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Export feature coming soon')),
    );
  }
}
```

---

# 6. Device Management & Licensing

## 6.1 Device Registration Flow

```
User launches app on new device
   ↓
App generates unique device UUID
   ↓
POST /api/devices/register
   {
     device_uuid: "abc-123",
     device_name: "iPad - Kitchen",
     device_type: "tablet",
     ip_address: "192.168.1.50"
   }
   ↓
Server checks active device count vs max_devices
   ↓
If limit reached → 403 Forbidden
If OK → Device registered with status='pending'
   ↓
Admin approves device via Settings → Devices screen
   ↓
Device status changes to 'active'
   ↓
Device can now sync data
```

## 6.2 License Tiers

```dart
enum LicenseTier {
  basic,    // 5 devices
  standard, // 10 devices
  premium,  // 25 devices
  enterprise, // Unlimited
}

class SystemSettings {
  final LicenseTier licenseTier;
  final int maxDevices;
  final DateTime? licenseExpiryDate;
  final bool autoDeactivateInactive;
  final int inactivityDays; // Default: 7
  // ...
}
```

## 6.3 Device States

| State | Description | Can Sync? |
|-------|-------------|-----------|
| **pending** | Awaiting admin approval | No |
| **active** | Approved and operational | Yes |
| **blocked** | Manually blocked by admin | No |
| **inactive** | Auto-deactivated (7+ days no activity) | No |

## 6.4 Admin Device Management Screen

```dart
class DeviceManagementScreen extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final devices = ref.watch(devicesProvider);
    final settings = ref.watch(systemSettingsProvider);

    return ResponsiveScaffold(
      title: 'Device Management',
      body: Column(
        children: [
          // Stats Card
          Card(
            margin: EdgeInsets.all(16),
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildStatColumn(
                    'Active',
                    devices.where((d) => d.status == 'active').length,
                    AppColors.success,
                  ),
                  _buildStatColumn(
                    'Pending',
                    devices.where((d) => d.status == 'pending').length,
                    AppColors.warning,
                  ),
                  _buildStatColumn(
                    'Blocked',
                    devices.where((d) => d.status == 'blocked').length,
                    AppColors.error,
                  ),
                  Divider(height: 40, thickness: 2),
                  _buildStatColumn(
                    'Max Allowed',
                    settings.maxDevices,
                    AppColors.info,
                  ),
                ],
              ),
            ),
          ),

          // Devices List
          Expanded(
            child: ListView.builder(
              itemCount: devices.length,
              itemBuilder: (context, index) {
                final device = devices[index];
                return Card(
                  margin: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: ListTile(
                    leading: _buildDeviceIcon(device.deviceType, device.status),
                    title: Text(device.deviceName),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${device.deviceType} • ${device.ipAddress}'),
                        Text('Last seen: ${_formatLastSeen(device.lastSeen)}'),
                        Text('Syncs: ${device.totalSyncs} (${device.failedSyncs} failed)'),
                      ],
                    ),
                    trailing: _buildActionButtons(context, ref, device),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatColumn(String label, int value, Color color) {
    return Column(
      children: [
        Text(value.toString(),
            style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: color)),
        Text(label, style: TextStyle(color: Colors.grey)),
      ],
    );
  }

  Widget _buildDeviceIcon(String type, String status) {
    IconData icon;
    switch (type) {
      case 'mobile':
        icon = Icons.smartphone;
        break;
      case 'tablet':
        icon = Icons.tablet;
        break;
      case 'desktop':
        icon = Icons.computer;
        break;
      case 'pos':
        icon = Icons.point_of_sale;
        break;
      default:
        icon = Icons.device_unknown;
    }

    Color color;
    switch (status) {
      case 'active':
        color = AppColors.success;
        break;
      case 'pending':
        color = AppColors.warning;
        break;
      case 'blocked':
        color = AppColors.error;
        break;
      default:
        color = Colors.grey;
    }

    return CircleAvatar(
      backgroundColor: color.withOpacity(0.2),
      child: Icon(icon, color: color),
    );
  }

  Widget _buildActionButtons(BuildContext context, WidgetRef ref, Device device) {
    if (device.status == 'pending') {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: Icon(Icons.check, color: AppColors.success),
            onPressed: () => _approveDevice(context, ref, device),
            tooltip: 'Approve',
          ),
          IconButton(
            icon: Icon(Icons.block, color: AppColors.error),
            onPressed: () => _blockDevice(context, ref, device),
            tooltip: 'Block',
          ),
        ],
      );
    } else if (device.status == 'active') {
      return IconButton(
        icon: Icon(Icons.block, color: AppColors.error),
        onPressed: () => _blockDevice(context, ref, device),
        tooltip: 'Block',
      );
    } else if (device.status == 'blocked') {
      return IconButton(
        icon: Icon(Icons.check, color: AppColors.success),
        onPressed: () => _approveDevice(context, ref, device),
        tooltip: 'Unblock',
      );
    }
    return SizedBox.shrink();
  }

  Future<void> _approveDevice(BuildContext context, WidgetRef ref, Device device) async {
    try {
      await ref.read(devicesProvider.notifier).approveDevice(device.deviceUuid);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Device approved successfully')),
      );
    } catch (e) {
      ErrorHandler.showErrorSnackBar(context, e);
    }
  }

  Future<void> _blockDevice(BuildContext context, WidgetRef ref, Device device) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (context) => _BlockDeviceDialog(),
    );

    if (reason != null) {
      try {
        await ref.read(devicesProvider.notifier).blockDevice(device.deviceUuid, reason);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Device blocked successfully')),
        );
      } catch (e) {
        ErrorHandler.showErrorSnackBar(context, e);
      }
    }
  }

  String _formatLastSeen(DateTime? lastSeen) {
    if (lastSeen == null) return 'Never';

    final diff = DateTime.now().difference(lastSeen);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}
```

---

# 7. Error Handling & Recovery

## 7.1 Error Categories

### 7.1.1 Database Errors

```dart
class DatabaseErrorHandler {
  static void handle(dynamic error) {
    if (error.toString().contains('UNIQUE constraint failed')) {
      throw DatabaseException('Record already exists', code: 'DUPLICATE_ENTRY');
    } else if (error.toString().contains('FOREIGN KEY constraint failed')) {
      throw DatabaseException('Cannot delete: Record is in use', code: 'FK_VIOLATION');
    } else if (error.toString().contains('Insufficient stock')) {
      throw DatabaseException('Insufficient stock for operation', code: 'STOCK_INSUFFICIENT');
    } else if (error.toString().contains('CHECK constraint failed')) {
      throw ValidationException('Invalid data: constraint violation', {});
    } else {
      throw DatabaseException('Database error: ${error.toString()}');
    }
  }
}
```

### 7.1.2 Sync Errors

```dart
enum SyncErrorType {
  networkUnavailable,
  serverUnreachable,
  authenticationFailed,
  conflictDetected,
  rateLimitExceeded,
  deviceBlocked,
  dataValidationFailed,
}

class SyncErrorRecovery {
  static Future<void> handleSyncError(SyncErrorType errorType, SyncOperation operation) async {
    switch (errorType) {
      case SyncErrorType.networkUnavailable:
        // Queue for retry when network is available
        await _queueForRetry(operation);
        break;

      case SyncErrorType.rateLimitExceeded:
        // Wait and retry after delay
        final retryAfter = operation.retryAfter ?? 300; // 5 minutes default
        await Future.delayed(Duration(seconds: retryAfter));
        await _retrySync(operation);
        break;

      case SyncErrorType.conflictDetected:
        // Log conflict for manual resolution
        await _logConflict(operation);
        break;

      case SyncErrorType.deviceBlocked:
        // Notify user and prevent further syncs
        throw DeviceLimitException(
          'Device has been blocked. Contact administrator.',
          0,
          0,
        );

      default:
        // Generic retry logic
        await _retryWithBackoff(operation);
    }
  }

  static Future<void> _queueForRetry(SyncOperation operation) async {
    // Add to retry queue with exponential backoff
    final retryCount = operation.retryCount + 1;
    final delaySeconds = min(pow(2, retryCount).toInt() * 60, 3600); // Max 1 hour

    await SyncQueue.add(operation.copyWith(
      retryCount: retryCount,
      nextRetryAt: DateTime.now().add(Duration(seconds: delaySeconds)),
    ));
  }

  static Future<void> _retryWithBackoff(SyncOperation operation) async {
    if (operation.retryCount >= 5) {
      // Max retries exceeded - log and notify user
      await _logFailedSync(operation);
      throw SyncException('Sync failed after ${operation.retryCount} retries');
    }

    await _queueForRetry(operation);
  }

  static Future<void> _logConflict(SyncOperation operation) async {
    await ConflictLogsDAO.insert(ConflictLog(
      table: operation.table,
      recordUuid: operation.uuid,
      localTimestamp: operation.localTimestamp,
      serverTimestamp: operation.serverTimestamp,
      conflictType: 'timestamp_mismatch',
      localData: jsonEncode(operation.localData),
      serverData: jsonEncode(operation.serverData),
      resolutionStatus: 'pending',
    ));
  }
}
```

### 7.1.3 UI Error Recovery

```dart
class UIErrorRecovery {
  // Retry mechanism for failed operations
  static Future<T> retryOperation<T>(
    Future<T> Function() operation, {
    int maxRetries = 3,
    Duration delay = const Duration(seconds: 1),
  }) async {
    int retryCount = 0;

    while (true) {
      try {
        return await operation();
      } catch (e) {
        retryCount++;
        if (retryCount >= maxRetries) {
          rethrow;
        }
        await Future.delayed(delay * retryCount); // Exponential backoff
      }
    }
  }

  // Graceful degradation
  static T withFallback<T>(
    T Function() operation,
    T fallbackValue,
  ) {
    try {
      return operation();
    } catch (e) {
      print('Operation failed, using fallback: $e');
      return fallbackValue;
    }
  }

  // Timeout wrapper
  static Future<T> withTimeout<T>(
    Future<T> operation,
    Duration timeout, {
    required T Function() onTimeout,
  }) async {
    try {
      return await operation.timeout(timeout);
    } on TimeoutException {
      return onTimeout();
    }
  }
}
```

## 7.2 Offline Operation Handling

```dart
class OfflineOperationManager {
  // Execute operation with offline support
  static Future<void> executeWithOfflineSupport(
    Future<void> Function() operation,
    SyncOperation syncOperation,
  ) async {
    try {
      // Try to execute operation locally
      await operation();

      // Queue for sync
      await SyncQueue.add(syncOperation);

      print('✅ Operation executed locally. Queued for sync.');
    } catch (e) {
      // If local execution fails, still queue for sync
      print('⚠️ Local execution failed: $e. Queuing for sync anyway.');
      await SyncQueue.add(syncOperation.copyWith(
        status: 'failed',
        error: e.toString(),
      ));
      rethrow;
    }
  }

  // Check if operation can be executed offline
  static bool canExecuteOffline(String operationType) {
    const offlineOperations = [
      'create_product',
      'update_product',
      'create_purchase',
      'update_purchase',
      'create_issue',
      'update_issue',
      'create_invoice',
      'update_invoice',
    ];

    return offlineOperations.contains(operationType);
  }
}
```

---

# 8. Security Model

## 8.1 Authentication

### 8.1.1 Password Requirements

- Minimum 8 characters
- At least 1 uppercase letter
- At least 1 lowercase letter
- At least 1 number
- At least 1 special character
- Hashed with bcrypt (10 rounds)

```dart
class PasswordValidator {
  static String? validate(String password) {
    if (password.length < 8) {
      return 'Password must be at least 8 characters';
    }
    if (!password.contains(RegExp(r'[A-Z]'))) {
      return 'Password must contain at least 1 uppercase letter';
    }
    if (!password.contains(RegExp(r'[a-z]'))) {
      return 'Password must contain at least 1 lowercase letter';
    }
    if (!password.contains(RegExp(r'[0-9]'))) {
      return 'Password must contain at least 1 number';
    }
    if (!password.contains(RegExp(r'[!@#$%^&*(),.?":{}|<>]'))) {
      return 'Password must contain at least 1 special character';
    }
    return null;
  }

  static String hash(String password) {
    return BCrypt.hashpw(password, BCrypt.gensalt(logRounds: 10));
  }

  static bool verify(String password, String hash) {
    return BCrypt.checkpw(password, hash);
  }
}
```

### 8.1.2 JWT Token Management

```dart
class TokenManager {
  static const String _tokenKey = 'auth_token';
  static const String _refreshTokenKey = 'refresh_token';

  // Store token
  static Future<void> saveToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token);
  }

  // Get token
  static Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_tokenKey);
  }

  // Check if token is expired
  static bool isTokenExpired(String token) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) return true;

      final payload = json.decode(
        utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
      );

      final exp = payload['exp'] as int?;
      if (exp == null) return true;

      final expiryDate = DateTime.fromMillisecondsSinceEpoch(exp * 1000);
      return DateTime.now().isAfter(expiryDate);
    } catch (e) {
      return true;
    }
  }

  // Refresh token
  static Future<String?> refreshToken() async {
    final token = await getToken();
    if (token == null) return null;

    try {
      final response = await dio.post('/api/auth/refresh', data: {'token': token});
      final newToken = response.data['token'] as String;
      await saveToken(newToken);
      return newToken;
    } catch (e) {
      print('Token refresh failed: $e');
      return null;
    }
  }

  // Clear tokens (logout)
  static Future<void> clearTokens() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_refreshTokenKey);
  }
}
```

## 8.2 Authorization (RBAC)

### 8.2.1 Role-Permission Matrix

| Permission | Admin | Manager | Staff | Viewer |
|------------|-------|---------|-------|--------|
| **Products** |
| View products | ✅ | ✅ | ✅ | ✅ |
| Create products | ✅ | ✅ | ❌ | ❌ |
| Edit products | ✅ | ✅ | ❌ | ❌ |
| Delete products | ✅ | ❌ | ❌ | ❌ |
| **Purchases** |
| View purchases | ✅ | ✅ | ✅ | ✅ |
| Create purchases | ✅ | ✅ | ✅ | ❌ |
| Approve purchases | ✅ | ✅ | ❌ | ❌ |
| Receive purchases | ✅ | ✅ | ✅ | ❌ |
| **Issues** |
| View issues | ✅ | ✅ | ✅ | ✅ |
| Create issues | ✅ | ✅ | ✅ | ❌ |
| Approve issues | ✅ | ✅ | ❌ | ❌ |
| **Invoices** |
| View invoices | ✅ | ✅ | ✅ | ✅ |
| Create invoices | ✅ | ✅ | ✅ | ❌ |
| Finalize invoices | ✅ | ✅ | ❌ | ❌ |
| **Reports** |
| View all reports | ✅ | ✅ | ❌ | ❌ |
| View basic reports | ✅ | ✅ | ✅ | ✅ |
| **Settings** |
| Manage users | ✅ | ❌ | ❌ | ❌ |
| Manage devices | ✅ | ❌ | ❌ | ❌ |
| System settings | ✅ | ❌ | ❌ | ❌ |

### 8.2.2 Permission Check Implementation

```dart
class PermissionGuard {
  static Future<bool> hasPermission(String permission) async {
    final currentUser = await AuthService.getCurrentUser();
    if (currentUser == null) return false;

    final userPermissions = currentUser.role.permissions;
    return userPermissions.contains(permission);
  }

  static Future<void> requirePermission(String permission) async {
    if (!await hasPermission(permission)) {
      throw AuthException('Insufficient permissions: $permission');
    }
  }

  static Widget withPermission(
    String permission, {
    required Widget child,
    Widget? fallback,
  }) {
    return FutureBuilder<bool>(
      future: hasPermission(permission),
      builder: (context, snapshot) {
        if (snapshot.data == true) {
          return child;
        }
        return fallback ?? SizedBox.shrink();
      },
    );
  }
}

// Usage example
class ProductsScreen extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ResponsiveScaffold(
      title: 'Products',
      floatingActionButton: PermissionGuard.withPermission(
        'products:create',
        child: FloatingActionButton(
          onPressed: () => Navigator.pushNamed(context, '/products/add'),
          child: Icon(Icons.add),
        ),
      ),
      body: ProductsList(),
    );
  }
}
```

## 8.3 Data Encryption

### 8.3.1 Database Encryption (Optional)

```dart
// Using SQLCipher for encrypted SQLite databases
class EncryptedDatabase {
  static Database? _database;

  static Future<Database> getDatabase() async {
    if (_database != null) return _database!;

    final path = await getDatabasePath();
    final password = await _getEncryptionKey();

    _database = await openDatabase(
      path,
      version: 1,
      password: password, // SQLCipher encryption
      onCreate: (db, version) async {
        // Create tables
      },
    );

    return _database!;
  }

  static Future<String> _getEncryptionKey() async {
    // Retrieve encryption key from secure storage
    final storage = FlutterSecureStorage();
    String? key = await storage.read(key: 'db_encryption_key');

    if (key == null) {
      // Generate new encryption key
      key = _generateSecureKey();
      await storage.write(key: 'db_encryption_key', value: key);
    }

    return key;
  }

  static String _generateSecureKey() {
    final random = Random.secure();
    final values = List<int>.generate(32, (i) => random.nextInt(256));
    return base64Url.encode(values);
  }
}
```

### 8.3.2 Network Encryption

- All API communication over HTTPS (TLS 1.2+)
- Certificate pinning for production (optional)

```dart
class SecureHttpClient {
  static Dio createSecureClient() {
    final dio = Dio(BaseOptions(
      baseUrl: 'https://your-server.com',
      connectTimeout: Duration(seconds: 10),
      receiveTimeout: Duration(seconds: 30),
    ));

    // Add interceptor for authentication
    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        final token = await TokenManager.getToken();
        if (token != null) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        handler.next(options);
      },
      onError: (error, handler) async {
        if (error.response?.statusCode == 401) {
          // Token expired, try to refresh
          final newToken = await TokenManager.refreshToken();
          if (newToken != null) {
            // Retry request with new token
            error.requestOptions.headers['Authorization'] = 'Bearer $newToken';
            final response = await dio.fetch(error.requestOptions);
            handler.resolve(response);
            return;
          }
        }
        handler.next(error);
      },
    ));

    return dio;
  }
}
```

---

# 9. UI/UX Design

## 9.1 Design Principles

1. **Offline-First UX**: Always show locally cached data, sync in background
2. **Instant Feedback**: Optimistic UI updates with rollback on error
3. **Clear Status Indicators**: Show sync status, device status, connectivity
4. **Consistent Navigation**: Same navigation patterns across all platforms
5. **Accessible Design**: Support for screen readers, keyboard navigation
6. **Progressive Disclosure**: Show essential info first, details on demand

## 9.2 Color Palette

```dart
class AppColors {
  // Primary
  static const Color primary = Color(0xFF1976D2);      // Blue
  static const Color primaryLight = Color(0xFF63A4FF);
  static const Color primaryDark = Color(0xFF004BA0);

  // Secondary
  static const Color secondary = Color(0xFFFFA726);    // Orange
  static const Color secondaryLight = Color(0xFFFFD95B);
  static const Color secondaryDark = Color(0xFFC77800);

  // Status
  static const Color success = Color(0xFF4CAF50);      // Green
  static const Color error = Color(0xFFF44336);        // Red
  static const Color warning = Color(0xFFFF9800);      // Amber
  static const Color info = Color(0xFF2196F3);         // Light Blue

  // Neutrals
  static const Color background = Color(0xFFF5F5F5);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color onSurface = Color(0xFF212121);
  static const Color textSecondary = Color(0xFF757575);

  // Device Status
  static const Color statusActive = success;
  static const Color statusPending = warning;
  static const Color statusBlocked = error;
  static const Color statusInactive = Color(0xFF9E9E9E);

  // Stock Status
  static const Color stockOk = success;
  static const Color stockWarning = warning;
  static const Color stockLow = error;
}
```

## 9.3 Typography

```dart
class AppTextStyles {
  static const String fontFamily = 'Roboto';

  // Headings
  static const TextStyle h1 = TextStyle(
    fontSize: 32,
    fontWeight: FontWeight.bold,
    letterSpacing: -0.5,
  );

  static const TextStyle h2 = TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.bold,
    letterSpacing: -0.5,
  );

  static const TextStyle h3 = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w600,
  );

  // Body
  static const TextStyle body1 = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.normal,
  );

  static const TextStyle body2 = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.normal,
  );

  // Caption
  static const TextStyle caption = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.normal,
    color: AppColors.textSecondary,
  );

  // Button
  static const TextStyle button = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.5,
  );
}
```

## 9.4 Key UI Components

### 9.4.1 Dashboard Cards

```dart
class DashboardCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  const DashboardCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  CircleAvatar(
                    backgroundColor: color.withOpacity(0.1),
                    child: Icon(icon, color: color),
                  ),
                  if (onTap != null)
                    Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
                ],
              ),
              SizedBox(height: 16),
              Text(value, style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
              SizedBox(height: 4),
              Text(title, style: TextStyle(fontSize: 14, color: Colors.grey)),
            ],
          ),
        ),
      ),
    );
  }
}
```

### 9.4.2 Sync Status Indicator

```dart
class SyncStatusIndicator extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final syncStatus = ref.watch(syncStatusProvider);

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: _getStatusColor(syncStatus.status).withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (syncStatus.status == SyncStatus.syncing)
            SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            Icon(_getStatusIcon(syncStatus.status), size: 12),
          SizedBox(width: 6),
          Text(
            _getStatusText(syncStatus.status),
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
          if (syncStatus.lastSyncTime != null) ...[
            SizedBox(width: 6),
            Text(
              '• ${_formatTime(syncStatus.lastSyncTime!)}',
              style: TextStyle(fontSize: 10, color: Colors.grey),
            ),
          ],
        ],
      ),
    );
  }

  Color _getStatusColor(SyncStatus status) {
    switch (status) {
      case SyncStatus.synced:
        return AppColors.success;
      case SyncStatus.syncing:
        return AppColors.info;
      case SyncStatus.error:
        return AppColors.error;
      case SyncStatus.pending:
        return AppColors.warning;
      default:
        return Colors.grey;
    }
  }

  IconData _getStatusIcon(SyncStatus status) {
    switch (status) {
      case SyncStatus.synced:
        return Icons.check_circle;
      case SyncStatus.error:
        return Icons.error;
      case SyncStatus.pending:
        return Icons.pending;
      default:
        return Icons.sync;
    }
  }

  String _getStatusText(SyncStatus status) {
    switch (status) {
      case SyncStatus.synced:
        return 'Synced';
      case SyncStatus.syncing:
        return 'Syncing...';
      case SyncStatus.error:
        return 'Sync Error';
      case SyncStatus.pending:
        return 'Pending Sync';
      default:
        return 'Unknown';
    }
  }

  String _formatTime(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return DateFormat('MMM d').format(time);
  }
}
```

---

# 10. Testing & Deployment

## 10.1 Testing Strategy

### 10.1.1 Unit Tests

```dart
// test/data/repositories/product_repository_test.dart
void main() {
  late AppDatabase database;
  late ProductRepository repository;

  setUp(() async {
    database = AppDatabase.forTesting();
    repository = ProductRepository(database.productsDAO);
  });

  tearDown(() async {
    await database.close();
  });

  group('ProductRepository', () {
    test('should create product successfully', () async {
      final product = Product(
        uuid: 'test-uuid',
        name: 'Test Product',
        defaultUnitId: 1,
        baseUnitId: 1,
        reorderLevel: 10,
        reorderQuantity: 50,
        taxRate: 18,
        isActive: true,
        createdAt: DateTime.now(),
        lastModified: DateTime.now(),
      );

      await repository.insert(product);

      final retrieved = await repository.getByUuid('test-uuid');
      expect(retrieved?.name, 'Test Product');
    });

    test('should update product lastModified timestamp', () async {
      // Test that lastModified is always updated
      final product = await repository.getByUuid('test-uuid');
      final oldModified = product!.lastModified;

      await Future.delayed(Duration(seconds: 1));

      await repository.update(product.copyWith(
        name: 'Updated Name',
        lastModified: DateTime.now(),
      ));

      final updated = await repository.getByUuid('test-uuid');
      expect(updated!.lastModified.isAfter(oldModified), true);
    });

    test('should enforce unique SKU constraint', () async {
      final product1 = Product(/* ... sku: 'SKU-001' */);
      final product2 = Product(/* ... sku: 'SKU-001' */);

      await repository.insert(product1);

      expect(
        () => repository.insert(product2),
        throwsA(isA<DatabaseException>()),
      );
    });
  });
}
```

### 10.1.2 Integration Tests

```dart
// integration_test/purchase_flow_test.dart
void main() {
  testWidgets('Complete purchase flow', (tester) async {
    // Initialize app
    await tester.pumpWidget(MyApp());
    await tester.pumpAndSettle();

    // Login
    await tester.enterText(find.byKey(Key('username')), 'admin');
    await tester.enterText(find.byKey(Key('password')), 'password');
    await tester.tap(find.byKey(Key('loginButton')));
    await tester.pumpAndSettle();

    // Navigate to Purchases
    await tester.tap(find.byIcon(Icons.shopping_cart));
    await tester.pumpAndSettle();

    // Create new purchase
    await tester.tap(find.byKey(Key('createPurchaseButton')));
    await tester.pumpAndSettle();

    // Fill form
    await tester.tap(find.byKey(Key('supplierDropdown')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Supplier A').last);
    await tester.pumpAndSettle();

    // Add line item
    await tester.tap(find.byKey(Key('addLineItemButton')));
    await tester.pumpAndSettle();

    // Select product
    await tester.tap(find.byKey(Key('productDropdown')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tomatoes').last);
    await tester.pumpAndSettle();

    // Enter quantity
    await tester.enterText(find.byKey(Key('quantityField')), '100');
    await tester.enterText(find.byKey(Key('priceField')), '50');

    // Save line item
    await tester.tap(find.byKey(Key('saveLineItemButton')));
    await tester.pumpAndSettle();

    // Submit purchase
    await tester.tap(find.byKey(Key('submitPurchaseButton')));
    await tester.pumpAndSettle();

    // Verify success message
    expect(find.text('Purchase order created successfully'), findsOneWidget);

    // Verify purchase appears in list
    expect(find.text('PO-'), findsWidgets);
  });
}
```

### 10.1.3 Widget Tests

```dart
// test/presentation/widgets/dashboard_card_test.dart
void main() {
  testWidgets('DashboardCard displays correct information', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DashboardCard(
            title: 'Total Products',
            value: '150',
            icon: Icons.inventory,
            color: Colors.blue,
          ),
        ),
      ),
    );

    expect(find.text('Total Products'), findsOneWidget);
    expect(find.text('150'), findsOneWidget);
    expect(find.byIcon(Icons.inventory), findsOneWidget);
  });

  testWidgets('DashboardCard handles tap events', (tester) async {
    bool tapped = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DashboardCard(
            title: 'Test',
            value: '100',
            icon: Icons.test_tube,
            color: Colors.red,
            onTap: () => tapped = true,
          ),
        ),
      ),
    );

    await tester.tap(find.byType(DashboardCard));
    await tester.pumpAndSettle();

    expect(tapped, true);
  });
}
```

## 10.2 Deployment

### 10.2.1 Flutter App Deployment

**Android (APK/AAB):**
```bash
# Build release APK
flutter build apk --release

# Build App Bundle for Play Store
flutter build appbundle --release

# Install on device
flutter install --release
```

**iOS (IPA):**
```bash
# Build for iOS
flutter build ios --release

# Archive in Xcode
# Upload to App Store Connect
```

**Windows:**
```bash
flutter build windows --release
```

**Web:**
```bash
flutter build web --release

# Deploy to hosting (e.g., Firebase)
firebase deploy --only hosting
```

### 10.2.2 Node.js Server Deployment

**Using PM2 (Process Manager):**

```bash
# Install PM2 globally
npm install -g pm2

# Start server
pm2 start src/server.js --name hims-sync-server

# Configure auto-restart
pm2 startup
pm2 save

# Monitor
pm2 logs hims-sync-server
pm2 monit
```

**systemd Service (Linux):**

```ini
# /etc/systemd/system/hims-sync.service
[Unit]
Description=HIMS Sync Server
After=network.target

[Service]
Type=simple
User=hims
WorkingDirectory=/opt/hims-sync-server
ExecStart=/usr/bin/node /opt/hims-sync-server/src/server.js
Restart=always
RestartSec=10
Environment=NODE_ENV=production

[Install]
WantedBy=multi-user.target
```

```bash
# Enable and start service
sudo systemctl enable hims-sync
sudo systemctl start hims-sync

# Check status
sudo systemctl status hims-sync
```

### 10.2.3 Database Deployment

**Initial Setup:**

```bash
# Copy database schema
cp database/v1_initial.sql /opt/hims-sync-server/database/

# Initialize database
sqlite3 /opt/hims-sync-server/database/hims.db < database/v1_initial.sql

# Load seed data (optional)
sqlite3 /opt/hims-sync-server/database/hims.db < database/seed_test_data_v1.0.1.sql

# Set permissions
chmod 600 /opt/hims-sync-server/database/hims.db
chown hims:hims /opt/hims-sync-server/database/hims.db
```

**Migrations:**

```bash
# Apply migration
sqlite3 /opt/hims-sync-server/database/hims.db < database/v1.0_to_v1.0.1_migration_CORRECTED.sql

# Verify schema version
sqlite3 /opt/hims-sync-server/database/hims.db "SELECT * FROM schema_migrations"

# Run verification tests
sqlite3 /opt/hims-sync-server/database/hims.db < database/verify_database.sql
```

### 10.2.4 Backup Strategy

```bash
#!/bin/bash
# /opt/hims-sync-server/scripts/backup.sh

BACKUP_DIR="/opt/hims-sync-server/database/backups"
DB_PATH="/opt/hims-sync-server/database/hims.db"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
BACKUP_FILE="$BACKUP_DIR/hims_backup_$TIMESTAMP.db"

# Create backup
sqlite3 $DB_PATH ".backup '$BACKUP_FILE'"

# Compress
gzip $BACKUP_FILE

# Keep only last 30 backups
cd $BACKUP_DIR
ls -t hims_backup_*.db.gz | tail -n +31 | xargs rm -f

echo "Backup completed: $BACKUP_FILE.gz"
```

**Schedule daily backups:**

```bash
# Add to crontab
0 2 * * * /opt/hims-sync-server/scripts/backup.sh
```

### 10.2.5 Monitoring & Logging

**Logging Configuration:**

```javascript
// src/utils/logger.js
const winston = require('winston');

const logger = winston.createLogger({
  level: process.env.LOG_LEVEL || 'info',
  format: winston.format.combine(
    winston.format.timestamp(),
    winston.format.json()
  ),
  transports: [
    new winston.transports.File({ filename: 'logs/error.log', level: 'error' }),
    new winston.transports.File({ filename: 'logs/combined.log' }),
  ],
});

if (process.env.NODE_ENV !== 'production') {
  logger.add(new winston.transports.Console({
    format: winston.format.simple(),
  }));
}

module.exports = logger;
```

**Health Check Endpoint:**

```javascript
// Health check with detailed status
app.get('/api/health', (req, res) => {
  const db = req.app.locals.db;

  const health = {
    status: 'ok',
    timestamp: new Date().toISOString(),
    uptime: process.uptime(),
    database: {
      status: db.open ? 'connected' : 'disconnected',
      wal_enabled: db.pragma('journal_mode', { simple: true }),
      foreign_keys: db.pragma('foreign_keys', { simple: true }),
    },
    memory: process.memoryUsage(),
    version: require('../package.json').version,
  };

  // Test database query
  try {
    db.prepare('SELECT 1').get();
    health.database.query_test = 'pass';
  } catch (e) {
    health.database.query_test = 'fail';
    health.status = 'degraded';
  }

  const statusCode = health.status === 'ok' ? 200 : 503;
  res.status(statusCode).json(health);
});
```

---

# 11. Conclusion

## 11.1 Summary

This document provides the complete technical specification for the **Hotel Inventory Management System (HIMS)**, an offline-first, multi-device inventory and invoicing solution designed specifically for hotels and hospitality businesses.

**Key Achievements:**

✅ **Offline-First Architecture** - Works 100% without internet
✅ **Multi-Device LAN Sync** - Supports up to 25+ devices (configurable)
✅ **Production-Hardened Database** - v1.0.1 with 60+ automated tests
✅ **Comprehensive Flutter UI** - Cross-platform (Android, iOS, Windows, Web, macOS, Linux)
✅ **Role-Based Access Control** - 4 built-in roles with granular permissions
✅ **GST Compliance** - Indian tax regulations built-in
✅ **Recipe Costing** - Ingredient-level profit analysis
✅ **PDF Invoice Generation** - Professional invoices with tax breakdown
✅ **Real-Time Stock Automation** - Trigger-based stock updates
✅ **Device Management** - License tier enforcement with approval workflow

## 11.2 Next Steps

### Immediate Actions:
1. **Review & Approval**: Get stakeholder sign-off on this specification
2. **Environment Setup**: Set up development environment for Flutter + Node.js
3. **Database Initialization**: Deploy v1.0.1 schema to master PC
4. **Team Assignment**: Assign developers to frontend/backend/testing teams

### Development Phase:
1. **Sprint 1 (Weeks 1-2)**: Core infrastructure (database, auth, navigation)
2. **Sprint 2 (Weeks 3-4)**: Inventory & Purchase modules
3. **Sprint 3 (Weeks 5-6)**: Issues, Transfers, Invoices modules
4. **Sprint 4 (Weeks 7-8)**: Reports, Settings, Device Management
5. **Sprint 5 (Weeks 9-10)**: Testing, bug fixes, performance optimization
6. **Sprint 6 (Weeks 11-12)**: User acceptance testing, deployment

### Post-Launch:
- Monitor sync performance and device stability
- Gather user feedback for v2.1 enhancements
- Plan multi-hotel support (v3.0)
- Consider cloud backup integration (optional)

## 11.3 Support & Maintenance

**Documentation:**
- User Manual: To be created
- Admin Guide: To be created
- API Documentation: Auto-generated from code comments

**Training:**
- Admin training: 2 days
- Staff training: 1 day
- Video tutorials: To be recorded

**Maintenance Schedule:**
- Daily: Automated backups
- Weekly: Review sync logs and error reports
- Monthly: Database optimization, performance review
- Quarterly: Security updates, dependency updates

## 11.4 Contact

For questions or clarifications regarding this specification:

- **Technical Lead**: [To be assigned]
- **Product Owner**: [To be assigned]
- **Project Repository**: [GitHub URL]
- **Issue Tracker**: [GitHub Issues URL]

---

**Document Version**: 2.0.0
**Last Updated**: 2025-11-12
**Status**: ✅ **COMPLETE - READY FOR IMPLEMENTATION**

---

**End of Document**