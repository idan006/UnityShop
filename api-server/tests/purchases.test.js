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
// Positive Flow - Valid UUID format
// ---------------------------------------------------------------------------
//
test("POST /api/purchases creates a purchase with valid UUID", async () => {
  const validUUID = "550e8400-e29b-41d4-a716-446655440000";
  const payload = {
    username: "idan",
    userid: validUUID,
    price: 42.5
  };

  const response = await request(app)
    .post("/api/purchases")
    .send(payload)
    .expect(201);

  expect(response.body.purchase).toBeDefined();
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
  const validUUID = "550e8400-e29b-41d4-a716-446655440000";
  await Purchase.create({
    username: "idan",
    userid: validUUID,
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
      // Missing userid, price
    })
    .expect(400);

  expect(response.body.error).toBeDefined();
  expect(response.body.details).toBeDefined();

  const docs = await Purchase.find();
  expect(docs.length).toBe(0);
});

test("POST fails when price is negative", async () => {
  const validUUID = "550e8400-e29b-41d4-a716-446655440000";
  const response = await request(app)
    .post("/api/purchases")
    .send({
      username: "idan",
      userid: validUUID,
      price: -5
    })
    .expect(400);

  expect(response.body.error).toBeDefined();
  expect(response.body.details).toBeDefined();
});

test("POST fails when price is not a number", async () => {
  const validUUID = "550e8400-e29b-41d4-a716-446655440000";
  const response = await request(app)
    .post("/api/purchases")
    .send({
      username: "idan",
      userid: validUUID,
      price: "hello"
    })
    .expect(400);

  expect(response.body.error).toBeDefined();
});

test("POST fails when userid is not a valid UUID", async () => {
  const response = await request(app)
    .post("/api/purchases")
    .send({
      username: "idan",
      userid: "not-a-uuid",
      price: 100
    })
    .expect(400);

  expect(response.body.error).toBeDefined();
  expect(response.body.details).toBeDefined();
});

test("POST fails when username is too short", async () => {
  const validUUID = "550e8400-e29b-41d4-a716-446655440000";
  const response = await request(app)
    .post("/api/purchases")
    .send({
      username: "ab", // Too short - needs min 3
      userid: validUUID,
      price: 100
    })
    .expect(400);

  expect(response.body.error).toBeDefined();
});

//
// ---------------------------------------------------------------------------
// Kafka Failure Scenarios
// ---------------------------------------------------------------------------
//
test("POST creates purchase even if Kafka fails", async () => {
  const validUUID = "550e8400-e29b-41d4-a716-446655440000";
  kafka.publishPurchase.mockRejectedValueOnce(new Error("Kafka down"));

  const payload = {
    username: "idan",
    userid: validUUID,
    price: 200
  };

  const response = await request(app)
    .post("/api/purchases")
    .send(payload)
    .expect(201);

  expect(response.body.purchase).toBeDefined();

  // Purchase must be persisted even if Kafka is down
  const docs = await Purchase.find();
  expect(docs.length).toBe(1);
});

//
// ---------------------------------------------------------------------------
// Sorting, Filtering, Data Quality Tests
// ---------------------------------------------------------------------------
//
test("GET returns purchases sorted by timestamp descending", async () => {
  const validUUID1 = "550e8400-e29b-41d4-a716-446655440001";
  const validUUID2 = "550e8400-e29b-41d4-a716-446655440002";
  const validUUID3 = "550e8400-e29b-41d4-a716-446655440003";

  // Insert and let MongoDB set createdAt
  await Purchase.create({ username: "u1", userid: validUUID1, price: 10, timestamp: new Date("2021-01-01") });
  await new Promise(resolve => setTimeout(resolve, 10));
  
  await Purchase.create({ username: "u2", userid: validUUID2, price: 20, timestamp: new Date("2022-01-01") });
  await new Promise(resolve => setTimeout(resolve, 10));
  
  await Purchase.create({ username: "u3", userid: validUUID3, price: 30, timestamp: new Date("2023-01-01") });

  const res = await request(app).get("/api/purchases").expect(200);

  // Should be sorted by createdAt descending, so u3 (most recent) comes first
  expect(res.body.purchases[0].username).toBe("u3");
  expect(res.body.purchases[1].username).toBe("u2");
  expect(res.body.purchases[2].username).toBe("u1");
});

test("GET returns empty list when no documents exist", async () => {
  const res = await request(app).get("/api/purchases").expect(200);
  expect(res.body.purchases).toEqual([]);
});
