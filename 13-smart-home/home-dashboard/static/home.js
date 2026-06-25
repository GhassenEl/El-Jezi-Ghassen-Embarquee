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

function setMqtt(connected, demo) {
  if (demo) {
    mqttStatus.textContent = "Mode demo (donnees locales)";
    mqttStatus.classList.remove("off");
    return;
  }
  mqttStatus.textContent = connected ? "MQTT connecte" : "MQTT deconnecte";
  mqttStatus.classList.toggle("off", !connected);
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
      <p class="zone-temp">${z.temp_c?.toFixed?.(1) ?? z.temp_c}°C</p>
      <p class="zone-meta">${z.humidity}% HR · ${z.lux} lux · ${z.power_w} W</p>
      <p class="zone-meta">${motion} · ${door}</p>
    </article>`;
  }).join("");
}

function renderState(state) {
  setMqtt(state.mqtt_connected, state.demo_mode);
  renderZones(state);
  const t = state.last_telemetry;
  const s = state.last_status;
  if (t) {
    tempValue.textContent = t.temp_c?.toFixed(1) ?? "—";
    luxValue.textContent = t.lux ?? "—";
    humValue.textContent = t.humidity?.toFixed(0) ?? "—";
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
