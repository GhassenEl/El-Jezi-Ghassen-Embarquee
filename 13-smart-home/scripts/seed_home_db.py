#!/usr/bin/env python3
"""Remplit SQLite Smart Home depuis data/demo_*.json (home-api ou home-cloud)."""
from __future__ import annotations

import argparse
import json
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DATA = ROOT / "data"


def _load(name: str) -> dict | list:
  path = DATA / name
  return json.loads(path.read_text(encoding="utf-8"))


def seed(target: str) -> None:
  if target == "cloud":
    sys.path.insert(0, str(ROOT / "home-cloud" / "cloud-api"))
    from db import init_db, insert_alert, insert_telemetry  # type: ignore
  else:
    sys.path.insert(0, str(ROOT / "home-api"))
    from db import init_db, insert_alert, insert_telemetry  # type: ignore

  snapshot = _load("demo_snapshot.json")
  history = _load("demo_history.json")

  init_db()
  now = datetime.now(timezone.utc)

  for zone_id, samples in history.items():
    live = next((z for z in snapshot["zones_live"] if z["zone"] == zone_id), None)
    for s in samples:
      mins = int(s.get("minutes_ago", 0))
      insert_telemetry(
          zone_id,
          float(s["temp_c"]),
          float(s["humidity"]),
          int(s["lux"]),
          bool(live and live.get("motion")),
          bool(live and live.get("door_open")),
          bool(live and live.get("light_on")),
          bool(live and live.get("heat_on")),
          int(s["power_w"]),
      )

  for a in snapshot.get("alerts_recent", []):
    insert_alert(a["zone"], a["alert"])

  print(f"OK — seed {target} : {sum(len(v) for v in history.values())} echantillons telemetry")
  print(f"     alertes : {len(snapshot.get('alerts_recent', []))}")


def main() -> int:
  p = argparse.ArgumentParser(description="Seed SQLite Smart Home")
  p.add_argument("--target", choices=["api", "cloud"], default="cloud")
  args = p.parse_args()
  seed(args.target)
  return 0


if __name__ == "__main__":
  raise SystemExit(main())
