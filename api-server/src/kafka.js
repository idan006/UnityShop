// api-server/src/kafka.js
const { Kafka } = require("kafkajs");
const { config } = require("./config");
const { createLogger } = require("./logger");
const { 
  kafkaMessagesPublished,
  kafkaPublishDuration,
  kafkaConnectionStatus,
  kafkaPublishErrors
} = require("./metrics");

const logger = createLogger("Kafka");

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
    logger.info("Connecting to Kafka", { brokers: config.kafkaBrokers, clientId: config.kafkaClientId });
    
    await producer.connect();
    await consumer.connect();
    
    await consumer.subscribe({
      topic: config.kafkaTopic,
      fromBeginning: true
    });
    
    consumer.run({
      eachMessage: async ({ topic, partition, message }) => {
        try {
          const value = message.value.toString();
          logger.debug("Message consumed", { topic, partition, messageSize: value.length });
        } catch (err) {
          logger.error("Consume error", { message: err.message });
        }
      }
    });
    
    kafkaReady = true;
    kafkaConnectionStatus.set(1);
    logger.info("Kafka ready");
    
  } catch (err) {
    logger.warn("Kafka connection failed (non-fatal, will retry)", { message: err.message });
    kafkaConnectionStatus.set(0);
    kafkaPublishErrors.labels(config.kafkaTopic, 'connection_error').inc();
  }
  
  connecting = false;
}

// Background retry every 10s
setInterval(tryConnectKafka, 10000).unref();
tryConnectKafka();

// ---------------------------------------------
// Monitor Kafka events
// ---------------------------------------------
function setupKafkaEventHandlers() {
  if (!producer) return;
  
  producer.on('producer.connect', () => {
    logger.info("Kafka producer connected");
    kafkaConnectionStatus.set(1);
  });
  
  producer.on('producer.disconnect', () => {
    logger.warn("Kafka producer disconnected");
    kafkaConnectionStatus.set(0);
    kafkaReady = false;
  });
  
  producer.on('producer.network.request_timeout', ({ payload }) => {
    logger.warn("Kafka request timeout");
    kafkaPublishErrors.labels(config.kafkaTopic, 'timeout').inc();
  });
}

// Setup event handlers after first connection attempt
setTimeout(() => setupKafkaEventHandlers(), 1000);

// ---------------------------------------------
// SAFE publish — never throws, tracks metrics
// ---------------------------------------------
async function publishPurchase(purchase) {
  initKafka();
  
  const startTime = Date.now();
  
  if (!kafkaReady) {
    logger.debug("Kafka not ready, skipping publish");
    kafkaMessagesPublished.labels(config.kafkaTopic, 'skipped').inc();
    return;
  }
  
  try {
    await producer.send({
      topic: config.kafkaTopic,
      messages: [
        {
          key: purchase.userid || purchase._id?.toString(),
          value: JSON.stringify({
            id: purchase._id,
            username: purchase.username,
            userid: purchase.userid,
            price: purchase.price,
            timestamp: purchase.timestamp || new Date()
          }),
          headers: {
            'content-type': 'application/json',
            'source': 'unityexpress-api'
          }
        }
      ]
    });
    
    const duration = (Date.now() - startTime) / 1000;
    
    // Record success metrics
    kafkaMessagesPublished.labels(config.kafkaTopic, 'success').inc();
    kafkaPublishDuration.labels(config.kafkaTopic, 'success').observe(duration);
    
    logger.debug("Purchase published to Kafka", { purchaseId: purchase._id, durationSeconds: duration });
    
  } catch (err) {
    const duration = (Date.now() - startTime) / 1000;
    
    // Record error metrics
    kafkaMessagesPublished.labels(config.kafkaTopic, 'error').inc();
    kafkaPublishDuration.labels(config.kafkaTopic, 'error').observe(duration);
    
    // Classify error type
    if (err.name === 'KafkaJSConnectionError') {
      kafkaPublishErrors.labels(config.kafkaTopic, 'connection_error').inc();
      kafkaConnectionStatus.set(0);
      kafkaReady = false;
      logger.error("Kafka connection error", { message: err.message });
    } else if (err.name === 'KafkaJSRequestTimeoutError') {
      kafkaPublishErrors.labels(config.kafkaTopic, 'timeout').inc();
      logger.warn("Kafka timeout", { message: err.message });
    } else {
      kafkaPublishErrors.labels(config.kafkaTopic, 'unknown').inc();
      logger.error("Kafka publish error", { message: err.message });
    }
  }
}

// ---------------------------------------------
// Graceful shutdown
// ---------------------------------------------
async function disconnectKafka() {
  if (kafkaReady && producer && consumer) {
    logger.info("Disconnecting from Kafka");
    try {
      await Promise.all([
        producer.disconnect(),
        consumer.disconnect()
      ]);
      kafkaConnectionStatus.set(0);
      logger.info("Kafka disconnected");
    } catch (err) {
      logger.error("Kafka disconnect error", { message: err.message });
    }
  }
}

// Handle process termination
process.on('SIGTERM', disconnectKafka);
process.on('SIGINT', disconnectKafka);

module.exports = { 
  publishPurchase,
  disconnectKafka,
  getKafkaStatus: () => kafkaReady
};