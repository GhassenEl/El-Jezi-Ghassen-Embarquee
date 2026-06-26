const tempValue = document.getElementById("tempValue");
const humValue = document.getElementById("humValue");
const voltValue = document.getElementById("voltValue");
const ledState = document.getElementById("ledState");
const relayState = document.getElementById("relayState");
const pwmState = document.getElementById("pwmState");
const mqttStatus = document.getElementById("mqttStatus");
const lastCmd = document.getElementById("lastCmd");
const alertsList = document.getElementById("alertsList");
const pwmSlider = document.getElementById("pwmSlider");
const pwmLabel = document.getElementById("pwmLabel");
const chart = document.getElementById("chart");
const ctx = chart.getContext("2d");

let history = [];

function setMqttStatus(connected) {
  mqttStatus.textContent = connected ? "MQTT connecté" : "MQTT déconnecté";
  mqttStatus.className = "status-pill " + (connected ? "status-pill--ok" : "status-pill--bad");
}

function applyTelemetry(sample) {
  if (!sample) return;
  tempValue.textContent = Number(sample.temperature).toFixed(1);
  humValue.textContent = Number(sample.humidity).toFixed(1);
  voltValue.textContent = Number(sample.voltage).toFixed(2);
}

function applyStatus(status) {
  if (!status) return;
  ledState.textContent = status.led_on ? "ON" : "OFF";
  relayState.textContent = status.relay_on ? "ON" : "OFF";
  pwmState.textContent = String(status.pwm);
}

function renderAlerts(alerts) {
  if (!alerts || !alerts.length) {
    alertsList.innerHTML = '<li class="alerts__empty">Aucune alerte pour le moment.</li>';
    return;
  }
  alertsList.innerHTML = alerts
    .slice()
    .reverse()
    .map((a) => `<li class="alert-item">${a.message}</li>`)
    .join("");
}

function drawChart() {
  const w = chart.width;
  const h = chart.height;
  ctx.clearRect(0, 0, w, h);

  if (history.length < 2) {
    ctx.fillStyle = "#64748b";
    ctx.font = "14px Segoe UI, sans-serif";
    ctx.fillText("En attente de données…", 16, 28);
    return;
  }

  const temps = history.map((s) => s.temperature);
  const minT = Math.min(...temps) - 1;
  const maxT = Math.max(...temps) + 1;

  ctx.strokeStyle = "#334155";
  ctx.lineWidth = 1;
  for (let i = 0; i <= 4; i++) {
    const y = 20 + ((h - 40) * i) / 4;
    ctx.beginPath();
    ctx.moveTo(40, y);
    ctx.lineTo(w - 10, y);
    ctx.stroke();
  }

  ctx.strokeStyle = "#10b981";
  ctx.lineWidth = 2;
  ctx.beginPath();
  history.forEach((s, i) => {
    const x = 40 + (i / (history.length - 1)) * (w - 50);
    const y = 20 + (1 - (s.temperature - minT) / (maxT - minT || 1)) * (h - 40);
    if (i === 0) ctx.moveTo(x, y);
    else ctx.lineTo(x, y);
  });
  ctx.stroke();

  ctx.fillStyle = "#94a3b8";
  ctx.font = "12px Segoe UI, sans-serif";
  ctx.fillText(`${maxT.toFixed(1)}°C`, 4, 24);
  ctx.fillText(`${minT.toFixed(1)}°C`, 4, h - 8);
}

function applySnapshot(snapshot) {
  setMqttStatus(snapshot.mqtt_connected);
  applyTelemetry(snapshot.last_telemetry);
  applyStatus(snapshot.last_status);
  history = snapshot.history || [];
  drawChart();
  renderAlerts(snapshot.alerts || []);
}

async function sendCommand(command) {
  const res = await fetch("/api/command", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ command }),
  });
  const data = await res.json();
  if (data.ok) {
    lastCmd.textContent = `Dernière commande : ${data.command}`;
  }
}

document.querySelectorAll("[data-cmd]").forEach((btn) => {
  btn.addEventListener("click", () => sendCommand(btn.dataset.cmd));
});

document.getElementById("btnStatus").addEventListener("click", () => sendCommand("STATUS"));

pwmSlider.addEventListener("input", () => {
  pwmLabel.textContent = pwmSlider.value;
});

document.getElementById("btnPwm").addEventListener("click", () => {
  sendCommand(`PWM_${pwmSlider.value}`);
});

function handleEvent(event) {
  const { kind, payload } = event;
  if (kind === "hello") {
    applySnapshot(payload);
    return;
  }
  if (kind === "mqtt_status") {
    setMqttStatus(payload.connected);
    return;
  }
  if (kind === "telemetry") {
    applyTelemetry(payload);
    history.push(payload);
    if (history.length > 60) history = history.slice(-60);
    drawChart();
    return;
  }
  if (kind === "status") {
    applyStatus(payload);
    return;
  }
  if (kind === "alert") {
    const li = document.createElement("li");
    li.className = "alert-item";
    li.textContent = payload.message;
    if (alertsList.querySelector(".alerts__empty")) {
      alertsList.innerHTML = "";
    }
    alertsList.prepend(li);
    return;
  }
  if (kind === "command_sent") {
    lastCmd.textContent = `Dernière commande : ${payload.command}`;
  }
}

function connectStream() {
  const source = new EventSource("/api/stream");
  source.onmessage = (msg) => {
    try {
      handleEvent(JSON.parse(msg.data));
    } catch (err) {
      console.error(err);
    }
  };
  source.onerror = () => {
    source.close();
    setTimeout(connectStream, 2000);
  };
}

fetch("/api/state")
  .then((r) => r.json())
  .then(applySnapshot)
  .catch(() => {});

connectStream();
