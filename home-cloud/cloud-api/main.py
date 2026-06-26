#!/usr/bin/env python3
"""API cloud Smart Home — REST + SSE + historique SQLite + IA."""
from __future__ import annotations

import json
import os
from pathlib import Path

from fastapi import FastAPI, HTTPException, Query
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import StreamingResponse
from pydantic import BaseModel

from ai_engine import analyze_zone, home_overview
from db import (
    ai_insights_history,
    alerts_history,
    init_db,
    insert_ai_insight,
    insert_command,
    latest_per_zone,
    latest_telemetry,
    telemetry_history,
)
from mqtt_ingest import CloudMqttIngest

ZONES_PATH = Path(os.environ.get(
    "ZONES_JSON_PATH",
    Path(__file__).resolve().parent.parent.parent / "data" / "zones.json",
))

app = FastAPI(title="El Jezi Smart Home Cloud", version="1.0.0")
ingest = CloudMqttIngest()

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)


class CommandBody(BaseModel):
  command: str


class AutoModeBody(BaseModel):
  confirm: bool = False
  mode: str = "SLEEP"


def _load_zones() -> dict:
  if ZONES_PATH.is_file():
    return json.loads(ZONES_PATH.read_text(encoding="utf-8"))
  return {"zones": []}


def _target_temp(zone: str) -> float:
  for z in _load_zones().get("zones", []):
    if z.get("id") == zone:
      return float(z.get("target_temp", 22))
  return 22.0


def _run_ai(zone: str = "salon", mode: str = "HOME", persist: bool = True):
  latest = latest_per_zone()
  history = telemetry_history(limit=200)
  insights = analyze_zone(
      history,
      zone=zone,
      mode=mode.upper(),
      target_temp=_target_temp(zone),
      latest_by_zone=latest,
  )
  if insights and persist:
    insert_ai_insight(
        insights.zone,
        insights.security_risk,
        insights.comfort_score,
        json.dumps(insights.to_dict(), ensure_ascii=False),
    )
  return insights


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
      "service": "smart-home-cloud",
      "version": "1.0.0",
      "ai_enabled": True,
      "mqtt_connected": ingest.connected,
      "broker": os.environ.get("MQTT_BROKER", "localhost"),
      "zones_tracked": len(latest),
  }


@app.get("/api/v1/zones")
def zones():
  return _load_zones()


@app.get("/api/v1/telemetry/latest")
def telemetry_latest(zone: str | None = None):
  row = latest_telemetry(zone)
  if not row:
    raise HTTPException(404, "no telemetry yet")
  return row


@app.get("/api/v1/telemetry/history")
def telemetry_hist(zone: str | None = None, limit: int = 100):
  limit = max(1, min(limit, 500))
  return {"items": telemetry_history(zone=zone, limit=limit)}


@app.get("/api/v1/alerts")
def alerts(limit: int = 50):
  limit = max(1, min(limit, 200))
  return {"items": alerts_history(limit)}


@app.post("/api/v1/command")
def send_command(body: CommandBody):
  cmd = body.command.strip().upper()
  if not cmd:
    raise HTTPException(400, "command required")
  ok = ingest.publish_command(cmd)
  if not ok:
    raise HTTPException(503, "mqtt not connected")
  insert_command(cmd, source="cloud-api")
  return {"ok": True, "command": cmd}


@app.get("/api/v1/ai/insights")
def ai_insights(
    zone: str = Query("salon"),
    mode: str = Query("HOME"),
    persist: bool = True,
):
  insights = _run_ai(zone=zone, mode=mode, persist=persist)
  data = insights.to_dict()
  data["overview"] = home_overview(latest_per_zone())
  data["recent_alerts"] = alerts_history(10)
  return data


@app.get("/api/v1/ai/history")
def ai_history(limit: int = 20):
  limit = max(1, min(limit, 100))
  return {"items": ai_insights_history(limit)}


@app.get("/api/v1/ai/overview")
def ai_overview():
  return home_overview(latest_per_zone())


@app.post("/api/v1/ai/auto-mode")
def ai_auto_mode(body: AutoModeBody):
  insights = _run_ai(persist=True)
  if not insights.auto_mode_recommended:
    return {
        "ok": False,
        "executed": False,
        "reason": "IA ne recommande pas de changement de mode",
        "insights": insights.to_dict(),
    }
  mode = (body.mode or insights.auto_mode_recommended or "SLEEP").upper()
  if not body.confirm:
    return {
        "ok": True,
        "executed": False,
        "reason": "Confirmation requise — renvoyer {\"confirm\": true}",
        "suggested_mode": mode,
        "insights": insights.to_dict(),
    }
  cmd = f"MODE_{mode}"
  ok = ingest.publish_command(cmd)
  if ok:
    insert_command(cmd, source="ai-auto")
  return {
      "ok": ok,
      "executed": ok,
      "command": cmd,
      "insights": insights.to_dict(),
  }


@app.get("/api/v1/stream")
def stream():
  def generate():
    latest = latest_per_zone()
    ai = _run_ai(persist=False)
    hello = {
        "kind": "hello",
        "payload": {
            "mqtt_connected": ingest.connected,
            "latest_by_zone": latest,
            "alerts": alerts_history(10),
            "ai": ai.to_dict() if ai else None,
        },
    }
    yield f"data: {json.dumps(hello)}\n\n"
    while True:
      event = ingest.poll_event(timeout=25.0)
      if event is None:
        yield ": keepalive\n\n"
        continue
      yield f"data: {json.dumps(event)}\n\n"

  return StreamingResponse(generate(), media_type="text/event-stream")
