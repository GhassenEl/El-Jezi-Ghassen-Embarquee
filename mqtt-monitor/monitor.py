#!/usr/bin/env python3
"""
El Jezi Ghassen — Moniteur MQTT IoT
Abonne telemetry + status, publie commandes, alertes seuil température.
"""
from __future__ import annotations

import argparse
import re
import sys
from datetime import datetime

import paho.mqtt.client as mqtt

TELEMETRY_TOPIC = "eljezi/esp32/telemetry"
COMMAND_TOPIC = "eljezi/esp32/command"
STATUS_TOPIC = "eljezi/esp32/status"

SAMPLE_RE = re.compile(
    r"T\s*=\s*(?P<t>[-.\d]+)\s*,\s*H\s*=\s*(?P<h>[-.\d]+)\s*,\s*V\s*=\s*(?P<v>[-.\d]+)",
    re.I,
)


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description="Moniteur MQTT El Jezi ESP32")
    p.add_argument("--broker", default="localhost", help="Hôte Mosquitto")
    p.add_argument("--port", type=int, default=1883)
    p.add_argument("--temp-alert", type=float, default=28.0, help="Alerte si T° > seuil")
    p.add_argument("--cmd", help="Publier une commande puis quitter (ex. LED_ON)")
    return p.parse_args()


def on_connect(client: mqtt.Client, userdata, flags, reason_code, properties=None):
    if reason_code != 0:
        print(f"[ERR] Connexion MQTT: {reason_code}")
        return
    print(f"[OK] Connecté à {userdata['broker']}:{userdata['port']}")
    client.subscribe(TELEMETRY_TOPIC)
    client.subscribe(STATUS_TOPIC)
    print(f"[OK] Abonné {TELEMETRY_TOPIC}, {STATUS_TOPIC}")


def on_message(client: mqtt.Client, userdata, msg):
    ts = datetime.now().strftime("%H:%M:%S")
    payload = msg.payload.decode(errors="ignore").strip()
    print(f"[{ts}] {msg.topic} → {payload}")

    if msg.topic == TELEMETRY_TOPIC:
        m = SAMPLE_RE.search(payload)
        if not m:
            return
        temp = float(m.group("t"))
        if temp > userdata["temp_alert"]:
            print(f"  ⚠ ALERTE : température {temp}°C > seuil {userdata['temp_alert']}°C")


def main() -> int:
    args = parse_args()
    userdata = {"broker": args.broker, "port": args.port, "temp_alert": args.temp_alert}

    try:
        client = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2, userdata=userdata)
    except AttributeError:
        client = mqtt.Client(userdata=userdata)

    client.on_connect = on_connect
    client.on_message = on_message

    client.connect(args.broker, args.port, keepalive=60)

    if args.cmd:
        client.loop_start()
        client.publish(COMMAND_TOPIC, args.cmd)
        print(f"[TX] {COMMAND_TOPIC} → {args.cmd}")
        client.loop_stop()
        return 0

    print("Ctrl+C pour quitter. Exemple commande :")
    print(f"  python monitor.py --broker {args.broker} --cmd LED_ON")
    try:
        client.loop_forever()
    except KeyboardInterrupt:
        print("\nArrêt.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
