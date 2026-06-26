"""Ingestion MQTT Smart Home vers SQLite."""
from __future__ import annotations

import re
import threading

import paho.mqtt.client as mqtt

from db import insert_alert, insert_telemetry

TELEMETRY_TOPIC = "eljezi/home/telemetry"
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


class HomeMqttIngest:
  def __init__(self, broker: str = "localhost", port: int = 1883) -> None:
    self.broker = broker
    self.port = port
    self.connected = False
    self._client: mqtt.Client | None = None
    self._lock = threading.Lock()

  def start(self) -> None:
    try:
      client = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2)
    except AttributeError:
      client = mqtt.Client()
    client.on_connect = self._on_connect
    client.on_message = self._on_message
    client.connect_async(self.broker, self.port, 60)
    client.loop_start()
    self._client = client

  def stop(self) -> None:
    if self._client:
      self._client.loop_stop()
      self._client.disconnect()
      self._client = None
    with self._lock:
      self.connected = False

  def _on_connect(self, client, userdata, flags, reason_code, properties=None):
    with self._lock:
      self.connected = reason_code == 0
    if reason_code == 0:
      client.subscribe(TELEMETRY_TOPIC)
      client.subscribe(ALERT_TOPIC)

  def _on_message(self, client, userdata, msg):
    payload = msg.payload.decode(errors="ignore").strip()
    if msg.topic == TELEMETRY_TOPIC:
      m = TEL_RE.search(payload)
      if not m:
        return
      insert_telemetry(
          m.group("zone").strip(),
          float(m.group("t")),
          float(m.group("h")),
          int(m.group("lux")),
          m.group("motion") == "1",
          m.group("door") == "1",
          m.group("light") == "1",
          m.group("heat") == "1",
          int(m.group("pwr")),
      )
      return
    if msg.topic == ALERT_TOPIC:
      m = ALERT_RE.search(payload)
      if not m:
        return
      insert_alert(m.group("zone").strip(), m.group("alert").strip())

