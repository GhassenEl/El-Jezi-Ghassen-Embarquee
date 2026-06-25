#!/usr/bin/env python3
"""Simulateur MQTT — alimente Farm, Meteo, Frigo, Home et City pour demos dashboard."""
from __future__ import annotations

import argparse
import math
import random
import time

import paho.mqtt.client as mqtt


def parse_args() -> argparse.Namespace:
  p = argparse.ArgumentParser(description="Simulateur telemetry El Jezi IoT")
  p.add_argument("--broker", default="localhost")
  p.add_argument("--port", type=int, default=1883)
  p.add_argument("--interval", type=float, default=3.0)
  return p.parse_args()


def main() -> int:
  args = parse_args()
  try:
    client = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2)
  except AttributeError:
    client = mqtt.Client()
  client.connect(args.broker, args.port, keepalive=60)
  client.loop_start()

  tick = 0
  rain = 0.0
  door = False
  home_door = False
  home_mode = "HOME"
  home_light = True
  home_heat = False
  city_mode = "NORMAL"
  city_light = True
  print(f"Simulateur MQTT -> {args.broker}:{args.port} (Ctrl+C pour arreter)")

  try:
    while True:
      tick += 1
      phase = tick * 0.15

      # Smart Farm
      soil = 35 + 10 * math.sin(phase)
      farm_tel = (
          f"ZONE=parcelle-a,T={22 + 3 * math.sin(phase):.1f},"
          f"H={55 + 10 * math.cos(phase * 0.7):.1f},"
          f"S={soil:.1f},L={8000 + tick % 500},PUMP={1 if soil < 30 else 0},MODE=AUTO"
      )
      farm_status = "ZONE=parcelle-a,PUMP=0,MODE=AUTO,THRESH=30"
      client.publish("eljezi/smartfarm/telemetry", farm_tel)
      if tick % 20 == 0:
        client.publish("eljezi/smartfarm/status", farm_status)
      if soil < 28 and tick % 15 == 0:
        client.publish("eljezi/smartfarm/alert", "ZONE=parcelle-a,ALERT=SOIL_DRY")

      # Smart Meteo
      wind = 8 + 12 * abs(math.sin(phase * 1.2))
      rain += 0.1 if tick % 10 < 2 else 0
      meteo_tel = (
          f"STATION=jardin,T={20 + 6 * math.sin(phase):.1f},"
          f"H={55 + 15 * math.cos(phase * 0.7):.1f},"
          f"P={1013 + 4 * math.sin(phase * 0.3):.1f},"
          f"W={wind:.1f},R={rain:.2f},UV={max(0, min(11, int(3 + 4 * math.sin(phase * 0.5))))}"
      )
      client.publish("eljezi/meteo/telemetry", meteo_tel)
      client.publish("eljezi/meteo/status", "STATION=jardin,ONLINE=1,MODE=AUTO")
      if wind > 35 and tick % 12 == 0:
        client.publish("eljezi/meteo/alert", f"STATION=jardin,ALERT=WIND_HIGH,W={wind:.1f}")

      # Smart Frigo
      if tick % 25 == 0:
        door = not door
      fridge = 4.0 + (1.5 if door else 0) + random.uniform(-0.2, 0.2)
      freezer = -18.0 + (2.0 if door else 0) + random.uniform(-0.3, 0.3)
      comp = 0 if door else (1 if fridge > 4.5 or freezer > -17 else 0)
      pwr = 120 if comp else 8
      frigo_tel = (
          f"ZONE=cuisine,T={fridge:.1f},F={freezer:.1f},H={55 if door else 42:.0f},"
          f"DOOR={1 if door else 0},COMP={comp},PWR={pwr}"
      )
      client.publish("eljezi/frigo/telemetry", frigo_tel)
      client.publish("eljezi/frigo/status", "ZONE=cuisine,ONLINE=1,MODE=NORMAL,TARGET_F=4,TARGET_Z=-18,ALARM=1")
      if door and tick % 18 == 0:
        client.publish("eljezi/frigo/alert", "ZONE=cuisine,ALERT=DOOR_OPEN_LONG")

      # Smart Home
      if tick % 30 == 0:
        home_door = not home_door
      if tick % 40 == 0:
        home_mode = "AWAY" if home_mode == "HOME" else "HOME"
        home_light = home_mode == "HOME"
        home_heat = home_mode == "HOME" and tick % 80 < 40
      motion = 1 if tick % 17 < 5 else 0
      temp = 22.0 + 2.0 * math.sin(phase) + (1.5 if home_heat else 0)
      lux = 420 if home_light else 60
      pwr = 80 + (45 if home_light else 0) + (850 if home_heat else 0) + (12 if motion else 0)
      home_tel = (
          f"ZONE=salon,T={temp:.1f},H={48 + 6 * math.cos(phase * 0.6):.0f},"
          f"LUX={lux},MOTION={motion},DOOR={1 if home_door else 0},"
          f"LIGHT={1 if home_light else 0},HEAT={1 if home_heat else 0},PWR={pwr}"
      )
      client.publish("eljezi/home/telemetry", home_tel)
      client.publish(
          "eljezi/home/status",
          f"ZONE=salon,ONLINE=1,MODE={home_mode},TARGET_T=22,ALARM=1,LOCK={0 if home_door else 1}",
      )
      if home_mode == "AWAY" and motion and tick % 14 == 0:
        client.publish("eljezi/home/alert", "ZONE=salon,ALERT=MOTION_AWAY")
      if home_door and tick % 20 == 0:
        client.publish("eljezi/home/alert", "ZONE=salon,ALERT=DOOR_OPEN")

      # Smart City
      if tick % 35 == 0:
        city_mode = "EVENT" if city_mode == "NORMAL" else "NORMAL"
        city_light = city_mode == "NORMAL"
      traffic = 1 + (tick // 18) % 4
      pm25 = 15 + int(8 * (math.sin(phase) + 1))
      aqi = 35 + pm25 + traffic * 8
      park = max(0, 40 - (tick % 38))
      noise = 50 + traffic * 6
      energy = (1400 if city_light else 200) + traffic * 120
      city_tel = (
          f"ZONE=centre-ville,AQI={aqi},PM25={pm25},CO2={400 + int(30 * math.sin(phase))},"
          f"NOISE={noise},TRAFFIC={traffic},PARK={park},LIGHT={1 if city_light else 0},"
          f"T={24 + 3 * math.sin(phase):.1f},H={52 + 8 * math.cos(phase * 0.5):.0f},ENERGY={energy}"
      )
      client.publish("eljezi/city/telemetry", city_tel)
      client.publish(
          "eljezi/city/status",
          f"ZONE=centre-ville,ONLINE=1,MODE={city_mode},ALERT_LVL={1 if city_mode == 'EVENT' else 0},SERVICES=4",
      )
      if aqi > 100 and tick % 16 == 0:
        client.publish("eljezi/city/alert", "ZONE=centre-ville,ALERT=AIR_QUALITY_BAD")
      if traffic >= 4 and tick % 22 == 0:
        client.publish("eljezi/city/alert", "ZONE=centre-ville,ALERT=TRAFFIC_JAM")
      if park < 5 and tick % 24 == 0:
        client.publish("eljezi/city/alert", "ZONE=centre-ville,ALERT=PARKING_FULL")

      print(f"[{tick}] farm/meteo/frigo/home/city publies")
      time.sleep(args.interval)
  except KeyboardInterrupt:
    print("\nArret simulateur.")
  finally:
    client.loop_stop()
    client.disconnect()
  return 0


if __name__ == "__main__":
  raise SystemExit(main())
