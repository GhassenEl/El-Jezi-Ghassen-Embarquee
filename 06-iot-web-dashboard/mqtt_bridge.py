"""Pont MQTT → file d'événements pour le dashboard Flask."""
from __future__ import annotations

import re
import threading
import time
from dataclasses import asdict, dataclass, field
from datetime import datetime, timezone
from queue import Empty, Queue
from typing import Any

import paho.mqtt.client as mqtt

TELEMETRY_TOPIC = "eljezi/esp32/telemetry"
COMMAND_TOPIC = "eljezi/esp32/command"
STATUS_TOPIC = "eljezi/esp32/status"

SAMPLE_RE = re.compile(
    r"T\s*=\s*(?P<t>[-.\d]+)\s*,\s*H\s*=\s*(?P<h>[-.\d]+)\s*,\s*V\s*=\s*(?P<v>[-.\d]+)",
    re.I,
)
STATUS_RE = re.compile(
    r"LED\s*=\s*(?P<led>\d+)\s*,\s*RELAY\s*=\s*(?P<relay>\d+)\s*,\s*PWM\s*=\s*(?P<pwm>\d+)",
    re.I,
)


@dataclass
class TelemetrySample:
    temperature: float
    humidity: float
    voltage: float
    at: str


@dataclass
class DeviceStatus:
    led_on: bool
    relay_on: bool
    pwm: int
    at: str


@dataclass
class BridgeState:
    mqtt_connected: bool = False
    broker: str = "localhost"
    port: int = 1883
    last_telemetry: TelemetrySample | None = None
    last_status: DeviceStatus | None = None
    history: list = field(default_factory=list)
    alerts: list = field(default_factory=list)


def _iso_now() -> str:
    return datetime.now(timezone.utc).isoformat()


class MqttBridge:
  def __init__(
      self,
      broker: str = "localhost",
      port: int = 1883,
      temp_alert: float = 28.0,
      history_size: int = 60,
  ) -> None:
    self.broker = broker
    self.port = port
    self.temp_alert = temp_alert
    self.history_size = history_size

    self._state = BridgeState(broker=broker, port=port)
    self._lock = threading.Lock()
    self._events: Queue[dict[str, Any]] = Queue()
    self._client: mqtt.Client | None = None
    self._thread: threading.Thread | None = None
    self._stop = threading.Event()

  def _make_client(self) -> mqtt.Client:
    try:
      return mqtt.Client(mqtt.CallbackAPIVersion.VERSION2, userdata=self)
    except AttributeError:
      return mqtt.Client(userdata=self)

  def start(self) -> None:
    if self._thread and self._thread.is_alive():
      return

    self._stop.clear()
    self._client = self._make_client()
    self._client.on_connect = self._on_connect
    self._client.on_message = self._on_message
    self._client.on_disconnect = self._on_disconnect
    self._client.connect_async(self.broker, self.port, keepalive=60)
    self._client.loop_start()

    self._thread = threading.Thread(target=self._reconnect_loop, daemon=True)
    self._thread.start()

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
    if not cmd:
      return False
    result = self._client.publish(COMMAND_TOPIC, cmd)
    self._push_event("command_sent", {"command": cmd, "at": _iso_now()})
    return result.rc == mqtt.MQTT_ERR_SUCCESS

  def snapshot(self) -> dict[str, Any]:
    with self._lock:
      return {
          "mqtt_connected": self._state.mqtt_connected,
          "broker": self._state.broker,
          "port": self._state.port,
          "temp_alert": self.temp_alert,
          "last_telemetry": asdict(self._state.last_telemetry) if self._state.last_telemetry else None,
          "last_status": asdict(self._state.last_status) if self._state.last_status else None,
          "history": list(self._state.history),
          "alerts": list(self._state.alerts)[-10:],
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
      self._push_event("mqtt_status", {"connected": True, "at": _iso_now()})
    else:
      self._push_event("mqtt_status", {"connected": False, "error": str(reason_code), "at": _iso_now()})

  def _on_disconnect(self, client, userdata, flags, reason_code, properties=None):
    with self._lock:
      self._state.mqtt_connected = False
    self._push_event("mqtt_status", {"connected": False, "at": _iso_now()})

  def _on_message(self, client, userdata, msg):
    payload = msg.payload.decode(errors="ignore").strip()
    topic = msg.topic
    at = _iso_now()

    if topic == TELEMETRY_TOPIC:
      m = SAMPLE_RE.search(payload)
      if not m:
        return
      sample = TelemetrySample(
          temperature=float(m.group("t")),
          humidity=float(m.group("h")),
          voltage=float(m.group("v")),
          at=at,
      )
      with self._lock:
        self._state.last_telemetry = sample
        self._state.history.append(asdict(sample))
        if len(self._state.history) > self.history_size:
          self._state.history = self._state.history[-self.history_size :]

        if sample.temperature > self.temp_alert:
          alert = {
              "level": "warning",
              "message": f"Température {sample.temperature:.1f}°C > seuil {self.temp_alert}°C",
              "at": at,
          }
          self._state.alerts.append(alert)
          self._push_event("alert", alert)

      self._push_event("telemetry", asdict(sample))
      return

    if topic == STATUS_TOPIC:
      m = STATUS_RE.search(payload)
      if not m:
        return
      status = DeviceStatus(
          led_on=m.group("led") == "1",
          relay_on=m.group("relay") == "1",
          pwm=int(m.group("pwm")),
          at=at,
      )
      with self._lock:
        self._state.last_status = status
      self._push_event("status", asdict(status))

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
