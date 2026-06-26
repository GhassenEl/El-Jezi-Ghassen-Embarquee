#!/usr/bin/env python3
"""Moniteur CLI Smart Poubelle — alertes remplissage."""
from __future__ import annotations

import argparse
import re
import sys

import paho.mqtt.client as mqtt

TOPIC_TEL = "eljezi/poubelle/telemetry"
TOPIC_ALERT = "eljezi/poubelle/alert"

TEL_RE = re.compile(r"BIN\s*=\s*([^,]+).*FILL\s*=\s*(\d+)", re.I)


def main() -> int:
  p = argparse.ArgumentParser(description="Moniteur Smart Poubelle")
  p.add_argument("--broker", default="localhost")
  p.add_argument("--port", type=int, default=1883)
  args = p.parse_args()

  try:
    client = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2)
  except AttributeError:
    client = mqtt.Client()

  def on_message(c, u, msg):
    payload = msg.payload.decode(errors="ignore").strip()
    if msg.topic == TOPIC_TEL:
      m = TEL_RE.search(payload)
      if m:
        fill = int(m.group(2))
        flag = " !!!" if fill >= 85 else ""
        print(f"[TELEMETRY] {m.group(1).strip()} fill={fill}%{flag}")
    elif msg.topic == TOPIC_ALERT:
      print(f"[ALERTE] {payload}")

  client.on_message = on_message
  client.connect(args.broker, args.port, 60)
  client.subscribe(TOPIC_TEL)
  client.subscribe(TOPIC_ALERT)
  print(f"Moniteur poubelle -> {args.broker}:{args.port} (Ctrl+C)")
  try:
    client.loop_forever()
  except KeyboardInterrupt:
    print("\nArret.")
  return 0


if __name__ == "__main__":
  sys.exit(main())
