const { Kafka } = require("kafkajs");

describe("Kafka Integration Tests", () => {
  const kafka = new Kafka({
    brokers: [process.env.KAFKA_BROKER || "unityexpress-kafka:9092"]
  });

  it("should connect to broker", async () => {
    const producer = kafka.producer();
    await expect(producer.connect()).resolves.not.toThrow();
    await producer.disconnect();
  });
});
