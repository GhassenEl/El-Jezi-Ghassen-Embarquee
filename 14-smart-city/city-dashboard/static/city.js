const mqttStatus = document.getElementById("mqttStatus");
const summaryBar = document.getElementById("summaryBar");
const zoneSelect = document.getElementById("zoneSelect");
const zoneTableBody = document.getElementById("zoneTableBody");
const aqiSparkline = document.getElementById("aqiSparkline");
const aqiValue = document.getElementById("aqiValue");
const pm25Value = document.getElementById("pm25Value");
const co2Value = document.getElementById("co2Value");
const trafficValue = document.getElementById("trafficValue");
const trafficLevel = document.getElementById("trafficLevel");
const parkValue = document.getElementById("parkValue");
const noiseValue = document.getElementById("noiseValue");
const tempValue = document.getElementById("tempValue");
const humValue = document.getElementById("humValue");
const busValue = document.getElementById("busValue");
const wifiValue = document.getElementById("wifiValue");
const crowdValue = document.getElementById("crowdValue");
const lightState = document.getElementById("lightState");
const energyValue = document.getElementById("energyValue");
const modeState = document.getElementById("modeState");
const alertList = document.getElementById("alertList");

let zoneLabels = {};
let lastState = null;

function aqiClass(aqi) {
  if (aqi <= 50) return "good";
  if (aqi <= 100) return "moderate";
  return "bad";
}

function zoneLabel(id) {
  return zoneLabels[id]?.label || id;
}

function setMqtt(connected) {
  mqttStatus.textContent = connected ? "MQTT connecte" : "MQTT deconnecte";
  mqttStatus.classList.toggle("off", !connected);
}

function pickTelemetry(state) {
  const sel = zoneSelect.value;
  if (sel && state.zones?.[sel]) return state.zones[sel];
  return state.last_telemetry;
}

function renderSparkline(state) {
  const sel = zoneSelect.value || Object.keys(state.zones || {})[0];
  const hist = (state.zone_history?.[sel] || []).slice(-24);
  if (!hist.length) {
    aqiSparkline.innerHTML = '<p class="muted">Pas encore d historique</p>';
    return;
  }
  const max = Math.max(...hist.map((h) => h.aqi), 100);
  aqiSparkline.innerHTML = hist
    .map((h) => {
      const hPct = Math.max(8, Math.round((h.aqi / max) * 100));
      const cls = aqiClass(h.aqi);
      return `<div class="spark-bar ${cls}" style="height:${hPct}%" title="AQI ${h.aqi}"></div>`;
    })
    .join("");
}

function renderDetail(t) {
  if (!t) return;
  aqiValue.textContent = t.aqi ?? "—";
  aqiValue.className = "metric " + aqiClass(t.aqi ?? 0);
  pm25Value.textContent = t.pm25 ?? "—";
  co2Value.textContent = t.co2 ?? "—";
  trafficValue.textContent = t.traffic_label ?? "—";
  trafficLevel.textContent = t.traffic_level ?? "—";
  trafficValue.className = "metric " + (t.traffic_level >= 4 ? "bad" : t.traffic_level >= 3 ? "warn" : "good");
  parkValue.textContent = t.parking_spots ?? "—";
  noiseValue.textContent = t.noise_db ?? "—";
  tempValue.textContent = t.temp_c?.toFixed(1) ?? "—";
  humValue.textContent = t.humidity?.toFixed(0) ?? "—";
  busValue.textContent = t.bus_delay_min ?? "—";
  wifiValue.textContent = t.wifi_users ?? "—";
  crowdValue.textContent = t.crowd_level ?? "—";
  lightState.textContent = t.light_on ? "Eclairage ON" : "Eclairage OFF";
  energyValue.textContent = t.energy_w ?? "—";
}

function renderZoneTable(zones) {
  const entries = Object.values(zones || {}).sort((a, b) => a.zone.localeCompare(b.zone));
  if (!entries.length) {
    zoneTableBody.innerHTML = '<tr><td colspan="8" class="muted">En attente de donnees…</td></tr>';
    return;
  }
  zoneTableBody.innerHTML = entries
    .map(
      (z) => `
    <tr>
      <td><strong>${zoneLabel(z.zone)}</strong><br><span class="muted small">${z.zone}</span></td>
      <td class="${aqiClass(z.aqi)}">${z.aqi}</td>
      <td>${z.traffic_label}</td>
      <td>${z.parking_spots}</td>
      <td>${z.noise_db} dB</td>
      <td>${z.bus_delay_min} min</td>
      <td>${z.wifi_users}</td>
      <td>${z.crowd_level}/5</td>
    </tr>`
    )
    .join("");
}

function renderState(state) {
  lastState = state;
  setMqtt(state.mqtt_connected);
  const s = state.summary || {};
  summaryBar.innerHTML = `
    <strong>${s.zone_count ?? 0}</strong> zones ·
    AQI moy. <strong>${s.avg_aqi ?? "—"}</strong> ·
    <strong>${s.total_parking ?? 0}</strong> places ·
    WiFi <strong>${s.total_wifi_users ?? 0}</strong> users ·
    <strong>${s.alert_count ?? 0}</strong> alertes`;
  renderDetail(pickTelemetry(state));
  if (state.last_status) modeState.textContent = state.last_status.mode ?? "—";
  renderZoneTable(state.zones);
  renderSparkline(state);
  const alerts = state.alerts ?? [];
  alertList.innerHTML = alerts.length
    ? alerts.slice().reverse().map((a) => `<li>${zoneLabel(a.zone)} — ${a.alert}</li>`).join("")
    : '<li class="muted">Aucune alerte</li>';
}

async function loadZoneMeta() {
  const res = await fetch("/api/zones");
  const zones = await res.json();
  zones.forEach((z) => {
    zoneLabels[z.id] = z;
    const opt = document.createElement("option");
    opt.value = z.id;
    opt.textContent = z.label;
    zoneSelect.appendChild(opt);
  });
}

zoneSelect.addEventListener("change", () => {
  if (lastState) renderState(lastState);
});

document.querySelectorAll("[data-cmd]").forEach((btn) => {
  btn.addEventListener("click", () => {
    fetch("/api/command", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ command: btn.dataset.cmd }),
    });
  });
});

const es = new EventSource("/api/stream");
es.onmessage = (ev) => {
  const data = JSON.parse(ev.data);
  if (data.kind === "hello") {
    renderState(data.payload);
    return;
  }
  if (["telemetry", "status", "alert", "mqtt_status"].includes(data.kind)) {
    fetch("/api/state").then((r) => r.json()).then(renderState);
  }
};
es.onerror = () => setMqtt(false);

loadZoneMeta();
fetch("/api/state").then((r) => r.json()).then(renderState).catch(() => setMqtt(false));
