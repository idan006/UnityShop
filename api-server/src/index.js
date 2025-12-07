const express = require("express");
const cors = require("cors");
const { router } = require("./routes");
const { connectMongo } = require("./mongo");
const { startKafka } = require("./kafka");

async function start() {
  console.log("[API] Starting UnityExpress API");

  await connectMongo();

  await startKafka();

  const app = express();
  app.use(cors());
  app.use(express.json());
  app.use("/api", router);

  const PORT = process.env.PORT || 3000;
  app.listen(PORT, () => console.log("[API] Listening on port", PORT));

  app.get("/health", (req, res) => res.json({ ok: true }));
}

start().catch(err => {
  console.error("[API] Startup failed:", err);
  process.exit(1);
});
