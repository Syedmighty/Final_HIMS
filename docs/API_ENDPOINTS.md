# HIMS API Endpoints Reference

**Version:** 1.0.1
**Last Updated:** 2025-11-12
**Base URL:** `http://localhost:3000/api`

---

## 🔐 Authentication

All endpoints except `/auth/login` require JWT authentication via `Authorization: Bearer <token>` header.

---

## **1. Authentication** (7 endpoints)

### Login
```http
POST /api/auth/login
```
**Public endpoint** - No authentication required

**Body:**
```json
{
  "username": "admin",
  "password": "admin123",
  "device_uuid": "optional-device-id"
}
```

**Response:**
```json
{
  "success": true,
  "token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
  "user": {
    "uuid": "user_admin",
    "username": "admin",
    "full_name": "System Administrator",
    "role": "admin",
    "email": null
  }
}
```

### Get Current User
```http
GET /api/auth/me
```
**Auth:** Required

### Change Password
```http
POST /api/auth/change-password
```
**Auth:** Required

**Body:**
```json
{
  "current_password": "old_password",
  "new_password": "new_password"
}
```

### List Users
```http
GET /api/auth/users?active_only=true
```
**Auth:** Required (Manager+)

### Create User
```http
POST /api/auth/users
```
**Auth:** Required (Admin only)

**Body:**
```json
{
  "username": "john_doe",
  "password": "password123",
  "full_name": "John Doe",
  "role": "staff",
  "email": "john@example.com",
  "phone": "1234567890"
}
```

### Update User
```http
PUT /api/auth/users/:uuid
```
**Auth:** Required (Admin only)

### Delete User
```http
DELETE /api/auth/users/:uuid
```
**Auth:** Required (Admin only)

---

## **2. Products** (10 endpoints)

### List Products
```http
GET /api/products?category_id=1&active_only=true&search=rice
```
**Auth:** Required

### Get Product
```http
GET /api/products/:uuid
```
**Auth:** Required

**Response includes:**
- Product details
- Stock levels across all locations
- Recent stock adjustments (last 10)

### Get Product Stock
```http
GET /api/products/:uuid/stock
```
**Auth:** Required

**Response:**
```json
{
  "success": true,
  "summary": {
    "uuid": "prod_001",
    "name": "Rice - Basmati",
    "total_quantity": 500,
    "locations_count": 2,
    "unit": "kg"
  },
  "by_location": [
    {
      "location_name": "Main Warehouse",
      "quantity": 300
    },
    {
      "location_name": "Kitchen",
      "quantity": 200
    }
  ]
}
```

### Create Product
```http
POST /api/products
```
**Auth:** Required (Staff+)

**Body:**
```json
{
  "name": "Rice - Basmati",
  "sku": "RICE001",
  "category_id": 1,
  "default_unit_id": 1,
  "base_unit_id": 1,
  "description": "Premium Basmati Rice",
  "reorder_level": 50,
  "min_stock_level": 20,
  "max_stock_level": 500,
  "cost_price": 80,
  "selling_price": 120,
  "gst_rate": 5
}
```

### Update Product
```http
PUT /api/products/:uuid
```
**Auth:** Required (Staff+)

### Delete Product
```http
DELETE /api/products/:uuid
```
**Auth:** Required (Staff+)
**Note:** Soft delete

### List Categories
```http
GET /api/products/categories/list
```
**Auth:** Required

### Create Category
```http
POST /api/products/categories
```
**Auth:** Required (Staff+)

### List Units
```http
GET /api/products/units/list
```
**Auth:** Required

### Get Unit Conversions
```http
GET /api/products/units/conversions
```
**Auth:** Required

---

## **3. Purchases** (7 endpoints)

### List Purchases
```http
GET /api/purchases?status=draft&supplier_uuid=xxx&from_date=2025-01-01
```
**Auth:** Required

**Query Parameters:**
- `status`: draft | ordered | received | cancelled
- `supplier_uuid`: Filter by supplier
- `location_uuid`: Filter by location
- `from_date`: YYYY-MM-DD
- `to_date`: YYYY-MM-DD

### Get Purchase
```http
GET /api/purchases/:uuid
```
**Auth:** Required

**Response includes:**
- Purchase header with supplier info
- All purchase items with product details
- Items count, totals, GST

### Create Purchase
```http
POST /api/purchases
```
**Auth:** Required (Staff+)

**Body:**
```json
{
  "supplier_uuid": "sup_001",
  "location_uuid": "loc_main",
  "purchase_date": "2025-11-12",
  "invoice_number": "INV001",
  "invoice_date": "2025-11-12",
  "notes": "Monthly order",
  "items": [
    {
      "product_uuid": "prod_001",
      "quantity": 100,
      "unit_id": 1,
      "unit_price": 80,
      "gst_rate": 5,
      "notes": "Grade A"
    }
  ]
}
```

**Response:**
```json
{
  "success": true,
  "message": "Purchase created successfully",
  "purchase": {
    "uuid": "pur_xxx",
    "purchase_number": "PUR0001"
  }
}
```

### Update Purchase Status
```http
PUT /api/purchases/:uuid/status
```
**Auth:** Required (Staff+)

**Body:**
```json
{
  "status": "received"
}
```

**Note:** When status changes to "received", stock is automatically updated via triggers!

### Delete Purchase
```http
DELETE /api/purchases/:uuid
```
**Auth:** Required (Staff+)
**Note:** Cannot delete received purchases

### List Suppliers
```http
GET /api/purchases/suppliers/list?active_only=true
```
**Auth:** Required

### Create Supplier
```http
POST /api/purchases/suppliers
```
**Auth:** Required (Staff+)

**Body:**
```json
{
  "name": "ABC Suppliers",
  "contact_person": "John Doe",
  "phone": "1234567890",
  "email": "contact@abc.com",
  "address": "123 Main St",
  "gst_number": "GST123456",
  "credit_days": 30
}
```

---

## **4. Issues (Stock Out)** (6 endpoints)

### List Issues
```http
GET /api/issues?status=draft&from_location_uuid=xxx
```
**Auth:** Required

**Query Parameters:**
- `status`: draft | issued | cancelled
- `from_location_uuid`: Source location
- `to_location_uuid`: Destination (if inter-location)
- `from_date`, `to_date`

### Get Issue
```http
GET /api/issues/:uuid
```
**Auth:** Required

**Response includes:**
- Issue details
- Items with available stock at source
- Stock availability for each item

### Create Issue
```http
POST /api/issues
```
**Auth:** Required (Staff+)

**Body:**
```json
{
  "from_location_uuid": "loc_main",
  "to_location_uuid": "loc_kitchen",
  "issue_date": "2025-11-12",
  "reason": "Kitchen consumption",
  "notes": "Daily requirement",
  "items": [
    {
      "product_uuid": "prod_001",
      "quantity": 50,
      "unit_id": 1,
      "notes": ""
    }
  ]
}
```

**Stock Validation:**
- Checks stock availability before creating
- Returns detailed error if insufficient stock
- No stock deduction until status = 'issued'

### Update Issue Status
```http
PUT /api/issues/:uuid/status
```
**Auth:** Required (Staff+)

**Body:**
```json
{
  "status": "issued"
}
```

**Important:**
- Status change to "issued" triggers stock deduction
- Trigger validates stock before allowing change
- Returns error if insufficient stock

### Delete Issue
```http
DELETE /api/issues/:uuid
```
**Auth:** Required (Staff+)
**Note:** Cannot delete issued items

### Check Stock Availability
```http
POST /api/issues/check-stock
```
**Auth:** Required

**Body:**
```json
{
  "from_location_uuid": "loc_main",
  "items": [
    {
      "product_uuid": "prod_001",
      "quantity": 50,
      "unit_id": 1
    }
  ]
}
```

**Response:**
```json
{
  "success": true,
  "all_sufficient": false,
  "items": [
    {
      "product_uuid": "prod_001",
      "product_name": "Rice",
      "unit": "kg",
      "requested": 50,
      "available": 30,
      "sufficient": false,
      "after_issue": -20,
      "below_reorder": true
    }
  ]
}
```

---

## **5. Transfers** (5 endpoints)

### List Transfers
```http
GET /api/transfers?status=draft&from_location_uuid=xxx
```
**Auth:** Required

**Query Parameters:**
- `status`: draft | in_transit | completed | cancelled
- `from_location_uuid`, `to_location_uuid`
- `from_date`, `to_date`

### Get Transfer
```http
GET /api/transfers/:uuid
```
**Auth:** Required

**Response includes:**
- Transfer details
- Items with available stock at source
- Both location names

### Create Transfer
```http
POST /api/transfers
```
**Auth:** Required (Staff+)

**Body:**
```json
{
  "from_location_uuid": "loc_main",
  "to_location_uuid": "loc_kitchen",
  "transfer_date": "2025-11-12",
  "notes": "Weekly transfer",
  "items": [
    {
      "product_uuid": "prod_001",
      "quantity": 100,
      "unit_id": 1,
      "notes": ""
    }
  ]
}
```

**Validation:**
- from_location must != to_location
- Checks stock at source before creating
- Returns detailed error if insufficient

### Update Transfer Status
```http
PUT /api/transfers/:uuid/status
```
**Auth:** Required (Staff+)

**Body:**
```json
{
  "status": "completed"
}
```

**Important:**
- Status change to "completed" triggers bidirectional stock update
- Deducts from source location
- Adds to destination location
- Creates 2 stock_adjustment entries (transfer_out, transfer_in)

### Delete Transfer
```http
DELETE /api/transfers/:uuid
```
**Auth:** Required (Staff+)
**Note:** Cannot delete completed transfers

---

## **6. Devices** (7 endpoints)

### Register Device
```http
POST /api/devices/register
```
**Auth:** Not required for registration

**Enforces MAX_DEVICES limit (default: 5)**

### Update Heartbeat
```http
POST /api/devices/heartbeat
```
**Auth:** Not required

### List Devices
```http
GET /api/devices?active_only=true
```
**Auth:** Required

### Get Device Stats
```http
GET /api/devices/:uuid/stats
```
**Auth:** Required

### Deactivate Device
```http
POST /api/admin/devices/:uuid/deactivate
```
**Auth:** Required (Admin only)

### Reactivate Device
```http
POST /api/admin/devices/:uuid/reactivate
```
**Auth:** Required (Admin only)

### Cleanup Stale Devices
```http
POST /api/admin/devices/cleanup-stale
```
**Auth:** Required (Admin only)

---

## **7. Sync** (4 endpoints)

### Push Data
```http
POST /api/sync/push
```
**Auth:** Required

**Body:**
```json
{
  "device_uuid": "device_001",
  "items": [
    {
      "table_name": "products",
      "operation": "update",
      "record_uuid": "prod_001",
      "last_modified": "2025-11-12T10:00:00Z",
      "payload": { /* full record */ }
    }
  ]
}
```

### Pull Data
```http
GET /api/sync/pull?device_uuid=xxx&since=2025-11-12T00:00:00Z&tables=products,purchases
```
**Auth:** Required

### List Conflicts
```http
GET /api/sync/conflicts?resolved=false
```
**Auth:** Required

### Resolve Conflict
```http
POST /api/sync/conflicts/:id/resolve
```
**Auth:** Required (Manager+)

---

## **8. Health** (3 endpoints)

### Basic Health
```http
GET /api/health
```
**Auth:** Not required

### Detailed Health
```http
GET /api/health/detailed
```
**Auth:** Not required

**Response includes:**
- Database integrity status
- Active devices count
- Unsynced items count
- Unresolved conflicts count
- Memory usage

### Metrics
```http
GET /api/health/metrics
```
**Auth:** Not required

---

## **Role-Based Access Control**

| Role | Permissions |
|------|-------------|
| **admin** | All operations |
| **manager** | All except user management |
| **staff** | Create/update inventory operations |
| **viewer** | Read-only access |

---

## **Error Responses**

### Insufficient Stock
```json
{
  "success": false,
  "error": "Insufficient stock for one or more items",
  "insufficient_items": [
    {
      "product": "Rice - Basmati",
      "required": 100,
      "available": 50
    }
  ]
}
```

### Unauthorized
```json
{
  "success": false,
  "error": "Insufficient permissions",
  "required_role": ["admin", "manager"],
  "user_role": "staff"
}
```

### Validation Error
```json
{
  "success": false,
  "error": "Validation failed: ...",
  "details": "..."
}
```

---

## **9. Invoices** (7 endpoints)

### List Invoices
```http
GET /api/invoices?status=draft&invoice_type=cash&from_date=2025-01-01
```
**Auth:** Required

**Query Parameters:**
- `status`: draft | finalized | cancelled
- `invoice_type`: cash | credit
- `from_date`, `to_date`: YYYY-MM-DD
- `customer`: Search by customer name or phone

### Get Invoice
```http
GET /api/invoices/:uuid
```
**Auth:** Required

**Response includes:**
- Invoice header with customer info
- All invoice items with product details
- Items count, totals, GST, discount

### Create Invoice
```http
POST /api/invoices
```
**Auth:** Required (Staff+)

**Body:**
```json
{
  "invoice_date": "2025-11-12",
  "customer_name": "John Doe",
  "customer_phone": "1234567890",
  "customer_address": "123 Main St",
  "customer_gst": "GST123456",
  "invoice_type": "cash",
  "discount_amount": 50,
  "notes": "Special discount",
  "items": [
    {
      "product_uuid": "prod_001",
      "quantity": 10,
      "unit_id": 1,
      "unit_price": 120,
      "discount_percent": 5,
      "gst_rate": 5
    }
  ]
}
```

**Response:**
```json
{
  "success": true,
  "message": "Invoice created successfully",
  "invoice": {
    "uuid": "inv_xxx",
    "invoice_number": "INV0001"
  }
}
```

### Update Invoice Status
```http
PUT /api/invoices/:uuid/status
```
**Auth:** Required (Staff+)

**Body:**
```json
{
  "status": "finalized",
  "location_uuid": "loc_main"
}
```

**Important:**
- Status change to "finalized" triggers stock deduction
- `location_uuid` is required when finalizing
- Validates stock availability before allowing finalization
- Returns detailed error if insufficient stock
- Cannot change status of already finalized invoices
- Cash invoices auto-marked as paid when finalized
- Credit invoices remain pending payment when finalized

### Update Payment Status
```http
PUT /api/invoices/:uuid/payment
```
**Auth:** Required (Staff+)

**Body:**
```json
{
  "payment_status": "paid",
  "amount_paid": 1000
}
```

**Note:** Only for finalized invoices

### Get Invoice Summary
```http
GET /api/invoices/summary?from_date=2025-01-01&to_date=2025-12-31
```
**Auth:** Required

**Response:**
```json
{
  "success": true,
  "summary": {
    "total_invoices": 150,
    "finalized_count": 120,
    "draft_count": 30,
    "cash_count": 100,
    "credit_count": 50,
    "total_sales": 500000,
    "paid_amount": 450000,
    "pending_amount": 50000
  }
}
```

### Delete Invoice
```http
DELETE /api/invoices/:uuid
```
**Auth:** Required (Staff+)
**Note:** Cannot delete finalized invoices

---

## **10. Wastage** (6 endpoints)

### List Wastage Records
```http
GET /api/wastage?status=draft&wastage_type=damage&from_date=2025-01-01
```
**Auth:** Required

**Query Parameters:**
- `status`: draft | approved | cancelled
- `wastage_type`: damage | expiry | spoilage | other
- `location_uuid`: Filter by location
- `from_date`, `to_date`: YYYY-MM-DD

### Get Wastage Record
```http
GET /api/wastage/:uuid
```
**Auth:** Required

**Response includes:**
- Wastage header with location info
- All wastage items with product details
- Items count

### Create Wastage Record
```http
POST /api/wastage
```
**Auth:** Required (Staff+)

**Body:**
```json
{
  "location_uuid": "loc_main",
  "wastage_date": "2025-11-12",
  "wastage_type": "expiry",
  "notes": "Expired items removed",
  "items": [
    {
      "product_uuid": "prod_001",
      "quantity": 10,
      "unit_id": 1,
      "reason": "Expired on 2025-11-10"
    }
  ]
}
```

**Response:**
```json
{
  "success": true,
  "message": "Wastage record created successfully",
  "wastage": {
    "uuid": "wst_xxx",
    "wastage_number": "WST0001"
  },
  "warning": "Some items have quantities exceeding available stock",
  "insufficient_items": [
    {
      "product": "Rice - Basmati",
      "required": 10,
      "available": 5
    }
  ]
}
```

**Note:** Creates in draft status. Warning shown if quantity exceeds stock, but doesn't block creation.

### Update Wastage Status
```http
PUT /api/wastage/:uuid/status
```
**Auth:** Required (Staff+)

**Body:**
```json
{
  "status": "approved"
}
```

**Important:**
- Status change to "approved" triggers stock deduction
- Validates stock availability before allowing approval
- Returns detailed error if insufficient stock
- Cannot change status of already approved wastage
- Trigger automatically deducts stock on approval

### Get Wastage Summary
```http
GET /api/wastage/summary?from_date=2025-01-01&to_date=2025-12-31&location_uuid=loc_main
```
**Auth:** Required

**Response:**
```json
{
  "success": true,
  "summary": {
    "total_records": 50,
    "approved_count": 40,
    "draft_count": 10,
    "damage_count": 20,
    "expiry_count": 15,
    "spoilage_count": 10,
    "other_count": 5
  },
  "top_wasted_products": [
    {
      "product_name": "Rice - Basmati",
      "sku": "RICE001",
      "unit": "kg",
      "total_quantity": 100,
      "wastage_count": 5
    }
  ]
}
```

### Delete Wastage Record
```http
DELETE /api/wastage/:uuid
```
**Auth:** Required (Staff+)
**Note:** Cannot delete approved wastage records

---

## **Total API Endpoints: 65+**

- Authentication: 7
- Products: 10
- Purchases: 7
- Issues: 6
- Transfers: 5
- Invoices: 7
- Wastage: 6
- Devices: 7
- Sync: 4
- Health: 3
- **Coming Soon:** Reports, Recipes, Settings, Locations

---

**For detailed business logic and workflows, see HIMS_FEATURE_SPEC_MASTER.md**
