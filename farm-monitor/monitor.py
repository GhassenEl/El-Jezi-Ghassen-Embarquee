#!/usr/bin/env python3
"""Moniteur CLI Smart Farm — télémétrie et alertes irrigation."""
from __future__ import annotations

import argparse
import re
import sys
from datetime import datetime

import paho.mqtt.client as mqtt

TELEMETRY = "eljezi/smartfarm/telemetry"
ALERT = "eljezi/smartfarm/alert"
COMMAND = "eljezi/smartfarm/command"

TEL_RE = re.compile(r"S\s*=\s*(?P<s>[-.\d]+)", re.I)
ALERT_RE = re.compile(r"ALERT\s*=\s*(?P<a>\w+)", re.I)


def parse_args() -> argparse.Namespace:
  p = argparse.ArgumentParser(description="Moniteur Smart Farm El Jezi")
  p.add_argument("--broker", default="localhost")
  p.add_argument("--port", type=int, default=1883)
  p.add_argument("--soil-alert", type=float, default=25.0)
  p.add_argument("--cmd", help="Publier commande (ex. MODE_AUTO)")
  return p.parse_args()


def on_connect(client, userdata, flags, reason_code, properties=None):
  if reason_code != 0:
    print(f"[ERR] MQTT {reason_code}")
    return
  print(f"[OK] Connecte {userdata['broker']}:{userdata['port']}")
  client.subscribe(TELEMETRY)
  client.subscribe(ALERT)


def on_message(client, userdata, msg):
  ts = datetime.now().strftime("%H:%M:%S")
  payload = msg.payload.decode(errors="ignore").strip()
  print(f"[{ts}] {msg.topic} -> {payload}")

  if msg.topic == TELEMETRY:
    m = TEL_RE.search(payload)
    if m and float(m.group("s")) < userdata["soil_alert"]:
      print(f"  !! Sol sec : {m.group('s')}% < {userdata['soil_alert']}%")

  if msg.topic == ALERT:
    m = ALERT_RE.search(payload)
    if m:
      print(f"  >> Alerte ferme : {m.group('a')}")


def main() -> int:
  args = parse_args()
  userdata = {"broker": args.broker, "port": args.port, "soil_alert": args.soil_alert}

  try:
    client = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2, userdata=userdata)
  except AttributeError:
    client = mqtt.Client(userdata=userdata)

  client.on_connect = on_connect
  client.on_message = on_message
  client.connect(args.broker, args.port, 60)

  if args.cmd:
    client.loop_start()
    client.publish(COMMAND, args.cmd)
    print(f"[TX] {COMMAND} -> {args.cmd}")
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
