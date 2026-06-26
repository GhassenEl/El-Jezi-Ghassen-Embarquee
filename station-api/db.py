"""SQLite historique telemetry Smart Station."""
from __future__ import annotations

import sqlite3
from pathlib import Path

DB_PATH = Path(__file__).resolve().parent.parent / "data" / "station.db"


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
        station_id TEXT NOT NULL,
        line_id TEXT,
        vehicle TEXT,
        direction TEXT,
        eta_min INTEGER,
        occ INTEGER,
        crowd INTEGER,
        validators INTEGER,
        recorded_at TEXT DEFAULT (datetime('now'))
      );
      CREATE INDEX IF NOT EXISTS idx_tel_station ON telemetry(station_id);
    """)


def insert_telemetry(
    station_id: str,
    line_id: str,
    vehicle: str,
    direction: str,
    eta_min: int,
    occ: int,
    crowd: int,
    validators: int,
) -> None:
  with _conn() as c:
    c.execute(
        """INSERT INTO telemetry
           (station_id, line_id, vehicle, direction, eta_min, occ, crowd, validators)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?)""",
        (station_id, line_id, vehicle, direction, eta_min, occ, crowd, validators),
    )


def telemetry_history(station_id: str | None = None, limit: int = 120) -> list[dict]:
  with _conn() as c:
    if station_id:
      rows = c.execute(
          "SELECT * FROM telemetry WHERE station_id = ? ORDER BY id DESC LIMIT ?",
          (station_id, limit),
      ).fetchall()
    else:
      rows = c.execute(
          "SELECT * FROM telemetry ORDER BY id DESC LIMIT ?",
          (limit,),
      ).fetchall()
  out = []
  for r in reversed(rows):
    out.append({
        "station_id": r["station_id"],
        "line_id": r["line_id"],
        "vehicle": r["vehicle"],
        "direction": r["direction"],
        "eta_min": r["eta_min"],
        "occ": r["occ"],
        "crowd": r["crowd"],
        "validators": r["validators"],
        "recorded_at": r["recorded_at"],
    })
  return out


def latest_per_station() -> dict[str, dict]:
  with _conn() as c:
    rows = c.execute("""
      SELECT t.* FROM telemetry t
      INNER JOIN (
        SELECT station_id, MAX(id) AS max_id FROM telemetry GROUP BY station_id
      ) m ON t.id = m.max_id
    """).fetchall()
  return {
      r["station_id"]: {
          "station_id": r["station_id"],
          "line_id": r["line_id"],
          "vehicle": r["vehicle"],
          "eta_min": r["eta_min"],
          "occ": r["occ"],
          "crowd": r["crowd"],
          "validators": r["validators"],
      }
      for r in rows
  }
