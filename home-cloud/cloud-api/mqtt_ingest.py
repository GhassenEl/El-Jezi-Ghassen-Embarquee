"""Ingestion MQTT cloud Smart Home + publication commandes + evenements SSE."""
from __future__ import annotations

import os
import re
import threading
import time
from queue import Empty, Queue
from typing import Any

import paho.mqtt.client as mqtt

from db import insert_alert, insert_telemetry

TELEMETRY_TOPIC = "eljezi/home/telemetry"
COMMAND_TOPIC = "eljezi/home/command"
ALERT_TOPIC = "eljezi/home/alert"

TEL_RE = re.compile(
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

ALERT_RE = re.compile(r"ZONE\s*=\s*(?P<zone>[^,]+)\s*,\s*ALERT\s*=\s*(?P<alert>[\w_,.=]+)", re.I)


class CloudMqttIngest:
  def __init__(self) -> None:
    self.broker = os.environ.get("MQTT_BROKER", "localhost")
    self.port = int(os.environ.get("MQTT_PORT", "1883"))
    self._client: mqtt.Client | None = None
    self._connected = False
    self._events: Queue[dict[str, Any]] = Queue()
    self._stop = threading.Event()
    self._lock = threading.Lock()

  @property
  def connected(self) -> bool:
    with self._lock:
      return self._connected

  def start(self) -> None:
    try:
      client = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2)
    except AttributeError:
      client = mqtt.Client()
    client.on_connect = self._on_connect
    client.on_message = self._on_message
    client.on_disconnect = self._on_disconnect
    self._client = client
    client.connect_async(self.broker, self.port, 60)
    client.loop_start()
    threading.Thread(target=self._reconnect_loop, daemon=True).start()

  def stop(self) -> None:
    self._stop.set()
    if self._client:
      self._client.loop_stop()
      self._client.disconnect()

  def publish_command(self, command: str) -> bool:
    if not self._client or not self.connected:
      return False
    cmd = command.strip().upper()
    result = self._client.publish(COMMAND_TOPIC, cmd)
    return result.rc == mqtt.MQTT_ERR_SUCCESS

  def poll_event(self, timeout: float = 20.0) -> dict[str, Any] | None:
    try:
      return self._events.get(timeout=timeout)
    except Empty:
      return None

  def _push(self, kind: str, payload: dict[str, Any]) -> None:
    self._events.put({"kind": kind, "payload": payload})

  def _on_connect(self, client, userdata, flags, reason_code, properties=None):
    with self._lock:
      self._connected = reason_code == 0
    if reason_code == 0:
      client.subscribe(TELEMETRY_TOPIC)
      client.subscribe(ALERT_TOPIC)
      self._push("mqtt_status", {"connected": True})

  def _on_disconnect(self, client, userdata, flags, reason_code, properties=None):
    with self._lock:
      self._connected = False
    self._push("mqtt_status", {"connected": False})

  def _on_message(self, client, userdata, msg):
    payload = msg.payload.decode(errors="ignore").strip()
    if msg.topic == TELEMETRY_TOPIC:
      m = TEL_RE.search(payload)
      if not m:
        return
      row = {
          "zone": m.group("zone").strip(),
          "temp_c": float(m.group("t")),
          "humidity": float(m.group("h")),
          "lux": int(m.group("lux")),
          "motion": m.group("motion") == "1",
          "door_open": m.group("door") == "1",
          "light_on": m.group("light") == "1",
          "heat_on": m.group("heat") == "1",
          "power_w": int(m.group("pwr")),
      }
      insert_telemetry(**row)
      self._push("telemetry", row)
      return
    if msg.topic == ALERT_TOPIC:
      m = ALERT_RE.search(payload)
      if not m:
        return
      zone = m.group("zone").strip()
      alert = m.group("alert").strip()
      insert_alert(zone, alert)
      self._push("alert", {"zone": zone, "alert": alert})

  def _reconnect_loop(self) -> None:
    while not self._stop.is_set():
      with self._lock:
        connected = self._connected
      if not connected and self._client:
        try:
          self._client.reconnect()
        except Exception:
          pass
      time.sleep(3)
