const mqttStatus = document.getElementById("mqttStatus");
const fridgeValue = document.getElementById("fridgeValue");
const freezerValue = document.getElementById("freezerValue");
const doorState = document.getElementById("doorState");
const humValue = document.getElementById("humValue");
const compState = document.getElementById("compState");
const powerValue = document.getElementById("powerValue");
const modeState = document.getElementById("modeState");
const targetFridge = document.getElementById("targetFridge");
const targetFreezer = document.getElementById("targetFreezer");
const alertList = document.getElementById("alertList");

function setMqtt(connected) {
  mqttStatus.textContent = connected ? "MQTT connecte" : "MQTT deconnecte";
  mqttStatus.classList.toggle("off", !connected);
}

function renderState(state) {
  setMqtt(state.mqtt_connected);
  const t = state.last_telemetry;
  const s = state.last_status;
  if (t) {
    fridgeValue.textContent = t.fridge_temp?.toFixed(1) ?? "—";
    freezerValue.textContent = t.freezer_temp?.toFixed(1) ?? "—";
    humValue.textContent = t.humidity?.toFixed(0) ?? "—";
    doorState.textContent = t.door_open ? "OUVERTE" : "Fermee";
    doorState.className = "metric " + (t.door_open ? "door-open" : "door-closed");
    compState.textContent = t.compressor_on ? "ON" : "OFF";
    powerValue.textContent = t.power_w ?? "—";
  }
  if (s) {
    modeState.textContent = s.mode ?? "—";
    targetFridge.textContent = s.target_fridge ?? "—";
    targetFreezer.textContent = s.target_freezer ?? "—";
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
