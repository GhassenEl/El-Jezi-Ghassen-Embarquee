#!/usr/bin/env python3
"""
El Jezi Ghassen — Moniteur MQTT Smart Meteo
Alertes vent fort, pluie, chaleur, UV.
"""
from __future__ import annotations

import argparse
import re
import sys
from datetime import datetime

import paho.mqtt.client as mqtt

TELEMETRY_TOPIC = "eljezi/meteo/telemetry"
COMMAND_TOPIC = "eljezi/meteo/command"
STATUS_TOPIC = "eljezi/meteo/status"
ALERT_TOPIC = "eljezi/meteo/alert"

TELEMETRY_RE = re.compile(
    r"T\s*=\s*(?P<t>[-.\d]+)\s*,\s*"
    r"H\s*=\s*(?P<h>[-.\d]+)\s*,\s*"
    r"P\s*=\s*(?P<p>[-.\d]+)\s*,\s*"
    r"W\s*=\s*(?P<w>[-.\d]+)\s*,\s*"
    r"R\s*=\s*(?P<r>[-.\d]+)\s*,\s*"
    r"UV\s*=\s*(?P<uv>\d+)",
    re.I,
)


def parse_args() -> argparse.Namespace:
  p = argparse.ArgumentParser(description="Moniteur Smart Meteo El Jezi")
  p.add_argument("--broker", default="localhost")
  p.add_argument("--port", type=int, default=1883)
  p.add_argument("--wind-alert", type=float, default=35.0)
  p.add_argument("--temp-alert", type=float, default=32.0)
  p.add_argument("--cmd", help="Publier une commande puis quitter")
  return p.parse_args()


def on_connect(client, userdata, flags, reason_code, properties=None):
  if reason_code != 0:
    print(f"[ERR] MQTT {reason_code}")
    return
  print(f"[OK] Connecte {userdata['broker']}:{userdata['port']}")
  client.subscribe(TELEMETRY_TOPIC)
  client.subscribe(STATUS_TOPIC)
  client.subscribe(ALERT_TOPIC)


def on_message(client, userdata, msg):
  ts = datetime.now().strftime("%H:%M:%S")
  payload = msg.payload.decode(errors="ignore").strip()
  print(f"[{ts}] {msg.topic} -> {payload}")

  if msg.topic != TELEMETRY_TOPIC:
    return
  m = TELEMETRY_RE.search(payload)
  if not m:
    return
  temp = float(m.group("t"))
  wind = float(m.group("w"))
  uv = int(m.group("uv"))
  if wind > userdata["wind_alert"]:
    print(f"  ! ALERTE vent {wind} km/h")
  if temp > userdata["temp_alert"]:
    print(f"  ! ALERTE chaleur {temp}°C")
  if uv >= 8:
    print(f"  ! ALERTE UV eleve ({uv})")


def main() -> int:
  args = parse_args()
  userdata = {
      "broker": args.broker,
      "port": args.port,
      "wind_alert": args.wind_alert,
      "temp_alert": args.temp_alert,
  }

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
    print(f"[TX] {COMMAND_TOPIC} -> {args.cmd}")
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
