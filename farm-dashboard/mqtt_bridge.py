"""Pont MQTT Smart Farm pour le dashboard Flask."""
from __future__ import annotations

import re
import threading
import time
from collections import deque
from dataclasses import asdict, dataclass, field
from datetime import datetime, timezone
from queue import Empty, Queue
from typing import Any

import paho.mqtt.client as mqtt

TELEMETRY_TOPIC = "eljezi/smartfarm/telemetry"
COMMAND_TOPIC = "eljezi/smartfarm/command"
STATUS_TOPIC = "eljezi/smartfarm/status"
ALERT_TOPIC = "eljezi/smartfarm/alert"

TELEMETRY_RE = re.compile(
    r"ZONE\s*=\s*(?P<zone>[^,]+)\s*,\s*"
    r"T\s*=\s*(?P<t>[-.\d]+)\s*,\s*"
    r"H\s*=\s*(?P<h>[-.\d]+)\s*,\s*"
    r"S\s*=\s*(?P<s>[-.\d]+)\s*,\s*"
    r"L\s*=\s*(?P<l>\d+)\s*,\s*"
    r"PUMP\s*=\s*(?P<pump>\d)\s*,\s*"
    r"MODE\s*=\s*(?P<mode>AUTO|MANUAL)",
    re.I,
)

STATUS_RE = re.compile(
    r"ZONE\s*=\s*(?P<zone>[^,]+)\s*,\s*"
    r"PUMP\s*=\s*(?P<pump>\d)\s*,\s*"
    r"MODE\s*=\s*(?P<mode>AUTO|MANUAL)\s*,\s*"
    r"THRESH\s*=\s*(?P<thresh>\d+)",
    re.I,
)

ALERT_RE = re.compile(r"ZONE\s*=\s*(?P<zone>[^,]+)\s*,\s*ALERT\s*=\s*(?P<alert>\w+)", re.I)


@dataclass
class FarmTelemetry:
  zone: str
  air_temp: float
  air_hum: float
  soil_moist: float
  light_lux: int
  pump_on: bool
  mode: str
  at: str


@dataclass
class FarmStatus:
  zone: str
  pump_on: bool
  mode: str
  soil_thresh: int
  at: str


@dataclass
class FarmAlert:
  zone: str
  alert: str
  at: str


@dataclass
class BridgeState:
  mqtt_connected: bool = False
  broker: str = "localhost"
  port: int = 1883
  last_telemetry: FarmTelemetry | None = None
  last_status: FarmStatus | None = None
  history: list = field(default_factory=list)
  alerts: list = field(default_factory=list)


def _iso_now() -> str:
  return datetime.now(timezone.utc).isoformat()


class FarmMqttBridge:
  def __init__(self, broker: str = "localhost", port: int = 1883, history_size: int = 60) -> None:
    self.broker = broker
    self.port = port
    self.history_size = history_size
    self.soil_alert_thresh = 30.0

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
      return {
          "mqtt_connected": self._state.mqtt_connected,
          "broker": self._state.broker,
          "port": self._state.port,
          "soil_alert_thresh": self.soil_alert_thresh,
          "last_telemetry": asdict(self._state.last_telemetry) if self._state.last_telemetry else None,
          "last_status": asdict(self._state.last_status) if self._state.last_status else None,
          "history": list(self._state.history),
          "alerts": list(self._state.alerts)[-12:],
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
      sample = FarmTelemetry(
          zone=m.group("zone"),
          air_temp=float(m.group("t")),
          air_hum=float(m.group("h")),
          soil_moist=float(m.group("s")),
          light_lux=int(m.group("l")),
          pump_on=m.group("pump") == "1",
          mode=m.group("mode").upper(),
          at=at,
      )
      with self._lock:
        self._state.last_telemetry = sample
        self._state.history.append(asdict(sample))
        if len(self._state.history) > self.history_size:
          self._state.history = self._state.history[-self.history_size :]
      self._push_event("telemetry", asdict(sample))
      return

    if topic == STATUS_TOPIC:
      m = STATUS_RE.search(payload)
      if not m:
        return
      status = FarmStatus(
          zone=m.group("zone"),
          pump_on=m.group("pump") == "1",
          mode=m.group("mode").upper(),
          soil_thresh=int(m.group("thresh")),
          at=at,
      )
      with self._lock:
        self._state.last_status = status
        self.soil_alert_thresh = status.soil_thresh
      self._push_event("status", asdict(status))
      return

    if topic == ALERT_TOPIC:
      m = ALERT_RE.search(payload)
      if not m:
        return
      alert = FarmAlert(zone=m.group("zone"), alert=m.group("alert"), at=at)
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
