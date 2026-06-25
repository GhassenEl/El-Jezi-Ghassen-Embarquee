const mqttStatus = document.getElementById("mqttStatus");
const aqiValue = document.getElementById("aqiValue");
const pm25Value = document.getElementById("pm25Value");
const co2Value = document.getElementById("co2Value");
const trafficValue = document.getElementById("trafficValue");
const trafficLevel = document.getElementById("trafficLevel");
const parkValue = document.getElementById("parkValue");
const noiseValue = document.getElementById("noiseValue");
const tempValue = document.getElementById("tempValue");
const humValue = document.getElementById("humValue");
const lightState = document.getElementById("lightState");
const energyValue = document.getElementById("energyValue");
const modeState = document.getElementById("modeState");
const alertList = document.getElementById("alertList");

function aqiClass(aqi) {
  if (aqi <= 50) return "good";
  if (aqi <= 100) return "moderate";
  return "bad";
}

function setMqtt(connected) {
  mqttStatus.textContent = connected ? "MQTT connecte" : "MQTT deconnecte";
  mqttStatus.classList.toggle("off", !connected);
}

function renderState(state) {
  setMqtt(state.mqtt_connected);
  const t = state.last_telemetry;
  const s = state.last_status;
  if (t) {
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
    lightState.textContent = t.light_on ? "Eclairage ON" : "Eclairage OFF";
    energyValue.textContent = t.energy_w ?? "—";
  }
  if (s) {
    modeState.textContent = s.mode ?? "—";
  }
  const alerts = state.alerts ?? [];
  if (!alerts.length) {
    alertList.innerHTML = '<li class="muted">Aucune alerte</li>';
  } else {
    alertList.innerHTML = alerts.slice().reverse().map((a) => `<li>${a.zone} — ${a.alert}</li>`).join("");
  }
}

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
fetch("/api/state").then((r) => r.json()).then(renderState).catch(() => setMqtt(false));
