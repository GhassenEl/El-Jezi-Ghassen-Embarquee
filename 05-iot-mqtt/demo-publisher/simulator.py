#!/usr/bin/env python3
"""Simulateur MQTT — alimente Farm, Meteo, Frigo, Home, City, Station et Poubelle."""
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

      # Smart Home — 5 zones
      home_zones = [
          {"id": "salon", "base_t": 22.0, "has_heat": True, "has_door": True},
          {"id": "chambre", "base_t": 20.0, "has_heat": True, "has_door": False},
          {"id": "cuisine", "base_t": 21.0, "has_heat": False, "has_door": True},
          {"id": "bureau", "base_t": 22.0, "has_heat": False, "has_door": False},
          {"id": "garage", "base_t": 17.0, "has_heat": False, "has_door": True},
      ]
      if tick % 50 == 0:
        home_mode = {"HOME": "AWAY", "AWAY": "SLEEP", "SLEEP": "HOME"}[home_mode]
      home_light = home_mode == "HOME"
      home_heat = home_mode == "HOME" and tick % 80 < 40
      if tick % 30 == 0:
        home_door = not home_door
      for zi, z in enumerate(home_zones):
        motion = 1 if (tick + zi * 3) % 17 < 5 else 0
        door = home_door if z["has_door"] else False
        heat = home_heat if z["has_heat"] else False
        light = home_light if z["id"] != "garage" else (tick % 20 < 8)
        temp = z["base_t"] + 1.5 * math.sin(phase + zi) + (1.5 if heat else 0)
        if z["id"] == "cuisine" and tick % 55 < 4:
          temp = 31.0 + math.sin(phase) * 0.5
        lux = 420 if light else (60 if z["id"] != "bureau" else 520)
        pwr = 40 + (45 if light else 0) + (850 if heat else 0) + (12 if motion else 0)
        if door and z["has_door"]:
          pwr += 5
        tel = (
            f"ZONE={z['id']},T={temp:.1f},H={48 + 6 * math.cos(phase * 0.6 + zi):.0f},"
            f"LUX={lux},MOTION={motion},DOOR={1 if door else 0},"
            f"LIGHT={1 if light else 0},HEAT={1 if heat else 0},PWR={pwr}"
        )
        client.publish("eljezi/home/telemetry", tel)
        if z["id"] == "cuisine" and temp > 29.5 and tick % 22 == 0:
          client.publish("eljezi/home/alert", f"ZONE=cuisine,ALERT=TEMP_HIGH,T={temp:.1f}")
      client.publish(
          "eljezi/home/status",
          f"ZONE=salon,ONLINE=1,MODE={home_mode},TARGET_T=22,ALARM=1,LOCK={0 if home_door else 1}",
      )
      if home_mode == "AWAY" and tick % 17 < 5 and tick % 14 == 0:
        client.publish("eljezi/home/alert", "ZONE=salon,ALERT=MOTION_AWAY")
      if home_door and tick % 20 == 0:
        client.publish("eljezi/home/alert", "ZONE=garage,ALERT=DOOR_OPEN")
      if home_mode == "AWAY" and home_door and tick % 17 < 5 and tick % 35 == 0:
        client.publish("eljezi/home/alert", "ZONE=garage,ALERT=INTRUSION")

      # Smart City — 5 zones Tunis
      city_zones = [
          {"id": "centre-ville", "pm": 0, "tr": 0, "park": 45, "noise": 0, "bus": 4, "wifi": 120, "crowd": 2},
          {"id": "medina", "pm": 8, "tr": 1, "park": 12, "noise": 12, "bus": 8, "wifi": 85, "crowd": 1},
          {"id": "lac", "pm": -4, "tr": 0, "park": 60, "noise": -8, "bus": 3, "wifi": 200, "crowd": 2},
          {"id": "ariana", "pm": 12, "tr": 0, "park": 35, "noise": 4, "bus": 6, "wifi": 95, "crowd": 2},
          {"id": "carthage", "pm": -2, "tr": 1, "park": 22, "noise": -4, "bus": 5, "wifi": 150, "crowd": 1},
      ]
      if tick % 35 == 0:
        city_mode = "EVENT" if city_mode == "NORMAL" else "NORMAL"
        city_light = city_mode == "NORMAL"
      for zi, z in enumerate(city_zones):
        phase_z = phase + zi * 0.9
        traffic = min(4, max(1, 1 + (tick // (14 + zi * 3) + z["tr"]) % 4))
        pm25 = max(8, 15 + z["pm"] + int(8 * (math.sin(phase_z) + 1)))
        aqi = 30 + pm25 + traffic * 9 + (5 if city_mode == "EVENT" else 0)
        park = max(0, z["park"] - (tick % (30 + zi * 5)))
        noise = max(40, 50 + z["noise"] + traffic * 6 + zi * 2)
        bus = z["bus"] + traffic
        wifi = z["wifi"] + (tick % 20) * 2
        crowd = min(5, max(1, z["crowd"] + (traffic // 2) + (1 if city_mode == "EVENT" else 0)))
        energy = (1400 if city_light else 200) + traffic * 130 + zi * 80
        temp = 23 + 3 * math.sin(phase_z) + zi * 0.3
        hum = 50 + 8 * math.cos(phase_z * 0.5) + zi
        city_tel = (
            f"ZONE={z['id']},AQI={aqi},PM25={pm25},CO2={400 + int(35 * math.sin(phase_z))},"
            f"NOISE={noise},TRAFFIC={traffic},PARK={park},LIGHT={1 if city_light else 0},"
            f"T={temp:.1f},H={hum:.0f},ENERGY={energy},BUS={bus},WIFI={wifi},CROWD={crowd}"
        )
        client.publish("eljezi/city/telemetry", city_tel)
        if zi == 0:
          client.publish(
              "eljezi/city/status",
              f"ZONE=centre-ville,ONLINE=1,MODE={city_mode},ALERT_LVL={1 if city_mode == 'EVENT' else 0},SERVICES=5",
          )
        if aqi > 100 and tick % (16 + zi) == 0:
          client.publish("eljezi/city/alert", f"ZONE={z['id']},ALERT=AIR_QUALITY_BAD")
        if traffic >= 4 and tick % (22 + zi) == 0:
          client.publish("eljezi/city/alert", f"ZONE={z['id']},ALERT=TRAFFIC_JAM")
        if park < 5 and tick % (24 + zi) == 0:
          client.publish("eljezi/city/alert", f"ZONE={z['id']},ALERT=PARKING_FULL")
        if noise > 75 and tick % (26 + zi) == 0:
          client.publish("eljezi/city/alert", f"ZONE={z['id']},ALERT=NOISE_HIGH")

      # Smart Station — 5 stations transport
      station_defs = [
          ("metro-lac", "M4", "METRO", "Ariana", 0),
          ("metro-republique", "M1", "METRO", "Ben Arous", 1),
          ("bus-bab-bhar", "L5", "BUS", "Lac", 2),
          ("tgm-carthage", "TGM", "TRAIN", "La Marsa", 1),
          ("metro-ariana", "M5", "METRO", "Centre-ville", 0),
      ]
      for si, (sid, line, veh, direction, eta_off) in enumerate(station_defs):
        eta = max(1, 2 + (tick + si * 3) % 12 + eta_off)
        occ = min(95, 40 + (tick * 2 + si * 11) % 55)
        crowd = min(5, 1 + occ // 20)
        validators = 2 + si % 3
        temp = 23 + math.sin(phase + si) * 2
        hum = 48 + si * 2
        tel = (
            f"STATION={sid},LINE={line},VEHICLE={veh},DIR={direction},"
            f"ETA={eta},OCC={occ},VALIDATORS={validators},"
            f"T={temp:.1f},H={hum:.0f},CROWD={crowd}"
        )
        client.publish("eljezi/station/telemetry", tel)
        if si == 0:
          client.publish(
              "eljezi/station/status",
              f"STATION={sid},ONLINE=1,MODE=NORMAL,LINES=8,SERVICES=6",
          )
        if eta > 10 and tick % (18 + si) == 0:
          client.publish("eljezi/station/alert", f"STATION={sid},ALERT=DELAY_HIGH,ETA={eta}")
        if occ > 85 and tick % (20 + si) == 0:
          client.publish("eljezi/station/alert", f"STATION={sid},ALERT=CROWD_HIGH,OCC={occ}")

      # Smart Poubelle — 5 conteneurs Grand Tunis
      poubelle_defs = [
          ("parc-lac", "RECYCLE", 0, 68),
          ("medina-centre", "GENERAL", 1, 91),
          ("campus-ensa", "PAPER", 2, 45),
          ("marche-central", "ORGANIC", 3, 82),
          ("plage-carthage", "GLASS", 4, 54),
      ]
      for bi, (bid, btype, off, base_fill) in enumerate(poubelle_defs):
        fill = min(98, max(5, base_fill + int(6 * math.sin(phase + bi * 0.8)) + (tick // 40 + off) % 5))
        weight = fill * (2.2 if btype == "GENERAL" else 0.65)
        lid = 1 if btype == "ORGANIC" and tick % 45 < 6 else 0
        gas = 50 + fill // 2 + (80 if lid else 0) + bi * 15
        batt = max(20, 95 - (tick // 30 + bi * 3) % 40)
        temp = 24 + 3 * math.sin(phase + bi) + (2 if btype == "ORGANIC" else 0)
        hum = 50 + 8 * math.cos(phase * 0.6 + bi) + (15 if btype == "ORGANIC" else 0)
        tel = (
            f"BIN={bid},TYPE={btype},FILL={fill},WEIGHT={weight:.1f},"
            f"LID={lid},GAS={gas},BATT={batt},T={temp:.1f},H={hum:.0f}"
        )
        client.publish("eljezi/poubelle/telemetry", tel)
        if bi == 0:
          client.publish(
              "eljezi/poubelle/status",
              f"BIN={bid},ONLINE=1,MODE=NORMAL,COLLECT={1 if fill >= 85 else 0},ALARM=1",
          )
        if fill >= 90 and tick % (17 + bi) == 0:
          client.publish("eljezi/poubelle/alert", f"BIN={bid},ALERT=FILL_HIGH")
        if fill >= 96 and tick % (22 + bi) == 0:
          client.publish("eljezi/poubelle/alert", f"BIN={bid},ALERT=FILL_FULL")
        if lid and tick % (28 + bi) == 0:
          client.publish("eljezi/poubelle/alert", f"BIN={bid},ALERT=LID_OPEN")
        if gas > 250 and tick % (30 + bi) == 0:
          client.publish("eljezi/poubelle/alert", f"BIN={bid},ALERT=ODOR_HIGH")

      # Smart Parking — 5 parkings Grand Tunis
      parking_defs = [
          ("lac-nord", 120, 8, 0, 72),
          ("medina-centre", 85, 2, 1, 93),
          ("ariana-mall", 200, 12, 2, 61),
          ("carthage-plage", 60, 4, 3, 63),
          ("enit-campus", 150, 6, 4, 37),
      ]
      for pi, (lid, spots, ev_total, off, base_occ) in enumerate(parking_defs):
        occ = min(98, max(5, base_occ + int(5 * math.sin(phase + pi * 0.7)) + (tick // 35 + off) % 6))
        free = max(0, int(spots * (100 - occ) / 100))
        ev_free = max(0, min(ev_total, ev_total - (occ // 25)))
        gate = 0 if tick % 120 == 0 and pi == 1 else 1
        temp = 24 + 3 * math.sin(phase + pi)
        hum = 50 + 6 * math.cos(phase * 0.5 + pi)
        tel = (
            f"LOT={lid},SPOTS={spots},FREE={free},OCC={occ},"
            f"EV={ev_free},GATE={gate},T={temp:.1f},H={hum:.0f}"
        )
        client.publish("eljezi/parking/telemetry", tel)
        if pi == 0:
          client.publish(
              "eljezi/parking/status",
              f"LOT={lid},ONLINE=1,MODE=NORMAL,GATE={'OPEN' if gate else 'CLOSED'}",
          )
        if occ >= 95 and tick % (16 + pi) == 0:
          client.publish("eljezi/parking/alert", f"LOT={lid},ALERT=FULL")
        if occ >= 85 and tick % (20 + pi) == 0:
          client.publish("eljezi/parking/alert", f"LOT={lid},ALERT=ALMOST_FULL")
        if ev_free == 0 and tick % (24 + pi) == 0:
          client.publish("eljezi/parking/alert", f"LOT={lid},ALERT=EV_FULL")

      print(f"[{tick}] farm/meteo/frigo/home/city/station/poubelle/parking publies")
      time.sleep(args.interval)
  except KeyboardInterrupt:
    print("\nArret simulateur.")
  finally:
    client.loop_stop()
    client.disconnect()
  return 0


if __name__ == "__main__":
  raise SystemExit(main())
