// =========================================================
//  Dynamic API base – works on ANY computer
//  Routed through the NGINX Gateway automatically
// =========================================================
const API_BASE = "/api";

const toastEl = document.getElementById("toast");
const tableBody = document.getElementById("tableBody");

// ---------------------------------------------------------
// UUID Generator (v4)
// ---------------------------------------------------------
function generateUUID() {
  return "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx".replace(/[xy]/g, function(c) {
    const r = (Math.random() * 16) | 0;
    const v = c === "x" ? r : (r & 0x3) | 0x8;
    return v.toString(16);
  });
}

// ---------------------------------------------------------
// Toast helper
// ---------------------------------------------------------
function toast(message, color = "#43a047") {
  toastEl.style.background = color;
  toastEl.textContent = message;
  toastEl.style.opacity = 1;

  setTimeout(() => (toastEl.style.opacity = 0), 2200);
}

// ---------------------------------------------------------
// API helper
// Uses dynamic relative path: /api/... (no static IP!)
// ---------------------------------------------------------
async function api(method, endpoint, body) {
  try {
    const res = await fetch(`${API_BASE}${endpoint}`, {
      method,
      headers: { "Content-Type": "application/json" },
      body: body ? JSON.stringify(body) : undefined
    });

    if (!res.ok) {
      let errText = await res.text();
      try {
        const jsonErr = JSON.parse(errText);
        // If response is JSON with details, format it nicely
        if (jsonErr.details && Array.isArray(jsonErr.details)) {
          const details = jsonErr.details.map(d => `${d.field}: ${d.message}`).join(", ");
          errText = `Validation Error: ${details}`;
        } else if (jsonErr.error) {
          errText = jsonErr.error;
        }
      } catch (e) {
        // Not JSON, use text as-is
      }
      console.error("API ERROR:", errText);
      throw new Error(errText);
    }

    return res.json();
  } catch (err) {
    console.error("API CALL FAILED:", err.message);
    toast(`API ERROR: ${err.message}`, "red");
    throw err;
  }
}

// ---------------------------------------------------------
// RENDER TABLE
// ---------------------------------------------------------
function renderTable(purchases) {
  if (!purchases || purchases.length === 0) {
    tableBody.innerHTML = `
      <tr>
        <td colspan="4" style="text-align:center;color:#777">No data</td>
      </tr>`;
    return;
  }

  tableBody.innerHTML = purchases
    .map(p => `
      <tr>
        <td>${p.username}</td>
        <td>${p.userid}</td>
        <td>${p.price}</td>
        <td>${new Date(p.timestamp).toLocaleString()}</td>
      </tr>`
    )
    .join("");
}

// ---------------------------------------------------------
// BUY BUTTON
// ---------------------------------------------------------
document.getElementById("buyBtn").addEventListener("click", async () => {
  const username = document.getElementById("username").value.trim();
  let userid = document.getElementById("userid").value.trim();
  const priceInput = document.getElementById("price").value.trim();
  const price = priceInput ? parseFloat(priceInput) : NaN;

  console.log("Buy button clicked:", { username, userid, price, priceInput });

  if (!username || isNaN(price)) {
    return toast("Please fill username and price fields", "red");
  }

  // Auto-generate UUID if userid is empty
  if (!userid) {
    userid = generateUUID();
    document.getElementById("userid").value = userid;
  }

  const payload = { username, userid, price };
  console.log("Sending to API:", payload);

  try {
    const result = await api("POST", "/purchases", payload);
    console.log("API response:", result);
    toast("Purchase added!");
    // Clear form after successful purchase
    document.getElementById("username").value = "";
    document.getElementById("userid").value = generateUUID();
    document.getElementById("price").value = "";
    loadPurchases();
  } catch (err) {
    console.error("Buy button error:", err);
  }
});

// ---------------------------------------------------------
// GET ALL BUTTON
// ---------------------------------------------------------
document.getElementById("getAllBtn").addEventListener("click", async () => {
  loadPurchases();
  toast("Loaded purchases");
});

// ---------------------------------------------------------
// LOAD PURCHASES
// ---------------------------------------------------------
async function loadPurchases() {
  try {
    const data = await api("GET", "/purchases");
    renderTable(data.purchases);
  } catch {}
}

// ---------------------------------------------------------
// DARK MODE
// ---------------------------------------------------------
document.getElementById("darkModeToggle").addEventListener("click", () => {
  document.body.classList.toggle("dark");
});

// ---------------------------------------------------------
// AUTO LOAD ON START
// ---------------------------------------------------------
// Initialize userid field with a new UUID on page load
document.getElementById("userid").value = generateUUID();
loadPurchases();
