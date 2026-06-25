"""Donnees demo Smart Home — fallback hors MQTT."""
from __future__ import annotations

import json
from pathlib import Path

_DATA = Path(__file__).resolve().parent.parent / "data"


def load_zones() -> dict:
  return json.loads((_DATA / "zones.json").read_text(encoding="utf-8"))


def load_snapshot() -> dict:
  return json.loads((_DATA / "demo_snapshot.json").read_text(encoding="utf-8"))


def demo_state_dict() -> dict:
  """Etat dashboard compatible avec mqtt_bridge.snapshot()."""
  snap = load_snapshot()
  zones = snap["zones_live"]
  primary = zones[0]
  status = snap["status"]
  history = []
  for z in zones:
    history.append({
        "zone": z["zone"],
        "temp_c": z["temp_c"],
        "humidity": z["humidity"],
        "lux": z["lux"],
        "motion": z["motion"],
        "door_open": z["door_open"],
        "light_on": z["light_on"],
        "heat_on": z["heat_on"],
        "power_w": z["power_w"],
        "at": "demo",
    })
  return {
      "mqtt_connected": False,
      "broker": "demo",
      "port": 0,
      "demo_mode": True,
      "house": load_zones().get("house", {}),
      "zones": zones,
      "totals": snap.get("totals", {}),
      "last_telemetry": {
          "zone": primary["zone"],
          "temp_c": primary["temp_c"],
          "humidity": primary["humidity"],
          "lux": primary["lux"],
          "motion": primary["motion"],
          "door_open": primary["door_open"],
          "light_on": primary["light_on"],
          "heat_on": primary["heat_on"],
          "power_w": primary["power_w"],
          "at": "demo",
      },
      "last_status": {
          "zone": status["zone"],
          "online": status["online"],
          "mode": status["mode"],
          "target_temp": status["target_temp"],
          "alarm_on": status["alarm_on"],
          "door_locked": status["door_locked"],
          "at": "demo",
      },
      "history": history,
      "alerts": [
          {"zone": a["zone"], "alert": a["alert"], "at": a.get("at", "demo")}
          for a in snap.get("alerts_recent", [])
      ],
  }
