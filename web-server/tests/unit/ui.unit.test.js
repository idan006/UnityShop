/**
 * UI Tests for UnityExpress Frontend
 * Uses JSDOM to simulate browser behavior
 */

import { 
  renderPurchases, 
  addPurchase, 
  clearPurchases, 
  validatePurchaseForm,
  formatPrice,
  connectWebSocket
} from "../app.js";

import { JSDOM } from "jsdom";

// ---------------------------------------------------------
// JSDOM setup
// ---------------------------------------------------------
let dom;
let document;

beforeEach(() => {
  dom = new JSDOM(`
    <body>
      <div id="purchase-list"></div>
      <form id="purchase-form">
        <input id="username" />
        <input id="userid" />
        <input id="price" />
      </form>
    </body>
  `);

  document = dom.window.document;

  global.document = document;
  global.window = dom.window;
  global.HTMLElement = dom.window.HTMLElement;
});

// ---------------------------------------------------------
// 1. Rendering Tests
// ---------------------------------------------------------

test("renderPurchases() should render all purchase items", () => {
  const items = [
    { username: "idan", price: 10 },
    { username: "john", price: 20 }
  ];

  renderPurchases(items);

  const list = document.getElementById("purchase-list");
  expect(list.children.length).toBe(2);
});

test("renderPurchases() clears old items before rendering", () => {
  renderPurchases([{ username: "a", price: 5 }]);
  renderPurchases([{ username: "b", price: 10 }]);

  const list = document.getElementById("purchase-list");
  expect(list.children.length).toBe(1);
});

// ---------------------------------------------------------
// 2. Add Purchase Tests
// ---------------------------------------------------------

test("addPurchase() appends a new purchase item", () => {
  addPurchase({ username: "idan", price: 99 });

  const list = document.getElementById("purchase-list");
  expect(list.children.length).toBe(1);
  expect(list.textContent).toContain("idan");
});

test("clearPurchases() should empty the UI list", () => {
  addPurchase({ username: "idan", price: 10 });
  clearPurchases();

  const list = document.getElementById("purchase-list");
  expect(list.children.length).toBe(0);
});

// ---------------------------------------------------------
// 3. Validation Tests
// ---------------------------------------------------------

test("validatePurchaseForm() fails when username is empty", () => {
  const result = validatePurchaseForm({
    username: "",
    userid: "123",
    price: "10"
  });

  expect(result.ok).toBe(false);
  expect(result.error).toContain("username");
});

test("validatePurchaseForm() fails when price is invalid", () => {
  const result = validatePurchaseForm({
    username: "idan",
    userid: "123",
    price: "abc"
  });

  expect(result.ok).toBe(false);
  expect(result.error).toContain("price");
});

test("validatePurchaseForm() passes with correct inputs", () => {
  const result = validatePurchaseForm({
    username: "idan",
    userid: "123",
    price: "42"
  });

  expect(result.ok).toBe(true);
});

// ---------------------------------------------------------
// 4. Format Price
// ---------------------------------------------------------

test("formatPrice() formats numbers correctly", () => {
  expect(formatPrice(10)).toBe("₪10.00");
  expect(formatPrice(10.5)).toBe("₪10.50");
});

// ---------------------------------------------------------
// 5. WebSocket Tests
// ---------------------------------------------------------

test("connectWebSocket() should attempt to open a WebSocket connection", () => {
  const mockWS = jest.fn();
  global.WebSocket = mockWS;

  connectWebSocket();

  expect(mockWS).toHaveBeenCalled();
});

test("connectWebSocket() handles incoming WebSocket messages", () => {
  const mockAdd = jest.spyOn(global, "addPurchase").mockImplementation(() => {});
  const mockWS = {
    onmessage: null,
    send: jest.fn()
  };

  global.WebSocket = jest.fn(() => mockWS);

  connectWebSocket();

  const msg = { data: JSON.stringify({ username: "idan", price: 10 }) };
  mockWS.onmessage(msg);

  expect(mockAdd).toHaveBeenCalledWith({ username: "idan", price: 10 });
});
