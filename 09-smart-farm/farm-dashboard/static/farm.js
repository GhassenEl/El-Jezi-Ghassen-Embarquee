const soilValue = document.getElementById("soilValue");
const soilBar = document.getElementById("soilBar");
const tempValue = document.getElementById("tempValue");
const humValue = document.getElementById("humValue");
const luxValue = document.getElementById("luxValue");
const pumpState = document.getElementById("pumpState");
const modeState = document.getElementById("modeState");
const threshState = document.getElementById("threshState");
const mqttStatus = document.getElementById("mqttStatus");
const alertsList = document.getElementById("alertsList");
const threshSlider = document.getElementById("threshSlider");
const threshLabel = document.getElementById("threshLabel");
const chart = document.getElementById("chart");
const ctx = chart.getContext("2d");

let history = [];

function setMqttStatus(connected) {
  mqttStatus.textContent = connected ? "MQTT connecté" : "MQTT déconnecté";
  mqttStatus.className = "status-pill " + (connected ? "status-pill--ok" : "status-pill--bad");
}

function applyTelemetry(t) {
  if (!t) return;
  soilValue.textContent = Number(t.soil_moist).toFixed(1);
  soilBar.style.width = Math.min(100, t.soil_moist) + "%";
  tempValue.textContent = Number(t.air_temp).toFixed(1);
  humValue.textContent = Number(t.air_hum).toFixed(0);
  luxValue.textContent = String(t.light_lux);
  pumpState.textContent = t.pump_on ? "ON" : "OFF";
  pumpState.style.color = t.pump_on ? "#4ade80" : "#94a3b8";
  modeState.textContent = t.mode || "—";
}

function applyStatus(s) {
  if (!s) return;
  if (s.mode) modeState.textContent = s.mode;
  if (s.soil_thresh != null) {
    threshState.textContent = s.soil_thresh;
    threshSlider.value = s.soil_thresh;
    threshLabel.textContent = s.soil_thresh;
  }
  if (s.pump_on != null) {
    pumpState.textContent = s.pump_on ? "ON" : "OFF";
  }
}

function drawChart() {
  const w = chart.width;
  const h = chart.height;
  ctx.clearRect(0, 0, w, h);
  if (history.length < 2) return;

  const vals = history.map((s) => s.soil_moist);
  const minV = Math.max(0, Math.min(...vals) - 5);
  const maxV = Math.min(100, Math.max(...vals) + 5);

  ctx.strokeStyle = "#2d4a35";
  for (let i = 0; i <= 4; i++) {
    const y = 16 + ((h - 32) * i) / 4;
    ctx.beginPath();
    ctx.moveTo(40, y);
    ctx.lineTo(w - 10, y);
    ctx.stroke();
  }

  ctx.strokeStyle = "#a16207";
  ctx.lineWidth = 2;
  ctx.beginPath();
  history.forEach((s, i) => {
    const x = 40 + (i / (history.length - 1)) * (w - 50);
    const y = 16 + (1 - (s.soil_moist - minV) / (maxV - minV || 1)) * (h - 32);
    if (i === 0) ctx.moveTo(x, y);
    else ctx.lineTo(x, y);
  });
  ctx.stroke();
}

function renderAlerts(alerts) {
  if (!alerts || !alerts.length) {
    alertsList.innerHTML = '<li class="alerts__empty">Aucune alerte.</li>';
    return;
  }
  alertsList.innerHTML = alerts
    .slice()
    .reverse()
    .map((a) => `<li class="alert-item">${a.zone}: ${a.alert}</li>`)
    .join("");
}

function applySnapshot(s) {
  setMqttStatus(s.mqtt_connected);
  applyTelemetry(s.last_telemetry);
  applyStatus(s.last_status);
  history = (s.history || []).map((h) => ({ soil_moist: h.soil_moist }));
  drawChart();
  renderAlerts(s.alerts || []);
}

async function sendCommand(command) {
  await fetch("/api/command", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ command }),
  });
}

document.querySelectorAll("[data-cmd]").forEach((btn) => {
  btn.addEventListener("click", () => sendCommand(btn.dataset.cmd));
});

threshSlider.addEventListener("input", () => {
  threshLabel.textContent = threshSlider.value;
});

document.getElementById("btnThresh").addEventListener("click", () => {
  sendCommand(`SET_THRESH_${threshSlider.value}`);
});

function handleEvent(event) {
  const { kind, payload } = event;
  if (kind === "hello") return applySnapshot(payload);
  if (kind === "mqtt_status") return setMqttStatus(payload.connected);
  if (kind === "telemetry") {
    applyTelemetry(payload);
    history.push({ soil_moist: payload.soil_moist });
    if (history.length > 60) history = history.slice(-60);
    drawChart();
    return;
  }
  if (kind === "status") return applyStatus(payload);
  if (kind === "alert") {
    const li = document.createElement("li");
    li.className = "alert-item";
    li.textContent = `${payload.zone}: ${payload.alert}`;
    if (alertsList.querySelector(".alerts__empty")) alertsList.innerHTML = "";
    alertsList.prepend(li);
  }
}

function connectStream() {
  const source = new EventSource("/api/stream");
  source.onmessage = (msg) => {
    try { handleEvent(JSON.parse(msg.data)); } catch (_) {}
  };
  source.onerror = () => {
    source.close();
    setTimeout(connectStream, 2000);
  };
}

fetch("/api/state").then((r) => r.json()).then(applySnapshot).catch(() => {});
connectStream();
