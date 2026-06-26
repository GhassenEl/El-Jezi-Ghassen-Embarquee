#!/usr/bin/env python3
"""API cloud Smart Farm — REST + SSE + historique SQLite + IA."""
from __future__ import annotations

import json
import os

from fastapi import FastAPI, HTTPException, Query
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import StreamingResponse
from pydantic import BaseModel

from ai_engine import analyze_farm, predict_soil_at
from db import (
    ai_insights_history,
    alerts_history,
    init_db,
    insert_ai_insight,
    insert_command,
    latest_telemetry,
    telemetry_history,
)
from mqtt_ingest import CloudMqttIngest

app = FastAPI(title="El Jezi Smart Farm Cloud", version="1.1.0")
ingest = CloudMqttIngest()

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)


class CommandBody(BaseModel):
  command: str


class AutoActionBody(BaseModel):
  confirm: bool = False


def _run_ai_analysis(history_limit: int = 120, soil_threshold: int = 30, persist: bool = True):
  history = telemetry_history(history_limit)
  insights = analyze_farm(history, soil_threshold=soil_threshold)
  if insights and persist:
    insert_ai_insight(
        insights.zone,
        insights.risk_level,
        insights.health_score,
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
  return {
      "ok": True,
      "service": "smart-farm-cloud",
      "version": "1.1.0",
      "ai_enabled": True,
      "mqtt_connected": ingest.connected,
      "broker": os.environ.get("MQTT_BROKER", "localhost"),
  }


@app.get("/api/v1/telemetry/latest")
def telemetry_latest():
  row = latest_telemetry()
  if not row:
    raise HTTPException(404, "no telemetry yet")
  return row


@app.get("/api/v1/telemetry/history")
def telemetry_hist(limit: int = 100):
  limit = max(1, min(limit, 500))
  return {"items": telemetry_history(limit)}


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
    history_limit: int = Query(120, ge=10, le=500),
    soil_threshold: int = Query(30, ge=10, le=80),
    persist: bool = True,
):
  insights = _run_ai_analysis(history_limit, soil_threshold, persist=persist)
  if not insights:
    raise HTTPException(404, "insufficient telemetry for AI analysis")
  return insights.to_dict()


@app.get("/api/v1/ai/history")
def ai_history(limit: int = 20):
  limit = max(1, min(limit, 100))
  return {"items": ai_insights_history(limit)}


@app.get("/api/v1/ai/predict")
def ai_predict(hours: int = Query(6, ge=1, le=48)):
  history = telemetry_history(120)
  insights = analyze_farm(history)
  if not insights:
    raise HTTPException(404, "insufficient data")
  latest = latest_telemetry()
  predicted = predict_soil_at(history, float(hours))
  return {
      "zone": insights.zone,
      "hours": hours,
      "current_soil": latest["soil_moist"] if latest else None,
      "predicted_soil": predicted,
      "hours_until_dry": insights.hours_until_dry,
      "soil_trend": insights.soil_trend,
  }


@app.post("/api/v1/ai/auto-irrigate")
def ai_auto_irrigate(body: AutoActionBody):
  insights = _run_ai_analysis(persist=True)
  if not insights:
    raise HTTPException(404, "insufficient data")
  if not insights.auto_irrigate_recommended:
    return {
        "ok": False,
        "executed": False,
        "reason": "IA ne recommande pas d'irrigation automatique maintenant",
        "insights": insights.to_dict(),
    }
  if not body.confirm:
    return {
        "ok": True,
        "executed": False,
        "reason": "Confirmation requise — renvoyer {\"confirm\": true}",
        "insights": insights.to_dict(),
    }
  ok = ingest.publish_command("PUMP_ON")
  if ok:
    insert_command("PUMP_ON", source="ai-auto")
  return {
      "ok": ok,
      "executed": ok,
      "command": "PUMP_ON",
      "insights": insights.to_dict(),
  }


@app.get("/api/v1/stream")
def stream():
  def generate():
    latest = latest_telemetry()
    ai = None
    try:
      ai = _run_ai_analysis(persist=False)
    except Exception:
      pass
    hello = {
        "kind": "hello",
        "payload": {
            "mqtt_connected": ingest.connected,
            "latest": latest,
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
