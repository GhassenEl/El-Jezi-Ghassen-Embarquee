#!/usr/bin/env python3
"""Moniteur MQTT Smart Frigo — El Jezi Ghassen."""
from __future__ import annotations

import argparse
import re
import sys
from datetime import datetime

import paho.mqtt.client as mqtt

TELEMETRY_TOPIC = "eljezi/frigo/telemetry"
COMMAND_TOPIC = "eljezi/frigo/command"
STATUS_TOPIC = "eljezi/frigo/status"
ALERT_TOPIC = "eljezi/frigo/alert"

TELEMETRY_RE = re.compile(
    r"T\s*=\s*(?P<t>[-.\d]+)\s*,\s*"
    r"F\s*=\s*(?P<f>[-.\d]+)\s*,\s*"
    r"DOOR\s*=\s*(?P<door>\d)\s*,\s*"
    r"COMP\s*=\s*(?P<comp>\d)\s*,\s*"
    r"PWR\s*=\s*(?P<pwr>\d+)",
    re.I,
)


def parse_args() -> argparse.Namespace:
  p = argparse.ArgumentParser(description="Moniteur Smart Frigo El Jezi")
  p.add_argument("--broker", default="localhost")
  p.add_argument("--port", type=int, default=1883)
  p.add_argument("--fridge-alert", type=float, default=8.0)
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
  if msg.topic != TELEMETRY_TOPIC:
    return
  m = TELEMETRY_RE.search(payload)
  if not m:
    return
  temp = float(m.group("t"))
  door = m.group("door") == "1"
  if temp > userdata["fridge_alert"]:
    print(f"  ! ALERTE frigo {temp}°C > {userdata['fridge_alert']}°C")
  if door:
    print("  ! Porte ouverte")


def main() -> int:
  args = parse_args()
  userdata = {"broker": args.broker, "port": args.port, "fridge_alert": args.fridge_alert}
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
