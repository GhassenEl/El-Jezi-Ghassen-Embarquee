"""Donnees demo Smart Poubelle."""
from __future__ import annotations

import json
from pathlib import Path

_DATA = Path(__file__).resolve().parent.parent / "data"


def load_bins() -> dict:
  return json.loads((_DATA / "bins.json").read_text(encoding="utf-8"))


def demo_state_dict() -> dict:
  snap = json.loads((_DATA / "demo_snapshot.json").read_text(encoding="utf-8"))
  bins = snap["bins_live"]
  primary = bins[0]
  status = snap["status"]
  return {
      "mqtt_connected": False,
      "broker": "demo",
      "port": 0,
      "demo_mode": True,
      "catalog": load_bins(),
      "totals": snap.get("totals", {}),
      "bins": bins,
      "last_telemetry": {
          "bin_id": primary["bin_id"],
          "waste_type": primary["type"],
          "fill_pct": primary["fill_pct"],
          "weight_kg": primary["weight_kg"],
          "lid_open": primary["lid_open"],
          "gas_ppm": primary["gas_ppm"],
          "battery_pct": primary["battery_pct"],
          "temp_c": primary["temp_c"],
          "humidity": primary["humidity"],
          "at": "demo",
      },
      "last_status": {
          "bin_id": status["bin_id"],
          "online": status["online"],
          "mode": status["mode"],
          "collection_due": status["collection_due"],
          "alarm_on": status["alarm_on"],
          "at": "demo",
      },
      "history": bins,
      "alerts": [
          {"bin_id": a["bin_id"], "alert": a["alert"], "at": a.get("at", "demo")}
          for a in snap.get("alerts_recent", [])
      ],
  }
