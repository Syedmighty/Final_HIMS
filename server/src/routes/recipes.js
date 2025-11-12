/**
 * Recipes Routes
 */

const express = require('express');
const router = express.Router();
const recipesController = require('../controllers/recipes');
const { authenticate, requireStaff } = require('../middleware/auth');

// All routes require authentication
router.use(authenticate);

// Recipes
router.get('/', recipesController.listRecipes);
router.get('/profitability', recipesController.getProfitabilityAnalysis);
router.get('/:uuid', recipesController.getRecipe);
router.post('/', requireStaff, recipesController.createRecipe);
router.post('/:uuid/recalculate-cost', requireStaff, recipesController.recalculateCost);
router.put('/:uuid', requireStaff, recipesController.updateRecipe);
router.delete('/:uuid', requireStaff, recipesController.deleteRecipe);

module.exports = router;
