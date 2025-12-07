const request = require("supertest");
const mongoose = require("mongoose");
const { MongoMemoryServer } = require("mongodb-memory-server");
const { app } = require("../src/index");
const { Purchase } = require("../src/mongo");

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
  if (mongoServer) {
    await mongoServer.stop();
  }
});

beforeEach(async () => {
  await Purchase.deleteMany({});
});

test("POST /api/purchases creates a purchase", async () => {
  const response = await request(app)
    .post("/api/purchases")
    .send({
      username: "idan",
      userid: "user-123",
      price: 42.5,
      timestamp: new Date().toISOString()
    })
    .expect(201);

  expect(response.body.ok).toBe(true);
  expect(response.body.purchase.username).toBe("idan");

  const docs = await Purchase.find();
  expect(docs.length).toBe(1);
});

test("GET /api/purchases returns list", async () => {
  await Purchase.create({
    username: "idan",
    userid: "user-123",
    price: 10,
    timestamp: new Date()
  });

  const response = await request(app).get("/api/purchases").expect(200);

  expect(Array.isArray(response.body.purchases)).toBe(true);
  expect(response.body.purchases.length).toBe(1);
});
