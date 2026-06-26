#!/usr/bin/env python3
"""API Smart Poubelle — IA collecte dechets (port 5150)."""
from __future__ import annotations

import json
import os
from pathlib import Path

from fastapi import FastAPI, Query
from fastapi.middleware.cors import CORSMiddleware

from ai_engine import analyze_bin, network_overview
from db import init_db, latest_per_bin, telemetry_history
from mqtt_ingest import PoubelleMqttIngest

BINS_PATH = Path(__file__).resolve().parent.parent / "data" / "bins.json"

app = FastAPI(title="El Jezi Smart Poubelle API", version="1.0.0")
ingest = PoubelleMqttIngest(
    broker=os.environ.get("MQTT_BROKER", "localhost"),
    port=int(os.environ.get("MQTT_PORT", "1883")),
)

app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_methods=["*"], allow_headers=["*"])


@app.on_event("startup")
def startup() -> None:
  init_db()
  ingest.start()


@app.on_event("shutdown")
def shutdown() -> None:
  ingest.stop()


@app.get("/api/v1/health")
def health():
  latest = latest_per_bin()
  return {
      "ok": True,
      "service": "smart-poubelle-api",
      "ai_enabled": True,
      "mqtt_connected": ingest.connected,
      "bins_tracked": len(latest),
  }


@app.get("/api/v1/bins")
def bins():
  if BINS_PATH.is_file():
    return json.loads(BINS_PATH.read_text(encoding="utf-8"))
  return {"bins": []}


@app.get("/api/v1/ai/insights")
def ai_insights(bin_id: str = Query("parc-lac")):
  latest = latest_per_bin()
  history = telemetry_history(limit=200)
  insights = analyze_bin(history, bin_id=bin_id, latest_by_bin=latest)
  data = insights.to_dict()
  data["network"] = network_overview(latest)
  return data


@app.get("/api/v1/ai/network")
def ai_network():
  return network_overview(latest_per_bin())
