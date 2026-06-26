const mqttStatus = document.getElementById("mqttStatus");
const fillValue = document.getElementById("fillValue");
const typeValue = document.getElementById("typeValue");
const weightValue = document.getElementById("weightValue");
const gasValue = document.getElementById("gasValue");
const lidState = document.getElementById("lidState");
const battValue = document.getElementById("battValue");
const tempValue = document.getElementById("tempValue");
const humValue = document.getElementById("humValue");
const modeState = document.getElementById("modeState");
const collectState = document.getElementById("collectState");
const alertList = document.getElementById("alertList");
const binGrid = document.getElementById("binGrid");
const cityMeta = document.getElementById("cityMeta");

function readInitialState() {
  const el = document.getElementById("initial-state");
  if (!el) return null;
  try { return JSON.parse(el.textContent); } catch { return null; }
}
const DEMO_FALLBACK = readInitialState();

function setMqtt(connected, demo) {
  if (demo) {
    mqttStatus.textContent = "Mode demo (donnees locales)";
    mqttStatus.classList.remove("off");
    return;
  }
  mqttStatus.textContent = connected ? "MQTT connecte" : "MQTT deconnecte · demo active";
  mqttStatus.classList.toggle("off", !connected);
}

function withDemoFallback(state) {
  if (!state || !state.bins?.length) return DEMO_FALLBACK ?? state;
  return state;
}

function renderBins(state) {
  const bins = state.bins ?? [];
  const cat = state.catalog ?? {};
  if (cat.city) cityMeta.textContent = `${cat.city} · ${bins.length} conteneurs · ${state.totals?.need_collection ?? 0} a collecter`;
  binGrid.innerHTML = bins.map((b) => {
    const fill = b.fill_pct ?? 0;
    const high = fill >= 85;
    const id = b.bin_id ?? b.bin ?? "—";
    const typ = b.waste_type ?? b.type ?? "—";
    return `<article class="bin-card">
      <h3>${id}</h3>
      <p class="bin-fill ${high ? "high" : ""}">${fill}%</p>
      <p class="bin-meta">${typ} · ${b.weight_kg ?? "—"} kg</p>
      <p class="bin-meta">Gaz ${b.gas_ppm ?? "—"} · Batt ${b.battery_pct ?? "—"}%</p>
    </article>`;
  }).join("");
}

function renderState(raw) {
  const state = withDemoFallback(raw);
  const demo = state.demo_mode || !raw?.mqtt_connected;
  setMqtt(state.mqtt_connected, demo);
  renderBins(state);
  const t = state.last_telemetry;
  const s = state.last_status;
  if (t) {
    fillValue.textContent = t.fill_pct ?? "—";
    fillValue.className = "metric" + ((t.fill_pct ?? 0) >= 85 ? " fill-high" : "");
    typeValue.textContent = t.waste_type ?? "—";
    weightValue.textContent = typeof t.weight_kg === "number" ? t.weight_kg.toFixed(1) : t.weight_kg;
    gasValue.textContent = t.gas_ppm ?? "—";
    lidState.textContent = t.lid_open ? "Ouvert" : "Ferme";
    battValue.textContent = t.battery_pct ?? "—";
    tempValue.textContent = typeof t.temp_c === "number" ? t.temp_c.toFixed(1) : t.temp_c;
    humValue.textContent = typeof t.humidity === "number" ? t.humidity.toFixed(0) : t.humidity;
  }
  if (s) {
    modeState.textContent = s.mode ?? "—";
    collectState.textContent = s.collection_due ? "oui" : "non";
  }
  const alerts = state.alerts ?? [];
  alertList.innerHTML = alerts.length
    ? alerts.slice().reverse().map((a) => `<li>${a.bin_id} — ${a.alert}</li>`).join("")
    : '<li class="muted">Aucune alerte</li>';
}

function refreshState() {
  return fetch("/api/state").then((r) => r.json()).then(renderState).catch(() => {
    if (DEMO_FALLBACK) renderState(DEMO_FALLBACK);
  });
}

document.querySelectorAll("[data-cmd]").forEach((btn) => {
  btn.addEventListener("click", () => {
    fetch("/api/command", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ command: btn.dataset.cmd }),
    }).catch(() => {});
  });
});

if (DEMO_FALLBACK) renderState(DEMO_FALLBACK);
const es = new EventSource("/api/stream");
es.onmessage = (ev) => {
  const data = JSON.parse(ev.data);
  if (data.kind === "hello") { renderState(data.payload); return; }
  if (["telemetry", "status", "alert", "mqtt_status"].includes(data.kind)) refreshState();
};
es.onerror = () => refreshState();
refreshState();
