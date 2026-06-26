"""Pont MQTT Smart City pour le dashboard Flask."""
from __future__ import annotations

import re
import threading
import time
from dataclasses import asdict, dataclass, field
from datetime import datetime, timezone
from queue import Empty, Queue
from typing import Any

import paho.mqtt.client as mqtt

TELEMETRY_TOPIC = "eljezi/city/telemetry"
COMMAND_TOPIC = "eljezi/city/command"
STATUS_TOPIC = "eljezi/city/status"
ALERT_TOPIC = "eljezi/city/alert"

TELEMETRY_RE = re.compile(
    r"ZONE\s*=\s*(?P<zone>[^,]+)\s*,\s*"
    r"AQI\s*=\s*(?P<aqi>\d+)\s*,\s*"
    r"PM25\s*=\s*(?P<pm25>\d+)\s*,\s*"
    r"CO2\s*=\s*(?P<co2>\d+)\s*,\s*"
    r"NOISE\s*=\s*(?P<noise>\d+)\s*,\s*"
    r"TRAFFIC\s*=\s*(?P<traffic>\d)\s*,\s*"
    r"PARK\s*=\s*(?P<park>\d+)\s*,\s*"
    r"LIGHT\s*=\s*(?P<light>\d)\s*,\s*"
    r"T\s*=\s*(?P<t>[-.\d]+)\s*,\s*"
    r"H\s*=\s*(?P<h>[-.\d]+)\s*,\s*"
    r"ENERGY\s*=\s*(?P<energy>\d+)"
    r"(?:\s*,\s*BUS\s*=\s*(?P<bus>\d+))?"
    r"(?:\s*,\s*WIFI\s*=\s*(?P<wifi>\d+))?"
    r"(?:\s*,\s*CROWD\s*=\s*(?P<crowd>\d))?",
    re.I,
)

STATUS_RE = re.compile(
    r"ZONE\s*=\s*(?P<zone>[^,]+)\s*,\s*"
    r"ONLINE\s*=\s*(?P<online>\d)\s*,\s*"
    r"MODE\s*=\s*(?P<mode>NORMAL|EVENT|ALERT)\s*,\s*"
    r"ALERT_LVL\s*=\s*(?P<lvl>\d+)\s*,\s*"
    r"SERVICES\s*=\s*(?P<services>\d+)",
    re.I,
)

ALERT_RE = re.compile(r"ZONE\s*=\s*(?P<zone>[^,]+)\s*,\s*ALERT\s*=\s*(?P<alert>[\w_,.=]+)", re.I)

TRAFFIC_LABELS = {1: "Fluide", 2: "Modere", 3: "Dense", 4: "Bloque"}


@dataclass
class CityTelemetry:
  zone: str
  aqi: int
  pm25: int
  co2: int
  noise_db: int
  traffic_level: int
  traffic_label: str
  parking_spots: int
  light_on: bool
  temp_c: float
  humidity: float
  energy_w: int
  bus_delay_min: int
  wifi_users: int
  crowd_level: int
  at: str


@dataclass
class CityStatus:
  zone: str
  online: bool
  mode: str
  alert_level: int
  services_up: int
  at: str


@dataclass
class CityAlert:
  zone: str
  alert: str
  at: str


@dataclass
class BridgeState:
  mqtt_connected: bool = False
  broker: str = "localhost"
  port: int = 1883
  last_telemetry: CityTelemetry | None = None
  last_status: CityStatus | None = None
  zones: dict = field(default_factory=dict)
  zone_history: dict = field(default_factory=dict)
  history: list = field(default_factory=list)
  alerts: list = field(default_factory=list)


def _iso_now() -> str:
  return datetime.now(timezone.utc).isoformat()


class CityMqttBridge:
  def __init__(self, broker: str = "localhost", port: int = 1883, history_size: int = 60) -> None:
    self.broker = broker
    self.port = port
    self.history_size = history_size
    self._state = BridgeState(broker=broker, port=port)
    self._lock = threading.Lock()
    self._events: Queue[dict[str, Any]] = Queue()
    self._client: mqtt.Client | None = None
    self._stop = threading.Event()

  def _make_client(self) -> mqtt.Client:
    try:
      return mqtt.Client(mqtt.CallbackAPIVersion.VERSION2, userdata=self)
    except AttributeError:
      return mqtt.Client(userdata=self)

  def start(self) -> None:
    self._stop.clear()
    self._client = self._make_client()
    self._client.on_connect = self._on_connect
    self._client.on_message = self._on_message
    self._client.on_disconnect = self._on_disconnect
    self._client.connect_async(self.broker, self.port, keepalive=60)
    self._client.loop_start()
    threading.Thread(target=self._reconnect_loop, daemon=True).start()

  def stop(self) -> None:
    self._stop.set()
    if self._client:
      self._client.loop_stop()
      self._client.disconnect()
      self._client = None

  def publish_command(self, command: str) -> bool:
    if not self._client:
      return False
    cmd = command.strip().upper()
    result = self._client.publish(COMMAND_TOPIC, cmd)
    self._push_event("command_sent", {"command": cmd, "at": _iso_now()})
    return result.rc == mqtt.MQTT_ERR_SUCCESS

  def snapshot(self) -> dict[str, Any]:
    with self._lock:
      zones = {k: asdict(v) for k, v in self._state.zones.items()}
      aqi_vals = [z["aqi"] for z in zones.values()]
      park_vals = [z["parking_spots"] for z in zones.values()]
      worst = max(zones.values(), key=lambda z: z["traffic_level"], default=None)
      return {
          "mqtt_connected": self._state.mqtt_connected,
          "broker": self._state.broker,
          "port": self._state.port,
          "last_telemetry": asdict(self._state.last_telemetry) if self._state.last_telemetry else None,
          "last_status": asdict(self._state.last_status) if self._state.last_status else None,
          "zones": zones,
          "zone_history": {k: list(v)[-30:] for k, v in self._state.zone_history.items()},
          "summary": {
              "zone_count": len(zones),
              "avg_aqi": round(sum(aqi_vals) / len(aqi_vals), 1) if aqi_vals else None,
              "total_parking": sum(park_vals) if park_vals else 0,
              "total_wifi_users": sum(z["wifi_users"] for z in zones.values()),
              "alert_count": len(self._state.alerts),
              "worst_traffic_zone": worst["zone"] if worst else None,
              "worst_traffic_label": worst["traffic_label"] if worst else None,
          },
          "history": list(self._state.history),
          "alerts": list(self._state.alerts)[-20:],
      }

  def poll_event(self, timeout: float = 25.0) -> dict[str, Any] | None:
    try:
      return self._events.get(timeout=timeout)
    except Empty:
      return None

  def _push_event(self, kind: str, payload: dict[str, Any]) -> None:
    self._events.put({"kind": kind, "payload": payload})

  def _on_connect(self, client, userdata, flags, reason_code, properties=None):
    ok = reason_code == 0
    with self._lock:
      self._state.mqtt_connected = ok
    if ok:
      client.subscribe(TELEMETRY_TOPIC)
      client.subscribe(STATUS_TOPIC)
      client.subscribe(ALERT_TOPIC)
      self._push_event("mqtt_status", {"connected": True, "at": _iso_now()})

  def _on_disconnect(self, client, userdata, flags, reason_code, properties=None):
    with self._lock:
      self._state.mqtt_connected = False
    self._push_event("mqtt_status", {"connected": False, "at": _iso_now()})

  def _on_message(self, client, userdata, msg):
    payload = msg.payload.decode(errors="ignore").strip()
    topic = msg.topic
    at = _iso_now()

    if topic == TELEMETRY_TOPIC:
      m = TELEMETRY_RE.search(payload)
      if not m:
        return
      traffic = int(m.group("traffic"))
      zone = m.group("zone")
      sample = CityTelemetry(
          zone=zone,
          aqi=int(m.group("aqi")),
          pm25=int(m.group("pm25")),
          co2=int(m.group("co2")),
          noise_db=int(m.group("noise")),
          traffic_level=traffic,
          traffic_label=TRAFFIC_LABELS.get(traffic, str(traffic)),
          parking_spots=int(m.group("park")),
          light_on=m.group("light") == "1",
          temp_c=float(m.group("t")),
          humidity=float(m.group("h")),
          energy_w=int(m.group("energy")),
          bus_delay_min=int(m.group("bus") or 0),
          wifi_users=int(m.group("wifi") or 0),
          crowd_level=int(m.group("crowd") or 1),
          at=at,
      )
      with self._lock:
        self._state.last_telemetry = sample
        self._state.zones[zone] = sample
        hist = self._state.zone_history.setdefault(zone, [])
        hist.append({"aqi": sample.aqi, "traffic_level": sample.traffic_level, "at": at})
        if len(hist) > self.history_size:
          self._state.zone_history[zone] = hist[-self.history_size :]
        self._state.history.append(asdict(sample))
        if len(self._state.history) > self.history_size:
          self._state.history = self._state.history[-self.history_size :]
      self._push_event("telemetry", asdict(sample))
      return

    if topic == STATUS_TOPIC:
      m = STATUS_RE.search(payload)
      if not m:
        return
      status = CityStatus(
          zone=m.group("zone"),
          online=m.group("online") == "1",
          mode=m.group("mode").upper(),
          alert_level=int(m.group("lvl")),
          services_up=int(m.group("services")),
          at=at,
      )
      with self._lock:
        self._state.last_status = status
      self._push_event("status", asdict(status))
      return

    if topic == ALERT_TOPIC:
      m = ALERT_RE.search(payload)
      if not m:
        return
      alert = CityAlert(zone=m.group("zone"), alert=m.group("alert"), at=at)
      with self._lock:
        self._state.alerts.append(asdict(alert))
      self._push_event("alert", asdict(alert))

  def _reconnect_loop(self) -> None:
    while not self._stop.is_set():
      with self._lock:
        connected = self._state.mqtt_connected
      if not connected and self._client:
        try:
          self._client.reconnect()
        except Exception:
          pass
      time.sleep(3)
