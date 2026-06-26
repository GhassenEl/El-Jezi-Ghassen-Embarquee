#!/usr/bin/env python3
"""Initialise la base SQLite films.db depuis les scripts SQL."""
from __future__ import annotations

import argparse
import sqlite3
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SQL_DIR = ROOT / "sql"
DEFAULT_DB = ROOT / "data" / "films.db"


def run_sql_file(conn: sqlite3.Connection, path: Path) -> None:
  sql = path.read_text(encoding="utf-8")
  conn.executescript(sql)


def main() -> int:
  p = argparse.ArgumentParser(description="Init base films SQLite")
  p.add_argument("--db", type=Path, default=DEFAULT_DB)
  p.add_argument("--reset", action="store_true", help="Supprimer et recreer la base")
  args = p.parse_args()

  args.db.parent.mkdir(parents=True, exist_ok=True)
  if args.reset and args.db.exists():
    args.db.unlink()

  conn = sqlite3.connect(args.db)
  conn.row_factory = sqlite3.Row
  try:
    for name in ("01_schema.sql", "02_seed.sql"):
      run_sql_file(conn, SQL_DIR / name)
    conn.commit()
    count = conn.execute("SELECT COUNT(*) FROM film").fetchone()[0]
    print(f"Base creee : {args.db} ({count} films)")
  finally:
    conn.close()
  return 0


if __name__ == "__main__":
  raise SystemExit(main())
