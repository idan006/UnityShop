export const api = {
  getPurchases: jest.fn().mockResolvedValue([
    { username: "mock1", price: 10 },
    { username: "mock2", price: 20 }
  ]),

  createPurchase: jest.fn().mockResolvedValue({
    ok: true,
    purchase: { username: "mock-created", price: 99 }
  })
};
