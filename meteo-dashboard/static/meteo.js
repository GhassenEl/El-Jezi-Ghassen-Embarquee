const mqttStatus = document.getElementById("mqttStatus");
const tempValue = document.getElementById("tempValue");
const humValue = document.getElementById("humValue");
const pressValue = document.getElementById("pressValue");
const windValue = document.getElementById("windValue");
const rainValue = document.getElementById("rainValue");
const uvValue = document.getElementById("uvValue");
const stationName = document.getElementById("stationName");
const alertList = document.getElementById("alertList");
const historyLog = document.getElementById("historyLog");

function setMqtt(connected) {
  mqttStatus.textContent = connected ? "MQTT connecte" : "MQTT deconnecte";
  mqttStatus.classList.toggle("off", !connected);
}

function renderTelemetry(t) {
  if (!t) return;
  tempValue.textContent = t.temp?.toFixed(1) ?? "—";
  humValue.textContent = t.hum?.toFixed(0) ?? "—";
  pressValue.textContent = t.pressure?.toFixed(1) ?? "—";
  windValue.textContent = t.wind_kmh?.toFixed(1) ?? "—";
  rainValue.textContent = t.rain_mm?.toFixed(2) ?? "—";
  uvValue.textContent = t.uv_index ?? "—";
  stationName.textContent = t.station ?? "—";
}

function renderAlerts(alerts) {
  if (!alerts?.length) {
    alertList.innerHTML = '<li class="muted">Aucune alerte</li>';
    return;
  }
  alertList.innerHTML = alerts
    .slice()
    .reverse()
    .map((a) => `<li class="alert-warn">${a.station} — ${a.alert}</li>`)
    .join("");
}

function renderHistory(history) {
  if (!history?.length) {
    historyLog.innerHTML = '<div class="muted">En attente de donnees…</div>';
    return;
  }
  historyLog.innerHTML = history
    .slice(-8)
    .reverse()
    .map(
      (h) =>
        `<div class="row">T=${h.temp}°C · W=${h.wind_kmh} km/h · R=${h.rain_mm} mm · UV=${h.uv_index}</div>`
    )
    .join("");
}

async function sendCommand(cmd) {
  await fetch("/api/command", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ command: cmd }),
  });
}

document.querySelectorAll("[data-cmd]").forEach((btn) => {
  btn.addEventListener("click", () => sendCommand(btn.dataset.cmd));
});

function applySnapshot(state) {
  setMqtt(state.mqtt_connected);
  renderTelemetry(state.last_telemetry);
  renderAlerts(state.alerts);
  renderHistory(state.history);
}

const es = new EventSource("/api/stream");
es.onmessage = (ev) => {
  const data = JSON.parse(ev.data);
  if (data.kind === "hello") {
    applySnapshot(data.payload);
    return;
  }
  if (data.kind === "mqtt_status") {
    setMqtt(data.payload.connected);
    return;
  }
  if (data.kind === "telemetry") {
    fetch("/api/state")
      .then((r) => r.json())
      .then(applySnapshot);
    return;
  }
  if (data.kind === "alert") {
    fetch("/api/state")
      .then((r) => r.json())
      .then(applySnapshot);
  }
};

es.onerror = () => setMqtt(false);

fetch("/api/state")
  .then((r) => r.json())
  .then(applySnapshot)
  .catch(() => setMqtt(false));
