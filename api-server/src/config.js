const config = {
  port: process.env.PORT || 3000,

  mongoUri: process.env.MONGO_URI || "mongodb://unityexpress-mongo:27017/unityexpress",

  kafkaBrokers: (process.env.KAFKA_BROKERS || "unityexpress-kafka:9092").split(","),
  kafkaTopic: process.env.KAFKA_TOPIC || "purchases",

  kafkaClientId: process.env.KAFKA_CLIENT_ID || "unityexpress-api",

  // CRITICAL FIX
  kafkaGroupId:
    process.env.KAFKA_GROUP_ID ||
    process.env.KAFKA_CONSUMER_GROUP ||
    "unityexpress-consumers",

  projectUuid: process.env.PROJECT_UUID || "UNKNOWN"
};

// Validate critical configuration at startup
function validateConfig() {
  const errors = [];

  // Check port is valid
  if (isNaN(config.port) || config.port < 1 || config.port > 65535) {
    errors.push("PORT must be a valid port number (1-65535)");
  }

  // Check MongoDB URI is provided
  if (!config.mongoUri || config.mongoUri.trim() === "") {
    errors.push("MONGO_URI is required");
  }

  // Check Kafka brokers are provided
  if (!config.kafkaBrokers || config.kafkaBrokers.length === 0) {
    errors.push("KAFKA_BROKERS must be provided");
  }

  if (errors.length > 0) {
    console.error("Configuration validation failed:");
    errors.forEach(err => console.error(`  - ${err}`));
    process.exit(1);
  }
}

module.exports = { config, validateConfig };
