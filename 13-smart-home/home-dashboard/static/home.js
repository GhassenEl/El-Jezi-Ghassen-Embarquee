const mqttStatus = document.getElementById("mqttStatus");
const tempValue = document.getElementById("tempValue");
const targetTemp = document.getElementById("targetTemp");
const luxValue = document.getElementById("luxValue");
const humValue = document.getElementById("humValue");
const motionState = document.getElementById("motionState");
const doorState = document.getElementById("doorState");
const lightState = document.getElementById("lightState");
const heatState = document.getElementById("heatState");
const powerValue = document.getElementById("powerValue");
const modeState = document.getElementById("modeState");
const lockState = document.getElementById("lockState");
const alertList = document.getElementById("alertList");
const zoneGrid = document.getElementById("zoneGrid");
const houseMeta = document.getElementById("houseMeta");

function readInitialState() {
  const el = document.getElementById("initial-state");
  if (!el) return null;
  try {
    return JSON.parse(el.textContent);
  } catch {
    return null;
  }
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
  if (!state) return DEMO_FALLBACK;
  if (state.last_telemetry && state.last_status) return state;
  if (!DEMO_FALLBACK) return state;
  const merged = { ...DEMO_FALLBACK, ...state };
  merged.demo_mode = !state.last_telemetry;
  if (!state.last_telemetry) {
    merged.last_telemetry = DEMO_FALLBACK.last_telemetry;
    merged.last_status = DEMO_FALLBACK.last_status;
    merged.zones = DEMO_FALLBACK.zones;
    merged.alerts = DEMO_FALLBACK.alerts;
    merged.house = DEMO_FALLBACK.house;
    merged.totals = DEMO_FALLBACK.totals;
  }
  return merged;
}

function renderZones(state) {
  const zones = state.zones ?? state.history ?? [];
  const house = state.house ?? {};
  if (house.name) {
    houseMeta.textContent = `${house.name} · ${house.address ?? ""} · ${zones.length} zones · ${state.totals?.power_w ?? "—"} W total`;
  }
  if (!zones.length) {
    zoneGrid.innerHTML = '<p class="muted">Aucune zone</p>';
    return;
  }
  zoneGrid.innerHTML = zones.map((z) => {
    const zid = z.zone ?? z.id ?? "—";
    const door = z.door_open ? "porte ouverte" : "ok";
    const motion = z.motion ? "mouvement" : "calme";
    return `<article class="zone-card">
      <h3>${zid}</h3>
      <p class="zone-temp">${typeof z.temp_c === "number" ? z.temp_c.toFixed(1) : z.temp_c}°C</p>
      <p class="zone-meta">${z.humidity}% HR · ${z.lux} lux · ${z.power_w} W</p>
      <p class="zone-meta">${motion} · ${door}</p>
    </article>`;
  }).join("");
}

function renderState(rawState) {
  const state = withDemoFallback(rawState);
  const useDemo = state.demo_mode || !rawState?.last_telemetry;
  setMqtt(state.mqtt_connected, useDemo);
  renderZones(state);
  const t = state.last_telemetry;
  const s = state.last_status;
  if (t) {
    tempValue.textContent = typeof t.temp_c === "number" ? t.temp_c.toFixed(1) : (t.temp_c ?? "—");
    luxValue.textContent = t.lux ?? "—";
    humValue.textContent = typeof t.humidity === "number" ? t.humidity.toFixed(0) : (t.humidity ?? "—");
    motionState.textContent = t.motion ? "Detecte" : "Calme";
    motionState.className = "metric " + (t.motion ? "warn" : "ok");
    doorState.textContent = t.door_open ? "ouverte" : "fermee";
    doorState.className = t.door_open ? "warn-text" : "ok-text";
    lightState.textContent = t.light_on ? "Lumiere ON" : "Lumiere OFF";
    heatState.textContent = t.heat_on ? "ON" : "OFF";
    powerValue.textContent = t.power_w ?? "—";
  }
  if (s) {
    modeState.textContent = s.mode ?? "—";
    targetTemp.textContent = s.target_temp ?? "—";
    lockState.textContent = s.door_locked ? "actif" : "off";
  }
  const alerts = state.alerts ?? [];
  if (!alerts.length) {
    alertList.innerHTML = '<li class="muted">Aucune alerte</li>';
  } else {
    alertList.innerHTML = alerts.slice().reverse().map((a) => `<li>${a.zone} — ${a.alert}</li>`).join("");
  }
}

function refreshState() {
  return fetch("/api/state")
    .then((r) => r.json())
    .then(renderState)
    .catch(() => {
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
  if (data.kind === "hello") {
    renderState(data.payload);
    return;
  }
  if (["telemetry", "status", "alert", "mqtt_status"].includes(data.kind)) {
    refreshState();
  }
};
es.onerror = () => refreshState();

refreshState();
