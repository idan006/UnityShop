const request = require("supertest");
const mongoose = require("mongoose");
const { MongoMemoryServer } = require("mongodb-memory-server");
const { app } = require("../src/index");
const { Purchase } = require("../src/mongo");
const kafka = require("../src/kafka");

jest.mock("../src/kafka", () => ({
  publishPurchase: jest.fn().mockResolvedValue(undefined)
}));

let mongoServer;

beforeAll(async () => {
  mongoServer = await MongoMemoryServer.create();
  const uri = mongoServer.getUri();
  await mongoose.connect(uri, { serverSelectionTimeoutMS: 5000 });
});

afterAll(async () => {
  await mongoose.disconnect();
  if (mongoServer) await mongoServer.stop();
});

beforeEach(async () => {
  jest.clearAllMocks();
  await Purchase.deleteMany({});
});

//
// ---------------------------------------------------------------------------
// Positive Flow
// ---------------------------------------------------------------------------
//
test("POST /api/purchases creates a purchase", async () => {
  const payload = {
    username: "idan",
    userid: "user-123",
    price: 42.5,
    timestamp: new Date().toISOString()
  };

  const response = await request(app)
    .post("/api/purchases")
    .send(payload)
    .expect(201);

  expect(response.body.ok).toBe(true);
  expect(response.body.purchase.username).toBe("idan");

  const docs = await Purchase.find();
  expect(docs.length).toBe(1);

  // Kafka must be called
  expect(kafka.publishPurchase).toHaveBeenCalledTimes(1);
});

//
// ---------------------------------------------------------------------------
// GET endpoint
// ---------------------------------------------------------------------------
//
test("GET /api/purchases returns list", async () => {
  await Purchase.create({
    username: "idan",
    userid: "user-123",
    price: 10,
    timestamp: new Date()
  });

  const response = await request(app)
    .get("/api/purchases")
    .expect(200);

  expect(Array.isArray(response.body.purchases)).toBe(true);
  expect(response.body.purchases.length).toBe(1);
});

//
// ---------------------------------------------------------------------------
// Validation Tests
// ---------------------------------------------------------------------------
//
test("POST fails when required fields are missing", async () => {
  const response = await request(app)
    .post("/api/purchases")
    .send({
      username: "idan"
      // Missing userid, price, timestamp
    })
    .expect(400);

  expect(response.body.ok).toBe(false);
  expect(response.body.error).toMatch(/missing/i);

  const docs = await Purchase.find();
  expect(docs.length).toBe(0);
});

test("POST fails when price is negative", async () => {
  const response = await request(app)
    .post("/api/purchases")
    .send({
      username: "idan",
      userid: "user-123",
      price: -5,
      timestamp: new Date().toISOString()
    })
    .expect(400);

  expect(response.body.ok).toBe(false);
  expect(response.body.error).toMatch(/price/i);
});

test("POST fails when price is not a number", async () => {
  const response = await request(app)
    .post("/api/purchases")
    .send({
      username: "idan",
      userid: "user-123",
      price: "hello",
      timestamp: new Date().toISOString()
    })
    .expect(400);

  expect(response.body.ok).toBe(false);
  expect(response.body.error).toMatch(/price/i);
});

//
// ---------------------------------------------------------------------------
// Kafka Failure Scenarios
// ---------------------------------------------------------------------------
//
test("POST handles Kafka failure gracefully but still returns 201 if app supports it", async () => {
  kafka.publishPurchase.mockRejectedValueOnce(new Error("Kafka down"));

  const payload = {
    username: "idan",
    userid: "user-123",
    price: 200,
    timestamp: new Date().toISOString()
  };

  const response = await request(app)
    .post("/api/purchases")
    .send(payload)
    .expect(201); // If API is designed to swallow Kafka errors

  expect(response.body.ok).toBe(true);

  // One purchase must be persisted even if Kafka is down
  const docs = await Purchase.find();
  expect(docs.length).toBe(1);
});

//
// ---------------------------------------------------------------------------
// MongoDB Error Injection
// ---------------------------------------------------------------------------
//
test("POST returns 500 when MongoDB insert fails", async () => {
  // Mock Mongo failing
  jest.spyOn(Purchase.prototype, "save").mockImplementationOnce(() => {
    throw new Error("DB insert failed");
  });

  const response = await request(app)
    .post("/api/purchases")
    .send({
      username: "idan",
      userid: "user-123",
      price: 55,
      timestamp: new Date().toISOString()
    })
    .expect(500);

  expect(response.body.ok).toBe(false);
  expect(response.body.error).toMatch(/db/i);
});


//
// ---------------------------------------------------------------------------
// Sorting, Filtering, Data Quality Tests
// ---------------------------------------------------------------------------
//
test("GET returns purchases sorted by timestamp descending", async () => {
  await Purchase.insertMany([
    { username: "u1", userid: "1", price: 10, timestamp: new Date("2021-01-01") },
    { username: "u2", userid: "2", price: 20, timestamp: new Date("2022-01-01") },
    { username: "u3", userid: "3", price: 30, timestamp: new Date("2023-01-01") }
  ]);

  const res = await request(app).get("/api/purchases").expect(200);

  expect(res.body.purchases[0].username).toBe("u3");
  expect(res.body.purchases[2].username).toBe("u1");
});

test("GET returns empty list when no documents exist", async () => {
  const res = await request(app).get("/api/purchases").expect(200);
  expect(res.body.purchases).toEqual([]);
});
