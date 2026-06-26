"""Ingestion MQTT Smart Poubelle."""
from __future__ import annotations

import re
import threading

import paho.mqtt.client as mqtt

from db import insert_alert, insert_telemetry

TEL_RE = re.compile(
    r"BIN\s*=\s*(?P<bin>[^,]+)\s*,\s*TYPE\s*=\s*(?P<typ>[^,]+)\s*,\s*"
    r"FILL\s*=\s*(?P<fill>\d+)\s*,\s*WEIGHT\s*=\s*(?P<w>[-.\d]+)\s*,\s*"
    r"LID\s*=\s*(?P<lid>\d)\s*,\s*GAS\s*=\s*(?P<gas>\d+)\s*,\s*BATT\s*=\s*(?P<batt>\d+)",
    re.I,
)
ALERT_RE = re.compile(r"BIN\s*=\s*(?P<bin>[^,]+)\s*,\s*ALERT\s*=\s*(?P<alert>[\w_,.=]+)", re.I)


class PoubelleMqttIngest:
  def __init__(self, broker: str = "localhost", port: int = 1883) -> None:
    self.broker = broker
    self.port = port
    self.connected = False
    self._client = None
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
    with self._lock:
      self.connected = False

  def _on_connect(self, client, userdata, flags, reason_code, properties=None):
    with self._lock:
      self.connected = reason_code == 0
    if reason_code == 0:
      client.subscribe("eljezi/poubelle/telemetry")
      client.subscribe("eljezi/poubelle/alert")

  def _on_message(self, client, userdata, msg):
    payload = msg.payload.decode(errors="ignore").strip()
    if msg.topic.endswith("telemetry"):
      m = TEL_RE.search(payload)
      if not m:
        return
      insert_telemetry(
          m.group("bin").strip(), m.group("typ").strip().upper(),
          int(m.group("fill")), float(m.group("w")),
          m.group("lid") == "1", int(m.group("gas")), int(m.group("batt")),
      )
    elif msg.topic.endswith("alert"):
      m = ALERT_RE.search(payload)
      if m:
        insert_alert(m.group("bin").strip(), m.group("alert").strip())
