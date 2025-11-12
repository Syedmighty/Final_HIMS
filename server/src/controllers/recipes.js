/**
 * Recipes Controller
 * Handles recipe management, ingredient tracking, and cost calculation
 */

const { getDatabase, transaction } = require('../config/database');
const logger = require('../config/logger');
const { v4: uuidv4 } = require('uuid');

/**
 * List all recipes
 * GET /api/recipes
 */
function listRecipes(req, res) {
  try {
    const db = getDatabase();
    const { active_only, search } = req.query;

    let query = `
      SELECT
        r.*,
        u.full_name as created_by_name,
        yu.abbreviation as yield_unit,
        COUNT(ri.id) as ingredients_count
      FROM recipes r
      LEFT JOIN users u ON u.uuid = r.created_by
      LEFT JOIN units yu ON yu.id = r.yield_unit_id
      LEFT JOIN recipe_ingredients ri ON ri.recipe_uuid = r.uuid
      WHERE 1=1
    `;

    const params = [];

    if (active_only === 'true') {
      query += ' AND r.is_active = 1';
    }

    if (search) {
      query += ' AND r.name LIKE ?';
      params.push(`%${search}%`);
    }

    query += ' GROUP BY r.id ORDER BY r.name ASC';

    const recipes = db.prepare(query).all(...params);

    // Calculate profit margin for each recipe
    const recipesWithMargin = recipes.map(recipe => {
      const margin = recipe.selling_price > 0 && recipe.cost_price > 0
        ? ((recipe.selling_price - recipe.cost_price) / recipe.selling_price * 100).toFixed(2)
        : 0;

      return {
        ...recipe,
        profit_margin_percent: parseFloat(margin)
      };
    });

    res.json({
      success: true,
      recipes: recipesWithMargin,
      count: recipesWithMargin.length
    });
  } catch (error) {
    logger.error('List recipes error', { error: error.message });
    res.status(500).json({
      success: false,
      error: 'Failed to list recipes'
    });
  }
}

/**
 * Get single recipe with ingredients and cost breakdown
 * GET /api/recipes/:uuid
 */
function getRecipe(req, res) {
  try {
    const { uuid } = req.params;
    const db = getDatabase();

    const recipe = db.prepare(`
      SELECT
        r.*,
        u.full_name as created_by_name,
        yu.abbreviation as yield_unit
      FROM recipes r
      LEFT JOIN users u ON u.uuid = r.created_by
      LEFT JOIN units yu ON yu.id = r.yield_unit_id
      WHERE r.uuid = ?
    `).get(uuid);

    if (!recipe) {
      return res.status(404).json({
        success: false,
        error: 'Recipe not found'
      });
    }

    // Get recipe ingredients with cost calculation
    const ingredients = db.prepare(`
      SELECT
        ri.*,
        p.name as product_name,
        p.sku,
        p.cost_price as product_cost_price,
        u.abbreviation as unit,
        (ri.quantity * p.cost_price) as ingredient_cost
      FROM recipe_ingredients ri
      JOIN products p ON p.uuid = ri.product_uuid
      LEFT JOIN units u ON u.id = ri.unit_id
      WHERE ri.recipe_uuid = ?
      ORDER BY ri.created_at
    `).all(uuid);

    // Calculate total cost from ingredients
    const calculatedCost = ingredients.reduce((sum, ing) => sum + (ing.ingredient_cost || 0), 0);

    // Calculate profit margin
    const profitMargin = recipe.selling_price > 0 && recipe.cost_price > 0
      ? ((recipe.selling_price - recipe.cost_price) / recipe.selling_price * 100).toFixed(2)
      : 0;

    res.json({
      success: true,
      recipe: {
        ...recipe,
        profit_margin_percent: parseFloat(profitMargin)
      },
      ingredients,
      cost_breakdown: {
        calculated_cost: calculatedCost,
        stored_cost: recipe.cost_price,
        selling_price: recipe.selling_price,
        profit_amount: recipe.selling_price - recipe.cost_price,
        profit_margin_percent: parseFloat(profitMargin)
      }
    });
  } catch (error) {
    logger.error('Get recipe error', { error: error.message });
    res.status(500).json({
      success: false,
      error: 'Failed to get recipe'
    });
  }
}

/**
 * Create new recipe
 * POST /api/recipes
 */
function createRecipe(req, res) {
  try {
    const {
      name,
      description,
      yield_quantity,
      yield_unit_id,
      preparation_time,
      selling_price,
      ingredients
    } = req.body;

    // Validation
    if (!name) {
      return res.status(400).json({
        success: false,
        error: 'Name is required'
      });
    }

    if (!ingredients || !Array.isArray(ingredients) || ingredients.length === 0) {
      return res.status(400).json({
        success: false,
        error: 'At least one ingredient is required'
      });
    }

    const db = getDatabase();
    const recipeUuid = uuidv4();
    const now = new Date().toISOString();

    const result = transaction(() => {
      // Calculate cost from ingredients
      let totalCost = 0;

      for (const ingredient of ingredients) {
        const product = db.prepare('SELECT cost_price FROM products WHERE uuid = ?').get(ingredient.product_uuid);
        if (product) {
          totalCost += (ingredient.quantity * product.cost_price);
        }
      }

      // Insert recipe
      db.prepare(`
        INSERT INTO recipes (
          uuid, name, description, yield_quantity, yield_unit_id,
          preparation_time, cost_price, selling_price, is_active,
          created_at, last_modified, created_by
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, 1, ?, ?, ?)
      `).run(
        recipeUuid,
        name,
        description || null,
        yield_quantity || 1,
        yield_unit_id || null,
        preparation_time || null,
        totalCost,
        selling_price || 0,
        now,
        now,
        req.user.uuid
      );

      // Insert recipe ingredients
      ingredients.forEach(ingredient => {
        const ingredientUuid = uuidv4();

        db.prepare(`
          INSERT INTO recipe_ingredients (
            uuid, recipe_uuid, product_uuid, quantity, unit_id,
            notes, created_at, last_modified
          ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        `).run(
          ingredientUuid,
          recipeUuid,
          ingredient.product_uuid,
          ingredient.quantity,
          ingredient.unit_id,
          ingredient.notes || null,
          now,
          now
        );
      });

      // Add to sync queue
      const recipeData = db.prepare('SELECT * FROM recipes WHERE uuid = ?').get(recipeUuid);
      db.prepare(`
        INSERT INTO sync_queue (table_name, operation, record_uuid, payload, created_at)
        VALUES ('recipes', 'insert', ?, ?, datetime('now'))
      `).run(recipeUuid, JSON.stringify(recipeData));

      // Log audit
      db.prepare(`
        INSERT INTO audit_logs (table_name, record_uuid, operation, user_uuid, new_values)
        VALUES ('recipes', ?, 'insert', ?, ?)
      `).run(recipeUuid, req.user.uuid, JSON.stringify({ name, ingredients: ingredients.length }));

      return { success: true, calculatedCost: totalCost };
    });

    logger.info('Recipe created', {
      recipe_uuid: recipeUuid,
      name,
      ingredients_count: ingredients.length,
      cost: result.calculatedCost,
      by_user: req.user.username
    });

    res.status(201).json({
      success: true,
      message: 'Recipe created successfully',
      recipe: {
        uuid: recipeUuid,
        name,
        cost_price: result.calculatedCost
      }
    });
  } catch (error) {
    logger.error('Create recipe error', { error: error.message, stack: error.stack });
    res.status(500).json({
      success: false,
      error: 'Failed to create recipe'
    });
  }
}

/**
 * Update recipe
 * PUT /api/recipes/:uuid
 */
function updateRecipe(req, res) {
  try {
    const { uuid } = req.params;
    const {
      name,
      description,
      yield_quantity,
      yield_unit_id,
      preparation_time,
      selling_price,
      is_active,
      ingredients
    } = req.body;

    const db = getDatabase();

    const recipe = db.prepare('SELECT * FROM recipes WHERE uuid = ?').get(uuid);

    if (!recipe) {
      return res.status(404).json({
        success: false,
        error: 'Recipe not found'
      });
    }

    const now = new Date().toISOString();

    const result = transaction(() => {
      let totalCost = recipe.cost_price;

      // If ingredients are being updated, recalculate cost
      if (ingredients && Array.isArray(ingredients)) {
        // Delete existing ingredients
        db.prepare('DELETE FROM recipe_ingredients WHERE recipe_uuid = ?').run(uuid);

        // Insert new ingredients and calculate cost
        totalCost = 0;
        ingredients.forEach(ingredient => {
          const ingredientUuid = uuidv4();

          db.prepare(`
            INSERT INTO recipe_ingredients (
              uuid, recipe_uuid, product_uuid, quantity, unit_id,
              notes, created_at, last_modified
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
          `).run(
            ingredientUuid,
            uuid,
            ingredient.product_uuid,
            ingredient.quantity,
            ingredient.unit_id,
            ingredient.notes || null,
            now,
            now
          );

          const product = db.prepare('SELECT cost_price FROM products WHERE uuid = ?').get(ingredient.product_uuid);
          if (product) {
            totalCost += (ingredient.quantity * product.cost_price);
          }
        });
      }

      // Update recipe
      const updates = {};
      if (name !== undefined) updates.name = name;
      if (description !== undefined) updates.description = description;
      if (yield_quantity !== undefined) updates.yield_quantity = yield_quantity;
      if (yield_unit_id !== undefined) updates.yield_unit_id = yield_unit_id;
      if (preparation_time !== undefined) updates.preparation_time = preparation_time;
      if (selling_price !== undefined) updates.selling_price = selling_price;
      if (is_active !== undefined) updates.is_active = is_active ? 1 : 0;
      if (ingredients && Array.isArray(ingredients)) updates.cost_price = totalCost;
      updates.last_modified = now;

      const updateFields = Object.keys(updates).map(k => `${k} = ?`).join(', ');
      const updateValues = [...Object.values(updates), uuid];

      db.prepare(`
        UPDATE recipes SET ${updateFields} WHERE uuid = ?
      `).run(...updateValues);

      // Add to sync queue
      const updatedRecipe = db.prepare('SELECT * FROM recipes WHERE uuid = ?').get(uuid);
      db.prepare(`
        INSERT INTO sync_queue (table_name, operation, record_uuid, payload, created_at)
        VALUES ('recipes', 'update', ?, ?, datetime('now'))
      `).run(uuid, JSON.stringify(updatedRecipe));

      // Log audit
      db.prepare(`
        INSERT INTO audit_logs (table_name, record_uuid, operation, user_uuid, old_values, new_values)
        VALUES ('recipes', ?, 'update', ?, ?, ?)
      `).run(uuid, req.user.uuid, JSON.stringify(recipe), JSON.stringify(updates));

      return { success: true };
    });

    logger.info('Recipe updated', { recipe_uuid: uuid, by_user: req.user.username });

    res.json({
      success: true,
      message: 'Recipe updated successfully'
    });
  } catch (error) {
    logger.error('Update recipe error', { error: error.message });
    res.status(500).json({
      success: false,
      error: 'Failed to update recipe'
    });
  }
}

/**
 * Delete recipe
 * DELETE /api/recipes/:uuid
 */
function deleteRecipe(req, res) {
  try {
    const { uuid } = req.params;
    const db = getDatabase();

    const recipe = db.prepare('SELECT * FROM recipes WHERE uuid = ?').get(uuid);

    if (!recipe) {
      return res.status(404).json({
        success: false,
        error: 'Recipe not found'
      });
    }

    const result = transaction(() => {
      // Delete recipe ingredients (CASCADE will handle this)
      db.prepare('DELETE FROM recipe_ingredients WHERE recipe_uuid = ?').run(uuid);

      // Delete recipe
      db.prepare('DELETE FROM recipes WHERE uuid = ?').run(uuid);

      // Log audit
      db.prepare(`
        INSERT INTO audit_logs (table_name, record_uuid, operation, user_uuid, old_values)
        VALUES ('recipes', ?, 'delete', ?, ?)
      `).run(uuid, req.user.uuid, JSON.stringify(recipe));

      return { success: true };
    });

    logger.info('Recipe deleted', { recipe_uuid: uuid, by_user: req.user.username });

    res.json({
      success: true,
      message: 'Recipe deleted successfully'
    });
  } catch (error) {
    logger.error('Delete recipe error', { error: error.message });
    res.status(500).json({
      success: false,
      error: 'Failed to delete recipe'
    });
  }
}

/**
 * Recalculate recipe cost based on current ingredient prices
 * POST /api/recipes/:uuid/recalculate-cost
 */
function recalculateCost(req, res) {
  try {
    const { uuid } = req.params;
    const db = getDatabase();

    const recipe = db.prepare('SELECT * FROM recipes WHERE uuid = ?').get(uuid);

    if (!recipe) {
      return res.status(404).json({
        success: false,
        error: 'Recipe not found'
      });
    }

    // Get recipe ingredients with current product costs
    const ingredients = db.prepare(`
      SELECT
        ri.*,
        p.cost_price as product_cost_price,
        (ri.quantity * p.cost_price) as ingredient_cost
      FROM recipe_ingredients ri
      JOIN products p ON p.uuid = ri.product_uuid
      WHERE ri.recipe_uuid = ?
    `).all(uuid);

    // Calculate total cost
    const totalCost = ingredients.reduce((sum, ing) => sum + (ing.ingredient_cost || 0), 0);

    const now = new Date().toISOString();

    // Update recipe cost
    db.prepare(`
      UPDATE recipes
      SET cost_price = ?, last_modified = ?
      WHERE uuid = ?
    `).run(totalCost, now, uuid);

    logger.info('Recipe cost recalculated', {
      recipe_uuid: uuid,
      old_cost: recipe.cost_price,
      new_cost: totalCost,
      by_user: req.user.username
    });

    res.json({
      success: true,
      message: 'Recipe cost recalculated successfully',
      old_cost: recipe.cost_price,
      new_cost: totalCost,
      difference: totalCost - recipe.cost_price
    });
  } catch (error) {
    logger.error('Recalculate recipe cost error', { error: error.message });
    res.status(500).json({
      success: false,
      error: 'Failed to recalculate recipe cost'
    });
  }
}

/**
 * Get recipe profitability analysis
 * GET /api/recipes/profitability
 */
function getProfitabilityAnalysis(req, res) {
  try {
    const db = getDatabase();

    const recipes = db.prepare(`
      SELECT
        r.uuid,
        r.name,
        r.cost_price,
        r.selling_price,
        (r.selling_price - r.cost_price) as profit_amount,
        CASE
          WHEN r.selling_price > 0 THEN
            ROUND(((r.selling_price - r.cost_price) / r.selling_price * 100), 2)
          ELSE 0
        END as profit_margin_percent,
        COUNT(ri.id) as ingredients_count
      FROM recipes r
      LEFT JOIN recipe_ingredients ri ON ri.recipe_uuid = r.uuid
      WHERE r.is_active = 1
      GROUP BY r.id
      ORDER BY profit_margin_percent DESC
    `).all();

    // Categorize recipes by profitability
    const highProfit = recipes.filter(r => r.profit_margin_percent >= 40);
    const mediumProfit = recipes.filter(r => r.profit_margin_percent >= 20 && r.profit_margin_percent < 40);
    const lowProfit = recipes.filter(r => r.profit_margin_percent < 20 && r.profit_margin_percent > 0);
    const lossmaking = recipes.filter(r => r.profit_margin_percent <= 0);

    res.json({
      success: true,
      summary: {
        total_recipes: recipes.length,
        high_profit_count: highProfit.length,
        medium_profit_count: mediumProfit.length,
        low_profit_count: lowProfit.length,
        lossmaking_count: lossmaking.length,
        average_margin: recipes.length > 0
          ? (recipes.reduce((sum, r) => sum + r.profit_margin_percent, 0) / recipes.length).toFixed(2)
          : 0
      },
      high_profit_recipes: highProfit.slice(0, 10),
      low_profit_recipes: [...lowProfit, ...lossmaking].slice(0, 10)
    });
  } catch (error) {
    logger.error('Get profitability analysis error', { error: error.message });
    res.status(500).json({
      success: false,
      error: 'Failed to get profitability analysis'
    });
  }
}

module.exports = {
  listRecipes,
  getRecipe,
  createRecipe,
  updateRecipe,
  deleteRecipe,
  recalculateCost,
  getProfitabilityAnalysis
};
