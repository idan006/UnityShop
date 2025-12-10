// api-server/src/index.js
const express = require("express");
const mongoose = require("mongoose");
const cors = require("cors");
const { config, validateConfig } = require("./config");
const { createLogger } = require("./logger");
const { publishPurchase } = require("./kafka");
const { Purchase } = require("./mongo");
const { validateCreatePurchase } = require("./validators/purchase");
const { errorHandler } = require("./middleware/errorHandler");

const logger = createLogger("API");
const app = express();

// Validate configuration before starting
validateConfig();

app.use(cors());
app.use(express.json());

// --------------------------------------------------
// Health endpoints
// --------------------------------------------------
app.get("/health", (req, res) => {
  res.json({ status: "ok" });
});

app.get("/ready", (req, res) => {
  if (mongoose.connection.readyState === 1) {
    return res.json({ status: "ready" });
  }
  return res.status(503).json({ status: "not_ready" });
});

// --------------------------------------------------
// API routes
// --------------------------------------------------
app.get("/api/purchases", async (req, res, next) => {
  try {
    logger.info("Fetching purchases");
    const purchases = await Purchase.find().sort({ createdAt: -1 }).limit(100);
    logger.info("Purchases fetched successfully", { count: purchases.length });
    res.json({ purchases });
  } catch (err) {
    logger.error("GET /api/purchases failed", { message: err.message, stack: err.stack });
    next(err);
  }
});

app.post("/api/purchases", validateCreatePurchase, async (req, res, next) => {
  try {
    const { username, userid, price } = req.validatedBody;

    logger.info("Creating purchase", { username, userid, price });

    const purchase = await Purchase.create({
      username,
      userid,
      price,
      timestamp: new Date()
    });

    // Fire-and-forget Kafka publish (non-blocking)
    publishPurchase(purchase).catch(err => {
      logger.warn("Kafka publish failed", { message: err.message, purchaseId: purchase._id });
    });

    logger.info("Purchase created successfully", { purchaseId: purchase._id, username });
    res.status(201).json({ purchase });
  } catch (err) {
    logger.error("POST /api/purchases failed", { message: err.message, stack: err.stack });
    next(err);
  }
});

// --------------------------------------------------
// Global error handler (must be last)
// --------------------------------------------------
app.use(errorHandler);

// --------------------------------------------------
// Startup
// --------------------------------------------------
async function start() {
  try {
    logger.info("Starting UnityExpress API", { port: config.port });
    logger.info("Connecting to MongoDB", { mongoUri: config.mongoUri.replace(/:\w+@/, ":***@") });

    await mongoose.connect(config.mongoUri, {
      serverSelectionTimeoutMS: 30000
    });

    logger.info("MongoDB connected successfully");

    // Properly await server startup
    await new Promise((resolve, reject) => {
      const server = app.listen(config.port, (err) => {
        if (err) reject(err);
        else {
          logger.info("API server listening", { port: config.port });
          resolve(server);
        }
      });
    });

  } catch (err) {
    logger.error("Startup failed", { message: err.message, stack: err.stack });
    process.exit(1);
  }
}

// Export app for testing
module.exports = { app };

// Start server only if not in test mode
if (process.env.NODE_ENV !== 'test' && require.main === module) {
  start();
}
