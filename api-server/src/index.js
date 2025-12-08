// api-server/src/index.js
const express = require("express");
const mongoose = require("mongoose");
const cors = require("cors");
const { config } = require("./config");
const { publishPurchase } = require("./kafka");
const { Purchase } = require("./mongo");
const app = express();

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
app.get("/api/purchases", async (req, res) => {
  try {
    const purchases = await Purchase.find().sort({ createdAt: -1 }).limit(100);
    res.json({ purchases });
  } catch (err) {
    console.error("[API] GET /purchases error:", err);
    res.status(500).json({ error: "Internal server error" });
  }
});

app.post("/api/purchases", async (req, res) => {
  try {
    const { username, userid, price } = req.body;

    if (!username || !userid || typeof price !== "number") {
      return res.status(400).json({ error: "Invalid payload" });
    }

    const purchase = await Purchase.create({
      username,
      userid,
      price,
      timestamp: new Date()
    });

    // Fire-and-forget Kafka publish (non-blocking)
    publishPurchase(purchase).catch(err => {
      console.warn("[API] Kafka publish failed:", err.message);
    });

    res.status(201).json({ purchase });
  } catch (err) {
    console.error("[API] POST /purchases error:", err);
    res.status(500).json({ error: "Internal server error" });
  }
});

// --------------------------------------------------
// Startup
// --------------------------------------------------
async function start() {
  try {
    console.log("[API] Starting UnityExpress API");
    console.log("[Mongo] Connecting to:", config.mongoUri);

    await mongoose.connect(config.mongoUri, {
      serverSelectionTimeoutMS: 30000
    });

    console.log("[Mongo] Connected");

    // Properly await server startup
    await new Promise((resolve, reject) => {
      const server = app.listen(config.port, (err) => {
        if (err) reject(err);
        else {
          console.log(`[API] Listening on port ${config.port}`);
          resolve(server);
        }
      });
    });

  } catch (err) {
    console.error("[API] Startup failed:", err);
    console.error("[API] Error message:", err.message);
    process.exit(1);
  }
}

start();