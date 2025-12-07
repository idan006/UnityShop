/**
 * Mock-based tests to validate UI behavior without real backend
 */

import { JSDOM } from "jsdom";

// Auto-mock modules
jest.mock("../api.js");
jest.mock("../websocket.js");

import { api } from "../api.js";
import MockWebSocket from "../websocket.js";
import { renderPurchases, addPurchase, connectWebSocket } from "../app.js";

let dom, document;

beforeEach(() => {
  dom = new JSDOM(`
    <body>
      <div id="purchase-list"></div>
    </body>
  `);

  document = dom.window.document;
  global.document = document;
  global.window = dom.window;
  global.WebSocket = MockWebSocket;
});

/* -----------------------------------------------------------
   1. Test UI rendering with mocked backend purchases
----------------------------------------------------------- */
test("UI loads purchases from mocked API", async () => {
  const purchases = await api.getPurchases();

  renderPurchases(purchases);

  const list = document.getElementById("purchase-list");
  expect(list.children.length).toBe(2);
  expect(list.textContent).toContain("mock1");
  expect(list.textContent).toContain("mock2");
});

/* -----------------------------------------------------------
   2. Test creating a purchase using mocked API
----------------------------------------------------------- */
test("UI creates purchase through mocked API", async () => {
  const res = await api.createPurchase({
    username: "idan",
    price: 50
  });

  addPurchase(res.purchase);

  const list = document.getElementById("purchase-list");

  expect(api.createPurchase).toHaveBeenCalled();
  expect(list.textContent).toContain("mock-created");
});

/* -----------------------------------------------------------
   3. Test WebSocket mocked connection
----------------------------------------------------------- */
test("UI reacts to WebSocket message", () => {
  const mockWS = new MockWebSocket("ws://localhost");

  global.WebSocket = jest.fn(() => mockWS);

  connectWebSocket();

  mockWS.triggerMessage(JSON.stringify({ username: "ws", price: 5 }));

  const list = document.getElementById("purchase-list");

  expect(list.textContent).toContain("ws");
});

/* -----------------------------------------------------------
   4. Test WebSocket sends message back to server
----------------------------------------------------------- */
test("WebSocket send() is tracked", () => {
  const mockWS = new MockWebSocket("ws://localhost");
  global.WebSocket = jest.fn(() => mockWS);

  connectWebSocket();
  mockWS.triggerOpen();

  mockWS.send("hello");

  expect(mockWS.sentMessages).toContain("hello");
});
