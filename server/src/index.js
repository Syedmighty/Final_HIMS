/**
 * HIMS Sync Server - Main Entry Point
 * LAN-based sync server for Hotel Inventory Management System
 */

require('dotenv').config();

const express = require('express');
const cors = require('cors');
const helmet = require('helmet');
const compression = require('compression');
const morgan = require('morgan');
const rateLimit = require('express-rate-limit');

const { initDatabase, closeDatabase, integrityCheck } = require('./config/database');
const logger = require('./config/logger');

// Import routes
const authRoutes = require('./routes/auth');
const deviceRoutes = require('./routes/devices');
const syncRoutes = require('./routes/sync');
const healthRoutes = require('./routes/health');
const productsRoutes = require('./routes/products');
const purchasesRoutes = require('./routes/purchases');
const issuesRoutes = require('./routes/issues');
const transfersRoutes = require('./routes/transfers');
const invoicesRoutes = require('./routes/invoices');
const wastageRoutes = require('./routes/wastage');
const locationsRoutes = require('./routes/locations');
const recipesRoutes = require('./routes/recipes');

// Initialize Express app
const app = express();
const PORT = process.env.PORT || 3000;
const HOST = process.env.HOST || '0.0.0.0';

// ============================================================================
// MIDDLEWARE CONFIGURATION
// ============================================================================

// Security headers
app.use(helmet());

// CORS
app.use(cors({
  origin: process.env.CORS_ORIGIN || '*',
  methods: ['GET', 'POST', 'PUT', 'DELETE'],
  allowedHeaders: ['Content-Type', 'Authorization']
}));

// Body parsing
app.use(express.json({ limit: '10mb' }));
app.use(express.urlencoded({ extended: true, limit: '10mb' }));

// Compression
if (process.env.ENABLE_COMPRESSION === 'true') {
  app.use(compression());
}

// Logging
if (process.env.NODE_ENV !== 'production') {
  app.use(morgan('dev'));
} else {
  app.use(morgan('combined', {
    stream: {
      write: (message) => logger.info(message.trim())
    }
  }));
}

// Rate limiting
const limiter = rateLimit({
  windowMs: parseInt(process.env.RATE_LIMIT_WINDOW_MS) || 60000,
  max: parseInt(process.env.RATE_LIMIT_MAX_REQUESTS) || 20,
  message: 'Too many requests from this IP, please try again later',
  standardHeaders: true,
  legacyHeaders: false
});

app.use('/api/', limiter);

// ============================================================================
// ROUTES
// ============================================================================

app.use('/api/health', healthRoutes);
app.use('/api/auth', authRoutes);
app.use('/api/devices', deviceRoutes);
app.use('/api/sync', syncRoutes);
app.use('/api/admin/devices', deviceRoutes);
app.use('/api/products', productsRoutes);
app.use('/api/purchases', purchasesRoutes);
app.use('/api/issues', issuesRoutes);
app.use('/api/transfers', transfersRoutes);
app.use('/api/invoices', invoicesRoutes);
app.use('/api/wastage', wastageRoutes);
app.use('/api/locations', locationsRoutes);
app.use('/api/recipes', recipesRoutes);

// Root route
app.get('/', (req, res) => {
  res.json({
    name: 'HIMS Sync Server',
    version: '1.0.1',
    status: 'running',
    endpoints: {
      health: '/api/health',
      devices: '/api/devices',
      sync: '/api/sync',
      admin: '/api/admin/devices'
    }
  });
});

// ============================================================================
// ERROR HANDLING
// ============================================================================

// 404 handler
app.use((req, res) => {
  res.status(404).json({
    success: false,
    error: 'Endpoint not found',
    path: req.path
  });
});

// Global error handler
app.use((err, req, res, next) => {
  logger.error('Unhandled error', {
    error: err.message,
    stack: err.stack,
    path: req.path,
    method: req.method
  });

  res.status(err.status || 500).json({
    success: false,
    error: err.message || 'Internal server error',
    details: process.env.NODE_ENV === 'development' ? err.stack : undefined
  });
});

// ============================================================================
// SERVER INITIALIZATION
// ============================================================================

function startServer() {
  try {
    // Initialize database
    logger.info('Initializing database...');
    initDatabase();

    // Run integrity check
    logger.info('Running database integrity check...');
    const health = integrityCheck();
    if (!health.isHealthy) {
      logger.error('Database integrity check failed', health);
      process.exit(1);
    }
    logger.info('Database integrity check passed ✓');

    // Start server
    const server = app.listen(PORT, HOST, () => {
      logger.info(`🚀 HIMS Sync Server started`);
      logger.info(`📡 Listening on ${HOST}:${PORT}`);
      logger.info(`🌍 Environment: ${process.env.NODE_ENV || 'development'}`);
      logger.info(`📊 Max devices: ${process.env.MAX_DEVICES || 5}`);
    });

    // Graceful shutdown
    const shutdown = (signal) => {
      logger.info(`${signal} received. Closing server gracefully...`);
      server.close(() => {
        logger.info('HTTP server closed');
        closeDatabase();
        logger.info('Database connection closed');
        process.exit(0);
      });

      // Force close after 10 seconds
      setTimeout(() => {
        logger.error('Forced shutdown after timeout');
        process.exit(1);
      }, 10000);
    };

    process.on('SIGTERM', () => shutdown('SIGTERM'));
    process.on('SIGINT', () => shutdown('SIGINT'));

    // Handle uncaught exceptions
    process.on('uncaughtException', (err) => {
      logger.error('Uncaught exception', { error: err.message, stack: err.stack });
      process.exit(1);
    });

    process.on('unhandledRejection', (reason, promise) => {
      logger.error('Unhandled rejection', { reason, promise });
      process.exit(1);
    });
  } catch (error) {
    logger.error('Server initialization failed', {
      error: error.message,
      stack: error.stack
    });
    process.exit(1);
  }
}

// Start the server
if (require.main === module) {
  startServer();
}

module.exports = app;
