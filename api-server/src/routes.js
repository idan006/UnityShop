// api-server/src/routes.js
const express = require("express");
const router = express.Router();
const { Purchase } = require("./mongo");
const { publishPurchase } = require("./kafka");

// ------------------------------------------------------------
// CREATE purchase
// ------------------------------------------------------------
router.post("/purchases", async (req, res) => {
  try {
    const purchase = await Purchase.create({
      username: req.body.username,
      userid: req.body.userid,
      price: req.body.price,
      timestamp: new Date()
    });

    // Fire-and-forget Kafka (NEVER awaited)
    publishPurchase(purchase).catch(err =>
      console.warn("[Kafka] Publish skipped:", err.message)
    );

    res.status(201).json({ ok: true, purchase });
  } catch (err) {
    console.error("[API] POST /purchases error:", err);
    res.status(500).json({ error: "Internal server error" });
  }
});

// ------------------------------------------------------------
// GET purchases
// ------------------------------------------------------------
router.get("/purchases", async (req, res) => {
  try {
    const purchases = await Purchase.find().sort({ createdAt: -1 });
    res.json({ purchases });
  } catch (err) {
    console.error("[API] GET /purchases error:", err);
    res.status(500).json({ error: "Internal server error" });
  }
});

module.exports = router;
