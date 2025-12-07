const mongoose = require("mongoose");
const { config } = require("./config");

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

  console.log("[Mongo] Connecting to:", uri);

  await mongoose.connect(uri, {
    serverSelectionTimeoutMS: 5000
  });

  console.log("[Mongo] Connected");
}

module.exports = { Purchase, connectMongo };
