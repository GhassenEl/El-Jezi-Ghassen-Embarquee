"""Pont MQTT Smart Home pour le dashboard Flask."""
from __future__ import annotations

import re
import threading
import time
from dataclasses import asdict, dataclass, field
from datetime import datetime, timezone
from queue import Empty, Queue
from typing import Any

import paho.mqtt.client as mqtt

TELEMETRY_TOPIC = "eljezi/home/telemetry"
COMMAND_TOPIC = "eljezi/home/command"
STATUS_TOPIC = "eljezi/home/status"
ALERT_TOPIC = "eljezi/home/alert"

TELEMETRY_RE = re.compile(
    r"ZONE\s*=\s*(?P<zone>[^,]+)\s*,\s*"
    r"T\s*=\s*(?P<t>[-.\d]+)\s*,\s*"
    r"H\s*=\s*(?P<h>[-.\d]+)\s*,\s*"
    r"LUX\s*=\s*(?P<lux>\d+)\s*,\s*"
    r"MOTION\s*=\s*(?P<motion>\d)\s*,\s*"
    r"DOOR\s*=\s*(?P<door>\d)\s*,\s*"
    r"LIGHT\s*=\s*(?P<light>\d)\s*,\s*"
    r"HEAT\s*=\s*(?P<heat>\d)\s*,\s*"
    r"PWR\s*=\s*(?P<pwr>\d+)",
    re.I,
)

STATUS_RE = re.compile(
    r"ZONE\s*=\s*(?P<zone>[^,]+)\s*,\s*"
    r"ONLINE\s*=\s*(?P<online>\d)\s*,\s*"
    r"MODE\s*=\s*(?P<mode>HOME|AWAY|SLEEP)\s*,\s*"
    r"TARGET_T\s*=\s*(?P<tt>[-.\d]+)\s*,\s*"
    r"ALARM\s*=\s*(?P<alarm>\d)\s*,\s*"
    r"LOCK\s*=\s*(?P<lock>\d)",
    re.I,
)

ALERT_RE = re.compile(r"ZONE\s*=\s*(?P<zone>[^,]+)\s*,\s*ALERT\s*=\s*(?P<alert>[\w_,.=]+)", re.I)


@dataclass
class HomeTelemetry:
  zone: str
  temp_c: float
  humidity: float
  lux: int
  motion: bool
  door_open: bool
  light_on: bool
  heat_on: bool
  power_w: int
  at: str


@dataclass
class HomeStatus:
  zone: str
  online: bool
  mode: str
  target_temp: float
  alarm_on: bool
  door_locked: bool
  at: str


@dataclass
class HomeAlert:
  zone: str
  alert: str
  at: str


@dataclass
class BridgeState:
  mqtt_connected: bool = False
  broker: str = "localhost"
  port: int = 1883
  last_telemetry: HomeTelemetry | None = None
  last_status: HomeStatus | None = None
  history: list = field(default_factory=list)
  alerts: list = field(default_factory=list)


def _iso_now() -> str:
  return datetime.now(timezone.utc).isoformat()


class HomeMqttBridge:
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
      return {
          "mqtt_connected": self._state.mqtt_connected,
          "broker": self._state.broker,
          "port": self._state.port,
          "last_telemetry": asdict(self._state.last_telemetry) if self._state.last_telemetry else None,
          "last_status": asdict(self._state.last_status) if self._state.last_status else None,
          "history": list(self._state.history),
          "alerts": list(self._state.alerts)[-15:],
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
      sample = HomeTelemetry(
          zone=m.group("zone"),
          temp_c=float(m.group("t")),
          humidity=float(m.group("h")),
          lux=int(m.group("lux")),
          motion=m.group("motion") == "1",
          door_open=m.group("door") == "1",
          light_on=m.group("light") == "1",
          heat_on=m.group("heat") == "1",
          power_w=int(m.group("pwr")),
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
      status = HomeStatus(
          zone=m.group("zone"),
          online=m.group("online") == "1",
          mode=m.group("mode").upper(),
          target_temp=float(m.group("tt")),
          alarm_on=m.group("alarm") == "1",
          door_locked=m.group("lock") == "1",
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
      alert = HomeAlert(zone=m.group("zone"), alert=m.group("alert"), at=at)
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
