#!/usr/bin/env python3
"""API cloud Smart Farm — REST + SSE + historique SQLite."""
from __future__ import annotations

import json
import os

from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import StreamingResponse
from pydantic import BaseModel

from db import alerts_history, init_db, insert_command, latest_telemetry, telemetry_history
from mqtt_ingest import CloudMqttIngest

app = FastAPI(title="El Jezi Smart Farm Cloud", version="1.0.0")
ingest = CloudMqttIngest()

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)


class CommandBody(BaseModel):
  command: str


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


@app.get("/api/v1/stream")
def stream():
  def generate():
    latest = latest_telemetry()
    hello = {
        "kind": "hello",
        "payload": {
            "mqtt_connected": ingest.connected,
            "latest": latest,
            "alerts": alerts_history(10),
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
