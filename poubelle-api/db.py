"""SQLite historique Smart Poubelle."""
from __future__ import annotations

import sqlite3
from pathlib import Path

DB_PATH = Path(__file__).resolve().parent.parent / "data" / "poubelle.db"


def _conn() -> sqlite3.Connection:
  DB_PATH.parent.mkdir(parents=True, exist_ok=True)
  c = sqlite3.connect(DB_PATH)
  c.row_factory = sqlite3.Row
  return c


def init_db() -> None:
  with _conn() as c:
    c.executescript("""
      CREATE TABLE IF NOT EXISTS telemetry (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        bin_id TEXT NOT NULL,
        waste_type TEXT,
        fill_pct INTEGER,
        weight_kg REAL,
        lid_open INTEGER,
        gas_ppm INTEGER,
        battery_pct INTEGER,
        recorded_at TEXT DEFAULT (datetime('now'))
      );
      CREATE TABLE IF NOT EXISTS alerts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        bin_id TEXT NOT NULL,
        alert TEXT NOT NULL,
        recorded_at TEXT DEFAULT (datetime('now'))
      );
      CREATE INDEX IF NOT EXISTS idx_bin ON telemetry(bin_id);
    """)


def insert_telemetry(bin_id: str, waste_type: str, fill_pct: int, weight_kg: float,
                     lid_open: bool, gas_ppm: int, battery_pct: int) -> None:
  with _conn() as c:
    c.execute(
        """INSERT INTO telemetry (bin_id, waste_type, fill_pct, weight_kg, lid_open, gas_ppm, battery_pct)
           VALUES (?, ?, ?, ?, ?, ?, ?)""",
        (bin_id, waste_type, fill_pct, weight_kg, int(lid_open), gas_ppm, battery_pct),
    )


def insert_alert(bin_id: str, alert: str) -> None:
  with _conn() as c:
    c.execute("INSERT INTO alerts (bin_id, alert) VALUES (?, ?)", (bin_id, alert))


def telemetry_history(bin_id: str | None = None, limit: int = 120) -> list[dict]:
  with _conn() as c:
    if bin_id:
      rows = c.execute(
          "SELECT * FROM telemetry WHERE bin_id = ? ORDER BY id DESC LIMIT ?",
          (bin_id, limit),
      ).fetchall()
    else:
      rows = c.execute("SELECT * FROM telemetry ORDER BY id DESC LIMIT ?", (limit,)).fetchall()
  out = []
  for r in reversed(rows):
    out.append({
        "bin_id": r["bin_id"],
        "waste_type": r["waste_type"],
        "fill_pct": r["fill_pct"],
        "weight_kg": r["weight_kg"],
        "lid_open": bool(r["lid_open"]),
        "gas_ppm": r["gas_ppm"],
        "battery_pct": r["battery_pct"],
        "recorded_at": r["recorded_at"],
    })
  return out


def latest_per_bin() -> dict[str, dict]:
  with _conn() as c:
    rows = c.execute("""
      SELECT t.* FROM telemetry t
      INNER JOIN (SELECT bin_id, MAX(id) AS max_id FROM telemetry GROUP BY bin_id) m
      ON t.id = m.max_id
    """).fetchall()
  return {
      r["bin_id"]: {
          "bin_id": r["bin_id"],
          "waste_type": r["waste_type"],
          "fill_pct": r["fill_pct"],
          "weight_kg": r["weight_kg"],
          "gas_ppm": r["gas_ppm"],
          "battery_pct": r["battery_pct"],
      }
      for r in rows
  }
