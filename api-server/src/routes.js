const express = require("express");
const router = express.Router();
const { Purchase } = require("./mongo");
const { publishPurchase } = require("./kafka");

// POST /purchases
router.post("/purchases", async (req, res) => {
  try {
    const { username, userid, price, timestamp } = req.body;

    if (!username || !userid || price == null) {
      return res.status(400).json({ error: "Missing required fields" });
    }

    // Safe timestamp handling
    let finalTimestamp;
    if (timestamp && !isNaN(new Date(timestamp).valueOf())) {
      finalTimestamp = new Date(timestamp);
    } else {
      finalTimestamp = new Date();
    }

    const purchaseData = {
      username,
      userid,
      price: Number(price),
      timestamp: finalTimestamp
    };

    const doc = new Purchase(purchaseData);
    await doc.save();

    await publishPurchase(purchaseData);

    return res.status(201).json({ ok: true, purchase: doc });
  } catch (err) {
    console.error("[API] POST /purchases error:", err);
    return res.status(500).json({ error: "Internal server error" });
  }
});

// GET /purchases
router.get("/purchases", async (_req, res) => {
  try {
    const purchases = await Purchase.find().sort({ createdAt: -1 }).lean();
    return res.json({ purchases });
  } catch (err) {
    console.error("[API] GET /purchases error:", err);
    return res.status(500).json({ error: "Internal server error" });
  }
});

module.exports = { router };
