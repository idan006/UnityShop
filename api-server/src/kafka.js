// api-server/src/kafka.js
const { Kafka } = require("kafkajs");
const { config } = require("./config");

let kafka = null;
let producer = null;
let consumer = null;
let kafkaReady = false;
let connecting = false;

// ---------------------------------------------
// Lazy init
// ---------------------------------------------
function initKafka() {
  if (kafka) return;

  kafka = new Kafka({
    clientId: config.kafkaClientId,
    brokers: config.kafkaBrokers,
    connectionTimeout: 5000,
    requestTimeout: 5000
  });

  producer = kafka.producer();
  consumer = kafka.consumer({ groupId: config.kafkaGroupId });
}

// ---------------------------------------------
// Safe connect (non-fatal, retried in background)
// ---------------------------------------------
async function tryConnectKafka() {
  if (connecting || kafkaReady) return;
  connecting = true;

  try {
    initKafka();

    console.log("[Kafka] Connecting...");
    await producer.connect();
    await consumer.connect();

    await consumer.subscribe({
      topic: config.kafkaTopic,
      fromBeginning: true
    });

    consumer.run({
      eachMessage: async ({ message }) => {
        try {
          console.log("[Kafka] Consumed:", message.value.toString());
        } catch (err) {
          console.error("[Kafka] Consume error:", err.message);
        }
      }
    });

    kafkaReady = true;
    console.log("[Kafka] READY");
  } catch (err) {
    console.warn("[Kafka] Connection failed (non-fatal):", err.message);
  }

  connecting = false;
}

// Background retry every 10s
setInterval(tryConnectKafka, 10000).unref();
tryConnectKafka();

// ---------------------------------------------
// SAFE publish — never throws
// ---------------------------------------------
async function publishPurchase(purchase) {
  initKafka();

  if (!kafkaReady) {
    console.warn("[Kafka] Not ready — skipping publish");
    return;
  }

  try {
    await producer.send({
      topic: config.kafkaTopic,
      messages: [{ value: JSON.stringify(purchase) }]
    });
    console.log("[Kafka] Published:", purchase._id || purchase);
  } catch (err) {
    console.warn("[Kafka] Publish failed (non-fatal):", err.message);
  }
}

module.exports = { publishPurchase };
