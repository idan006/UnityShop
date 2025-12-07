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

module.exports = { config };
