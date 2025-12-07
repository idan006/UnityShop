// =========================================================
//  Dynamic API base – works on ANY computer
//  Routed through the NGINX Gateway automatically
// =========================================================
const API_BASE = "/api";

const toastEl = document.getElementById("toast");
const tableBody = document.getElementById("tableBody");

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
      const errText = await res.text();
      console.error("API ERROR:", errText);
      throw new Error(errText);
    }

    return res.json();
  } catch (err) {
    console.error("API CALL FAILED:", err);
    toast("API ERROR", "red");
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
  const userid = document.getElementById("userid").value.trim();
  const price = parseFloat(document.getElementById("price").value);

  if (!username || !userid || isNaN(price)) {
    return toast("Please fill all fields", "red");
  }

  try {
    await api("POST", "/purchases", { username, userid, price });
    toast("Purchase added!");
    loadPurchases();
  } catch {}
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
loadPurchases();
