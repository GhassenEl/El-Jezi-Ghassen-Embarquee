#!/usr/bin/env python3
"""API Smart Parking — IA recommandation (port 5160)."""
from __future__ import annotations

import json
import os
from pathlib import Path

from fastapi import FastAPI, Query
from fastapi.middleware.cors import CORSMiddleware

from ai_engine import analyze_lot, network_overview

LOTS_PATH = Path(__file__).resolve().parent.parent / "data" / "lots.json"
HIST_PATH = Path(__file__).resolve().parent.parent / "data" / "demo_history.json"
SNAP_PATH = Path(__file__).resolve().parent.parent / "data" / "demo_snapshot.json"

app = FastAPI(title="El Jezi Smart Parking API", version="1.0.0")
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_methods=["*"], allow_headers=["*"])


def _demo_latest() -> dict[str, dict]:
  if not SNAP_PATH.is_file():
    return {}
  snap = json.loads(SNAP_PATH.read_text(encoding="utf-8"))
  out = {}
  for row in snap.get("lots_live", []):
    lid = row["lot_id"]
    out[lid] = row
  return out


def _demo_history() -> list[dict]:
  if not HIST_PATH.is_file():
    return []
  hist = json.loads(HIST_PATH.read_text(encoding="utf-8"))
  rows = []
  for lot_id, samples in hist.items():
    for s in samples:
      rows.append({"lot_id": lot_id, "occupancy_pct": s["occupancy_pct"], "spots_free": s["spots_free"]})
  return rows


@app.get("/api/v1/health")
def health():
  latest = _demo_latest()
  return {"ok": True, "service": "smart-parking-api", "ai_enabled": True, "lots_tracked": len(latest)}


@app.get("/api/v1/lots")
def lots():
  if LOTS_PATH.is_file():
    return json.loads(LOTS_PATH.read_text(encoding="utf-8"))
  return {"lots": []}


@app.get("/api/v1/ai/insights")
def ai_insights(lot_id: str = Query("lac-nord")):
  latest = _demo_latest()
  history = _demo_history()
  insights = analyze_lot(history, lot_id=lot_id, latest_by_lot=latest)
  data = insights.to_dict()
  data["network"] = network_overview(latest)
  return data
