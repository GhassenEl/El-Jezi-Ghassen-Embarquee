#!/usr/bin/env python3
"""
El Jezi Ghassen — Passerelle MQTT Raspberry Pi (Linux embarque).

Publie telemetrie capteurs / GPIO sur Mosquitto, ecoute commandes.
Compatible avec l'ecosysteme IoT (05-iot-mqtt, 06-iot-web-dashboard).
"""
from __future__ import annotations

import argparse
import platform
import random
import signal
import subprocess
import sys
import time

import paho.mqtt.client as mqtt

TELEMETRY_TOPIC = "eljezi/rpi/telemetry"
COMMAND_TOPIC = "eljezi/rpi/command"
STATUS_TOPIC = "eljezi/rpi/status"
ALERT_TOPIC = "eljezi/rpi/alert"

_running = True


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description="Passerelle MQTT Raspberry Pi El Jezi")
    p.add_argument("--broker", default="localhost", help="Hote Mosquitto")
    p.add_argument("--port", type=int, default=1883)
    p.add_argument("--interval", type=float, default=3.0, help="Periode telemetrie (s)")
    p.add_argument("--gpio", type=int, default=17, help="Ligne GPIO relais/LED (libgpiod)")
    p.add_argument("--simulate", action="store_true", help="Forcer capteurs simules")
    p.add_argument("--temp-alert", type=float, default=35.0, help="Alerte si T > seuil")
    return p.parse_args()


def is_linux() -> bool:
    return platform.system().lower() == "linux"


class GpioOutput:
    """Controle GPIO via gpioset (libgpiod CLI) sur Pi, sinon simulation."""

    def __init__(self, line: int, simulate: bool) -> None:
        self.line = line
        self.simulate = simulate or not is_linux()
        self._on = False

    def set(self, on: bool) -> None:
        self._on = on
        if self.simulate:
            return
        val = "1" if on else "0"
        try:
            subprocess.run(
                ["gpioset", "-c", "gpiochip0", f"{self.line}={val}"],
                check=False,
                capture_output=True,
                timeout=2,
            )
        except (FileNotFoundError, subprocess.TimeoutExpired):
            self.simulate = True

    @property
    def on(self) -> bool:
        return self._on


def read_sensors(simulate: bool) -> tuple[float, float]:
    """Retourne (temperature C, humidite %). Simulation si pas de materiel."""
    if simulate or not is_linux():
        base_t = 22.0 + random.uniform(-1.5, 1.5)
        base_h = 55.0 + random.uniform(-5, 5)
        return round(base_t, 1), round(base_h, 1)

    # Lecture 1-Wire DS18B20 si present
    for path in ("/sys/bus/w1/devices/28-*/w1_slave",):
        import glob

        for slave in glob.glob(path):
            try:
                with open(slave, encoding="utf-8") as f:
                    lines = f.readlines()
                if len(lines) >= 2 and "YES" in lines[0]:
                    idx = lines[1].find("t=")
                    if idx >= 0:
                        raw = int(lines[1][idx + 2 :].strip())
                        temp = round(raw / 1000.0, 1)
                        return temp, round(50.0 + random.uniform(-3, 3), 1)
            except OSError:
                continue

    return round(22.0 + random.uniform(-0.5, 0.5), 1), round(55.0, 1)


def format_telemetry(temp: float, hum: float, gpio: GpioOutput, uptime_s: int) -> str:
    return f"T={temp},H={hum},GPIO={1 if gpio.on else 0},UP={uptime_s}"


def on_signal(sig, frame) -> None:
    global _running
    _running = False


def main() -> int:
    global _running
    args = parse_args()
    simulate = args.simulate or not is_linux()
    gpio = GpioOutput(args.gpio, simulate)
    start = time.time()

    signal.signal(signal.SIGINT, on_signal)
    signal.signal(signal.SIGTERM, on_signal)

    try:
        client = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2)
    except AttributeError:
        client = mqtt.Client()

    def on_connect(c, userdata, flags, reason_code, properties=None):
        if reason_code != 0:
            print(f"[ERR] MQTT {reason_code}")
            return
        print(f"[OK] Connecte {args.broker}:{args.port}")
        c.subscribe(COMMAND_TOPIC)
        print(f"[OK] Abonne {COMMAND_TOPIC}")

    def on_message(c, userdata, msg):
        cmd = msg.payload.decode(errors="ignore").strip().upper()
        print(f"[RX] {msg.topic} -> {cmd}")
        if cmd in ("LED_ON", "GPIO_ON", "PUMP_ON"):
            gpio.set(True)
        elif cmd in ("LED_OFF", "GPIO_OFF", "PUMP_OFF"):
            gpio.set(False)
        elif cmd == "STATUS":
            pass
        else:
            print(f"  Commande inconnue : {cmd}")
        publish_status(c, gpio, args.gpio)

    def publish_status(c, g: GpioOutput, line: int) -> None:
        payload = f"GPIO={1 if g.on else 0},LINE={line},MODE={'SIM' if g.simulate else 'HW'}"
        c.publish(STATUS_TOPIC, payload)

    client.on_connect = on_connect
    client.on_message = on_message
    client.connect(args.broker, args.port, keepalive=60)
    client.loop_start()

    mode = "simulation" if gpio.simulate else f"GPIO {args.gpio}"
    print(f"=== El Jezi Pi MQTT Gateway ({mode}) ===")
    print(f"Topics : {TELEMETRY_TOPIC} | {STATUS_TOPIC}")
    print("Ctrl+C pour quitter.")

    publish_status(client, gpio, args.gpio)

    while _running:
        temp, hum = read_sensors(gpio.simulate)
        uptime = int(time.time() - start)
        payload = format_telemetry(temp, hum, gpio, uptime)
        client.publish(TELEMETRY_TOPIC, payload)
        print(f"[TX] {payload}")

        if temp > args.temp_alert:
            alert = f"ZONE=rpi,ALERT=TEMP_HIGH,T={temp}"
            client.publish(ALERT_TOPIC, alert)
            print(f"  ! {alert}")

        time.sleep(args.interval)

    gpio.set(False)
    client.loop_stop()
    client.disconnect()
    print("Passerelle arretee.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
