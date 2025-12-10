const mongoose = require("mongoose");
const { config } = require("./config");
const { createLogger } = require("./logger");

const logger = createLogger("MongoDB");

const purchaseSchema = new mongoose.Schema(
  {
    username: { type: String, required: true },
    userid: { type: String, required: true },
    price: { type: Number, required: true },
    timestamp: { type: Date, required: true }
  },
  { timestamps: true }
);

const Purchase = mongoose.model("Purchase", purchaseSchema);

async function connectMongo() {
  mongoose.set("strictQuery", true);

  const uri =
    process.env.MONGO_URI ||
    process.env.MONGO_URL ||
    config.mongoUri;

  logger.info("Connecting to MongoDB");

  await mongoose.connect(uri, {
    serverSelectionTimeoutMS: 5000
  });

  logger.info("MongoDB connected successfully");
}

module.exports = { Purchase, connectMongo };
