const { Kafka } = require("kafkajs");
const { config } = require("./config");

let kafka;
let producer;
let consumer;

function initKafka() {
  if (kafka) return; // Already initialized

  kafka = new Kafka({
    clientId: config.kafkaClientId,
    brokers: config.kafkaBrokers
  });

  producer = kafka.producer();
  consumer = kafka.consumer({ groupId: config.kafkaGroupId });
}

async function startKafka() {
  initKafka();

  console.log("[Kafka] Starting...");
  console.log("[Kafka] groupId =", config.kafkaGroupId);

  await producer.connect();
  console.log("[Kafka] Producer connected");

  await consumer.connect();
  console.log("[Kafka] Consumer connected");

  await consumer.subscribe({
    topic: config.kafkaTopic,
    fromBeginning: true
  });

  console.log("[Kafka] Subscribed to topic:", config.kafkaTopic);

  await consumer.run({
    eachMessage: async ({ message }) => {
      try {
        const payload = JSON.parse(message.value.toString());
        console.log("[Kafka] Consumed message:", payload);
      } catch (err) {
        console.error("[Kafka] Failed processing message:", err.message);
      }
    }
  });
}

async function publishPurchase(purchase) {
  initKafka();

  if (!producer) {
    throw new Error("Kafka producer not initialized");
  }

  await producer.send({
    topic: config.kafkaTopic,
    messages: [{ value: JSON.stringify(purchase) }]
  });

  console.log("[Kafka] Published:", purchase);
}

module.exports = { startKafka, publishPurchase };
