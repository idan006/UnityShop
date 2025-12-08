// api-server/src/kafka.js
const { Kafka } = require("kafkajs");
const { config } = require("./config");
const { 
  kafkaMessagesPublished,
  kafkaPublishDuration,
  kafkaConnectionStatus,
  kafkaPublishErrors
} = require("./metrics");

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
      eachMessage: async ({ topic, partition, message }) => {
        try {
          const value = message.value.toString();
          console.log(`[Kafka] Consumed from ${topic} [${partition}]:`, value);
          
          // Track consumed messages (optional)
          // consumedMessagesCounter.labels(topic).inc();
        } catch (err) {
          console.error("[Kafka] Consume error:", err.message);
        }
      }
    });
    
    kafkaReady = true;
    kafkaConnectionStatus.set(1);
    console.log("[Kafka] READY");
    
  } catch (err) {
    console.warn("[Kafka] Connection failed (non-fatal):", err.message);
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
    console.log('[Kafka] Producer connected');
    kafkaConnectionStatus.set(1);
  });
  
  producer.on('producer.disconnect', () => {
    console.log('[Kafka] Producer disconnected');
    kafkaConnectionStatus.set(0);
    kafkaReady = false;
  });
  
  producer.on('producer.network.request_timeout', ({ payload }) => {
    console.warn('[Kafka] Request timeout:', payload);
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
    console.warn("[Kafka] Not ready — skipping publish");
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
    
    console.log(`[Kafka] Published purchase ${purchase._id} in ${duration}s`);
    
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
    } else if (err.name === 'KafkaJSRequestTimeoutError') {
      kafkaPublishErrors.labels(config.kafkaTopic, 'timeout').inc();
    } else {
      kafkaPublishErrors.labels(config.kafkaTopic, 'unknown').inc();
    }
    
    console.warn("[Kafka] Publish failed (non-fatal):", err.message);
  }
}

// ---------------------------------------------
// Graceful shutdown
// ---------------------------------------------
async function disconnectKafka() {
  if (kafkaReady && producer && consumer) {
    console.log('[Kafka] Disconnecting...');
    try {
      await Promise.all([
        producer.disconnect(),
        consumer.disconnect()
      ]);
      kafkaConnectionStatus.set(0);
      console.log('[Kafka] Disconnected');
    } catch (err) {
      console.error('[Kafka] Disconnect error:', err.message);
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