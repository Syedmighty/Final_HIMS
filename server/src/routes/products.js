/**
 * Products Routes
 */

const express = require('express');
const router = express.Router();
const productsController = require('../controllers/products');
const { authenticate, requireStaff } = require('../middleware/auth');

// All product routes require authentication
router.use(authenticate);

// Products
router.get('/', productsController.listProducts);
router.get('/:uuid', productsController.getProduct);
router.get('/:uuid/stock', productsController.getProductStock);
router.post('/', requireStaff, productsController.createProduct);
router.put('/:uuid', requireStaff, productsController.updateProduct);
router.delete('/:uuid', requireStaff, productsController.deleteProduct);

// Categories
router.get('/categories/list', productsController.listCategories);
router.post('/categories', requireStaff, productsController.createCategory);

// Units
router.get('/units/list', productsController.listUnits);
router.get('/units/conversions', productsController.getUnitConversions);

module.exports = router;
