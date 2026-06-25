"""SQLite cloud Smart Home — historique, alertes, commandes, IA."""
from __future__ import annotations

import json
import os
import sqlite3
from pathlib import Path

DB_PATH = Path(os.environ.get("HOME_DB_PATH", Path(__file__).resolve().parent.parent.parent / "data" / "home_cloud.db"))


def _conn() -> sqlite3.Connection:
  DB_PATH.parent.mkdir(parents=True, exist_ok=True)
  conn = sqlite3.connect(DB_PATH)
  conn.row_factory = sqlite3.Row
  return conn


def init_db() -> None:
  with _conn() as c:
    c.executescript("""
      CREATE TABLE IF NOT EXISTS telemetry (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        zone TEXT NOT NULL,
        temp_c REAL,
        humidity REAL,
        lux INTEGER,
        motion INTEGER,
        door_open INTEGER,
        light_on INTEGER,
        heat_on INTEGER,
        power_w INTEGER,
        recorded_at TEXT DEFAULT (datetime('now'))
      );
      CREATE TABLE IF NOT EXISTS alerts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        zone TEXT NOT NULL,
        alert TEXT NOT NULL,
        recorded_at TEXT DEFAULT (datetime('now'))
      );
      CREATE TABLE IF NOT EXISTS commands (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        command TEXT NOT NULL,
        source TEXT DEFAULT 'cloud-api',
        recorded_at TEXT DEFAULT (datetime('now'))
      );
      CREATE TABLE IF NOT EXISTS ai_insights (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        zone TEXT NOT NULL,
        security_risk TEXT,
        comfort_score INTEGER,
        payload TEXT,
        recorded_at TEXT DEFAULT (datetime('now'))
      );
      CREATE INDEX IF NOT EXISTS idx_tel_zone ON telemetry(zone);
    """)


def insert_telemetry(
    zone: str,
    temp_c: float,
    humidity: float,
    lux: int,
    motion: bool,
    door_open: bool,
    light_on: bool,
    heat_on: bool,
    power_w: int,
) -> None:
  with _conn() as c:
    c.execute(
        """INSERT INTO telemetry
           (zone, temp_c, humidity, lux, motion, door_open, light_on, heat_on, power_w)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)""",
        (zone, temp_c, humidity, lux, int(motion), int(door_open),
         int(light_on), int(heat_on), power_w),
    )


def insert_alert(zone: str, alert: str) -> None:
  with _conn() as c:
    c.execute("INSERT INTO alerts (zone, alert) VALUES (?, ?)", (zone, alert))


def insert_command(command: str, source: str = "cloud-api") -> None:
  with _conn() as c:
    c.execute("INSERT INTO commands (command, source) VALUES (?, ?)", (command, source))


def insert_ai_insight(zone: str, security_risk: str, comfort_score: int, payload: str) -> None:
  with _conn() as c:
    c.execute(
        "INSERT INTO ai_insights (zone, security_risk, comfort_score, payload) VALUES (?, ?, ?, ?)",
        (zone, security_risk, comfort_score, payload),
    )


def telemetry_history(zone: str | None = None, limit: int = 120) -> list[dict]:
  with _conn() as c:
    if zone:
      rows = c.execute(
          "SELECT * FROM telemetry WHERE zone = ? ORDER BY id DESC LIMIT ?",
          (zone, limit),
      ).fetchall()
    else:
      rows = c.execute(
          "SELECT * FROM telemetry ORDER BY id DESC LIMIT ?",
          (limit,),
      ).fetchall()
  out = []
  for r in reversed(rows):
    out.append({
        "zone": r["zone"],
        "temp_c": r["temp_c"],
        "humidity": r["humidity"],
        "lux": r["lux"],
        "motion": bool(r["motion"]),
        "door_open": bool(r["door_open"]),
        "light_on": bool(r["light_on"]),
        "heat_on": bool(r["heat_on"]),
        "power_w": r["power_w"],
        "recorded_at": r["recorded_at"],
    })
  return out


def latest_telemetry(zone: str | None = None) -> dict | None:
  with _conn() as c:
    if zone:
      r = c.execute(
          "SELECT * FROM telemetry WHERE zone = ? ORDER BY id DESC LIMIT 1",
          (zone,),
      ).fetchone()
    else:
      r = c.execute("SELECT * FROM telemetry ORDER BY id DESC LIMIT 1").fetchone()
  if not r:
    return None
  return {
      "zone": r["zone"],
      "temp_c": r["temp_c"],
      "humidity": r["humidity"],
      "lux": r["lux"],
      "motion": bool(r["motion"]),
      "door_open": bool(r["door_open"]),
      "light_on": bool(r["light_on"]),
      "heat_on": bool(r["heat_on"]),
      "power_w": r["power_w"],
      "recorded_at": r["recorded_at"],
  }


def latest_per_zone() -> dict[str, dict]:
  with _conn() as c:
    rows = c.execute("""
      SELECT t.* FROM telemetry t
      INNER JOIN (
        SELECT zone, MAX(id) AS max_id FROM telemetry GROUP BY zone
      ) m ON t.id = m.max_id
    """).fetchall()
  return {
      r["zone"]: {
          "zone": r["zone"],
          "temp_c": r["temp_c"],
          "humidity": r["humidity"],
          "lux": r["lux"],
          "motion": bool(r["motion"]),
          "door_open": bool(r["door_open"]),
          "light_on": bool(r["light_on"]),
          "heat_on": bool(r["heat_on"]),
          "power_w": r["power_w"],
      }
      for r in rows
  }


def alerts_history(limit: int = 50) -> list[dict]:
  with _conn() as c:
    rows = c.execute(
        "SELECT zone, alert, recorded_at FROM alerts ORDER BY id DESC LIMIT ?",
        (limit,),
    ).fetchall()
  return [{"zone": r["zone"], "alert": r["alert"], "at": r["recorded_at"]} for r in rows]


def ai_insights_history(limit: int = 20) -> list[dict]:
  with _conn() as c:
    rows = c.execute(
        "SELECT zone, security_risk, comfort_score, payload, recorded_at FROM ai_insights ORDER BY id DESC LIMIT ?",
        (limit,),
    ).fetchall()
  out = []
  for r in rows:
    item = {
        "zone": r["zone"],
        "security_risk": r["security_risk"],
        "comfort_score": r["comfort_score"],
        "at": r["recorded_at"],
    }
    try:
      item["insights"] = json.loads(r["payload"])
    except json.JSONDecodeError:
      item["insights"] = {}
    out.append(item)
  return out
