#!/usr/bin/env python3
"""API Smart Home — IA domotique (port 8120)."""
from __future__ import annotations

import json
import os
from pathlib import Path

from fastapi import FastAPI, Query
from fastapi.middleware.cors import CORSMiddleware

from ai_engine import analyze_zone, home_overview
from db import init_db, latest_per_zone, recent_alerts, telemetry_history
from mqtt_ingest import HomeMqttIngest

ZONES_PATH = Path(__file__).resolve().parent.parent / "data" / "zones.json"

app = FastAPI(title="El Jezi Smart Home API", version="1.0.0")
ingest = HomeMqttIngest(
    broker=os.environ.get("MQTT_BROKER", "localhost"),
    port=int(os.environ.get("MQTT_PORT", "1883")),
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)


def _load_zones() -> dict:
  if ZONES_PATH.is_file():
    return json.loads(ZONES_PATH.read_text(encoding="utf-8"))
  return {"zones": []}


@app.on_event("startup")
def startup() -> None:
  init_db()
  ingest.start()


@app.on_event("shutdown")
def shutdown() -> None:
  ingest.stop()


@app.get("/api/v1/health")
def health():
  latest = latest_per_zone()
  return {
      "ok": True,
      "service": "smart-home-api",
      "ai_enabled": True,
      "mqtt_connected": ingest.connected,
      "zones_tracked": len(latest),
  }


@app.get("/api/v1/zones")
def zones():
  return _load_zones()


@app.get("/api/v1/ai/insights")
def ai_insights(
    zone: str = Query("salon"),
    mode: str = Query("HOME"),
):
  latest = latest_per_zone()
  history = telemetry_history(limit=200)
  zones_data = _load_zones()
  target = 22.0
  for z in zones_data.get("zones", []):
    if z.get("id") == zone:
      target = float(z.get("target_temp", 22))
      break
  insights = analyze_zone(
      history,
      zone=zone,
      mode=mode.upper(),
      target_temp=target,
      latest_by_zone=latest,
  )
  data = insights.to_dict()
  data["overview"] = home_overview(latest)
  data["recent_alerts"] = recent_alerts(10)
  return data


@app.get("/api/v1/ai/overview")
def ai_overview():
  latest = latest_per_zone()
  return home_overview(latest)


@app.get("/api/v1/history")
def history(zone: str | None = None, limit: int = 60):
  return {"samples": telemetry_history(zone=zone, limit=limit)}
