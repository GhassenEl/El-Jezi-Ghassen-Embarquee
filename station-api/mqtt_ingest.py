"""Ingestion MQTT Smart Station vers SQLite."""
from __future__ import annotations

import re
import threading

import paho.mqtt.client as mqtt

from db import insert_telemetry

TELEMETRY_TOPIC = "eljezi/station/telemetry"

TEL_RE = re.compile(
    r"STATION\s*=\s*(?P<st>[^,]+)\s*,\s*"
    r"LINE\s*=\s*(?P<line>[^,]+)\s*,\s*"
    r"VEHICLE\s*=\s*(?P<veh>[^,]+)\s*,\s*"
    r"DIR\s*=\s*(?P<dir>[^,]+)\s*,\s*"
    r"ETA\s*=\s*(?P<eta>\d+)\s*,\s*"
    r"OCC\s*=\s*(?P<occ>\d+)\s*,.*?"
    r"VALIDATORS\s*=\s*(?P<val>\d+)\s*,.*?"
    r"CROWD\s*=\s*(?P<crowd>\d)",
    re.I,
)


class StationMqttIngest:
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

  def _on_message(self, client, userdata, msg):
    payload = msg.payload.decode(errors="ignore").strip()
    m = TEL_RE.search(payload)
    if not m:
      return
    insert_telemetry(
        m.group("st").strip(),
        m.group("line").strip(),
        m.group("veh").strip().upper(),
        m.group("dir").strip(),
        int(m.group("eta")),
        int(m.group("occ")),
        int(m.group("crowd")),
        int(m.group("val")),
    )
