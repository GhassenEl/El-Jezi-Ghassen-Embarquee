#!/usr/bin/env python3
"""API Smart Energy — IA optimisation (port 5170)."""
from __future__ import annotations

import json
from pathlib import Path

from fastapi import FastAPI, Query
from fastapi.middleware.cors import CORSMiddleware

from ai_engine import analyze_site, network_overview

SITES_PATH = Path(__file__).resolve().parent.parent / "data" / "sites.json"
HIST_PATH = Path(__file__).resolve().parent.parent / "data" / "demo_history.json"
SNAP_PATH = Path(__file__).resolve().parent.parent / "data" / "demo_snapshot.json"

app = FastAPI(title="El Jezi Smart Energy API", version="1.0.0")
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_methods=["*"], allow_headers=["*"])


def _demo_latest() -> dict[str, dict]:
  if not SNAP_PATH.is_file():
    return {}
  snap = json.loads(SNAP_PATH.read_text(encoding="utf-8"))
  return {r["site_id"]: r for r in snap.get("sites_live", [])}


def _demo_history() -> list[dict]:
  if not HIST_PATH.is_file():
    return []
  hist = json.loads(HIST_PATH.read_text(encoding="utf-8"))
  rows = []
  for site_id, samples in hist.items():
    for s in samples:
      rows.append({"site_id": site_id, **s})
  return rows


@app.get("/api/v1/health")
def health():
  return {"ok": True, "service": "smart-energy-api", "ai_enabled": True, "sites_tracked": len(_demo_latest())}


@app.get("/api/v1/sites")
def sites():
  if SITES_PATH.is_file():
    return json.loads(SITES_PATH.read_text(encoding="utf-8"))
  return {"sites": []}


@app.get("/api/v1/ai/insights")
def ai_insights(site_id: str = Query("lac-solar")):
  latest = _demo_latest()
  insights = analyze_site(_demo_history(), site_id=site_id, latest_by_site=latest)
  data = insights.to_dict()
  data["network"] = network_overview(latest)
  return data
