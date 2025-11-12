/**
 * Payload Validation Hook
 * Validates sync payloads for JSON structure and required fields
 */

const Joi = require('joi');
const logger = require('../config/logger');

// Define schemas for each table
const schemas = {
  products: Joi.object({
    uuid: Joi.string().required(),
    name: Joi.string().required(),
    sku: Joi.string().allow(null, ''),
    category_id: Joi.number().allow(null),
    default_unit_id: Joi.number().required(),
    base_unit_id: Joi.number().required(),
    description: Joi.string().allow(null, ''),
    reorder_level: Joi.number().min(0).default(0),
    min_stock_level: Joi.number().min(0).default(0),
    max_stock_level: Joi.number().min(0).allow(null),
    cost_price: Joi.number().min(0).default(0),
    selling_price: Joi.number().min(0).default(0),
    gst_rate: Joi.number().min(0).max(100).default(0),
    is_active: Joi.number().valid(0, 1).default(1),
    created_at: Joi.string().isoDate().required(),
    last_modified: Joi.string().isoDate().required(),
    created_by: Joi.string().allow(null),
    deleted_at: Joi.string().isoDate().allow(null),
    deleted_by: Joi.string().allow(null)
  }),

  categories: Joi.object({
    uuid: Joi.string().required(),
    name: Joi.string().required(),
    description: Joi.string().allow(null, ''),
    parent_category_id: Joi.number().allow(null),
    created_at: Joi.string().isoDate().required(),
    last_modified: Joi.string().isoDate().required()
  }),

  units: Joi.object({
    uuid: Joi.string().required(),
    name: Joi.string().required(),
    abbreviation: Joi.string().required(),
    unit_type: Joi.string().valid('weight', 'volume', 'count', 'length').allow(null),
    is_base_unit: Joi.number().valid(0, 1).default(0),
    created_at: Joi.string().isoDate().required(),
    last_modified: Joi.string().isoDate().required()
  }),

  suppliers: Joi.object({
    uuid: Joi.string().required(),
    name: Joi.string().required(),
    contact_person: Joi.string().allow(null, ''),
    phone: Joi.string().allow(null, ''),
    email: Joi.string().email().allow(null, ''),
    address: Joi.string().allow(null, ''),
    gst_number: Joi.string().allow(null, ''),
    credit_days: Joi.number().min(0).default(0),
    is_active: Joi.number().valid(0, 1).default(1),
    created_at: Joi.string().isoDate().required(),
    last_modified: Joi.string().isoDate().required(),
    created_by: Joi.string().allow(null),
    deleted_at: Joi.string().isoDate().allow(null),
    deleted_by: Joi.string().allow(null)
  }),

  locations: Joi.object({
    uuid: Joi.string().required(),
    name: Joi.string().required(),
    location_type: Joi.string().valid('warehouse', 'kitchen', 'bar', 'restaurant', 'store').allow(null),
    description: Joi.string().allow(null, ''),
    is_active: Joi.number().valid(0, 1).default(1),
    created_at: Joi.string().isoDate().required(),
    last_modified: Joi.string().isoDate().required()
  }),

  purchases: Joi.object({
    uuid: Joi.string().required(),
    purchase_number: Joi.string().required(),
    supplier_uuid: Joi.string().required(),
    location_uuid: Joi.string().required(),
    purchase_date: Joi.string().isoDate().required(),
    invoice_number: Joi.string().allow(null, ''),
    invoice_date: Joi.string().isoDate().allow(null),
    total_amount: Joi.number().min(0).default(0),
    gst_amount: Joi.number().min(0).default(0),
    grand_total: Joi.number().min(0).default(0),
    status: Joi.string().valid('draft', 'ordered', 'received', 'cancelled').default('draft'),
    payment_status: Joi.string().valid('pending', 'partial', 'paid').default('pending'),
    notes: Joi.string().allow(null, ''),
    created_at: Joi.string().isoDate().required(),
    last_modified: Joi.string().isoDate().required(),
    created_by: Joi.string().required(),
    approved_at: Joi.string().isoDate().allow(null),
    approved_by: Joi.string().allow(null)
  }),

  purchase_items: Joi.object({
    uuid: Joi.string().required(),
    purchase_uuid: Joi.string().required(),
    product_uuid: Joi.string().required(),
    quantity: Joi.number().positive().required(),
    unit_id: Joi.number().required(),
    unit_price: Joi.number().min(0).default(0),
    gst_rate: Joi.number().min(0).max(100).default(0),
    gst_amount: Joi.number().min(0).default(0),
    total_amount: Joi.number().min(0).default(0),
    notes: Joi.string().allow(null, ''),
    created_at: Joi.string().isoDate().required(),
    last_modified: Joi.string().isoDate().required()
  }),

  issues: Joi.object({
    uuid: Joi.string().required(),
    issue_number: Joi.string().required(),
    from_location_uuid: Joi.string().required(),
    to_location_uuid: Joi.string().allow(null),
    issue_date: Joi.string().isoDate().required(),
    status: Joi.string().valid('draft', 'issued', 'cancelled').default('draft'),
    reason: Joi.string().allow(null, ''),
    notes: Joi.string().allow(null, ''),
    created_at: Joi.string().isoDate().required(),
    last_modified: Joi.string().isoDate().required(),
    created_by: Joi.string().required(),
    issued_at: Joi.string().isoDate().allow(null),
    issued_by: Joi.string().allow(null)
  }),

  issue_items: Joi.object({
    uuid: Joi.string().required(),
    issue_uuid: Joi.string().required(),
    product_uuid: Joi.string().required(),
    quantity: Joi.number().positive().required(),
    unit_id: Joi.number().required(),
    notes: Joi.string().allow(null, ''),
    created_at: Joi.string().isoDate().required(),
    last_modified: Joi.string().isoDate().required()
  }),

  transfers: Joi.object({
    uuid: Joi.string().required(),
    transfer_number: Joi.string().required(),
    from_location_uuid: Joi.string().required(),
    to_location_uuid: Joi.string().required(),
    transfer_date: Joi.string().isoDate().required(),
    status: Joi.string().valid('draft', 'in_transit', 'completed', 'cancelled').default('draft'),
    notes: Joi.string().allow(null, ''),
    created_at: Joi.string().isoDate().required(),
    last_modified: Joi.string().isoDate().required(),
    created_by: Joi.string().required(),
    completed_at: Joi.string().isoDate().allow(null),
    completed_by: Joi.string().allow(null)
  }),

  transfer_items: Joi.object({
    uuid: Joi.string().required(),
    transfer_uuid: Joi.string().required(),
    product_uuid: Joi.string().required(),
    quantity: Joi.number().positive().required(),
    unit_id: Joi.number().required(),
    notes: Joi.string().allow(null, ''),
    created_at: Joi.string().isoDate().required(),
    last_modified: Joi.string().isoDate().required()
  }),

  wastages: Joi.object({
    uuid: Joi.string().required(),
    wastage_number: Joi.string().required(),
    location_uuid: Joi.string().required(),
    wastage_date: Joi.string().isoDate().required(),
    wastage_type: Joi.string().valid('damage', 'expiry', 'spoilage', 'other').allow(null),
    status: Joi.string().valid('draft', 'approved', 'cancelled').default('draft'),
    notes: Joi.string().allow(null, ''),
    created_at: Joi.string().isoDate().required(),
    last_modified: Joi.string().isoDate().required(),
    created_by: Joi.string().required(),
    approved_at: Joi.string().isoDate().allow(null),
    approved_by: Joi.string().allow(null)
  }),

  wastage_items: Joi.object({
    uuid: Joi.string().required(),
    wastage_uuid: Joi.string().required(),
    product_uuid: Joi.string().required(),
    quantity: Joi.number().positive().required(),
    unit_id: Joi.number().required(),
    reason: Joi.string().allow(null, ''),
    created_at: Joi.string().isoDate().required(),
    last_modified: Joi.string().isoDate().required()
  }),

  recipes: Joi.object({
    uuid: Joi.string().required(),
    name: Joi.string().required(),
    description: Joi.string().allow(null, ''),
    yield_quantity: Joi.number().positive().default(1),
    yield_unit_id: Joi.number().allow(null),
    preparation_time: Joi.number().min(0).allow(null),
    cost_price: Joi.number().min(0).default(0),
    selling_price: Joi.number().min(0).default(0),
    is_active: Joi.number().valid(0, 1).default(1),
    created_at: Joi.string().isoDate().required(),
    last_modified: Joi.string().isoDate().required(),
    created_by: Joi.string().allow(null)
  }),

  recipe_ingredients: Joi.object({
    uuid: Joi.string().required(),
    recipe_uuid: Joi.string().required(),
    product_uuid: Joi.string().required(),
    quantity: Joi.number().positive().required(),
    unit_id: Joi.number().required(),
    notes: Joi.string().allow(null, ''),
    created_at: Joi.string().isoDate().required(),
    last_modified: Joi.string().isoDate().required()
  }),

  invoices: Joi.object({
    uuid: Joi.string().required(),
    invoice_number: Joi.string().required(),
    invoice_date: Joi.string().isoDate().required(),
    customer_name: Joi.string().allow(null, ''),
    customer_phone: Joi.string().allow(null, ''),
    customer_address: Joi.string().allow(null, ''),
    customer_gst: Joi.string().allow(null, ''),
    invoice_type: Joi.string().valid('cash', 'credit').default('cash'),
    payment_status: Joi.string().valid('pending', 'partial', 'paid').default('pending'),
    subtotal: Joi.number().min(0).default(0),
    discount_amount: Joi.number().min(0).default(0),
    gst_amount: Joi.number().min(0).default(0),
    grand_total: Joi.number().min(0).default(0),
    notes: Joi.string().allow(null, ''),
    status: Joi.string().valid('draft', 'finalized', 'cancelled').default('draft'),
    created_at: Joi.string().isoDate().required(),
    last_modified: Joi.string().isoDate().required(),
    created_by: Joi.string().required(),
    finalized_at: Joi.string().isoDate().allow(null),
    finalized_by: Joi.string().allow(null)
  }),

  invoice_items: Joi.object({
    uuid: Joi.string().required(),
    invoice_uuid: Joi.string().required(),
    product_uuid: Joi.string().required(),
    quantity: Joi.number().positive().required(),
    unit_id: Joi.number().required(),
    unit_price: Joi.number().min(0).default(0),
    discount_percent: Joi.number().min(0).max(100).default(0),
    discount_amount: Joi.number().min(0).default(0),
    gst_rate: Joi.number().min(0).max(100).default(0),
    gst_amount: Joi.number().min(0).default(0),
    total_amount: Joi.number().min(0).default(0),
    created_at: Joi.string().isoDate().required(),
    last_modified: Joi.string().isoDate().required()
  }),

  stock_levels: Joi.object({
    product_uuid: Joi.string().required(),
    location_uuid: Joi.string().required(),
    quantity: Joi.number().min(0).required(),
    last_modified: Joi.string().isoDate().required()
  }),

  stock_adjustments: Joi.object({
    uuid: Joi.string().required(),
    product_uuid: Joi.string().required(),
    location_uuid: Joi.string().required(),
    adjustment_type: Joi.string().valid(
      'purchase', 'issue', 'transfer_in', 'transfer_out',
      'wastage', 'return', 'adjustment', 'recipe_consumption'
    ).required(),
    quantity_change: Joi.number().required(),
    quantity_before: Joi.number().required(),
    quantity_after: Joi.number().required(),
    unit_id: Joi.number().required(),
    conversion_factor: Joi.number().positive().default(1.0),
    reference_type: Joi.string().allow(null),
    reference_uuid: Joi.string().allow(null),
    reason: Joi.string().allow(null, ''),
    created_at: Joi.string().isoDate().required(),
    created_by: Joi.string().required(),
    notes: Joi.string().allow(null, '')
  })
};

/**
 * Validate sync payload against table schema
 * @param {string} tableName - Name of the table
 * @param {Object} payload - Data payload to validate
 * @returns {Object} { valid: boolean, error?: string, value?: Object }
 */
function validateSyncPayload(tableName, payload) {
  // Check if payload is valid JSON
  if (typeof payload !== 'object' || payload === null) {
    return {
      valid: false,
      error: 'Payload must be a valid JSON object'
    };
  }

  // Check if table has a schema
  const schema = schemas[tableName];
  if (!schema) {
    // No schema defined - allow but log warning
    logger.warn('No validation schema for table', { tableName });
    return {
      valid: true,
      value: payload
    };
  }

  // Validate against schema
  const { error, value } = schema.validate(payload, {
    abortEarly: false,
    stripUnknown: false
  });

  if (error) {
    const errorMessages = error.details.map(d => d.message).join('; ');
    logger.warn('Payload validation failed', {
      tableName,
      errors: errorMessages,
      payload
    });

    return {
      valid: false,
      error: `Validation failed: ${errorMessages}`
    };
  }

  return {
    valid: true,
    value
  };
}

/**
 * Validate JSON string
 * @param {string} jsonString - JSON string to validate
 * @returns {boolean}
 */
function isValidJson(jsonString) {
  try {
    JSON.parse(jsonString);
    return true;
  } catch (e) {
    return false;
  }
}

module.exports = {
  validateSyncPayload,
  isValidJson,
  schemas
};
