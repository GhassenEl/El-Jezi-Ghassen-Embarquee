"""Persistance SQLite — télémétrie et alertes Smart Farm cloud."""
from __future__ import annotations

import os
import sqlite3
from contextlib import contextmanager
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

DB_PATH = Path(os.environ.get("FARM_DB_PATH", "data/farm_cloud.db"))


def _iso_now() -> str:
  return datetime.now(timezone.utc).isoformat()


def init_db() -> None:
  DB_PATH.parent.mkdir(parents=True, exist_ok=True)
  with _conn() as conn:
    conn.executescript(
        """
        CREATE TABLE IF NOT EXISTS telemetry (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          zone TEXT NOT NULL,
          air_temp REAL,
          air_hum REAL,
          soil_moist REAL,
          light_lux INTEGER,
          pump_on INTEGER,
          mode TEXT,
          recorded_at TEXT NOT NULL
        );
        CREATE TABLE IF NOT EXISTS alerts (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          zone TEXT NOT NULL,
          alert TEXT NOT NULL,
          recorded_at TEXT NOT NULL
        );
        CREATE TABLE IF NOT EXISTS commands (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          command TEXT NOT NULL,
          source TEXT NOT NULL,
          recorded_at TEXT NOT NULL
        );
        CREATE TABLE IF NOT EXISTS ai_insights (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          zone TEXT NOT NULL,
          risk_level TEXT NOT NULL,
          health_score INTEGER,
          payload_json TEXT NOT NULL,
          recorded_at TEXT NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_telemetry_at ON telemetry(recorded_at);
        CREATE INDEX IF NOT EXISTS idx_alerts_at ON alerts(recorded_at);
        CREATE INDEX IF NOT EXISTS idx_ai_at ON ai_insights(recorded_at);
        """
    )


@contextmanager
def _conn():
  conn = sqlite3.connect(DB_PATH)
  conn.row_factory = sqlite3.Row
  try:
    yield conn
    conn.commit()
  finally:
    conn.close()


def insert_telemetry(
    zone: str,
    air_temp: float,
    air_hum: float,
    soil_moist: float,
    light_lux: int,
    pump_on: bool,
    mode: str,
) -> None:
  with _conn() as conn:
    conn.execute(
        """
        INSERT INTO telemetry (zone, air_temp, air_hum, soil_moist, light_lux, pump_on, mode, recorded_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        """,
        (zone, air_temp, air_hum, soil_moist, light_lux, int(pump_on), mode, _iso_now()),
    )


def insert_alert(zone: str, alert: str) -> None:
  with _conn() as conn:
    conn.execute(
        "INSERT INTO alerts (zone, alert, recorded_at) VALUES (?, ?, ?)",
        (zone, alert, _iso_now()),
    )


def insert_command(command: str, source: str = "api") -> None:
  with _conn() as conn:
    conn.execute(
        "INSERT INTO commands (command, source, recorded_at) VALUES (?, ?, ?)",
        (command, source, _iso_now()),
    )


def latest_telemetry() -> dict[str, Any] | None:
  with _conn() as conn:
    row = conn.execute(
        "SELECT * FROM telemetry ORDER BY id DESC LIMIT 1"
    ).fetchone()
  return dict(row) if row else None


def telemetry_history(limit: int = 100) -> list[dict[str, Any]]:
  with _conn() as conn:
    rows = conn.execute(
        "SELECT * FROM telemetry ORDER BY id DESC LIMIT ?",
        (limit,),
    ).fetchall()
  return [dict(r) for r in reversed(rows)]


def alerts_history(limit: int = 50) -> list[dict[str, Any]]:
  with _conn() as conn:
    rows = conn.execute(
        "SELECT * FROM alerts ORDER BY id DESC LIMIT ?",
        (limit,),
    ).fetchall()
  return [dict(r) for r in rows]


def insert_ai_insight(zone: str, risk_level: str, health_score: int, payload_json: str) -> None:
  with _conn() as conn:
    conn.execute(
        """
        INSERT INTO ai_insights (zone, risk_level, health_score, payload_json, recorded_at)
        VALUES (?, ?, ?, ?, ?)
        """,
        (zone, risk_level, health_score, payload_json, _iso_now()),
    )


def ai_insights_history(limit: int = 20) -> list[dict[str, Any]]:
  with _conn() as conn:
    rows = conn.execute(
        "SELECT * FROM ai_insights ORDER BY id DESC LIMIT ?",
        (limit,),
    ).fetchall()
  return [dict(r) for r in rows]
