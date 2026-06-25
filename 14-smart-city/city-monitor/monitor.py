#!/usr/bin/env python3
"""Moniteur MQTT Smart City — El Jezi Ghassen."""
from __future__ import annotations

import argparse
import re
import sys
from datetime import datetime

import paho.mqtt.client as mqtt

TELEMETRY_TOPIC = "eljezi/city/telemetry"
COMMAND_TOPIC = "eljezi/city/command"
STATUS_TOPIC = "eljezi/city/status"
ALERT_TOPIC = "eljezi/city/alert"

TELEMETRY_RE = re.compile(
    r"AQI\s*=\s*(?P<aqi>\d+)\s*,\s*"
    r"TRAFFIC\s*=\s*(?P<traffic>\d)\s*,\s*"
    r"PARK\s*=\s*(?P<park>\d+)",
    re.I,
)


def parse_args() -> argparse.Namespace:
  p = argparse.ArgumentParser(description="Moniteur Smart City El Jezi")
  p.add_argument("--broker", default="localhost")
  p.add_argument("--port", type=int, default=1883)
  p.add_argument("--aqi-alert", type=int, default=100)
  p.add_argument("--cmd", help="Commande unique puis quitter")
  return p.parse_args()


def on_connect(client, userdata, flags, reason_code, properties=None):
  if reason_code != 0:
    return
  print(f"[OK] Connecte {userdata['broker']}:{userdata['port']}")
  client.subscribe(TELEMETRY_TOPIC)
  client.subscribe(STATUS_TOPIC)
  client.subscribe(ALERT_TOPIC)


def on_message(client, userdata, msg):
  ts = datetime.now().strftime("%H:%M:%S")
  payload = msg.payload.decode(errors="ignore").strip()
  print(f"[{ts}] {msg.topic} -> {payload}")
  if msg.topic == ALERT_TOPIC:
    print("  ! Alerte ville")
    return
  if msg.topic != TELEMETRY_TOPIC:
    return
  m = TELEMETRY_RE.search(payload)
  if not m:
    return
  aqi = int(m.group("aqi"))
  if aqi > userdata["aqi_alert"]:
    print(f"  ! AQI eleve : {aqi}")
  if int(m.group("traffic")) >= 4:
    print("  ! Embouteillage")
  if int(m.group("park")) < 5:
    print("  ! Parking sature")


def main() -> int:
  args = parse_args()
  userdata = {"broker": args.broker, "port": args.port, "aqi_alert": args.aqi_alert}
  try:
    client = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2, userdata=userdata)
  except AttributeError:
    client = mqtt.Client(userdata=userdata)
  client.on_connect = on_connect
  client.on_message = on_message
  client.connect(args.broker, args.port, keepalive=60)
  if args.cmd:
    client.loop_start()
    client.publish(COMMAND_TOPIC, args.cmd.strip().upper())
    client.loop_stop()
    return 0
  print("Ctrl+C pour quitter.")
  try:
    client.loop_forever()
  except KeyboardInterrupt:
    print("\nArret.")
  return 0


if __name__ == "__main__":
  sys.exit(main())
