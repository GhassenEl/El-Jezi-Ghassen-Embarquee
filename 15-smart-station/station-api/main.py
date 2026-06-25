#!/usr/bin/env python3
"""API Smart Station — IA transport public (port 8130)."""
from __future__ import annotations

import os

from fastapi import FastAPI, Query
from fastapi.middleware.cors import CORSMiddleware

from ai_engine import analyze_station, network_overview
from db import init_db, latest_per_station, telemetry_history
from mqtt_ingest import StationMqttIngest

app = FastAPI(title="El Jezi Smart Station API", version="1.0.0")
ingest = StationMqttIngest(
    broker=os.environ.get("MQTT_BROKER", "localhost"),
    port=int(os.environ.get("MQTT_PORT", "1883")),
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.on_event("startup")
def startup() -> None:
  init_db()
  ingest.start()


@app.on_event("shutdown")
def shutdown() -> None:
  ingest.stop()


@app.get("/api/v1/health")
def health():
  latest = latest_per_station()
  return {
      "ok": True,
      "service": "smart-station-api",
      "ai_enabled": True,
      "mqtt_connected": ingest.connected,
      "stations_tracked": len(latest),
  }


@app.get("/api/v1/ai/insights")
def ai_insights(station: str = Query("metro-lac")):
  latest = latest_per_station()
  history = telemetry_history(limit=200)
  insights = analyze_station(history, station_id=station, latest_by_station=latest)
  data = insights.to_dict()
  data["network"] = network_overview(latest)
  return data


@app.get("/api/v1/ai/network")
def ai_network():
  latest = latest_per_station()
  return network_overview(latest)
